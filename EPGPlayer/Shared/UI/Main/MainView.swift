//
//  MainView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import SwiftData
import OpenAPIRuntime

struct MainView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var userSettings: UserSettings
    @Bindable var appState: AppState
    
    @State private var activeTab: TabSelection = .recordings
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    @Query var localFiles: [LocalFile]
    
    var body: some View {
        mainBody
            .sheet(isPresented: $appState.isAuthenticating) {
                if case .redirect = appState.authType {
                    NavigationStack {
                        AuthWebView(url: appState.client.endpoint.appending(path: "version"), expectedContentType: "application/json", isAuthenticaing: $appState.isAuthenticating)
                            .navigationTitle("Login")
                            #if !os(macOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                            .toolbar {
                                ToolbarItem(placement: appState.isOnMac ? .cancellationAction : .topBarTrailing) {
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
                            } else if case .unknown(let type) = appState.authType {
                                CustomAuthView(authType: type)
                            }
                        }
                        .navigationTitle("Login")
                        #if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: appState.isOnMac ? .cancellationAction : .topBarTrailing) {
                                Button("Close") {
                                    appState.isAuthenticating = false
                                }
                            }
                        }
                    }
                }
            }
    }
    
    var mainBody: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility, sidebar: {
            List(selection: $activeTab) {
                Label("Recordings", systemImage: "recordingtape").tag(TabSelection.recordings)
                Label("Live", systemImage: "dot.radiowaves.left.and.right").tag(TabSelection.live)
                Label("Downloads", systemImage: "square.and.arrow.down").tag(TabSelection.downloads)
                Label("Settings", systemImage: "gearshape").tag(TabSelection.settings)
            }
        }, detail: {
            switch activeTab {
            case .live:
                LiveChannelsView(activeTab: $activeTab)
            case .recordings:
                RecordingsView(appState: appState, activeTab: $activeTab)
            case .downloads:
                DownloadsView()
            case .settings:
                SettingsView()
            }
        })
        #else
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
            PlayerView(item: item)
                .environment(appState)
                .environmentObject(userSettings)
        }
        #endif
    }
}

enum TabSelection: String, Hashable {
    case live
    case recordings
    case downloads
    case settings
}
