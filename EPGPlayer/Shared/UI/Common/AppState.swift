//
//  AppState.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import KeychainSwift
import OpenAPIRuntime

@Observable
final class AppState {
    var client = EPGClient()
    
    var serverVersion: String = ""
    var serverId: String { client.endpoint.absoluteString }
    
    var isAuthenticating = false
    var clientState: ClientState = .notInitialized
    var authType: AuthType = .redirect
    var clientError: Text? = nil
    
    var playingItem: PlayerItem? = nil
    
    var downloadsSetupError: Error? = nil
    
    var activeDownloads: [ActiveDownload] = []
    
    var keychain: KeychainSwift! = nil
    
    #if os(macOS)
    let isOnMac = true
    #else
    let isOnMac = false
    #endif
}

struct SearchQuery: Equatable {
    let keyword: String
    let channel: SearchChannel?
    
    func apiQuery(offset: Int? = nil) -> Operations.GetRecorded.Input.Query {
        return Operations.GetRecorded.Input.Query(isHalfWidth: true, offset: offset, channelId: channel?.channelId, keyword: keyword)
    }
}

struct SearchChannel: Hashable, Identifiable {
    let name: String
    let channelId: Int?
    
    var id: String {
        if let channelId {
            "\(channelId)"
        } else {
            name
        }
    }
}

enum ClientState {
    case notInitialized
    case initialized
    case authNeeded
    case setupNeeded
    case error
}

enum AuthType {
    case redirect
    case basicAuth
    case unknown(String)
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
