//
//  SettingsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    
    @State private var showServerUrlAlert: Bool = false
    @State private var serverUrl: String = ""
    @State private var showServerUrlInvalidAlert: Bool = false
    
    @State private var showLicenseList: Bool = false
    @State private var showHTTPAlert: Bool = false
    @State private var showResetAlert: Bool = false
    @State private var resetAlertMessage: Text? = nil
    
    @State private var currentDownloadsSize: Int? = nil
    @State private var downloadSizeError: String? = nil
    @State private var currentDatabaseSize: Int? = nil
    @State private var databaseSizeError: String? = nil
    @State private var currentCacheSize: Int = 0
    
    var body: some View {
        NavigationStack {
            Form {
                serverSection
                playerSection
                storageSection
                resetSection
                aboutSection
                #if DEBUG
                if !userSettings.demoMode {
                    debugSection
                }
                #endif
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(isPresented: $showLicenseList, destination: {
                LicenseList()
            })
        }
    }
    
    var serverSection: some View {
        Section {
            if userSettings.serverUrl != "" {
                Group {
                    #if DEBUG
                    if userSettings.demoMode {
                        Text(verbatim: "https://demo.example.com")
                    } else {
                        Text(verbatim: userSettings.serverUrl)
                    }
                    #else
                    Text(verbatim: userSettings.serverUrl)
                    #endif
                }
                    .foregroundStyle(.secondary)
                if appState.serverVersion != "" {
                    Text("Server version: \(appState.serverVersion)")
                        .foregroundStyle(.secondary)
                } else if appState.clientState == .authNeeded {
                    if let clientError = appState.clientError {
                        clientError
                            .foregroundStyle(.orange)
                    }
                    Button("Login") {
                        appState.isAuthenticating = true
                    }
                } else if appState.clientState == .error {
                    (appState.clientError ?? Text("Unknown error"))
                        .foregroundStyle(.red)
                    Button {
                        appState.isAuthenticating = true
                    } label: {
                        HStack {
                            Text("Open test page")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .tint(.primary)
                } else if appState.clientState == .notInitialized {
                    ProgressView()
                }
            } else {
                Text("Please set EPGStation URL")
                    .foregroundStyle(.secondary)
            }
            
            Button("Set URL") {
                showServerUrlAlert.toggle()
            }
            .alert("Set EPGStation URL", isPresented: $showServerUrlAlert) {
                TextField("EPGStation URL", text: $serverUrl, prompt: Text(verbatim: "https://example.com"))
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                Button("Done") {
                    guard let url = URL(string: serverUrl, encodingInvalidCharacters: false) else {
                        showServerUrlInvalidAlert.toggle()
                        return
                    }
                    if url.scheme?.lowercased() == "http" {
                        showHTTPAlert.toggle()
                        return
                    }
                    userSettings.serverUrl = url.absoluteString
                }
                Button("Cancel", role: .cancel) {
                    serverUrl = userSettings.serverUrl
                }
            } message: {
                Text("Don't add \"/api\" at the end of URL.")
            }
            .alert("Warning", isPresented: $showHTTPAlert, actions: {
                Button("No", role: .cancel) {
                }
                Button("Yes", role: .destructive) {
                    userSettings.serverUrl = serverUrl
                }
            }, message: {
                Text("Accessing HTTP server over public Internet is not secure. Only do this if your server is on the local network or behind a VPN. Do you wish to continue?")
            })
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
            
            Toggle(isOn: userSettings.$forceStrokeText) {
                Text("Force stroke text")
            }
            
            Toggle(isOn: userSettings.$force16To9) {
                Text("Force 16:9")
            }
            
            #if !os(macOS)
            Toggle(isOn: userSettings.$forceLandscape) {
                Text("Force landscape")
            }
            #endif
            
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
            .foregroundStyle(.secondary)
            
            Group {
                if let downloadSizeError {
                    Text("Database error: \(downloadSizeError)")
                } else {
                    Text("Database size: ")
                    + (currentDatabaseSize == nil ? Text("Calculating") : Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(currentDatabaseSize!))))
                }
            }
            .foregroundStyle(.secondary)
            
            HStack {
                Text("Cache size: \(ByteCountFormatter().string(fromByteCount: Int64(currentCacheSize)))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    URLCache.imageCache.removeAllCachedResponses()
                    Task {
                        try await Task.sleep(for: .milliseconds(100))
                        currentCacheSize = URLCache.imageCache.currentDiskUsage
                    }
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
                if let downloadError = appState.downloadsSetupError {
                    databaseSizeError = downloadError.localizedDescription
                } else if let url = context.container.configurations.first?.url {
                    do {
                        if let fileSize = try url.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize {
                            currentDatabaseSize = fileSize
                        }
                    } catch let error {
                        Logger.error("Failed to get database size: \(error.localizedDescription)")
                        databaseSizeError = error.localizedDescription
                    }
                } else {
                    databaseSizeError = "Unknown database location"
                }
                
                do {
                    self.currentDownloadsSize = try LocalFileManager.shared.totalSize()
                } catch let error {
                    Logger.error("Failed to get total download size: \(error.localizedDescription)")
                    downloadSizeError = error.localizedDescription
                }
            }
        }
    }
    
    var resetSection: some View {
        Section {
            Button("Clear login info", role: .destructive) {
                resetAlertMessage = Text("You will be signed out if your server requires authentication. Restart the app to apply the changes.")
                showResetAlert.toggle()
            }
            .alert("Are you sure?", isPresented: $showResetAlert) {
                Button("Continue", role: .destructive) {
                    DispatchQueue.global(qos: .background).async {
                        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
                    }
                    if !appState.keychain.clear() {
                        Logger.error("Failed to clear keychain")
                    }
                }
                Button("Cancel", role: .cancel) {
                }
            } message: {
                if let resetAlertMessage {
                    resetAlertMessage
                }
            }
        } header: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
    }
    
    var aboutSection: some View {
        let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String
        return Section {
            Button {
                #if os(macOS)
                NSWorkspace.shared.open(URL(string: "https://github.com/imxieyi/EPGPlayer")!)
                #else
                UIApplication.shared.open(URL(string: "https://github.com/imxieyi/EPGPlayer")!)
                #endif
            } label: {
                HStack {
                    Text("\(appName ?? "EPGPlayer") on GitHub")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            
            Button {
                #if os(macOS)
                NSWorkspace.shared.open(URL(string: "https://github.com/imxieyi/EPGPlayer/issues/new")!)
                #else
                UIApplication.shared.open(URL(string: "https://github.com/imxieyi/EPGPlayer/issues/new")!)
                #endif
            } label: {
                HStack {
                    Text("Report issues")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            
            Button {
                showLicenseList.toggle()
            } label: {
                HStack {
                    Text("Licenses")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
        } header: {
            Label("About", systemImage: "info.circle")
        } footer: {
            if let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text(verbatim: "\(appName ?? "EPGPlayer") \(shortVersion) (\(buildNumber))")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    #if DEBUG
    var debugSection: some View {
        Section {
            Toggle(isOn: $userSettings.demoMode) {
                Text(verbatim: "Demo mode")
            }
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
            Button(role: .destructive) {
                _ = Array(arrayLiteral: 0)[2]
            } label: {
                Text(verbatim: "Trigger crash")
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
