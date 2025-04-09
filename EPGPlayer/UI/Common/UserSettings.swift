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
    @AppStorage("enable_subtitle") var enableSubtitle = true
    @AppStorage("force_landscape") var forceLandscape = true
    
    func reset() {
        serverUrl = ""
    }
}
