//
//  PlayerView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import os
import SwiftUI
import SwiftData
import VLCKit

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EPGPlayer", category: "player")

struct PlayerView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userSettings: UserSettings
    @EnvironmentObject private var appDelegate: AppDelegate
    
    let item: PlayerItem
    
    let paddingSize: CGFloat = 15
    
    @StateObject var playerEvents = PlayerEvents()
    
    @State var playbackSpeed: PlaybackSpeed = .x1
    @State var playerState: VLCMediaPlayerState = .opening
    @State var playbackPosition: Double = 0
    @State var loadedPlaybackPosition = false
    @State var hadErrorState = false
    @State var hadPlayingState = false
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
    #if os(macOS)
    @State var macHelper: MacHelper? = nil
    @State var lastMouseMoveHandled: TimeInterval = 0
    #endif
    
    @State var savedPlaybackPosition: SavedPlaybackPosition? = nil
    
    #if !os(macOS)
    @State var originalOrientation: UIInterfaceOrientation?
    #endif
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VLCPlayer(videoItem: item.videoItem, httpHeaders: appState.client.headers, playerEvents: playerEvents, playerState: $playerState, hadErrorState: $hadErrorState, hadPlayingState: $hadPlayingState)
                .ignoresSafeArea(edges: .vertical)
                .gesture(TapGesture().onEnded {
                    withAnimation(.default.speed(2)) {
                        playerUIOpacity = playerUIOpacity == 0 ? 1 : 0
                    }
                })
                #if os(macOS)
                .simultaneousGesture(TapGesture(count: 2).onEnded{
                    macHelper?.toggleFullscreen()
                })
                #endif
            
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
            
            if !playerState.isPlaying && hadErrorState {
                if hadErrorState {
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            ContentUnavailableView("Unable to play", systemImage: "xmark.circle")
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            
            if userSettings.showPlayerStats {
                PlayerStatsView()
                    .allowsHitTesting(false)
                    .offset(x: 10, y: 10)
                    .environmentObject(playerEvents)
            }
            
            VStack(spacing: 0) {
                #if !os(macOS)
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
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        
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
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                        
                        Spacer()
                            .frame(width: paddingSize)
                    }
                    Spacer()
                        .frame(height: paddingSize)
                }
                .background(.black.opacity(0.7))
                .opacity(playerUIOpacity)
                #endif
                
                Spacer()
                
                HStack {
                    Spacer()
                        .frame(width: paddingSize)
                    
                    PlayerProgressControl(item: item, playerState: $playerState, hadErrorState: $hadErrorState, hadPlayingState: $hadPlayingState, loadedPlaybackPosition: $loadedPlaybackPosition, playbackPosition: $playbackPosition, playerEvents: playerEvents)
                    
                    Spacer()
                        .frame(width: paddingSize)
                }
                .background(.black.opacity(0.7))
                .opacity(playerUIOpacity)
                
                #if os(macOS)
                Color.black
                    .frame(height: 10)
                    .opacity(playerUIOpacity * 0.7)
                #endif
            }
            
            #if os(macOS)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    playerMenu
                        .font(.title)
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .opacity(playerUIOpacity)
                    Spacer()
                        .frame(width: item.videoItem.type == .livestream ? 18 : 70)
                }
                Spacer()
                    .frame(height: 18)
            }
            #endif
        }
        .preferredColorScheme(.dark)
        .tint(.primary)
        .background(.black)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            #if os(macOS)
            do {
                self.macHelper = try MacHelper(window: "player-window")
            } catch let error {
                logger.error("Unable to load Mac UI helper: \(error)")
            }
            #else
            UIApplication.shared.addUserActivityTracker()
            originalOrientation = appDelegate.windowScene?.interfaceOrientation
            if userSettings.forceLandscape {
                appDelegate.orientationLock = .landscape
                appDelegate.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
//                appDelegate.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape), errorHandler: { error in
//                    logger.error("Unable to force landscape orientation: \(error)")
//                })
            }
            #endif
            fetchSavedPlaybackPosition()
        }
        .onDisappear {
            if let idleTimer {
                idleTimer.invalidate()
            }
            #if os(macOS)
            macHelper?.stopMonitorMouseMovement()
            macHelper?.showMouseCursor()
            #else
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
            #endif
            savePlaybackPosition()
        }
        .onChange(of: scenePhase, { _, newValue in
            savePlaybackPosition()
        })
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
        .onChange(of: playerState, { _, newValue in
            if !newValue.isPlaying {
                savePlaybackPosition()
            }
        })
        .onChange(of: hadPlayingState, { oldValue, newValue in
            if !oldValue && newValue {
                resetIdleTimer()
                #if os(macOS)
                setupMacMouseMonitoring()
                #endif
                if let savedPlaybackPosition {
                    playerEvents.setPlaybackPosition.send(savedPlaybackPosition.position)
                }
            }
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
        .onReceive(playerEvents.resetPlayer) {
            playbackSpeed = .x1
            playerState = .opening
            playbackPosition = 0
            loadedPlaybackPosition = false
            hadErrorState = false
            hadPlayingState = false
            playerUIOpacity = 1
            
            videoTracks = []
            audioTracks = []
            textTracks = []
            resetIdleTimer()
            fetchSavedPlaybackPosition()
        }
    }
    
    var playerMenu: some View {
        Menu {
            if item.videoItem.type != .livestream {
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
            }
            
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
                Image(systemName: "gearshape.fill")
            }
            .frame(width: 20, height: 20, alignment: .center)
            .contentShape(Rectangle())
        }
    }
    
    #if os(macOS)
    func setupMacMouseMonitoring() {
        guard let macHelper else {
            return
        }
        macHelper.startMonitorMouseMovement {
            macHelper.showMouseCursor()
            guard macHelper.isMousePointerInWindow() else {
                return
            }
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
    }
    #endif
    
    func fetchSavedPlaybackPosition() {
        guard item.videoItem.type != .livestream else {
            return
        }
        let serverId: String?
        if let localVideoItem = item.videoItem as? LocalVideoItem {
            serverId = localVideoItem.recordedItem?.serverId
        } else {
            serverId = appState.serverId
        }
        guard let serverId else {
            return
        }
        do {
            let epgId = item.videoItem.epgId
            guard let savedPlaybackPosition = try context.fetch(FetchDescriptor<SavedPlaybackPosition>(predicate: #Predicate { $0.serverId == serverId && $0.videoItemEpgId == epgId })).first else {
                return
            }
            self.savedPlaybackPosition = savedPlaybackPosition
            self.loadedPlaybackPosition = true
            print("Loaded saved playback position: \(savedPlaybackPosition.position)")
        } catch let error {
            print("Failed to fetch saved playback position: \(error)")
        }
    }
    
    func savePlaybackPosition() {
        guard hadPlayingState && item.videoItem.type != .livestream else {
            return
        }
        if let savedPlaybackPosition {
            savedPlaybackPosition.position = playbackPosition
            print("Saved playback position: \(savedPlaybackPosition.position)")
            return
        }
        let serverId: String?
        if let localVideoItem = item.videoItem as? LocalVideoItem {
            serverId = localVideoItem.recordedItem?.serverId
        } else {
            serverId = appState.serverId
        }
        guard let serverId else {
            return
        }
        let savedPlaybackPosition = SavedPlaybackPosition(serverId: serverId, videoItemEpgId: item.videoItem.epgId, position: playbackPosition)
        context.insert(savedPlaybackPosition)
        self.savedPlaybackPosition = savedPlaybackPosition
        print("Saved playback position: \(savedPlaybackPosition.position)")
    }
    
    func resetIdleTimer() {
        if let idleTimer {
            idleTimer.invalidate()
        }
        guard userSettings.inactiveTimer != .max else {
            return
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(userSettings.inactiveTimer), repeats: false) { _ in
            Task {
                await MainActor.run {
                    #if os(macOS)
                    if let macHelper, macHelper.isMousePointerInWindow() {
                        macHelper.hideMouseCursor()
                    }
                    #endif
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
