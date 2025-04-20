//
//  EPGModel.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/11.
//
//  SPDX-License-Identifier: MPL-2.0

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
    
    var canPlay: Bool {
        true
    }
    
}

struct EPGLiveStreamItem: VideoItem {
    let channel: Components.Schemas.ChannelItem
    let format: String
    let mode: Int
    
    var name: String {
        "\(channel.name) - \(format) - \(mode)"
    }
    
    var epgId: Int {
        channel.id
    }
    
    var type: VideoFileType {
        .livestream
    }
    
    var fileSize: Int64 {
        0
    }
    
    var url: URL {
        Components.Schemas.RecordedItem.endpoint.appending(path: "streams/live/\(channel.id)/\(format)").appending(queryItems: [URLQueryItem(name: "mode", value: "\(mode)")])
    }
    
    var canPlay: Bool {
        true
    }
}
