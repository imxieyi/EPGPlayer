//
//  MainView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//

import SwiftUI
import OpenAPIRuntime

struct MainView: View {
    @Bindable var appState: AppState
    
    @State private var activeTab: TabSelection = .recordings
    
    var body: some View {
        NavigationStack {
            TabView(selection: $activeTab) {
                Tab("Recordings", systemImage: "recordingtape", value: .recordings) {
                    RecordingsView(appState: appState, activeTab: $activeTab)
                }
                Tab("Settings", systemImage: "gearshape", value: .settings) {
                    SettingsView()
                }
            }
        }
        .fullScreenCover(item: $appState.playingItem) { item in
            PlayerView(item: item)
        }
        .sheet(isPresented: $appState.isAuthenticating) {
            NavigationView {
                AuthWebView(url: appState.client.endpoint.appending(path: "version"), isAuthenticaing: $appState.isAuthenticating)
                    .navigationTitle("Login")
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
    case recordings
    case settings
}
