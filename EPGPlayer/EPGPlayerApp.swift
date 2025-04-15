//
//  EPGPlayerApp.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//

import SwiftUI
import SwiftData
import OpenAPIRuntime
import KeychainSwift
@preconcurrency import UserNotifications

@main
struct EPGPlayerApp: App {
    @Environment(\.scenePhase) var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var appState = AppState()
    @StateObject private var userSettings = UserSettings()
    @State private var container: ModelContainer?
    
    let modelContainer: ModelContainer?
    let modelSetupError: Error?
    
    init() {
        do {
            modelContainer = try ModelContainer(for: Schema(versionedSchema: LocalSchemaV3.self), migrationPlan: LocalSchemaMigrationPlan.self)
            modelSetupError = nil
        } catch let error {
            modelContainer = nil
            modelSetupError = error
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainer {
                    MainView(appState: appState)
                        .modelContainer(modelContainer)
                        .onAppear {
                            DownloadManager.shared.container = modelContainer
                            LocalFileManager.shared.container = modelContainer
                            self.container = modelContainer
                        }
                } else if let modelSetupError {
                    MainView(appState: appState)
                        .onAppear {
                            appState.downloadsSetupError = modelSetupError
                        }
                }
            }
            .environment(appState)
            .environmentObject(userSettings)
            .onChange(of: userSettings.serverUrl, { oldValue, newValue in
                guard oldValue != newValue else {
                    return
                }
                refreshClient(newValue)
            })
            .onChange(of: appState.isAuthenticating) { oldValue, newValue in
                if oldValue && !newValue {
                    refreshClient(userSettings.serverUrl, waitTime: .seconds(1))
                }
            }
            .onChange(of: appState.activeDownloads, initial: true, { oldValue, newValue in
                let count = newValue.count
                Task(priority: .background) {
                    do {
                        try await UNUserNotificationCenter.current().setBadgeCount(count)
                    } catch let error {
                        print("Failed to set badge count: \(error.localizedDescription)")
                    }
                }
            })
            .onChange(of: scenePhase, { oldValue, newValue in
                switch newValue {
                case .active:
                    LocalFileManager.shared.fixFilesAvailability()
                case .background, .inactive:
                    break
                @unknown default:
                    print("Unknown scene phase: \(newValue)")
                    break
                }
            })
            .onReceive(DownloadManager.shared.events.downloadSuccess, perform: { url in
                appState.activeDownloads.removeAll(where: { $0.url == url })
                if appState.activeDownloads.isEmpty {
                    LocalFileManager.shared.fixFilesAvailability()
                    Task {
                        let center = UNUserNotificationCenter.current()
                        let settings = await center.notificationSettings()
                        guard settings.authorizationStatus == .authorized else {
                            return
                        }
                        let content = UNMutableNotificationContent()
                        content.title = String(localized: "Download completed")
                        content.body = String(localized: "Background downloads have been completed.")
                        content.sound = .default
                        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                        do {
                            try await UNUserNotificationCenter.current().add(request)
                        } catch let error {
                            print("Failed to schedule notification: \(error.localizedDescription)")
                        }
                        do {
                            try await UNUserNotificationCenter.current().setBadgeCount(0)
                        } catch let error {
                            print("Failed to update badge cound: \(error.localizedDescription)")
                        }
                    }
                }
            })
            .onReceive(DownloadManager.shared.events.downloadFailure, perform: { (url: URL, task: URLSessionDownloadTask, error: String) in
                if let index = appState.activeDownloads.firstIndex(where: { $0.url == url }) {
                    appState.activeDownloads[index].errorMessage = error
                    appState.activeDownloads[index].videoItem.file.unavailableReason = error
                    return
                }
                let insertDownload = { (container: ModelContainer) in
                    do {
                        guard let videoItem = try container.mainContext.fetch(FetchDescriptor<LocalVideoItem>(predicate: #Predicate { $0.originalUrl == url })).first else {
                            print("Local video item does not exist for: \(url)")
                            return
                        }
                        appState.activeDownloads.append(ActiveDownload(url: url, videoItem: videoItem, downloadTask: task, progress: task.progress.fractionCompleted, errorMessage: error))
                        videoItem.file.unavailableReason = error
                    } catch let error {
                        print("Failed to fetch video item: \(error.localizedDescription)")
                    }
                }
                if let container {
                    insertDownload(container)
                } else {
                    Task {
                        while container == nil {
                            try await Task.sleep(for: .seconds(1))
                        }
                        insertDownload(container!)
                    }
                }
            })
            .onAppear {
                DownloadManager.shared.initialize()
                Task(priority: .background) {
                    do {
                        appState.activeDownloads += try await DownloadManager.shared.getActiveDownloads()
                    } catch let error {
                        print("Failed to load active downloads: \(error)")
                    }
                }
                do {
                    try LocalFileManager.shared.initialize()
                } catch let error {
                    appState.downloadsSetupError = error
                }
                if appState.isOnMac {
                    userSettings.forceLandscape = false
                }
                refreshClient(userSettings.serverUrl)
            }
        }
    }
    
    func refreshClient(_ urlString: String, waitTime: Duration = .zero) {
        appState.clientError = nil
        if urlString != "", let url = URL(string: urlString) {
            appState.clientState = .notInitialized
            var headers: [String : String] = [:]
            if let basicAuth = KeychainSwift().get("basic:\(urlString)") {
                headers["authorization"] = "Basic \(basicAuth)"
            }
            appState.client = EPGClient(endpoint: url.appending(path: "api"), headers: headers)
            refreshServerInfo(waitTime: waitTime)
        } else {
            appState.clientState = .setupNeeded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.client = EPGClient()
            }
        }
    }
    
    func refreshServerInfo(waitTime: Duration = .zero) {
        Task {
            do {
                appState.clientState = .notInitialized
                appState.serverVersion = ""
                try await Task.sleep(for: waitTime)
                appState.serverVersion = try await appState.client.api.getVersion().ok.body.json.version
                appState.clientState = .initialized
            } catch let error {
                print("Failed to get server version: \(error)")
                if let error = error as? ClientError {
                    if error.response?.status == .unauthorized {
                        appState.clientState = .authNeeded
                        appState.clientError = Text(verbatim: "401 Unauthorized")
                        if let wwwAuthticate = error.response?.headerFields[.wwwAuthenticate] {
                            if wwwAuthticate.hasPrefix("Basic") {
                                appState.authType = .basicAuth
                            } else {
                                appState.authType = .unknown(wwwAuthticate)
                            }
                        } else {
                            appState.clientState = .error
                        }
                        return
                    } else if error.response?.status.kind == .redirection {
                        appState.clientState = .authNeeded
                        appState.authType = .redirect
                        appState.clientError = Text("Redirection detected")
                        return
                    }
                }
                appState.clientError = Text("Failed to get server version: \(error.localizedDescription)")
                appState.clientState = .error
            }
        }
    }
}
