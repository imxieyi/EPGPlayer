//
//  EPGModel.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/11.
//

import Foundation
import OpenAPIRuntime

extension Components.Schemas.RecordedItem: RecordedItem {
    @MainActor static var channelMap: [Int : Components.Schemas.ChannelItem] = [:]
    @MainActor static var endpoint: URL! = nil
    
    var epgId: Int {
        id
    }
    
    @MainActor var channelName: String? {
        if let channelId {
            Components.Schemas.RecordedItem.channelMap[channelId]?.name ?? "\(channelId)"
        } else {
            nil
        }
    }
    
    var startTime: Date {
        Date(timeIntervalSince1970: TimeInterval(startAt) / 1000)
    }
    
    var endTime: Date {
        Date(timeIntervalSince1970: TimeInterval(endAt) / 1000)
    }
    
    var shortDesc: String? {
        description
    }
    
    var extendedDesc: String? {
        extended
    }
    
    var thumbnail: URL? {
        if let thumbnailId = thumbnails?.first {
            Components.Schemas.RecordedItem.endpoint.appending(path: "thumbnails/\(thumbnailId)")
        } else {
            nil
        }
    }
    
    var videoItems: [any VideoItem] {
        videoFiles ?? []
    }
}

extension Components.Schemas.VideoFile: VideoItem {
    var epgId: Int {
        id
    }
    
    var type: VideoFileType {
        switch _type {
        case .ts:
            return .ts
        case .encoded:
            return .encoded
        }
    }
    
    var fileSize: Int64 {
        Int64(size)
    }
    
    var url: URL {
        Components.Schemas.RecordedItem.endpoint.appending(path: "videos/\(id)")
    }
    
}
