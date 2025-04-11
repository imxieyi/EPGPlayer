//
//  AbstractModel.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/11.
//

import Foundation

protocol RecordedItem {
    var epgId: Int { get }
    var name: String { get }
    @MainActor var channelName: String? { get }
    var startTime: Date { get }
    var endTime: Date { get }
    var shortDesc: String? { get }
    var extendedDesc: String? { get }
    @MainActor var thumbnail: URL? { get }
    var videoItems: [any VideoItem] { get }
}

protocol VideoItem {
    var epgId: Int { get }
    var name: String { get }
    var type: VideoFileType { get }
    var fileSize: Int64 { get }
    @MainActor var url: URL { get }
}

enum VideoFileType: Codable {
    case ts
    case encoded
}
