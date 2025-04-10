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
    
    var channelMap: [Int : Components.Schemas.ChannelItem] = [:]
    
    var downloads: [LocalVideo] = []
    
    let isOnMac: Bool = ProcessInfo().isiOSAppOnMac
}

enum ClientState {
    case notInitialized
    case initialized
    case authNeeded
    case setupNeeded
}

struct PlayerItem: Identifiable {
    let id: Int
    let title: String
}
