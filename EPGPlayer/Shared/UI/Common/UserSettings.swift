//
//  UserSettings.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

enum VideoAspectRatio: String, CaseIterable, Identifiable {
    case automatic
    case fillScreen = "fill_screen"
    case sixteenNine = "16:9"
    case sixteenTen = "16:10"
    case square = "1:1"

    var id: Self { self }
    var vlcValue: String? {
        switch self {
        case .automatic, .fillScreen:
            nil
        default:
            rawValue
        }
    }
    var label: String {
        switch self {
        case .automatic:
            String(localized: "Automatic")
        case .fillScreen:
            String(localized: "Fill Screen")
        default:
            rawValue
        }
    }
}

@MainActor
class UserSettings: ObservableObject {

    // Server Settings
    @AppStorage("server_url") var serverUrl: String = ""
    
    // Player Settings
    @AppStorage("enable_subtitles") var enableSubtitles = false
    @AppStorage("force_stroke_text") var forceStrokeText = false
    @AppStorage("video_aspect_ratio") var videoAspectRatio: VideoAspectRatio = .automatic
    @AppStorage("force_landscape") var forceLandscape = false
    @AppStorage("show_player_stats") var showPlayerStats = false
    @AppStorage("inactive_timer") var inactiveTimer = 5
    
    // EPG Settings
    @AppStorage("epg_show_gr") var epgShowGR = true
    @AppStorage("epg_show_bs") var epgShowBS = true
    @AppStorage("epg_show_cs") var epgShowCS = true
    @AppStorage("epg_show_sky") var epgShowSKY = true
    @AppStorage("epg_genres") var epgGenres = Data()
    @AppStorage("epg_notify_time_diff") var epgNotifyTimeDiff: TimeInterval = -600
    
    // Live Settings
    @AppStorage("live_show_gr") var liveShowGR = true
    @AppStorage("live_show_bs") var liveShowBS = true
    @AppStorage("live_show_cs") var liveShowCS = true
    @AppStorage("live_show_sky") var liveShowSKY = true
    
    // Debug Settings
    #if DEBUG
    @Published var demoMode = false
    #endif
    
    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "video_aspect_ratio") == nil && defaults.bool(forKey: "force_16_9") {
            videoAspectRatio = .sixteenNine
        }
    }

    func reset() {
        serverUrl = ""
        enableSubtitles = true
        videoAspectRatio = .automatic
        forceLandscape = false
        showPlayerStats = false
        inactiveTimer = 5
    }
}
