//
//  PlayerView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import os
import SwiftUI
import VLCKit

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EPGPlayer", category: "player")

struct PlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userSettings: UserSettings
    @EnvironmentObject private var appDelegate: AppDelegate
    
    let item: PlayerItem
    
    let paddingSize: CGFloat = 15
    
    @StateObject var playerEvents = PlayerEvents()
    
    @State var playbackSpeed: PlaybackSpeed = .x1
    @State var playerState: VLCMediaPlayerState = .opening
    @State var isPIPSupported = false
    @State var isPIPEnabled = false
    @State var isExternalPlay = false
    
    @State var playerUIOpacity: Double = 1
    
    @State var activeVideoTrack = MediaTrack(id: "none", name: "video", codec: "")
    @State var videoTracks: [MediaTrack] = []
    @State var activeAudioTrack = MediaTrack(id: "none", name: "audio", codec: "")
    @State var audioTracks: [MediaTrack] = []
    @State var activeTextTrack = MediaTrack(id: "none", name: "text", codec: "")
    @State var textTracks: [MediaTrack] = []
    
    @State var idleTimer: Timer? = nil
    @State var uiHelper: UIHelper? = nil
    @State var lastMouseMoveHandled: TimeInterval = 0
    
    @State var originalOrientation: UIInterfaceOrientation?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VLCPlayer(videoURL: item.videoItem.url, playerEvents: playerEvents, playerState: $playerState)
                .ignoresSafeArea(edges: .vertical)
                .onTapGesture {
                    withAnimation(.default.speed(2)) {
                        playerUIOpacity = playerUIOpacity == 0 ? 1 : 0
                    }
                }
            
            if isExternalPlay {
                HStack {
                    Spacer()
                    VStack(alignment: .center) {
                        Spacer()
                        Image(systemName: "play.display")
                            .font(.system(size: 100))
                        Text("Playing in external display")
                        Spacer()
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            
            if userSettings.showPlayerStats {
                PlayerStatsView()
                    .allowsHitTesting(false)
                    .offset(x: 10, y: 10)
                    .environmentObject(playerEvents)
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
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if !appState.isOnMac && isPIPSupported && !isExternalPlay {
                            Button {
                                playerEvents.togglePIPMode.send(!isPIPEnabled)
                            } label: {
                                Image(systemName: isPIPEnabled ? "pip.exit" : "pip.enter")
                            }
                        }
                        
                        playerMenu
                        
                        Spacer()
                            .frame(width: paddingSize)
                    }
                    Spacer()
                        .frame(height: paddingSize)
                }
                .background(.black.opacity(0.7))
                .opacity(playerUIOpacity)
                
                Spacer()
                
                HStack {
                    Spacer()
                        .frame(width: paddingSize)
                    
                    PlayerProgressControl(item: item, playerState: $playerState, playerEvents: playerEvents)
                    
                    Spacer()
                        .frame(width: paddingSize)
                }
                .background(.black.opacity(0.7))
                .opacity(playerUIOpacity)
                
                if appState.isOnMac {
                    Color.black
                        .frame(height: 10)
                        .opacity(playerUIOpacity * 0.7)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.primary)
        .background(.black)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.addUserActivityTracker()
            resetIdleTimer()
            originalOrientation = appDelegate.windowScene?.interfaceOrientation
            if userSettings.forceLandscape {
                appDelegate.orientationLock = .landscape
                appDelegate.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
//                appDelegate.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape), errorHandler: { error in
//                    logger.error("Unable to force landscape orientation: \(error)")
//                })
            }
            setupMouseMoveDetection()
        }
        .onDisappear {
            UIApplication.shared.removeUserActivityTracker()
            if userSettings.forceLandscape {
                appDelegate.orientationLock = .allButUpsideDown
                if let originalOrientation, originalOrientation == .portrait {
                    appDelegate.orientationLock = .portrait
                    UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                }
                appDelegate.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
//                appDelegate.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .allButUpsideDown))
            }
            uiHelper?.stopMonitorMouseMovement()
        }
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
            if userSettings.enableSubtitles && textTracks.count == 1 {
                activeTextTrack = track
            }
        }
        .onReceive(playerEvents.setPIPSupported, perform: { supported in
            isPIPSupported = supported
        })
        .onReceive(playerEvents.setPIPEnabled, perform: { enabled in
            isPIPEnabled = enabled
        })
        .onReceive(playerEvents.setExternalPlay, perform: { enabled in
            isExternalPlay = enabled
        })
        .onReceive(playerEvents.userInteracted) {
            resetIdleTimer()
        }
    }
    
    var playerMenu: some View {
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
            
            if !videoTracks.isEmpty || !audioTracks.isEmpty || !textTracks.isEmpty {
                Divider()
            }
            
            Toggle(isOn: userSettings.$showPlayerStats) {
                Label("Show stats", systemImage: "waveform.path.ecg")
            }
        } label: {
            ZStack(alignment: .center) {
                Color.clear
                Image(systemName: "ellipsis")
            }
            .frame(width: 20, height: 20, alignment: .center)
            .contentShape(Rectangle())
        }
    }
    
    func setupMouseMoveDetection() {
        if !appState.isOnMac {
            return
        }
        do {
            let uiHelper = try MacNativeBundle.loadUIHelper()
            uiHelper.startMonitorMouseMovement {
                let timestamp = Date().timeIntervalSinceReferenceDate
                if timestamp - lastMouseMoveHandled < 0.3 {
                    return
                }
                lastMouseMoveHandled = timestamp
                resetIdleTimer()
                if playerUIOpacity == 0 {
                    withAnimation(.default.speed(2)) {
                        playerUIOpacity = 1
                    }
                }
            }
            self.uiHelper = uiHelper
        } catch let error {
            logger.error("Unable to load Mac UI helper: \(error)")
        }
    }
    
    func resetIdleTimer() {
        if let idleTimer {
            idleTimer.invalidate()
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            Task {
                await MainActor.run {
                    withAnimation(.default.speed(2)) {
                        playerUIOpacity = 0
                    }
                }
            }
        }
    }
}

enum PlaybackSpeed: Float, Hashable, Identifiable {
    case x0_5 = 0.5
    case x0_75 = 0.75
    case x1 = 1
    case x1_5 = 1.5
    case x2 = 2
    case x4 = 4
    static let all = [PlaybackSpeed.x0_5, .x0_75, .x1, .x1_5, .x2, .x4]
    
    var id: Float { rawValue }
    
    var text: String {
        switch self {
        case .x0_5:
            "0.5x"
        case .x0_75:
            "0.75x"
        case .x1:
            "1x"
        case .x1_5:
            "1.5x"
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
