//
//  RecordingDetailView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import SwiftUI
import SwiftData
import OpenAPIRuntime
import CachedAsyncImage
import VLCKit

struct RecordingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @Query var localRecorded: [LocalRecordedItem]
    
    var item: RecordedItem
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .center) {
                if let thumbnail = item.thumbnail {
                    CachedAsyncImage(url: thumbnail, urlCache: .imageCache) { image in
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
                    .textSelection(.enabled)
                if let channelName = item.channelName {
                    Text(verbatim: channelName)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                Text(verbatim: item.startTime.formatted(RecordingCell.startDateFormatStyle)
                     + " ~ "
                     + item.endTime.formatted(RecordingCell.endDateFormatStyle)
                     + " (\(Int(item.endTime.timeIntervalSinceReferenceDate - item.startTime.timeIntervalSinceReferenceDate) / 60)分)")
                    .font(.subheadline)
                    .textSelection(.enabled)
                if !item.videoItems.isEmpty {
                    Divider()
                    HStack(alignment: .center, spacing: 20) {
                        Menu {
                            Section("TS") {
                                ForEach(item.videoItems.filter({ $0.type == .ts }), id: \.epgId) { videoItem in
                                    Button {
                                        appState.playingItem = PlayerItem(videoItem: videoItem, title: item.name)
                                    } label: {
                                        Text(verbatim: videoItem.name)
                                        Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                                    }
                                }
                            }
                            Section("Encoded") {
                                ForEach(item.videoItems.filter({ $0.type == .encoded }), id: \.epgId) { videoItem in
                                    Button {
                                        appState.playingItem = PlayerItem(videoItem: videoItem, title: item.name)
                                    } label: {
                                        Text(verbatim: videoItem.name)
                                        Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
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
                        
                        if let videoFiles = (item as? Components.Schemas.RecordedItem)?.videoFiles {
                            Menu {
                                Section("TS") {
                                    ForEach(videoFiles.filter({ $0._type == .ts })) { videoFile in
                                        Button {
                                            startDownloding(videoFile: videoFile)
                                        } label: {
                                            Text(verbatim: videoFile.name)
                                            Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
                                        }
                                    }
                                }
                                Section("Encoded") {
                                    ForEach(videoFiles.filter({ $0._type == .encoded })) { videoFile in
                                        Button {
                                            startDownloding(videoFile: videoFile)
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
                        } else if let item = item as? LocalRecordedItem {
                            Menu {
                                Section("TS") {
                                    ForEach(item._videoItems.filter({ $0.type == .ts })) { videoItem in
                                        Button {
                                            deleteDownloaded(item: item, videoItem: videoItem)
                                        } label: {
                                            Text(verbatim: videoItem.name)
                                            Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                                        }
                                    }
                                }
                                Section("Encoded") {
                                    ForEach(item._videoItems.filter({ $0.type == .encoded })) { videoItem in
                                        Button {
                                            deleteDownloaded(item: item, videoItem: videoItem)
                                        } label: {
                                            Text(verbatim: videoItem.name)
                                            Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                                        }
                                    }
                                }
                            } label: {
                                HStack(alignment: .center) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 20))
                                    Text("Delete")
                                }
                            }
                            .tint(.red)
                        }
                    }
                }
                
                if let shortDesc = item.shortDesc {
                    Divider()
                    Text(LocalizedStringKey(shortDesc))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let extendedDesc = item.extendedDesc {
                    Divider()
                    Text(LocalizedStringKey(extendedDesc))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                    .frame(height: 10)
            }
        }
        .navigationTitle("Detail")
    }
    
    fileprivate func startDownloding(videoFile: Components.Schemas.VideoFile) {
        let existingItem = localRecorded.first { $0.epgId == item.epgId }
        guard existingItem == nil || !existingItem!.videoItems.contains(where: { $0.epgId == videoFile.epgId }) else {
            return
        }
        Task(priority: .background) {
            let localVideoFile = LocalFile()
            let videoItem = LocalVideoItem(epgId: videoFile.epgId, name: videoFile.name, type: videoFile.type, fileSize: videoFile.fileSize, duration: nil, file: localVideoFile)
            
            let recordItem: LocalRecordedItem
            if let existingItem {
                existingItem._videoItems.append(videoItem)
                recordItem = existingItem
            } else {
                var thumbnailFile: LocalFile? = nil
                thumbnailFetch: if let thumbnail = item.thumbnail {
                    let configuration = URLSessionConfiguration.default
                    configuration.urlCache = .imageCache
                    do {
                        let (data, response) = try await URLSession(configuration: configuration).data(from: thumbnail)
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                            print("Failed to download thumbnail: HTTP status code: \(httpResponse.statusCode)")
                            break thumbnailFetch
                        }
                        let localFile = LocalFile()
                        try LocalFileManager.shared.saveData(name: localFile.id.uuidString, data: data)
                        localFile.available = true
                        context.insert(localFile)
                        thumbnailFile = localFile
                    } catch let error {
                        print("Failed to download thumbnail: \(error.localizedDescription)")
                    }
                }
                recordItem = LocalRecordedItem(epgId: item.epgId, name: item.name, channelName: item.channelName, startTime: item.startTime, endTime: item.endTime, shortDesc: item.shortDesc, extendedDesc: item.extendedDesc, thumbnail: thumbnailFile, videoItems: [videoItem])
                context.insert(recordItem)
            }
            
            do {
                videoItem.duration = try await appState.client.api.getVideosVideoFileIdDuration(Operations.GetVideosVideoFileIdDuration.Input(path: Operations.GetVideosVideoFileIdDuration.Input.Path(videoFileId: videoFile.epgId))).ok.body.json.duration
            } catch let error {
                print("Failed to get video length: \(error.localizedDescription)")
            }
            
            videoFetch: do {
                let (url, response) = try await URLSession.shared.download(from: videoFile.url, delegate: nil)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("Failed to download video file: HTTP status code: \(httpResponse.statusCode)")
                    break videoFetch
                }
                if videoItem.duration == nil, let media = VLCMedia(url: url) {
                    media.parse(options: .parseLocal)
                    if let length = media.lengthWait(until: .now.advanced(by: 60)).value?.doubleValue {
                        videoItem.duration = length / 1000
                    }
                }
                try LocalFileManager.shared.moveFile(name: localVideoFile.id.uuidString, url: url)
                localVideoFile.available = true
                return
            } catch let error {
                print("Failed to download video file: \(error.localizedDescription)")
            }
            deleteDownloaded(item: recordItem, videoItem: videoItem)
        }
    }
    
    fileprivate func deleteDownloaded(item: LocalRecordedItem, videoItem: LocalVideoItem) {
        item._videoItems.removeAll(where: { $0 == videoItem })
        context.delete(videoItem)
        if item.videoItems.isEmpty {
            context.delete(item)
            dismiss()
        }
    }
}

extension Components.Schemas.VideoFile: Identifiable {
    
}
