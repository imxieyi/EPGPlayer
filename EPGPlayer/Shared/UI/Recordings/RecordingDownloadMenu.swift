//
//  RecordingDownloadMenu.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/11.
//

import SwiftUI
import SwiftData
import OpenAPIRuntime
import VLCKit
import UserNotifications

public struct RecordingDownloadMenu: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    let item: RecordedItem
    
    @Query var localRecorded: [LocalRecordedItem]
    @Query var storedItem: [LocalRecordedItem]
    
    init(item: RecordedItem) {
        self.item = item
        let epgId = item.epgId
        _storedItem = Query(filter: #Predicate {
            $0.epgId == epgId
        })
    }
    
    public var body: some View {
        if let videoFiles = (item as? Components.Schemas.RecordedItem)?.videoFiles {
            Menu {
                if videoFiles.contains(where: { $0._type == .ts }) {
                    Section("TS") {
                        ForEach(videoFiles.filter({ $0._type == .ts })) { videoFile in
                            Button {
                                startDownloding(videoFile: videoFile)
                            } label: {
                                Text(verbatim: videoFile.name)
                                Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
                            }
                            .disabled(storedItem.contains(where: { $0.videoItems.contains(where: { $0.epgId == videoFile.epgId }) }))
                        }
                    }
                }
                if videoFiles.contains(where: { $0._type == .encoded }) {
                    Section("Encoded") {
                        ForEach(videoFiles.filter({ $0._type == .encoded })) { videoFile in
                            Button {
                                startDownloding(videoFile: videoFile)
                            } label: {
                                Text(verbatim: videoFile.name)
                                Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
                            }
                            .disabled(storedItem.contains(where: { $0.videoItems.contains(where: { $0.epgId == videoFile.epgId }) }))
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
                if item._videoItems.contains(where: { $0.type == .ts }) {
                    Section("TS") {
                        ForEach(item._videoItems.filter({ $0.type == .ts })) { videoItem in
                            Button {
                                deleteDownloaded(videoItem: videoItem)
                            } label: {
                                Text(verbatim: videoItem.name)
                                Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                            }
                        }
                    }
                }
                if item._videoItems.contains(where: { $0.type == .encoded }) {
                    Section("Encoded") {
                        ForEach(item._videoItems.filter({ $0.type == .encoded })) { videoItem in
                            Button {
                                deleteDownloaded(videoItem: videoItem)
                            } label: {
                                Text(verbatim: videoItem.name)
                                Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                            }
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
        } else {
            EmptyView()
        }
    }
    
    fileprivate func startDownloding(videoFile: Components.Schemas.VideoFile) {
        let existingItem = localRecorded.first { $0.epgId == item.epgId }
        guard existingItem == nil || !existingItem!.videoItems.contains(where: { $0.epgId == videoFile.epgId }) else {
            return
        }
        Task(priority: .background) {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                print("Notification authorization granted: \(granted)")
            } catch let error {
                print("Failed to aquire notification authorization: \(error.localizedDescription)")
            }
        }
        Task(priority: .background) {
            let localVideoFile = LocalFile()
            let videoItem = LocalVideoItem(epgId: videoFile.epgId, name: videoFile.name, type: videoFile.type, fileSize: videoFile.fileSize, duration: nil, originalUrl: videoFile.url, recordedItem: nil, file: localVideoFile)
            
            let recordItem: LocalRecordedItem
            if let existingItem {
                existingItem._videoItems.append(videoItem)
                recordItem = existingItem
            } else {
                var thumbnailFile: LocalFile? = nil
                thumbnailFetch: if let thumbnail = item.thumbnail {
                    let configuration = URLSessionConfiguration.default
                    configuration.urlCache = .imageCache
                    configuration.httpAdditionalHeaders = appState.client.headers
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
                recordItem = LocalRecordedItem(serverId: appState.serverId, epgId: item.epgId, name: item.name, channelName: item.channelName, startTime: item.startTime, endTime: item.endTime, shortDesc: item.shortDesc, extendedDesc: item.extendedDesc, thumbnail: thumbnailFile)
                context.insert(recordItem)
                recordItem._videoItems = [videoItem]
            }
            videoItem.recordedItem = recordItem
            
            do {
                videoItem.duration = try await appState.client.api.getVideosVideoFileIdDuration(Operations.GetVideosVideoFileIdDuration.Input(path: Operations.GetVideosVideoFileIdDuration.Input.Path(videoFileId: videoFile.epgId))).ok.body.json.duration
            } catch let error {
                print("Failed to get video length: \(error.localizedDescription)")
            }
            
            guard let downloadTask = DownloadManager.shared.startDownloading(url: videoFile.url, expectedBytes: videoFile.fileSize, headers: appState.client.headers) else {
                print("Failed to start download")
                return
            }
            
            appState.activeDownloads.append(ActiveDownload(url: videoFile.url, videoItem: videoItem, downloadTask: downloadTask))
        }
    }
    
    fileprivate func deleteDownloaded(videoItem: LocalVideoItem) {
        guard let recordedItem = videoItem.recordedItem else {
            fatalError("videoItem.recordedItem should not be nil")
        }
        recordedItem._videoItems.removeAll(where: { $0 == videoItem })
        appState.activeDownloads.removeAll { $0.videoItem == videoItem }
        context.delete(videoItem)
        if recordedItem.videoItems.isEmpty {
            context.delete(recordedItem)
            dismiss()
        }
    }
}
