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
    var rule: SearchRule? = nil
    
    func apiQuery(offset: Int? = nil) -> Operations.GetRecorded.Input.Query {
        return Operations.GetRecorded.Input.Query(isHalfWidth: true, offset: offset, ruleId: rule?.id, channelId: channel?.channelId, keyword: keyword)
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

/// A recording rule, offered as a search filter by its keyword (e.g. "search recordings
/// that were recorded because they matched this rule").
struct SearchRule: Hashable, Identifiable {
    let id: Int
    let keyword: String
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
    let subtitle: String?
    let programDescription: String?
    /// The program that is played, which helps translating its subtitles.
    let program: SubtitleProgramInfo?
    /// When the program of a live stream ends and the channel moves on to the next one.
    let programEnd: Date?

    init(videoItem: any VideoItem, title: String, subtitle: String? = nil, programDescription: String? = nil, program: SubtitleProgramInfo? = nil, programEnd: Date? = nil) {
        self.videoItem = videoItem
        self.title = title
        self.subtitle = subtitle
        self.programDescription = programDescription
        self.program = program
        self.programEnd = programEnd
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
