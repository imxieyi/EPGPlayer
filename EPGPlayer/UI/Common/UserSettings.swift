//
//  UserSettings.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//

import SwiftUI

@MainActor
class UserSettings: ObservableObject {
    @AppStorage("server_url") var serverUrl: String = ""
    
    func reset() {
        serverUrl = ""
    }
}
