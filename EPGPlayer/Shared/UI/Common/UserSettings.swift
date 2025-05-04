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
    @AppStorage("force_landscape") var forceLandscape = false
    @AppStorage("show_player_stats") var showPlayerStats = false
    @AppStorage("inactive_timer") var inactiveTimer = 5
    
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
