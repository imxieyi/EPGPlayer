//
//  SettingsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    @EnvironmentObject private var client: EPGClient
    
    @State private var showServerUrlAlert: Bool = false
    @State private var serverUrl: String = ""
    @State private var showServerUrlInvalidAlert: Bool = false
    
    @State private var currentCacheSize: Int = 0
    
    var body: some View {
        Form {
            serverSection
            playerSection
            cacheSection
            resetSection
        }
    }
    
    var serverSection: some View {
        Section {
            if userSettings.serverUrl != "" {
                Text(verbatim: userSettings.serverUrl)
                    .foregroundStyle(.gray)
                if appState.serverVersion != "" {
                    Text("Server version: \(appState.serverVersion)")
                        .foregroundStyle(.gray)
                } else if appState.clientState == .authNeeded {
                    Button("Login") {
                        appState.isAuthenticating = true
                    }
                } else {
                    appState.serverError
                        .foregroundStyle(.red)
                }
            } else {
                Text("Please set EPGStation URL")
                    .foregroundStyle(.gray)
            }
            
            Button("Set URL") {
                showServerUrlAlert.toggle()
            }
            .alert("Set EPGStation URL", isPresented: $showServerUrlAlert) {
                TextField("EPGStation URL", text: $serverUrl, prompt: Text(verbatim: "https://example.com"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                Button("Done") {
                    guard let url = URL(string: serverUrl, encodingInvalidCharacters: false) else {
                        showServerUrlInvalidAlert.toggle()
                        return
                    }
                    userSettings.serverUrl = url.absoluteString
                }
                Button("Cancel", role: .cancel) {
                    serverUrl = userSettings.serverUrl
                }
            }
            .alert("Invalid URL", isPresented: $showServerUrlInvalidAlert) {
                Button("Close", role: .cancel) {
                }
            }
            .onAppear {
                serverUrl = userSettings.serverUrl
            }
        } header: {
            Label("Server Settings", systemImage: "network")
        }
    }
    
    var playerSection: some View {
        Section {
            Toggle(isOn: userSettings.$enableSubtitle) {
                Text("Enable subtitles")
            }
            Toggle(isOn: userSettings.$forceLandscape) {
                Text("Force landscape")
            }
        } header: {
            Label("Player Settings", systemImage: "play.rectangle")
        }
    }
    
    var cacheSection: some View {
        Section {
            Text("Image cache size: \(currentCacheSize / 1024 / 1024) MB")
                .foregroundStyle(.gray)
            Button("Clear cache") {
                URLCache.imageCache.removeAllCachedResponses()
                currentCacheSize = 0
            }
        } header: {
            Label("Caches", systemImage: "arrow.up.bin")
        }
        .onAppear {
            currentCacheSize = URLCache.imageCache.currentDiskUsage
        }
    }
    
    var resetSection: some View {
        Section {
            Button("Clear cookies", role: .destructive) {
                HTTPCookieStorage.shared.removeCookies(since: .distantPast)
            }
            Button("Reset settings") {
                userSettings.reset()
            }
        } header: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
    }
}
