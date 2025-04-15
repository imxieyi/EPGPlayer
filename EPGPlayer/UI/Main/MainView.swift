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
        .fullScreenCover(item: $appState.playingItem) { item in
            if appState.isOnMac {
                PlayerView(item: item)
                    .environment(appState)
                    .environmentObject(userSettings)
            } else {
                PlayerView(item: item)
            }
        }
        .sheet(isPresented: $appState.isAuthenticating) {
            NavigationView {
                Group {
                    switch appState.authType {
                    case .redirect:
                        AuthWebView(url: appState.client.endpoint.appending(path: "version"), expectedContentType: "application/json", isAuthenticaing: $appState.isAuthenticating)
                            .navigationTitle("Login")
                    case .basicAuth:
                        BasicAuthView()
                            .navigationTitle("Login")
                    case .unknown(let type):
                        ContentUnavailableView("Unsupported auth type", systemImage: "lock.trianglebadge.exclamationmark", description: Text(verbatim: type))
                            .navigationTitle("Error")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            appState.isAuthenticating = false
                        }
                    }
                }
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
