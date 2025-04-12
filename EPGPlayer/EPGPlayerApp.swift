//
//  EPGPlayerApp.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//

import SwiftUI
import SwiftData
import OpenAPIRuntime
@preconcurrency import UserNotifications

@main
struct EPGPlayerApp: App {
    @Environment(\.scenePhase) var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var appState = AppState()
    @StateObject private var userSettings = UserSettings()
    @State private var container: ModelContainer?
    
    var body: some Scene {
        WindowGroup {
            MainView(appState: appState)
                .environment(appState)
                .environmentObject(userSettings)
                .modelContainer(for: [
                    LocalRecordedItem.self,
                    LocalVideoItem.self,
                    LocalFile.self
                ], onSetup: { result in
                    do {
                        let container = try result.get()
                        DownloadManager.shared.container = container
                        LocalFileManager.shared.container = container
                        self.container = container
                    } catch let error {
                        appState.downloadsSetupError = error
                    }
                })
                .onChange(of: userSettings.serverUrl, { oldValue, newValue in
                    guard oldValue != newValue else {
                        return
                    }
                    if newValue != "", let url = URL(string: newValue) {
                        appState.client = EPGClient(endpoint: url.appending(path: "api"))
                        appState.clientState = .notInitialized
                        refreshServerInfo()
                        return
                    }
                    appState.client = EPGClient()
                })
                .onChange(of: appState.isAuthenticating) { oldValue, newValue in
                    if oldValue && !newValue {
                        refreshServerInfo(waitTime: .seconds(1))
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
                    if userSettings.serverUrl != "", let url = URL(string: userSettings.serverUrl) {
                        appState.client = EPGClient(endpoint: url.appending(path: "api"))
                        appState.clientState = .notInitialized
                        refreshServerInfo()
                    } else {
                        appState.clientState = .setupNeeded
                    }
                }
        }
    }
    
    func refreshServerInfo(waitTime: Duration = .zero) {
        Task {
            do {
                try await Task.sleep(for: waitTime)
                appState.serverVersion = try await appState.client.api.getVersion().ok.body.json.version
            } catch let error {
                print("Failed to get server version: \(error)")
                if let error = error as? ClientError, error.response?.status.kind == .redirection {
                    appState.clientState = .authNeeded
                    appState.serverError = Text("Redirection detected")
                    return
                }
                appState.serverError = Text("Failed to get server version: \(error.localizedDescription)")
            }
            
            appState.clientState = .initialized
        }
    }
}
