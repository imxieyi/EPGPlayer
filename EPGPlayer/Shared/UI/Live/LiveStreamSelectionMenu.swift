//
//  LiveStreamSelectionMenu.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/13.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import OpenAPIRuntime

struct LiveStreamSelectionMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow // Add environment for opening windows
    
    let channel: Components.Schemas.ChannelItem
    let format: String
    let formatName: String
    let selections: [String]
    
    var body: some View {
        Menu {
            ForEach(0..<selections.count, id: \.self) { index in
                Button {
                    let playableItem = PlayerItem(videoItem: EPGLiveStreamItem(channel: channel, format: format, mode: index), title: channel.name)
                    // Set the playing item in appState. The player window observes this.
                    appState.playingItem = playableItem
                    #if os(macOS)
                    // Open/focus the single player window.
                    openWindow(id: "player-window")
                    #endif
                    // On iOS, setting playingItem triggers the .fullScreenCover
                } label: {
                    Text(verbatim: selections[index])
                }
            }
        } label: {
            Label(formatName, systemImage: "dot.radiowaves.left.and.right")
        }
    }
}
