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
                    HStack {
                        ForEach(videoFiles) { videoFile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(verbatim: videoFile._type.rawValue)
                                        .font(.headline)
                                    Text(verbatim: videoFile.name)
                                        .font(.subheadline)
                                    Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
                                        .font(.subheadline)
                                }
                                VStack(alignment: .leading) {
                                    Button {
                                        appState.playingItem = PlayerItem(title: item.name, url: appState.client.endpoint.appending(path: "videos/\(videoFile.id)"))
                                    } label: {
                                        Text("Play")
                                    }
                                }
                            }
                            if videoFile != videoFiles.last {
                                Divider()
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
