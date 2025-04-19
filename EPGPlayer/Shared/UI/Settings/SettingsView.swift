//
//  SettingsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//

import Foundation
import SwiftUI
//import LicenseList

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    
    @State private var showServerUrlAlert: Bool = false
    @State private var serverUrl: String = ""
    @State private var showServerUrlInvalidAlert: Bool = false
    
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
                debugSection
                #endif
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
    
    var serverSection: some View {
        Section {
            if userSettings.serverUrl != "" {
                Text(verbatim: userSettings.serverUrl)
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
                } else {
                    (appState.clientError ?? Text("Unknown error"))
                        .foregroundStyle(.red)
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
                    userSettings.serverUrl = url.absoluteString
                }
                Button("Cancel", role: .cancel) {
                    serverUrl = userSettings.serverUrl
                }
            } message: {
                Text("Don't add \"/api\" at the end of URL.")
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
                    DispatchQueue.main.async {
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
                        print("Failed to get database size: \(error.localizedDescription)")
                        databaseSizeError = error.localizedDescription
                    }
                } else {
                    databaseSizeError = "Unknown database location"
                }
                
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
                        print("Failed to clear keychain")
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
            
            Menu {
//                NavigationLink {
//                    LicenseListView()
//                        .licenseViewStyle(.withRepositoryAnchorLink)
//                        .navigationTitle("Licenses")
//                        .navigationBarTitleDisplayMode(.inline)
//                } label: {
//                    Label("Packages", systemImage: "shippingbox")
//                }
                
                NavigationLink {
                    LicenseView(name: "VLCKit")
                } label: {
                    Label("VLCKit", image: "VLCLogo")
                }
                
                NavigationLink {
                    LicenseView(name: "EPGStation")
                } label: {
                    Label("EPGStation", systemImage: "tv")
                }
            } label: {
                HStack {
                    Text("Licenses")
                    #if !os(macOS)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                    #endif
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
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
