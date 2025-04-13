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
    @Environment(AppState.self) private var appState
    @Binding var activeTab: TabSelection
    
    @State var loadingState = LoadingState.loading
    @State var loadingMoreState = LoadingState.loaded
    
    @State var liveStreamConfig: Components.Schemas.Config.StreamConfigPayload.LivePayload.TsPayload? = nil
    @State var channels: [Components.Schemas.ChannelItem] = []
    
    var body: some View {
        NavigationStack {
            Group {
                if case .loading = loadingState {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                } else if case .loaded = loadingState, let liveStreamConfig {
                    List(channels) { channel in
                        Menu {
                            if let m2ts = liveStreamConfig.m2ts?.map({ $0.name }), !m2ts.isEmpty {
                                LiveStreamSelectionMenu(channel: channel, format: "m2ts", formatName: "M2TS", selections: m2ts)
                            }
                            if let m2tsll = liveStreamConfig.m2tsll, !m2tsll.isEmpty {
                                LiveStreamSelectionMenu(channel: channel, format: "m2tsll", formatName: "M2TS-LL", selections: m2tsll)
                            }
                            if let webm = liveStreamConfig.webm, !webm.isEmpty {
                                LiveStreamSelectionMenu(channel: channel, format: "webm", formatName: "WebM", selections: webm)
                            }
                            if let mp4 = liveStreamConfig.mp4, !mp4.isEmpty {
                                LiveStreamSelectionMenu(channel: channel, format: "mp4", formatName: "MP4", selections: mp4)
                            }
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
                    ContentUnavailableView("Unknown error", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
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
                guard let liveStreamConfig = try await appState.client.api.getConfig().ok.body.json.streamConfig.live?.ts else {
                    loadingState = .error(Text("Failed to load live stream config"))
                    return
                }
                self.liveStreamConfig = liveStreamConfig
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
