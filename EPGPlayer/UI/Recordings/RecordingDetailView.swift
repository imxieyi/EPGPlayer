//
//  RecordingDetailView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import SwiftUI
import OpenAPIRuntime
import CachedAsyncImage

struct RecordingDetailView: View {
    @Environment(AppState.self) private var appState
    
    let item: Components.Schemas.RecordedItem
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .center) {
                if let thumbnailId = item.thumbnails?.first {
                    CachedAsyncImage(url: appState.client.endpoint.appending(path: "thumbnails/\(thumbnailId)"), urlCache: .imageCache) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 500)
                    } placeholder: {
                        ProgressView()
                    }
                }
                Text(verbatim: item.name)
                    .font(.headline)
                if let channelId = item.channelId {
                    Text(verbatim: appState.channelMap[channelId]?.name ?? "\(channelId)")
                        .font(.subheadline)
                }
                Text(verbatim: Date(timeIntervalSince1970: TimeInterval(item.startAt) / 1000).formatted(RecordingCell.startDateFormatStyle)
                     + " ~ "
                     + Date(timeIntervalSince1970: TimeInterval(item.endAt) / 1000).formatted(RecordingCell.endDateFormatStyle)
                     + " (\((item.endAt - item.startAt) / 60000)分)")
                    .font(.subheadline)
                if let videoFiles = item.videoFiles, !videoFiles.isEmpty {
                    Divider()
                    HStack(alignment: .center, spacing: 20) {
                        Menu {
                            Section("TS") {
                                ForEach(videoFiles.filter({ $0._type == .ts })) { videoFile in
                                    Button {
                                        appState.playingItem = PlayerItem(id: videoFile.id, title: item.name)
                                    } label: {
                                        Text(verbatim: videoFile.name)
                                        Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
                                    }
                                }
                            }
                            Section("Encoded") {
                                ForEach(videoFiles.filter({ $0._type == .encoded })) { videoFile in
                                    Button {
                                        appState.playingItem = PlayerItem(id: videoFile.id, title: item.name)
                                    } label: {
                                        Text(verbatim: videoFile.name)
                                        Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
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
                        
                        Menu {
                            Section("TS") {
                                ForEach(videoFiles.filter({ $0._type == .ts })) { videoFile in
                                    Button {
                                    } label: {
                                        Text(verbatim: videoFile.name)
                                        Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
                                    }
                                }
                            }
                            Section("Encoded") {
                                ForEach(videoFiles.filter({ $0._type == .encoded })) { videoFile in
                                    Button {
                                    } label: {
                                        Text(verbatim: videoFile.name)
                                        Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
                                    }
                                }
                            }
                        } label: {
                            HStack(alignment: .center) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 25))
                                Text("Download")
                            }
                        }
                    }
                }
                
                if let description = item.description {
                    Divider()
                    Text(LocalizedStringKey(description))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let extended = item.extended {
                    Divider()
                    Text(LocalizedStringKey(extended))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Detail")
    }
}

extension Components.Schemas.VideoFile: Identifiable {
    
}
