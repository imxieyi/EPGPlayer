//
//  LocalSchemaV3.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/13.
//

import Foundation
import SwiftData

typealias LocalRecordedItem = LocalSchemaV3.LocalRecordedItem
typealias LocalVideoItem = LocalSchemaV3.LocalVideoItem
typealias LocalFile = LocalSchemaV3.LocalFile
typealias SavedPlaybackPosition = LocalSchemaV3.SavedPlaybackPosition

enum LocalSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [LocalRecordedItem.self, LocalVideoItem.self, LocalFile.self, SavedPlaybackPosition.self]
    }
    
    @Model
    class LocalRecordedItem: RecordedItem {
        @Attribute(.unique) var id: UUID
        var serverId: String
        var epgId: Int
        var name: String
        var _channelName: String?
        var startTime: Date
        var endTime: Date
        var shortDesc: String?
        var extendedDesc: String?
        @Relationship(deleteRule: .cascade) var _thumbnail: LocalFile?
        @Relationship(deleteRule: .cascade) var _videoItems: [LocalVideoItem]
        
        @MainActor var channelName: String? { _channelName }
        @MainActor var thumbnail: URL? { _thumbnail?.url }
        var videoItems: [any VideoItem] { _videoItems }
        
        init(serverId: String, epgId: Int, name: String, channelName: String?, startTime: Date, endTime: Date, shortDesc: String?, extendedDesc: String?, thumbnail: LocalFile?) {
            self.serverId = serverId
            self.id = UUID()
            self.epgId = epgId
            self.name = name
            self._channelName = channelName
            self.startTime = startTime
            self.endTime = endTime
            self.shortDesc = shortDesc
            self.extendedDesc = extendedDesc
            self._thumbnail = thumbnail
            self._videoItems = []
        }
    }

    @Model
    class LocalVideoItem: VideoItem, Identifiable {
        @Attribute(.unique) var id: UUID
        var epgId: Int
        var name: String
        var type: VideoFileType
        var fileSize: Int64
        var duration: Double?
        var originalUrl: URL
        var recordedItem: LocalRecordedItem?
        @Relationship(deleteRule: .cascade) var file: LocalFile
        
        @MainActor var url: URL { file.url }
        var canPlay: Bool { file.available }
        
        init(epgId: Int, name: String, type: VideoFileType, fileSize: Int64, duration: Double?, originalUrl: URL, recordedItem: LocalRecordedItem?, file: LocalFile) {
            self.id = UUID()
            self.epgId = epgId
            self.name = name
            self.type = type
            self.fileSize = fileSize
            self.duration = duration
            self.originalUrl = originalUrl
            self.recordedItem = recordedItem
            self.file = file
        }
    }
    
    @Model
    class LocalFile {
        @Attribute(.unique) var id: UUID
        var available: Bool
        var unavailableReason: String?
        
        @MainActor var url: URL {
            LocalFileManager.shared.filesDir.appending(path: id.uuidString)
        }
        
        init() {
            self.id = UUID()
            self.available = false
            self.unavailableReason = nil
        }
    }
    
    @Model
    class SavedPlaybackPosition {
        var serverId: String
        var videoItemEpgId: Int
        var position: Double
        
        init(serverId: String, videoItemEpgId: Int, position: Double) {
            self.serverId = serverId
            self.videoItemEpgId = videoItemEpgId
            self.position = position
        }
    }
}
