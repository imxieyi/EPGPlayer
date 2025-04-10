//
//  LocalVideo.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/10.
//

import Foundation
import OpenAPIRuntime

struct LocalVideo: Identifiable {
    let id: String
    let thumbnail: URL?
    let item: Components.Schemas.RecordedItem
    let videoFiles: [Components.Schemas.VideoFile]
    
    init(thumbnail: URL?, item: Components.Schemas.RecordedItem, videoFiles: [Components.Schemas.VideoFile]) {
        self.thumbnail = thumbnail
        self.item = item
        self.videoFiles = videoFiles.sorted(by: { $1._type != .ts })
        var id = "\(item.id)"
        videoFiles.forEach { videoFile in
            id += "-\(videoFile.id)"
        }
        self.id = id
    }
}
