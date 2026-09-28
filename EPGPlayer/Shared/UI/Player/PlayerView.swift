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
    
    @State var playerUIOpacity: Double = 1
    
    @State var activeVideoTrack = MediaTrack(id: "none", name: "video", codec: "")
    @State var videoTracks: [MediaTrack] = []
    @State var activeAudioTrack = MediaTrack(id: "none", name: "audio", codec: "")
    @State var audioTracks: [MediaTrack] = []
    @State var activeTextTrack = MediaTrack(id: "none", name: "text", codec: "")
    @State var textTracks: [MediaTrack] = []
    /// Whether the subtitles still follow the default, until the user selects a subtitle track.
    @State var usesDefaultTextTrack = true
    
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
    
    #if os(iOS) || os(macOS)
    @State var liveTranslator = LiveSubtitleTranslator()
    /// Why Apple Intelligence can't be used, or nil when it can.
    @State var appleIntelligenceProblem: String?
    @State var appleIntelligenceLanguages: Set<Locale.LanguageCode>?
    /// The top of the bottom controls, which the live translation stays above.
    @State var controlsTop: CGFloat?
    #endif
    
    var videoPlayer: VLCPlayer {
        var player = VLCPlayer(videoItem: item.videoItem, httpHeaders: appState.client.headers, playerEvents: playerEvents, forceStrokeText: userSettings.$forceStrokeText, force16To9: userSettings.$force16To9, audioStereoMode: $audioStereoMode, playerState: $playerState, hadErrorState: $hadErrorState, hadPlayingState: $hadPlayingState)
        #if os(iOS) || os(macOS)
        player.liveTranslator = liveTranslator
        player.translateSubtitles = userSettings.liveTranslation
        #endif
        return player
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            videoPlayer
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
            
            #if os(iOS) || os(macOS)
            // A live stream stops instead of pausing, which leaves no video to translate.
            if item.videoItem.supportsLiveTranslation && !isExternalPlay && playerState != .stopping && playerState != .stopped {
                LiveSubtitleOverlay(translator: liveTranslator, controlsTop: playerUIOpacity == 1 ? controlsTop : nil)
                    .ignoresSafeArea(edges: .vertical)
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
                            #if !os(tvOS)
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
                #if os(iOS) || os(macOS)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.frame(in: .named(LiveSubtitleOverlay.coordinateSpace)).minY
                } action: { top in
                    controlsTop = top
                }
                #endif
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
        #if os(iOS) || os(macOS)
        .coordinateSpace(.named(LiveSubtitleOverlay.coordinateSpace))
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
            guard !videoTracks.contains(where: { $0.id == track.id }) else {
                return
            }
            videoTracks.append(track)
            if videoTracks.count == 1 {
                activeVideoTrack = track
            }
        }
        .onReceive(playerEvents.addAudioTrack) { track in
            guard !audioTracks.contains(where: { $0.id == track.id }) else {
                return
            }
            audioTracks.append(track)
            if audioTracks.count == 1 {
                activeAudioTrack = track
            }
        }
        .onReceive(playerEvents.addTextTrack) { track in
            guard !textTracks.contains(where: { $0.id == track.id }) else {
                return
            }
            textTracks.append(track)
            guard userSettings.enableSubtitles, usesDefaultTextTrack, let defaultTextTrack else {
                return
            }
            activeTextTrack = defaultTextTrack
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
            // VLC shows no subtitles in the new media, so the subtitles are selected again when their track is added.
            activeTextTrack = MediaTrack(id: "none", name: "text", codec: "")
            usesDefaultTextTrack = true
            showPlayerUI()
            resetIdleTimer()
            fetchSavedPlaybackPosition()
            #if os(iOS) || os(macOS)
            liveTranslator.updateProgram(item.program)
            #endif
        }
        #if os(iOS) || os(macOS)
        .task {
            liveTranslator.updateProgram(item.program)
            await loadAppleIntelligenceStatus()
        }
        .task(id: userSettings.liveTranslation) {
            if userSettings.liveTranslation {
                await followLivePrograms()
            }
        }
        .onChange(of: liveTranslationSettings, initial: true) {
            applyLiveTranslationSettings()
        }
        .onChange(of: userSettings.liveTranslation) { _, enabled in
            // The stream has to be opened again to read its captions.
            guard enabled, item.videoItem.supportsLiveTranslation, !liveTranslator.isAttached else {
                return
            }
            savePlaybackPosition()
            playerEvents.reloadMedia.send()
        }
        #endif
    }
    
    /// The newest translation together with the broadcast subtitles when the video has a translation,
    /// or else the first subtitle track.
    var defaultTextTrack: MediaTrack? {
        let original = textTracks.first { $0.translationRank == nil }
        guard let translation = textTracks.filter({ $0.translationRank != nil }).min(by: { $0.translationRank! < $1.translationRank! }) else {
            return original
        }
        guard let original else {
            return translation
        }
        return combinedTextTracks.first { $0.combinedIds == [translation.id, original.id] }
    }

    /// Entries that show a translation together with an original subtitle track.
    var combinedTextTracks: [MediaTrack] {
        textTracks.filter({ $0.translationRank != nil }).flatMap { translation in
            textTracks.filter({ $0.translationRank == nil }).map { original in
                MediaTrack(id: "\(translation.id)+\(original.id)", name: "\(translation.name) + \(original.name)", codec: "", combinedIds: [translation.id, original.id])
            }
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
                Picker(selection: Binding(get: { activeTextTrack }, set: { track in
                    usesDefaultTextTrack = false
                    activeTextTrack = track
                })) {
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
                    ForEach(combinedTextTracks) { track in
                        Text(verbatim: track.name)
                            .tag(track)
                    }
                } label: {
                    Label("Subtitle", systemImage: "captions.bubble")
                }
                .pickerStyle(.menu)
            }
            
            #if os(iOS) || os(macOS)
            if item.videoItem.supportsLiveTranslation {
                liveTranslationMenu
            }
            #endif
            
            if !videoTracks.isEmpty || !audioTracks.isEmpty || !textTracks.isEmpty || showsLiveTranslationMenu {
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

extension PlayerView {
    var showsLiveTranslationMenu: Bool {
        #if os(iOS) || os(macOS)
        item.videoItem.supportsLiveTranslation
        #else
        false
        #endif
    }
}

#if os(iOS) || os(macOS)
extension PlayerView {
    /// The model selected last time, which is shared with the translation of downloaded videos.
    var liveTranslationEngine: SubtitleTranslationEngine {
        if let saved = SubtitleTranslationEngine(rawValue: userSettings.translationEngine), SubtitleTranslationEngine.supported.contains(saved) {
            return saved
        }
        return SubtitleTranslationEngine.supported[0]
    }

    var liveTranslationLanguages: [String] {
        SubtitleTranslationTarget.identifiers(for: liveTranslationEngine, appleIntelligenceLanguages: appleIntelligenceLanguages)
    }

    var liveTranslationTarget: String {
        SubtitleTranslationTarget.defaultIdentifier(saved: userSettings.translationTargetLanguage, available: liveTranslationLanguages)
    }

    /// Everything that the live translation depends on, to apply changes to the translator.
    var liveTranslationSettings: [String] {
        [String(userSettings.liveTranslation), userSettings.translationEngine, userSettings.translationTargetLanguage,
         userSettings.customModelAPIFormat, userSettings.customModelBaseURL, userSettings.customModelName,
         appleIntelligenceProblem ?? "", appleIntelligenceLanguages.map { $0.map(\.identifier).sorted().joined(separator: ",") } ?? ""]
    }

    var liveTranslationMenu: some View {
        Menu {
            Toggle(isOn: userSettings.$liveTranslation) {
                Text("Translate Subtitles")
            }
            Picker(selection: Binding(get: { liveTranslationTarget }, set: { userSettings.translationTargetLanguage = $0 })) {
                ForEach(liveTranslationLanguages, id: \.self) { identifier in
                    Text(verbatim: SubtitleTranslationTarget.displayName(of: identifier))
                        .tag(identifier)
                }
            } label: {
                Text("Translate to")
            }
            .pickerStyle(.menu)
            Picker(selection: Binding(get: { liveTranslationEngine }, set: { userSettings.translationEngine = $0.rawValue })) {
                ForEach(SubtitleTranslationEngine.supported) { engine in
                    Text(engine.name)
                        .tag(engine)
                }
            } label: {
                Text("Model")
            }
            .pickerStyle(.menu)
            if let message = liveTranslator.statusMessage {
                Section {
                    Text(verbatim: message)
                }
            }
        } label: {
            Label("Translation", systemImage: "translate")
        }
    }

    func applyLiveTranslationSettings() {
        let engine = liveTranslationEngine
        let customConfiguration = CustomModelConfiguration(settings: userSettings, keychain: appState.keychain)
        let problem: String?
        switch engine {
        case .appleIntelligence:
            problem = appleIntelligenceProblem
        case .customModel:
            problem = customConfiguration.isComplete ? nil : String(localized: "Set up the custom model in Settings first.")
        }
        liveTranslator.configure(enabled: userSettings.liveTranslation && item.videoItem.supportsLiveTranslation, engine: engine,
                                 target: liveTranslationTarget, customConfiguration: customConfiguration, problem: problem)
    }

    func loadAppleIntelligenceStatus() async {
        #if compiler(>=6.4) && canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *), item.videoItem.supportsLiveTranslation {
            appleIntelligenceProblem = PrivateCloudComputeTranslationModel.availabilityMessage
            if appleIntelligenceProblem == nil {
                appleIntelligenceLanguages = await PrivateCloudComputeTranslationModel.supportedLanguageCodes()
            }
        }
        #endif
    }

    /// Keeps the program information of a live stream current, since the channel moves on to the next program.
    func followLivePrograms() async {
        guard let liveStream = item.videoItem as? EPGLiveStreamItem, var end = item.programEnd else {
            return
        }
        while !Task.isCancelled {
            // Give the server a moment to switch to the next program.
            let wait = end.timeIntervalSinceNow + 5
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled else {
                return
            }
            do {
                let schedules = try await appState.client.api.getSchedulesBroadcasting(query: Operations.GetSchedulesBroadcasting.Input.Query(isHalfWidth: true)).ok.body.json
                guard let program = schedules.first(where: { $0.channel.id == liveStream.channel.id })?.programs.first else {
                    return
                }
                Logger.info("Current live program: \(pii: program.name)")
                liveTranslator.updateProgram(program.subtitleProgramInfo)
                end = max(program.endDate, .now + 60)
            } catch {
                Logger.error("Failed to load the current program: \(error)")
                end = .now + 60
            }
        }
    }
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
        case .playing:
            return true
        case .nothingSpecial, .opening, .paused, .error, .stopped, .stopping:
            return false
        @unknown default:
            return false
        }
    }
}
