//
//  EPGPlayerApp.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import SwiftData
import OpenAPIRuntime
import KeychainSwift
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
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
        let hasFirebase = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
        Logger.initialize(crashlytics: hasFirebase)
        if hasFirebase {
            DispatchQueue.main.async {
                #if os(macOS)
                UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
                #endif
                FirebaseApp.configure()
                #if DEBUG
                Analytics.setAnalyticsCollectionEnabled(false)
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
                #else
                Analytics.setAnalyticsCollectionEnabled(true)
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
                #endif
            }
        }
        do {
            modelContainer = try ModelContainer(for: Schema(versionedSchema: LocalSchemaV3.self), migrationPlan: LocalSchemaMigrationPlan.self)
            modelSetupError = nil
        } catch let error {
            modelContainer = nil
            modelSetupError = error
        }
    }
    
    var body: some Scene {
        #if os(macOS)
        Window("Player", id: "player-window") {
             Group {
                 if let item = appState.playingItem {
                     Group {
                         if let modelContainer {
                             PlayerView(item: item)
                                 .modelContainer(modelContainer)
                         } else {
                             PlayerView(item: item)
                         }
                     }
                     .environment(appState)
                     .environmentObject(userSettings)
                     .navigationTitle(item.title)
                     .onDisappear {
                         appState.playingItem = nil
                     }
                 } else {
                     ContentUnavailableView("No media selected", systemImage: "play.slash")
                         .padding()
                 }
             }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowIdealSize(.maximum)
        .defaultSize(width: 1600, height: 900)
        
        Window("EPGPlayer", id: "main") {
            mainBody
        }
        .windowToolbarLabelStyle(fixed: .iconOnly)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1600, height: 900)
        #else
        WindowGroup {
            mainBody
        }
        #endif
    }
    
    var mainBody: some View {
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
                    #if os(macOS)
                    NSApplication.shared.dockTile.badgeLabel = (count > 0) ? String(count) : nil
                    #else
                    try await UNUserNotificationCenter.current().setBadgeCount(count)
                    #endif
                } catch let error {
                    Logger.error("Failed to set badge count: \(error.localizedDescription)")
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
                Logger.error("Unknown scene phase: \(newValue)")
                break
            }
        })
        #if !os(tvOS)
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
                        Logger.error("Failed to schedule notification: \(error.localizedDescription)")
                    }
                    do {
                        try await UNUserNotificationCenter.current().setBadgeCount(0)
                    } catch let error {
                        Logger.error("Failed to update badge cound: \(error.localizedDescription)")
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
                        Logger.error("Local video item does not exist for: \(pii: url.absoluteString)")
                        return
                    }
                    appState.activeDownloads.append(ActiveDownload(url: url, videoItem: videoItem, downloadTask: task, progress: task.progress.fractionCompleted, errorMessage: error))
                    videoItem.file.unavailableReason = error
                } catch let error {
                    Logger.error("Failed to fetch video item: \(error.localizedDescription)")
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
        #endif
        .onAppear {
            setupKeychain()
            DownloadManager.shared.initialize()
            Task(priority: .background) {
                do {
                    appState.activeDownloads += try await DownloadManager.shared.getActiveDownloads()
                } catch let error {
                    Logger.error("Failed to load active downloads: \(error.localizedDescription)")
                }
            }
            do {
                try LocalFileManager.shared.initialize()
            } catch let error {
                appState.downloadsSetupError = error
            }
            #if os(macOS)
            userSettings.forceLandscape = false
            #endif
            DispatchQueue.main.async {
                refreshClient(userSettings.serverUrl)
            }
        }
    }
    
    func setupKeychain() {
        appState.keychain = KeychainSwift()
        if let teamId = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String {
            appState.keychain.accessGroup = "\(teamId)com.imxieyi.EPGPlayer"
        }
    }
    
    func refreshClient(_ urlString: String, waitTime: Duration = .zero) {
        appState.clientError = nil
        if urlString != "", let url = URL(string: urlString) {
            Logger.info("Server URL set to \(pii: urlString)")
            appState.clientState = .notInitialized
            var headers: [String : String] = [:]
            if let authHeader = appState.keychain.get("auth_header:\(urlString)") {
                Logger.info("Adding authentication header")
                headers["authorization"] = authHeader
            }
            appState.client = EPGClient(endpoint: url.appending(path: "api"), headers: headers)
            refreshServerInfo(waitTime: waitTime)
        } else {
            Logger.info("Server URL set to empty")
            appState.clientState = .setupNeeded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.client = EPGClient()
            }
        }
    }
    
    func refreshServerInfo(waitTime: Duration = .zero) {
        Task {
            Logger.info("Refreshing server info")
            do {
                appState.clientState = .notInitialized
                appState.serverVersion = ""
                try await Task.sleep(for: waitTime)
                appState.serverVersion = try await appState.client.api.getVersion().ok.body.json.version
                appState.clientState = .initialized
                Components.Schemas.RecordedItem.endpoint = appState.client.endpoint
            } catch let error {
                Logger.error("Failed to get server version: \(error)")
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
                appState.authType = .redirect
            }
        }
    }
}
