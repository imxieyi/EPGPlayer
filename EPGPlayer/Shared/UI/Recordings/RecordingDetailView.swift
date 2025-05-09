//
//  RecordingDetailView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import SwiftData
import OpenAPIRuntime
import CachedAsyncImage
import VLCKit

struct RecordingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow // Add environment for opening windows
    #endif
    
    var item: RecordedItem
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .center) {
                if let thumbnail = item.thumbnail {
                    AsyncImageWithHeaders(url: thumbnail, headers: appState.client.headers) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 500)
                        } else if phase.error != nil {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 50))
                                .foregroundStyle(.placeholder)
                        } else {
                            ProgressView()
                                #if !os(tvOS)
                                .controlSize(.large)
                                #endif
                        }
                    }
                }
                Text(verbatim: item.name)
                    .font(.headline)
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
                if let channelName = item.channelName {
                    Text(verbatim: channelName)
                        .font(.subheadline)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                }
                Text(verbatim: item.startTime.formatted(RecordingCell.startDateFormatStyle)
                     + " ~ "
                     + item.endTime.formatted(RecordingCell.endDateFormatStyle)
                     + " (\(Int(item.endTime.timeIntervalSinceReferenceDate - item.startTime.timeIntervalSinceReferenceDate) / 60)分)")
                    .font(.subheadline)
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
                if !item.videoItems.isEmpty {
                    Divider()
                    HStack(alignment: .center, spacing: 20) {
                        Menu {
                            if item.videoItems.contains(where: { $0.type == .ts }) {
                                Section("TS") {
                                    ForEach(item.videoItems.filter({ $0.type == .ts }), id: \.epgId) { videoItem in
                                        Button {
                                            appState.playingItem = PlayerItem(videoItem: videoItem, title: item.name)
                                            #if os(macOS)
                                            openWindow(id: "player-window")
                                            #endif
                                        } label: {
                                            Text(verbatim: videoItem.name)
                                            Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                                        }
                                        .disabled(!videoItem.canPlay)
                                    }
                                }
                            }
                            if item.videoItems.contains(where: { $0.type == .encoded }) {
                                Section("Encoded") {
                                    ForEach(item.videoItems.filter({ $0.type == .encoded }), id: \.epgId) { videoItem in
                                        Button {
                                            appState.playingItem = PlayerItem(videoItem: videoItem, title: item.name)
                                            #if os(macOS)
                                            openWindow(id: "player-window")
                                            #endif
                                        } label: {
                                            Text(verbatim: videoItem.name)
                                            Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                                        }
                                        .disabled(!videoItem.canPlay)
                                    }
                                }
                            }
                        } label: {
                            HStack(alignment: .center) {
                                Image(systemName: "play")
                                    .font(.system(size: 25))
                                Text("Play")
                            }
                        }
                        #if !os(tvOS)
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        #endif
                        
                        #if !os(tvOS)
                        RecordingDownloadMenu(item: item)
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                        #endif
                    }
                }
                
                if let shortDesc = item.shortDesc {
                    Divider()
                    Text(LocalizedStringKey(shortDesc))
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let extendedDesc = item.extendedDesc {
                    Divider()
                    Text(LocalizedStringKey(extendedDesc))
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                    .frame(height: 10)
            }
        }
        .navigationTitle(item.name)
    }
}

extension Components.Schemas.VideoFile: Identifiable {
    
}
