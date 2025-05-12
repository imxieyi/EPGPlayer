//
//  LiveChannelsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/12.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import CachedAsyncImage
import OpenAPIRuntime

struct LiveChannelsView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    @Binding var activeTab: TabSelection
    
    @State var loadingState = LoadingState.loading
    @State var loadingMoreState = LoadingState.loaded
    
    @State var liveStreamConfig: Components.Schemas.Config.StreamConfigPayload.LivePayload.TsPayload? = nil
    @State var channels: [Components.Schemas.ChannelItem] = []
    
    var body: some View {
        NavigationStack {
            ClientContentView(activeTab: $activeTab, loadingState: $loadingState) { waitTime in
                refresh(waitTime: waitTime)
            } content: {
                if let liveStreamConfig {
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
                                AsyncImageWithHeaders(url: appState.client.endpoint.appending(path: "channels/\(channel.id)/logo"), headers: appState.client.headers) { phase in
                                    if let image = phase.image {
                                        #if DEBUG
                                        if userSettings.demoMode {
                                            Image(systemName: "inset.filled.tv")
                                        } else {
                                            image
                                                .resizable()
                                                .scaledToFit()
                                        }
                                        #else
                                        image
                                            .resizable()
                                            .scaledToFit()
                                        #endif
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
                        #if !os(tvOS)
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        #endif
                        .tint(.primary)
                    }
                    .refreshable {
                        refresh()
                    }
                } else {
                    ContentUnavailableView("Failed to load live stream config", systemImage: "exclamationmark.triangle")
                }
            }
            #if os(macOS)
            .toolbar(content: {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            })
            #endif
            #if !os(tvOS)
            .navigationTitle("Live")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #endif
        }
        .onAppear {
            if channels.isEmpty || liveStreamConfig == nil {
                refresh()
            }
        }
    }
    
    func refresh(waitTime: Duration = .zero) {
        guard appState.clientState == .initialized else {
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
                channels = try await appState.client.api.getChannels().ok.body.json
                loadingState = .loaded
                Logger.info("Loaded \(channels.count) channels")
            } catch let error {
                Logger.error("Failed to load recordings: \(error)")
                loadingState = .error(Text(verbatim: error.localizedDescription))
            }
        }
    }
}

extension Components.Schemas.ChannelItem: Identifiable {
    
}
