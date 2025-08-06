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
