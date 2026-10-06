//
//  PlayerProgressControl.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/03.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import VLCKit

struct PlayerProgressControl: View {
    @Environment(AppState.self) private var appState
    
    let item: PlayerItem
    
    @Binding var playerState: VLCMediaPlayerState
    @Binding var hadErrorState: Bool
    @Binding var hadPlayingState: Bool
    @Binding var loadedPlaybackPosition: Bool
    @Binding var playbackPosition: Double
    @StateObject var playerEvents: PlayerEvents
    
    @State var videoLength: Double? = nil
    
    @State var playbackTime: Double = 0
    
    @State var isSeeking = false
    #if os(tvOS)
    @Binding var isScrubbing: Bool
    #endif
    
    var body: some View {
        VStack {
            if item.videoItem.type != .livestream {
                Spacer()
                    .frame(height: 5)
                
                #if !os(tvOS)
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
                .disabled(playerState == .opening || !hadPlayingState)
                #else
                TVOSScrubber(position: playbackPosition, isActive: isScrubbing)
                #endif
            } else {
                Spacer()
                    .frame(height: 10)
            }
            
            ZStack (alignment: .top) {
                if item.videoItem.type != .livestream {
                    HStack {
                        if isSeeking || (loadedPlaybackPosition && !(item.videoItem is LocalVideoItem)), let videoLength {
                            Text(verbatim: Duration.seconds(playbackPosition * videoLength).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                        } else {
                            Text(verbatim: Duration.seconds(playbackTime).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                        }
                        Spacer()
                        if let videoLength {
                            Text(verbatim: Duration.seconds(videoLength).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                        }
                    }
                }
                
                #if !os(tvOS)
                HStack {
                    Spacer()
                    if playerState == .opening || (!hadPlayingState && !hadErrorState) {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        if item.videoItem.type != .livestream {
                            Button {
                                seekBy(seconds: -10)
                            } label: {
                                Image(systemName: "10.arrow.trianglehead.counterclockwise")
                                    .font(.system(size: 25))
                            }
                            .buttonStyle(.borderless)
                            .keyboardShortcut(.leftArrow, modifiers: [])
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
                            .buttonStyle(.borderless)
                            .keyboardShortcut(.space, modifiers: [])
                            
                            Spacer()
                                .frame(width: 15)
                            
                            Button {
                                seekBy(seconds: 30)
                            } label: {
                                Image(systemName: "30.arrow.trianglehead.clockwise")
                                    .font(.system(size: 25))
                            }
                            .buttonStyle(.borderless)
                            .keyboardShortcut(.rightArrow, modifiers: [])
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
                            .buttonStyle(.borderless)
                            .keyboardShortcut(.space, modifiers: [])
                        }
                    }
                    Spacer()
                }
                .disabled(isSeeking)
                #else
                if playerState == .opening || (!hadPlayingState && !hadErrorState) {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                #endif
            }
        }
        .onAppear {
            reload()
        }
        .onChange(of: item.id, { oldValue, newValue in
            guard oldValue != newValue else {
                return
            }
            reload()
        })
        .onReceive(playerEvents.updatePosition) { position in
            guard !isSeeking else {
                return
            }
            playbackPosition = position.position
            playbackTime = Double(position.time) / 1000
        }
        #if os(tvOS)
        .onChange(of: isScrubbing) { _, scrubbing in
            isSeeking = scrubbing
        }
        .onReceive(playerEvents.seekBy) { seconds in
            seekBy(seconds: seconds)
        }
        #endif
        .onReceive(playerEvents.resetPlayer) {
            videoLength = nil
            playbackTime = 0
        }
    }

    func reload() {
        if let item = item.videoItem as? Components.Schemas.VideoFile {
            Task {
                do {
                    videoLength = try await appState.client.api.getVideosVideoFileIdDuration(Operations.GetVideosVideoFileIdDuration.Input(path: Operations.GetVideosVideoFileIdDuration.Input.Path(videoFileId: item.id))).ok.body.json.duration
                } catch let error {
                    Logger.error("Failed to get video length: \(error)")
                }
            }
            return
        }
        if let item = item.videoItem as? LocalVideoItem, let duration = item.duration {
            videoLength = duration
        }
    }
    
    func seekBy(seconds: Double) {
        guard let videoLength, videoLength > 0 else {
            return
        }
        #if os(tvOS)
        let newPosition = min(max(playbackPosition + seconds / videoLength, 0), 1)
        #else
        let fakeLength = playbackTime / playbackPosition
        let diff = seconds / videoLength / videoLength * fakeLength
        let newPosition = min(max(diff + playbackPosition, 0), 1)
        #endif
        playerEvents.setPlaybackPosition.send(newPosition)
    }
}

#if os(tvOS)
/// SwiftUI's `Slider` is unavailable on tvOS. This is a pure display component;
/// Select/swipe are handled by PlayerView (see `handleSelect`/`onMoveCommand`),
/// which owns `playbackPosition` and `isScrubbing` directly, instead of tvOS
/// focus ever moving onto this view.
private struct TVOSScrubber: View {
    let position: Double
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 8)
                Capsule()
                    .fill(Color.white)
                    .frame(width: proxy.size.width * position, height: 8)
                Circle()
                    .fill(Color.white)
                    .frame(width: isActive ? 22 : 14, height: isActive ? 22 : 14)
                    .offset(x: proxy.size.width * position - (isActive ? 11 : 7))
                    .animation(.easeOut(duration: 0.15), value: isActive)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 44)
    }
}
#endif
