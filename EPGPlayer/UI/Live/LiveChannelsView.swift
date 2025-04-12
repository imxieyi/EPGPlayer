//
//  LiveChannelsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/12.
//

import SwiftUI
import CachedAsyncImage
import OpenAPIRuntime

struct LiveChannelsView: View {
    @Bindable var appState: AppState
    @Binding var activeTab: TabSelection
    
    @State var loadingState = LoadingState.loading
    @State var loadingMoreState = LoadingState.loaded
    
    @State var channels: [Components.Schemas.ChannelItem] = []
    
    var body: some View {
        Group {
            if case .loading = loadingState {
                ProgressView()
                    .padding()
            } else if case .loaded = loadingState {
                List(channels) { channel in
                    Button {
                        appState.playingItem = PlayerItem(videoItem: channel, title: channel.halfWidthName)
                    } label: {
                        HStack {
                            CachedAsyncImage(url: appState.client.endpoint.appending(path: "channels/\(channel.id)/logo"), urlCache: .imageCache) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                } else if phase.error != nil {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .foregroundStyle(.placeholder)
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(height: 20)
                            Text(verbatim: channel.halfWidthName)
                            Spacer()
                            Text(verbatim: channel.channelType.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }
                .refreshable {
                    refresh()
                }
            } else if case .error(let message) = loadingState {
                ContentUnavailableView {
                    if appState.clientState == .setupNeeded {
                        Label("Setup needed", systemImage: "exclamationmark.triangle")
                    } else if appState.clientState == .authNeeded {
                        Label("Authentication required", systemImage: "exclamationmark.triangle")
                    } else {
                        Label("Error loading content", systemImage: "xmark.circle")
                    }
                } description: {
                    message
                } actions: {
                    if appState.clientState == .authNeeded {
                        Button("Login") {
                            appState.isAuthenticating = true
                        }
                    } else if appState.clientState == .setupNeeded {
                        Button("Go to settings") {
                            activeTab = .settings
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
        .onChange(of: appState.isAuthenticating) { oldValue, newValue in
            if oldValue && !newValue {
                refresh(waitTime: .seconds(1))
            }
        }
        .onChange(of: appState.clientState) { _, newValue in
            if newValue == .initialized {
                refresh()
            } else if newValue == .authNeeded {
                loadingState = .error(Text("Redirection detected"))
            } else if newValue == .setupNeeded {
                loadingState = .error(Text("Please set EPGStation URL"))
            }
        }
        .onAppear {
            if channels.isEmpty {
                refresh()
            }
        }
    }
    
    func refresh(waitTime: Duration = .zero) {
        guard appState.clientState == .initialized else {
            loadingState = .error(appState.serverError)
            return
        }
        channels = []
        loadingState = .loading
        Task {
            do {
                try await Task.sleep(for: waitTime)
                channels = try await appState.client.api.getChannels().ok.body.json.filter { $0._type == 1 }
                loadingState = .loaded
                print("Loaded \(channels.count) channels")
            } catch let error {
                print("Failed to load recordings: \(error)")
                if let error = error as? ClientError, error.response?.status.kind == .redirection {
                    appState.clientState = .authNeeded
                    loadingState = .error(Text("Redirection detected"))
                    return
                }
                loadingState = .error(Text(verbatim: error.localizedDescription))
            }
        }
    }
}

extension Components.Schemas.ChannelItem: Identifiable {
    
}
