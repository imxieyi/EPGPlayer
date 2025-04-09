//
//  EPGPlayerApp.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//

import SwiftUI
import OpenAPIRuntime

@main
struct EPGPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var appState = AppState()
    @StateObject private var userSettings = UserSettings()
    
    var body: some Scene {
        WindowGroup {
            MainView(appState: appState)
                .environment(appState)
                .environmentObject(userSettings)
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
                .onAppear {
                    Task {
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
