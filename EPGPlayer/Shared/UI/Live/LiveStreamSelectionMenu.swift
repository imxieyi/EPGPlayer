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
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow // Add environment for opening windows
    #endif
    
    let channel: Components.Schemas.ScheduleChannleItem
    let program: Components.Schemas.ScheduleProgramItem?
    let format: String
    let formatName: String
    let selections: [String]
    
    var body: some View {
        Menu {
            ForEach(0..<selections.count, id: \.self) { index in
                Button {
                    #if os(tvOS)
                    let playableItem = PlayerItem(
                        videoItem: EPGLiveStreamItem(channel: channel, format: format, mode: index, audioComponentType: program?.audioComponentType),
                        title: program?.name ?? channel.name,
                        subtitle: channel.name,
                        programDescription: [program?.description, program?.extended].compactMap { $0 }.joined(separator: "\n\n"),
                        program: program?.subtitleProgramInfo, programEnd: program?.endDate
                    )
                    #else
                    let playableItem = PlayerItem(videoItem: EPGLiveStreamItem(channel: channel, format: format, mode: index, audioComponentType: program?.audioComponentType),
                                                  title: channel.name, program: program?.subtitleProgramInfo, programEnd: program?.endDate)
                    #endif
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
