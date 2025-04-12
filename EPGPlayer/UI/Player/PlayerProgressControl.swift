//
//  PlayerProgressControl.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/03.
//

import os
import SwiftUI
import VLCKit

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EPGPlayer", category: "player")

struct PlayerProgressControl: View {
    @Environment(AppState.self) private var appState
    
    let item: PlayerItem
    
    @Binding var playerState: VLCMediaPlayerState
    @StateObject var playerEvents: PlayerEvents
    
    @State var videoLength: Double? = nil
    
    @State var playbackPosition: Double = 0
    @State var playbackTime: Double = 0
    
    @State var isSeeking = false
    
    var body: some View {
        VStack {
            Spacer()
                .frame(height: 5)
            
            if item.videoItem.type != .livestream {
                Slider(value: $playbackPosition, onEditingChanged: { editing in
                    isSeeking = editing
                    if editing && playerState.isPlaying {
                        playerEvents.togglePlay.send()
                    }
                    if !editing {
                        playerEvents.setPlaybackPosition.send(playbackPosition)
                        if !playerState.isPlaying {
                            playerEvents.togglePlay.send()
                        }
                    }
                })
                .disabled(playerState == .opening)
            }
            
            ZStack (alignment: .top) {
                if item.videoItem.type != .livestream {
                    HStack {
                        Text(verbatim: Duration.seconds(playbackTime).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                        Spacer()
                        if let videoLength {
                            Text(verbatim: Duration.seconds(videoLength).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                        }
                    }
                }
                
                HStack {
                    Spacer()
                    if playerState == .opening {
                        ProgressView()
                    } else {
                        if item.videoItem.type != .livestream {
                            Button {
                                seekBy(seconds: -10)
                            } label: {
                                Image(systemName: "10.arrow.trianglehead.counterclockwise")
                                    .font(.system(size: 25))
                            }
                            .disabled(videoLength == nil)
                            
                            Spacer()
                                .frame(width: 15)
                            
                            Button {
                                playerEvents.togglePlay.send()
                            } label: {
                                Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                    .scaledToFit()
                            }
                            
                            Spacer()
                                .frame(width: 15)
                            
                            Button {
                                seekBy(seconds: 30)
                            } label: {
                                Image(systemName: "30.arrow.trianglehead.clockwise")
                                    .font(.system(size: 25))
                            }
                            .disabled(videoLength == nil)
                        } else {
                            Button {
                                playerEvents.togglePlay.send()
                            } label: {
                                Image(systemName: playerState.isPlaying ? "stop.fill" : "play.fill")
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                    .scaledToFit()
                            }
                        }
                    }
                    Spacer()
                }
                .disabled(isSeeking)
            }
        }
        .onAppear {
            if let item = item.videoItem as? Components.Schemas.VideoFile {
                Task {
                    do {
                        videoLength = try await appState.client.api.getVideosVideoFileIdDuration(Operations.GetVideosVideoFileIdDuration.Input(path: Operations.GetVideosVideoFileIdDuration.Input.Path(videoFileId: item.id))).ok.body.json.duration
                    } catch let error {
                        logger.error("Failed to get video length: \(error)")
                    }
                }
                return
            }
            if let item = item.videoItem as? LocalVideoItem, let duration = item.duration {
                videoLength = duration
            }
        }
        .onReceive(playerEvents.updatePosition) { position in
            guard !isSeeking else {
                return
            }
            playbackPosition = position.position
            playbackTime = Double(position.time) / 1000
        }
    }
    
    func seekBy(seconds: Double) {
        guard let videoLength else {
            return
        }
        let fakeLength = playbackTime / playbackPosition
        let diff = seconds / videoLength / videoLength * fakeLength
        let newPosition = min(max(diff + playbackPosition, 0), 1)
        playerEvents.setPlaybackPosition.send(newPosition)
    }
}
