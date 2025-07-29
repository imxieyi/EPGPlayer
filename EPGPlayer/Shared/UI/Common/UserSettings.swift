//
//  UserSettings.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

@MainActor
class UserSettings: ObservableObject {
    
    // Server Settings
    @AppStorage("server_url") var serverUrl: String = ""
    
    // Player Settings
    @AppStorage("enable_subtitles") var enableSubtitles = false
    @AppStorage("force_stroke_text") var forceStrokeText = false
    @AppStorage("force_16_9") var force16To9 = false
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
    
    func reset() {
        serverUrl = ""
        enableSubtitles = true
        forceLandscape = false
        showPlayerStats = false
        inactiveTimer = 5
    }
}
