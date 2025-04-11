//
//  UserSettings.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//

import SwiftUI

@MainActor
class UserSettings: ObservableObject {
    
    // Server Settings
    @AppStorage("server_url") var serverUrl: String = ""
    
    // Player Settings
    @AppStorage("enable_subtitles") var enableSubtitles = true
    @AppStorage("force_landscape") var forceLandscape = true
    @AppStorage("show_player_stats") var showPlayerStats = false
    @AppStorage("inactive_timer") var inactiveTimer = 5
    
    func reset() {
        serverUrl = ""
        enableSubtitles = true
        forceLandscape = true
        showPlayerStats = false
        inactiveTimer = 5
    }
}
