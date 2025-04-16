//
//  MainView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//

import SwiftUI
import SwiftData
import OpenAPIRuntime

struct MainView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var userSettings: UserSettings
    @Bindable var appState: AppState
    
    @State private var activeTab: TabSelection = .recordings
    
    @Query var localFiles: [LocalFile]
    
    var body: some View {
        TabView(selection: $activeTab) {
            Tab("Recordings", systemImage: "recordingtape", value: .recordings) {
                RecordingsView(appState: appState, activeTab: $activeTab)
            }
            
            Tab("Live", systemImage: "dot.radiowaves.left.and.right", value: .live) {
                LiveChannelsView(activeTab: $activeTab)
            }
            
            Tab("Downloads", systemImage: "square.and.arrow.down", value: .downloads) {
                DownloadsView()
            }
            .badge(appState.activeDownloads.count)
            
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        #if os(macOS)
        .overlay(content: {
            if let playingItem = appState.playingItem {
                PlayerView(item: playingItem)
                    .environment(appState)
                    .environmentObject(userSettings)
            }
        })
        #else
        .fullScreenCover(item: $appState.playingItem) { item in
            PlayerView(item: item)
                .environment(appState)
                .environmentObject(userSettings)
        }
        #endif
        .sheet(isPresented: $appState.isAuthenticating) {
            if case .redirect = appState.authType {
                NavigationStack {
                    AuthWebView(url: appState.client.endpoint.appending(path: "version"), expectedContentType: "application/json", isAuthenticaing: $appState.isAuthenticating)
                        .navigationTitle("Login")
                        .toolbar {
                            ToolbarItem(placement: appState.isNativeMac ? .cancellationAction : .topBarTrailing) {
                                Button("Close") {
                                    appState.isAuthenticating = false
                                }
                            }
                        }
                }
                #if os(macOS)
                .presentationSizing(.page)
                #endif
            } else {
                NavigationStack {
                    Group {
                        if case .basicAuth = appState.authType {
                            BasicAuthView()
                                .navigationTitle("Login")
                        } else if case .unknown(let type) = appState.authType {
                            ContentUnavailableView("Unsupported auth type", systemImage: "lock.trianglebadge.exclamationmark", description: Text(verbatim: type))
                                .navigationTitle("Error")
                        }
                    }
                    #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: appState.isNativeMac ? .cancellationAction : .topBarTrailing) {
                            Button("Close") {
                                appState.isAuthenticating = false
                            }
                        }
                    }
                }
                #if os(macOS)
                .frame(width: 400, height: 300)
                #endif
            }
        }
    }
}

enum TabSelection: String, Hashable {
    case live
    case recordings
    case downloads
    case settings
}
