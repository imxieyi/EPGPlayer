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
    
    @State private var activeTab: TabSelection = .settings
    
    var body: some View {
        NavigationStack {
            TabView(selection: $activeTab) {
                Tab("Recordings", systemImage: "recordingtape", value: .recordings) {
                    RecordingsView(appState: appState)
                }
                Tab("Settings", systemImage: "gearshape", value: .settings) {
                    SettingsView()
                }
            }
            .navigationTitle("EPGPlayer")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $appState.selectedRecording) { item in
                VStack {
                    VLCPlayerView(videoURL: appState.client.endpoint.appending(path: "videos/\(item.videoFiles?.first?.id ?? 0)"))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16/9, contentMode: .fit)
                    ScrollView(.vertical) {
                        Text(item.name)
                            .font(.headline)
                        if let desc = item.description {
                            Text(desc)
                                .font(.subheadline)
                        }
                        if let ext = item.extended {
                            Text(ext)
                                .font(.caption)
                        }
                    }
                }
            }
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
