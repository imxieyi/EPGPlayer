//
//  SwiftDataModel.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/11.
//

import Foundation
import SwiftData

@Model
class LocalRecordedItem: RecordedItem {
    @Attribute(.unique) var id: UUID
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
    
    init(epgId: Int, name: String, channelName: String?, startTime: Date, endTime: Date, shortDesc: String?, extendedDesc: String?, thumbnail: LocalFile?, videoItems: [LocalVideoItem]) {
        self.id = UUID()
        self.epgId = epgId
        self.name = name
        self._channelName = channelName
        self.startTime = startTime
        self.endTime = endTime
        self.shortDesc = shortDesc
        self.extendedDesc = extendedDesc
        self._thumbnail = thumbnail
        self._videoItems = videoItems
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
    @Relationship(deleteRule: .cascade) var file: LocalFile
    
    @MainActor var url: URL { file.url }
    init(epgId: Int, name: String, type: VideoFileType, fileSize: Int64, duration: Double?, file: LocalFile) {
        self.id = UUID()
        self.epgId = epgId
        self.name = name
        self.type = type
        self.fileSize = fileSize
        self.duration = duration
        self.file = file
    }
}

@Model
class LocalFile {
    @Attribute(.unique) var id: UUID
    var available: Bool
    
    @MainActor var url: URL {
        LocalFileManager.shared.filesDir.appending(path: id.uuidString)
    }
    
    init() {
        self.id = UUID()
        self.available = false
    }
}
