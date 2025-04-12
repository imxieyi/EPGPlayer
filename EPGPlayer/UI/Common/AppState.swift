//
//  AppState.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import SwiftUI
import OpenAPIRuntime

@Observable
final class AppState {
    var client = EPGClient()
    
    var serverVersion: String = ""
    var serverError = Text(verbatim: "")
    
    var isAuthenticating = false
    var clientState: ClientState = .notInitialized
    
    var playingItem: PlayerItem? = nil
    
    var downloadsSetupError: Error? = nil
    
    var activeDownloads: [ActiveDownload] = []
    
    let isOnMac: Bool = ProcessInfo().isiOSAppOnMac
}

enum ClientState {
    case notInitialized
    case initialized
    case authNeeded
    case setupNeeded
}

class PlayerItem: Identifiable {
    var id: any VideoItem { videoItem }

    let videoItem: any VideoItem
    let title: String
    
    init(videoItem: any VideoItem, title: String) {
        self.videoItem = videoItem
        self.title = title
    }
}

struct ActiveDownload: Identifiable, Equatable {
    let url: URL
    let videoItem: LocalVideoItem
    let downloadTask: URLSessionDownloadTask
    var progress: Double = 0
    var errorMessage: String?
    
    var id: URL { url }
    
    static func ==(a: ActiveDownload, b: ActiveDownload) -> Bool {
        return a.url == b.url
    }
}
