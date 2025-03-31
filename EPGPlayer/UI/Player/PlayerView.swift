//
//  PlayerView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import SwiftUI
import VLCKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userSettings: UserSettings
    
    let item: PlayerItem
    
    let paddingSize: CGFloat = 15
    
    @StateObject var playerEvents = PlayerEvents()
    
    @State var playbackPosition: Double = 0.3
    @State var playbackSpeed: PlaybackSpeed = .x1
    @State var playerState: VLCMediaPlayerState = .opening
    
    @State var activeVideoTrack = MediaTrack(id: "none", name: "video", codec: "")
    @State var videoTracks: [MediaTrack] = []
    @State var activeAudioTrack = MediaTrack(id: "none", name: "audio", codec: "")
    @State var audioTracks: [MediaTrack] = []
    @State var activeTextTrack = MediaTrack(id: "none", name: "text", codec: "")
    @State var textTracks: [MediaTrack] = []
    
    var body: some View {
        ZStack(alignment: .center) {
            VLCPlayer(videoURL: item.url, playerEvents: playerEvents, playerState: $playerState)
                .disabled(true)
            
            if playerState == .opening {
                ProgressView()
            }
            
            VStack {
                VStack {
                    Spacer()
                        .frame(height: paddingSize)
                    
                    HStack {
                        Spacer()
                            .frame(width: paddingSize)
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        
                        Text(verbatim: item.title)
                        
                        Spacer()
                        
                        Menu {
                            Picker(selection: $playbackSpeed) {
                                ForEach(PlaybackSpeed.all) { speed in
                                    Text(verbatim: speed.text)
                                        .tag(speed)
                                }
                            } label: {
                                Label("Speed", systemImage: "gauge.with.dots.needle.67percent")
                            }
                            .pickerStyle(.menu)
                            
                            Divider()
                            
                            if !videoTracks.isEmpty {
                                Picker(selection: $activeVideoTrack) {
                                    ForEach(videoTracks) { track in
                                        Button {
                                        } label: {
                                            Text(verbatim: track.name)
                                            Text(verbatim: track.codec)
                                        }
                                        .tag(track)
                                    }
                                } label: {
                                    Label("Video", systemImage: "film")
                                }
                                .pickerStyle(.menu)
                            }
                            
                            if !audioTracks.isEmpty {
                                Picker(selection: $activeAudioTrack) {
                                    ForEach(audioTracks) { track in
                                        Button {
                                        } label: {
                                            Text(verbatim: track.name)
                                            Text(verbatim: track.codec)
                                        }
                                        .tag(track)
                                    }
                                } label: {
                                    Label("Audio", systemImage: "waveform")
                                }
                                .pickerStyle(.menu)
                            }

                            if !textTracks.isEmpty {
                                Picker(selection: $activeTextTrack) {
                                    Text("None")
                                        .tag(MediaTrack(id: "none", name: "text", codec: ""))
                                    ForEach(textTracks) { track in
                                        Button {
                                        } label: {
                                            Text(verbatim: track.name)
                                            Text(verbatim: track.codec)
                                        }
                                        .tag(track)
                                    }
                                } label: {
                                    Label("Subtitle", systemImage: "captions.bubble")
                                }
                                .pickerStyle(.menu)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        Spacer()
                            .frame(width: paddingSize)
                    }
                    Spacer()
                        .frame(height: paddingSize)
                }
                .background(.thickMaterial)
                
                Spacer()
                
                VStack {
                    Spacer()
                        .frame(height: 5)
                    
                    Slider(value: $playbackPosition)
                    Spacer()
                        .frame(height: 5)
                    
                    HStack {
                        Spacer()
                        Button {
                        } label: {
                            Image(systemName: "10.arrow.trianglehead.counterclockwise")
                                .font(.system(size: 25))
                        }
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
                        } label: {
                            Image(systemName: "30.arrow.trianglehead.clockwise")
                                .font(.system(size: 25))
                        }
                        Spacer()
                    }
                }
                .background(.thickMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.primary)
        .background(.black)
        .onChange(of: activeVideoTrack, { _, newValue in
            playerEvents.enableTrack.send(newValue)
        })
        .onChange(of: activeAudioTrack, { _, newValue in
            playerEvents.enableTrack.send(newValue)
        })
        .onChange(of: activeTextTrack, { _, newValue in
            playerEvents.enableTrack.send(newValue)
        })
        .onChange(of: playbackSpeed, { _, newValue in
            playerEvents.setPlaybackRate.send(newValue.rawValue)
        })
        .onReceive(playerEvents.addVideoTrack) { track in
            videoTracks.append(track)
            if videoTracks.count == 1 {
                activeVideoTrack = track
            }
        }
        .onReceive(playerEvents.addAudioTrack) { track in
            audioTracks.append(track)
            if audioTracks.count == 1 {
                activeAudioTrack = track
            }
        }
        .onReceive(playerEvents.addTextTrack) { track in
            textTracks.append(track)
            if userSettings.enableSubtitle && textTracks.count == 1 {
                activeTextTrack = track
            }
        }
    }
}

enum PlaybackSpeed: Float, Hashable, Identifiable {
    case x0_5 = 0.5
    case x0_75 = 0.75
    case x1 = 1
    case x2 = 2
    case x4 = 4
    static let all = [PlaybackSpeed.x0_5, .x0_75, .x1, .x2, .x4]
    
    var id: Float { rawValue }
    
    var text: String {
        switch self {
        case .x0_5:
            "0.5x"
        case .x0_75:
            "0.75x"
        case .x1:
            "1x"
        case .x2:
            "2x"
        case .x4:
            "4x"
        }
    }
}

extension VLCMediaPlayerState {
    var isPlaying: Bool {
        switch self {
        case .buffering, .playing:
            return true
        case .opening, .paused, .error, .stopped, .stopping:
            return false
        @unknown default:
            return false
        }
    }
}
