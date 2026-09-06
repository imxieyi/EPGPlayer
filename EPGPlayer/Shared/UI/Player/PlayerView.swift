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
    @State var isProgramInfoPresented = false
    #if os(tvOS)
    @FocusState private var isRemoteSurfaceFocused: Bool
    @FocusState private var focusedPlaybackSetting: PlaybackSetting?
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
                .gesture(TapGesture().onEnded {
                    if playerUIOpacity == 1 {
                        hidePlayerUI()
                    } else {
                        showPlayerUI()
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
                        
                        #if !os(tvOS)
                        playerMenu
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                        #endif
                        
                        Spacer()
                            .frame(width: paddingSize)
                    }
                    Spacer()
                        .frame(height: paddingSize)
                }
                .background(.black.opacity(0.7))
                #if os(tvOS)
                .opacity(isProgramInfoPresented ? 0 : playerUIOpacity)
                .allowsHitTesting(!isProgramInfoPresented && playerUIOpacity > 0)
                #else
                .opacity(playerUIOpacity)
                #endif
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
                #if os(tvOS)
                .opacity(isProgramInfoPresented ? 0 : playerUIOpacity)
                .allowsHitTesting(!isProgramInfoPresented && playerUIOpacity > 0)
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
            .allowsHitTesting(playerUIOpacity > 0)
            #endif

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
        #if os(tvOS)
        .focusable(!isProgramInfoPresented)
        .focused($isRemoteSurfaceFocused)
        #endif
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
            
            videoTracks = []
            audioTracks = []
            textTracks = []
            showPlayerUI()
            resetIdleTimer()
            fetchSavedPlaybackPosition()
        }
        #if os(tvOS)
        .onMoveCommand { direction in
            if isProgramInfoPresented {
                switch direction {
                case .left:
                    movePlaybackSetting(by: -1)
                case .right:
                    movePlaybackSetting(by: 1)
                case .up:
                    closeProgramInfo()
                default:
                    break
                }
                resetIdleTimer()
                return
            }

            switch direction {
            case .down:
                withAnimation(.easeOut(duration: 0.2)) {
                    isProgramInfoPresented = true
                }
                showPlayerUI()
                resetIdleTimer()
                Task { @MainActor in
                    await Task.yield()
                    focusedPlaybackSetting = .aspect
                }
            case .up:
                showPlayerUI()
                resetIdleTimer()
            case .left:
                if item.videoItem.type != .livestream {
                    playerEvents.seekBy.send(-10)
                }
                showPlayerUI()
                resetIdleTimer()
            case .right:
                if item.videoItem.type != .livestream {
                    playerEvents.seekBy.send(10)
                }
                showPlayerUI()
                resetIdleTimer()
            default:
                showPlayerUI()
                resetIdleTimer()
            }
        }
        .onExitCommand {
            if isProgramInfoPresented {
                closeProgramInfo()
            } else {
                dismiss()
            }
        }
        .onPlayPauseCommand {
            playerEvents.togglePlay.send()
        }
        #endif
    }

    #if os(tvOS)
    var programInfoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.title)
                .font(.title2.bold())
                .lineLimit(2)
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let programDescription = item.programDescription, !programDescription.isEmpty {
                Text(verbatim: programDescription)
                    .font(.body)
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
            } else {
                Text("No program information")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 56)
        .padding(.vertical, 22)
        .background(.black.opacity(0.68))
    }

    var tvOSPlaybackSettings: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(VideoAspectRatio.allCases) { aspectRatio in
                    Button {
                        userSettings.videoAspectRatio = aspectRatio
                    } label: {
                        if userSettings.videoAspectRatio == aspectRatio {
                            Label(aspectRatio.label, systemImage: "checkmark")
                        } else {
                            Text(verbatim: aspectRatio.label)
                        }
                    }
                }
            } label: {
                playbackSettingLabel("Aspect", value: userSettings.videoAspectRatio.label, systemImage: "aspectratio", setting: .aspect)
            }
            .focused($focusedPlaybackSetting, equals: .aspect)
            .buttonStyle(.plain)
            .focusEffectDisabled()

            if item.videoItem.type != .livestream {
                Menu {
                    ForEach(PlaybackSpeed.all) { speed in
                        Button {
                            playbackSpeed = speed
                        } label: {
                            if playbackSpeed == speed {
                                Label(speed.text, systemImage: "checkmark")
                            } else {
                                Text(verbatim: speed.text)
                            }
                        }
                    }
                } label: {
                    playbackSettingLabel("Speed", value: playbackSpeed.text, systemImage: "gauge.with.dots.needle.67percent", setting: .speed)
                }
                .focused($focusedPlaybackSetting, equals: .speed)
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }

            Menu {
                ForEach(videoTracks) { track in
                    Button {
                        activeVideoTrack = track
                    } label: {
                        if activeVideoTrack == track {
                            Label(track.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: track.name)
                        }
                    }
                }
            } label: {
                playbackSettingLabel("Video", value: activeVideoTrack.id == "none" ? String(localized: "None") : activeVideoTrack.name, systemImage: "film", setting: .video)
            }
            .disabled(videoTracks.isEmpty)
            .focused($focusedPlaybackSetting, equals: .video)
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Menu {
                ForEach(audioTracks) { track in
                    Button {
                        activeAudioTrack = track
                    } label: {
                        if activeAudioTrack == track {
                            Label(track.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: track.name)
                        }
                    }
                }
            } label: {
                playbackSettingLabel("Audio", value: activeAudioTrack.id == "none" ? String(localized: "None") : activeAudioTrack.name, systemImage: "waveform", setting: .audio)
            }
            .disabled(audioTracks.isEmpty)
            .focused($focusedPlaybackSetting, equals: .audio)
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Menu {
                Button {
                    activeTextTrack = MediaTrack(id: "none", name: "text", codec: "")
                } label: {
                    if activeTextTrack.id == "none" {
                        Label("None", systemImage: "checkmark")
                    } else {
                        Text("None")
                    }
                }
                ForEach(textTracks) { track in
                    Button {
                        activeTextTrack = track
                    } label: {
                        if activeTextTrack == track {
                            Label(track.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: track.name)
                        }
                    }
                }
            } label: {
                playbackSettingLabel("Subtitle", value: activeTextTrack.id == "none" ? String(localized: "None") : activeTextTrack.name, systemImage: "captions.bubble", setting: .subtitle)
            }
            .disabled(textTracks.isEmpty)
            .focused($focusedPlaybackSetting, equals: .subtitle)
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(10)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
    }

    func playbackSettingLabel(_ title: LocalizedStringKey, value: String, systemImage: String, setting: PlaybackSetting) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(.callout)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
        .background(
            focusedPlaybackSetting == setting ? Color.white.opacity(0.28) : Color.white.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    var availablePlaybackSettings: [PlaybackSetting] {
        var settings: [PlaybackSetting] = [.aspect]
        if item.videoItem.type != .livestream {
            settings.append(.speed)
        }
        if !videoTracks.isEmpty {
            settings.append(.video)
        }
        if !audioTracks.isEmpty {
            settings.append(.audio)
        }
        if !textTracks.isEmpty {
            settings.append(.subtitle)
        }
        return settings
    }

    func movePlaybackSetting(by offset: Int) {
        let settings = availablePlaybackSettings
        guard !settings.isEmpty else {
            return
        }
        let currentIndex = focusedPlaybackSetting.flatMap { settings.firstIndex(of: $0) } ?? 0
        focusedPlaybackSetting = settings[(currentIndex + offset + settings.count) % settings.count]
    }

    func closeProgramInfo() {
        withAnimation(.easeOut(duration: 0.2)) {
            isProgramInfoPresented = false
        }
        focusedPlaybackSetting = nil
        showPlayerUI()
        resetIdleTimer()
        Task { @MainActor in
            await Task.yield()
            isRemoteSurfaceFocused = true
        }
    }
    #endif
    
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
        #if os(tvOS)
        isRemoteSurfaceFocused = false
        #endif
        #if os(macOS)
        macHelper?.setWindowTitleBar(visible: true)
        #endif
    }
    
    func hidePlayerUI() {
        guard !isProgramInfoPresented else {
            return
        }
        if playerUIOpacity == 1 {
            withAnimation(.default.speed(2)) {
                playerUIOpacity = 0
                isProgramInfoPresented = false
            }
            #if os(tvOS)
            Task { @MainActor in
                await Task.yield()
                isRemoteSurfaceFocused = true
            }
            #endif
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
                    hidePlayerUI()
                }
            }
        }
    }
}

#if os(tvOS)
enum PlaybackSetting: Hashable {
    case aspect
    case speed
    case video
    case audio
    case subtitle
}
#endif

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
