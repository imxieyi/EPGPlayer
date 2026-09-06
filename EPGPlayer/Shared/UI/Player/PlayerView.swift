//
//  PlayerView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import SwiftData
import VLCKit

struct PlayerView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userSettings: UserSettings
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
    @State var isProgramInfoPresented = false
    #if os(tvOS)
    @FocusState var focusedPlaybackSetting: PlaybackSetting?
    // The whole player surface (minus Settings) has exactly one focusable target;
    // Select cycles through Idle -> Transport -> Scrubbing -> commit via isScrubbing,
    // instead of moving tvOS focus onto the slider itself.
    @FocusState private var isWakeSurfaceFocused: Bool
    @State var isScrubbing = false
    @State var isChannelSwitcherPresented = false
    @State var isChannelCategoryStageActive = false
    @State var channelSwitcherAllSchedules: [Components.Schemas.Schedule] = []
    @State var channelSwitcherCategory: Components.Schemas.ChannelType = .gr
    
    static let channelSwitcherTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return formatter
    }()
    #endif
    
    @State var playerUIOpacity: Double = 1
    
    @State var activeVideoTrack = MediaTrack(id: "none", name: "video", codec: "")
    @State var videoTracks: [MediaTrack] = []
    @State var activeAudioTrack = MediaTrack(id: "none", name: "audio", codec: "")
    @State var audioTracks: [MediaTrack] = []
    @State var activeTextTrack = MediaTrack(id: "none", name: "text", codec: "")
    @State var textTracks: [MediaTrack] = []
    
    @State var audioStereoMode: VLCMediaPlayer.AudioStereoMode = .unset
    
    @State var idleTimer: Timer? = nil
    #if os(macOS)
    @State var macHelper: MacHelper? = nil
    @State var lastMouseMoveHandled: TimeInterval = 0
    #endif
    
    @State var savedPlaybackPosition: SavedPlaybackPosition? = nil
    
    #if !os(macOS) && !os(tvOS)
    @State var originalOrientation: UIInterfaceOrientation?
    #endif
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VLCPlayer(videoItem: item.videoItem, httpHeaders: appState.client.headers, playerEvents: playerEvents, forceStrokeText: userSettings.$forceStrokeText, force16To9: userSettings.$force16To9, videoAspectRatio: userSettings.$videoAspectRatio, audioStereoMode: $audioStereoMode, playerState: $playerState, hadErrorState: $hadErrorState, hadPlayingState: $hadPlayingState)
                .ignoresSafeArea(edges: .vertical)
                #if !os(tvOS)
                .gesture(TapGesture().onEnded {
                    if playerUIOpacity == 1 {
                        hidePlayerUI()
                    } else {
                        showPlayerUI()
                    }
                })
                #endif
                #if os(macOS)
                .simultaneousGesture(TapGesture(count: 2).onEnded{
                    macHelper?.toggleFullscreen()
                })
                #endif

            #if os(tvOS)
            // Always mounted (never inserted/removed) so requesting focus never races
            // against the view appearing. This is the only focusable element in the
            // player (besides Settings/the channel switcher); Select's meaning depends
            // on playerUIOpacity/isScrubbing rather than on tvOS focus ever moving
            // onto the slider.
            if !isProgramInfoPresented && !isChannelSwitcherPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusable()
                    .focused($isWakeSurfaceFocused)
                    .onAppear {
                        isWakeSurfaceFocused = true
                    }
                    .onTapGesture {
                        handleSelect()
                    }
            }
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
                #if !os(macOS) && !os(tvOS)
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
                    
                    #if os(tvOS)
                    PlayerProgressControl(item: item, playerState: $playerState, hadErrorState: $hadErrorState, hadPlayingState: $hadPlayingState, loadedPlaybackPosition: $loadedPlaybackPosition, playbackPosition: $playbackPosition, playerEvents: playerEvents, isScrubbing: $isScrubbing)
                    #else
                    PlayerProgressControl(item: item, playerState: $playerState, hadErrorState: $hadErrorState, hadPlayingState: $hadPlayingState, loadedPlaybackPosition: $loadedPlaybackPosition, playbackPosition: $playbackPosition, playerEvents: playerEvents)
                    #endif
                    
                    Spacer()
                        .frame(width: paddingSize)
                }
                .background(.black.opacity(0.7))
                #if os(tvOS)
                .opacity(isProgramInfoPresented ? 0 : playerUIOpacity)
                // Hit-testing must stay enabled even while invisible: Select can reveal
                // the HUD and immediately start scrubbing from the very same tap.
                .allowsHitTesting(!isProgramInfoPresented)
                #else
                .opacity(playerUIOpacity)
                #endif
                
                #if os(macOS)
                Color.black
                    .frame(height: 10)
                    .opacity(playerUIOpacity * 0.7)
                #endif
            }

            #if os(tvOS)
            if isProgramInfoPresented {
                VStack(spacing: 0) {
                    tvOSPlaybackSettings
                        .padding(.horizontal, 48)
                        .padding(.top, 26)
                    Spacer()
                    programInfoPanel
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            if isChannelSwitcherPresented {
                HStack(spacing: 0) {
                    if isChannelCategoryStageActive {
                        channelCategorySwitcherPanel
                    } else {
                        channelSwitcherPanel
                    }
                    Spacer()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            #endif
            
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
                Logger.error("Unable to load Mac UI helper: \(error)")
            }
            #elseif !os(tvOS)
            UIApplication.shared.addUserActivityTracker()
            originalOrientation = appDelegate.windowScene?.interfaceOrientation
            if userSettings.forceLandscape {
                appDelegate.orientationLock = .landscape
                appDelegate.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
//                appDelegate.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape), errorHandler: { error in
//                    Logger.error("Unable to force landscape orientation: \(error)")
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
            #elseif !os(tvOS)
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
        #if os(tvOS)
        .onChange(of: isProgramInfoPresented) { _, newValue in
            if newValue {
                Task { @MainActor in
                    await Task.yield()
                    focusedPlaybackSetting = .aspect
                }
            } else {
                focusedPlaybackSetting = nil
            }
        }
        .onChange(of: userSettings.videoAspectRatio, { _, newValue in
            playerEvents.setVideoAspectRatio.send(newValue)
        })
        #endif
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
                if activeTextTrack.id == "none" {
                    // VLC can finalize its own default subtitle track selection once playback
                    // actually starts, after all per-track "disable" commands already ran.
                    playerEvents.enableTrack.send(activeTextTrack)
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
            } else if activeTextTrack.id == "none" {
                // VLC can auto-select a newly discovered track (e.g. ARIB captions) on its own;
                // re-assert "None" so it doesn't silently override the user's choice.
                playerEvents.enableTrack.send(activeTextTrack)
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
            
            videoTracks = []
            audioTracks = []
            textTracks = []
            showPlayerUI()
            resetIdleTimer()
            fetchSavedPlaybackPosition()
        }
        #if os(tvOS)
        // Swipe either quick-seeks (Idle/Transport) or moves the scrub preview
        // (Scrubbing, entered/exited via Select in handleSelect()).
        .onMoveCommand { direction in
            guard !isProgramInfoPresented else {
                return
            }
            if isChannelSwitcherPresented {
                // Up/down navigate the list/category rows via native tvOS focus;
                // only left (one more step "outward") needs explicit handling here.
                if direction == .left && !isChannelCategoryStageActive {
                    openCategorySwitcher()
                    resetIdleTimer()
                }
                return
            }
            switch direction {
            case .left:
                if isScrubbing {
                    playbackPosition = max(0, playbackPosition - 0.01)
                } else if item.videoItem.type != .livestream {
                    playerEvents.seekBy.send(-10)
                }
            case .right:
                if isScrubbing {
                    playbackPosition = min(1, playbackPosition + 0.01)
                } else if item.videoItem.type != .livestream {
                    playerEvents.seekBy.send(30)
                } else {
                    openChannelSwitcher()
                }
            case .up:
                if !isScrubbing {
                    isProgramInfoPresented = true
                }
            default:
                break
            }
            resetIdleTimer()
        }
        .onExitCommand {
            if isChannelSwitcherPresented {
                if isChannelCategoryStageActive {
                    // Back out of category picking, not all the way out of the switcher.
                    isChannelCategoryStageActive = false
                } else {
                    isChannelSwitcherPresented = false
                }
                resetIdleTimer()
            } else if isProgramInfoPresented {
                closeProgramInfo()
            } else if isScrubbing {
                // Cancel without seeking; resume whatever state playback was in.
                isScrubbing = false
                if !playerState.isPlaying {
                    playerEvents.togglePlay.send()
                }
                resetIdleTimer()
            } else if playerUIOpacity == 1 {
                // Transport HUD only: dismiss it, don't leave the player.
                hidePlayerUI()
            } else {
                dismiss()
            }
        }
        .onPlayPauseCommand {
            playerEvents.togglePlay.send()
        }
        #endif
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
            }
            
            // Stereo mode is broken on libvlc.
            if false {
                Picker(selection: $audioStereoMode) {
                    Text("Unset")
                        .tag(VLCMediaPlayer.AudioStereoMode.unset)
                    Text("Stereo")
                        .tag(VLCMediaPlayer.AudioStereoMode.stereo)
                    Text("Left")
                        .tag(VLCMediaPlayer.AudioStereoMode.left)
                    Text("Right")
                        .tag(VLCMediaPlayer.AudioStereoMode.right)
                } label: {
                    Label("Stereo mode", systemImage: "hifispeaker.2")
                }
                
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
                hidePlayerUI()
                return
            }
            let timestamp = Date().timeIntervalSinceReferenceDate
            if timestamp - lastMouseMoveHandled < 0.3 {
                return
            }
            lastMouseMoveHandled = timestamp
            resetIdleTimer()
            showPlayerUI()
        }
    }
    #endif
    
    func showPlayerUI() {
        if playerUIOpacity == 0 {
            withAnimation(.default.speed(2)) {
                playerUIOpacity = 1
            }
        }
        #if os(macOS)
        macHelper?.setWindowTitleBar(visible: true)
        #endif
    }
    
    func hidePlayerUI() {
        guard !isProgramInfoPresented else {
            return
        }
        #if os(tvOS)
        guard !isChannelSwitcherPresented else {
            return
        }
        if isScrubbing {
            // Idle timeout mid-scrub: don't leave playback stuck paused.
            isScrubbing = false
            if !playerState.isPlaying {
                playerEvents.togglePlay.send()
            }
        }
        #endif
        if playerUIOpacity == 1 {
            withAnimation(.default.speed(2)) {
                playerUIOpacity = 0
            }
        }
        #if os(macOS)
        if let macHelper, !macHelper.isFullScreen {
            macHelper.setWindowTitleBar(visible: false)
        }
        #endif
    }
    
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
            Logger.info("Loaded saved playback position: \(savedPlaybackPosition.position)")
        } catch let error {
            Logger.error("Failed to fetch saved playback position: \(error.localizedDescription)")
        }
    }
    
    func savePlaybackPosition() {
        guard hadPlayingState && item.videoItem.type != .livestream else {
            return
        }
        if let savedPlaybackPosition {
            savedPlaybackPosition.position = playbackPosition
            Logger.info("Saved playback position: \(savedPlaybackPosition.position)")
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
        Logger.info("Saved playback position: \(savedPlaybackPosition.position)")
    }
    
    func resetIdleTimer(after seconds: Int? = nil) {
        if let idleTimer {
            idleTimer.invalidate()
        }
        #if os(tvOS)
        // tvOS doesn't expose the "Auto hide UI" setting; always use a fixed, short delay.
        let delay = seconds ?? 3
        #else
        guard userSettings.inactiveTimer != .max else {
            return
        }
        let delay = seconds ?? userSettings.inactiveTimer
        #endif
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(delay), repeats: false) { _ in
            Task {
                await MainActor.run {
                    #if os(macOS)
                    if let macHelper, macHelper.isMousePointerInWindow() {
                        macHelper.hideMouseCursor()
                    }
                    #endif
                    hidePlayerUI()
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
