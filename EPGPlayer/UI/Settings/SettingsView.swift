//
//  SettingsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    @EnvironmentObject private var client: EPGClient
    
    @State private var showServerUrlAlert: Bool = false
    @State private var serverUrl: String = ""
    @State private var showServerUrlInvalidAlert: Bool = false
    
    @State private var currentDownloadsSize: Int? = nil
    @State private var downloadSizeError: String? = nil
    @State private var currentCacheSize: Int = 0
    
    var body: some View {
        NavigationStack {
            Form {
                serverSection
                playerSection
                storageSection
                resetSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
            Toggle(isOn: userSettings.$enableSubtitles) {
                Text("Enable subtitles")
            }
            
            if !appState.isOnMac {
                Toggle(isOn: userSettings.$forceLandscape) {
                    Text("Force landscape")
                }
            }
            
            Picker(selection: userSettings.$inactiveTimer) {
                ForEach([3, 5, 10, 15, .max], id: \.self) { time in
                    if time == .max {
                        Text("Never")
                    } else {
                        Text("\(time)s")
                    }
                }
            } label: {
                Text("Auto hide UI")
            }
            .pickerStyle(.menu)
        } header: {
            Label("Player Settings", systemImage: "play.rectangle")
        }
    }
    
    var storageSection: some View {
        Section {
            Group {
                if let downloadSizeError {
                    Text("Download size error: \(downloadSizeError)")
                } else {
                    Text("Downloads size: ")
                    + (currentDownloadsSize == nil ? Text("Calculating") : Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(currentDownloadsSize!))))
                }
            }
            .foregroundStyle(.gray)
            HStack {
                Text("Image cache size: \(ByteCountFormatter().string(fromByteCount: Int64(currentCacheSize)))")
                    .foregroundStyle(.gray)
                Spacer()
                Button {
                    URLCache.imageCache.removeAllCachedResponses()
                    currentCacheSize = 0
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        } header: {
            Label("Storage", systemImage: "internaldrive")
        }
        .onAppear {
            currentCacheSize = URLCache.imageCache.currentDiskUsage
            currentDownloadsSize = nil
            downloadSizeError = nil
            Task(priority: .background) {
                do {
                    self.currentDownloadsSize = try LocalFileManager.shared.totalSize()
                } catch let error {
                    print("Failed to get total download size: \(error.localizedDescription)")
                    downloadSizeError = error.localizedDescription
                }
            }
        }
    }
    
    var resetSection: some View {
        Section {
            Button("Clear cookies", role: .destructive) {
                HTTPCookieStorage.shared.removeCookies(since: .distantPast)
            }
        } header: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
    }
    
    #if DEBUG
    var debugSection: some View {
        Section {
            Button {
                LocalFileManager.shared.deleteOrphans()
            } label: {
                Text(verbatim: "Clean orphan files")
            }
            Button(role: .destructive) {
                try! context.container.erase()
            } label: {
                Text(verbatim: "Clear SwiftData")
            }
            Button(role: .destructive) {
                userSettings.reset()
            } label: {
                Text(verbatim: "Reset settings")
            }
        } header: {
            Label {
                Text(verbatim: "Debug")
            } icon: {
                Image(systemName: "ladybug")
            }
        }
    }
    #endif
}
