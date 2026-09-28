//
//  AbstractModel.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/11.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftUI

protocol RecordedItem {
    var epgId: Int { get }
    var name: String { get }
    @MainActor var channelName: String? { get }
    var startTime: Date { get }
    var endTime: Date { get }
    var shortDesc: String? { get }
    var extendedDesc: String? { get }
    var audioComponentType: Int? { get }
    @MainActor var thumbnail: URL? { get }
    var videoItems: [any VideoItem] { get }
}

protocol VideoItem {
    var epgId: Int { get }
    var name: String { get }
    var type: VideoFileType { get }
    var fileSize: Int64 { get }
    @MainActor var url: URL { get }
    var canPlay: Bool { get }
}

extension VideoItem {
    /// Whether the video is streamed from the server and may be in MPEG-TS, which carries the ARIB captions that live
    /// translation reads. Encoded recordings can be MPEG-TS as well, depending on the settings of the server.
    /// Downloaded videos are translated as a whole instead.
    var supportsLiveTranslation: Bool {
        if let liveStream = self as? EPGLiveStreamItem {
            return liveStream.format.hasPrefix("m2ts")
        }
        return self is Components.Schemas.VideoFile
    }
}

enum VideoFileType: Codable {
    case ts
    case encoded
    case livestream
    
    var text: Text {
        switch self {
        case .ts:
            return Text("TS")
        case .encoded:
            return Text("Encoded")
        case .livestream:
            return Text("Live")
        }
    }
}
