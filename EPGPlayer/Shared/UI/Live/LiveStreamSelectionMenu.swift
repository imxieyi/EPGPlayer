//
//  LiveStreamSelectionMenu.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/13.
//

import SwiftUI
import OpenAPIRuntime

struct LiveStreamSelectionMenu: View {
    @Environment(AppState.self) private var appState
    
    let channel: Components.Schemas.ChannelItem
    let format: String
    let formatName: String
    let selections: [String]
    
    var body: some View {
        Menu {
            ForEach(0..<selections.count, id: \.self) { index in
                Button {
                    appState.playingItem = PlayerItem(videoItem: EPGLiveStreamItem(channel: channel, format: format, mode: index), title: channel.name)
                } label: {
                    Text(verbatim: selections[index])
                }
            }
        } label: {
            Label(formatName, systemImage: "dot.radiowaves.left.and.right")
        }
    }
}
