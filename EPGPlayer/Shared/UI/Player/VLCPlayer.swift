//
//  VLCPlayer.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//
//  SPDX-License-Identifier: MPL-2.0

import AVKit
@preconcurrency import VLCKit
import SwiftUI
import Combine

struct VLCPlayer: UIViewControllerRepresentable {
    let videoItem: any VideoItem
    let httpHeaders: [String: String]
    let playerEvents: PlayerEvents
    
    @Binding var forceStrokeText: Bool
    @Binding var force16To9: Bool
    @Binding var videoAspectRatio: VideoAspectRatio
    @Binding var audioStereoMode: VLCMediaPlayer.AudioStereoMode
    
    @Binding var playerState: VLCMediaPlayerState
    @Binding var hadErrorState: Bool
    @Binding var hadPlayingState: Bool
    
    #if os(iOS) || os(macOS)
    /// Receives the captions of the stream when `translateSubtitles` is on.
    var liveTranslator: LiveSubtitleTranslator? = nil
    /// Whether to read the stream through the caption proxy for live translation.
    var translateSubtitles = false
    /// Shows the translation saved next to a downloaded video.
    var savedSubtitles: SavedSubtitles? = nil
    #endif
    
    #if !os(macOS)
    func makeUIViewController(context: Context) -> VLCPlayerViewController {
        return makeViewController(context: context)
    }
    
    func updateUIViewController(_ uiViewController: VLCPlayerViewController, context: Context) {
        updateViewController(uiViewController, context: context)
    }
    #else
    func makeNSViewController(context: Context) -> VLCPlayerViewController {
        return makeViewController(context: context)
    }
    
    func updateNSViewController(_ nsViewController: VLCPlayerViewController, context: Context) {
        updateViewController(nsViewController, context: context)
    }
    #endif

    func makeViewController(context: Context) -> VLCPlayerViewController {
        let playerVC = VLCPlayerViewController()
        playerVC.delegate = context.coordinator
        context.coordinator.viewController = playerVC
        playerVC.playerEvents = playerEvents
        playerVC.videoItem = videoItem
        playerVC.httpHeaders = httpHeaders
        playerVC.forceStrokeText = forceStrokeText
        playerVC.force16To9 = force16To9
        playerVC.videoAspectRatio = videoAspectRatio
        playerVC.mediaPlayer.audioStereoMode = audioStereoMode
        #if os(iOS) || os(macOS)
        playerVC.liveTranslator = liveTranslator
        playerVC.savedSubtitles = savedSubtitles
        playerVC.readsCaptions = translateSubtitles && videoItem.supportsLiveTranslation
        #endif
        return playerVC
    }

    func updateViewController(_ uiViewController: VLCPlayerViewController, context: Context) {
//        if uiViewController.mediaPlayer.audioStereoMode != audioStereoMode {
//            uiViewController.mediaPlayer.audioStereoMode = audioStereoMode
//        }
        #if os(tvOS)
        if uiViewController.videoAspectRatio != videoAspectRatio {
            uiViewController.videoAspectRatio = videoAspectRatio
            uiViewController.applyVideoAspectRatio()
        }
        #else
        if uiViewController.force16To9 != force16To9 {
            uiViewController.force16To9 = force16To9
            uiViewController.applyVideoAspectRatio()
        }
        #endif
        #if os(iOS) || os(macOS)
        uiViewController.readsCaptions = translateSubtitles && videoItem.supportsLiveTranslation
        #endif
        guard uiViewController.videoItem?.epgId != videoItem.epgId else {
            return
        }
        uiViewController.videoItem = videoItem
        uiViewController.httpHeaders = httpHeaders
        uiViewController.forceStrokeText = forceStrokeText
        uiViewController.force16To9 = force16To9
        uiViewController.videoAspectRatio = videoAspectRatio
        uiViewController.reload()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, playerEvents: playerEvents)
    }
    
    class Coordinator: NSObject, VLCMediaPlayerDelegate, VLCMediaDelegate {
        let parent: VLCPlayer
        weak var playerEvents: PlayerEvents?
        weak var viewController: VLCPlayerViewController?
        #if os(tvOS)
        private var lastTimeUpdate: Date = .distantPast
        #endif
        
        init(parent: VLCPlayer, playerEvents: PlayerEvents) {
            self.parent = parent
            self.playerEvents = playerEvents
        }
        
        func mediaPlayerTrackSelected(_ trackType: VLCMedia.TrackType, selectedId: String, unselectedId: String) {
            guard trackType == .text else {
                return
            }
            Task { @MainActor [weak viewController] in
                guard let viewController else {
                    return
                }
                let player = viewController.mediaPlayer
                let desiredTrackId = viewController.desiredTextTrackId
                guard selectedId != desiredTrackId else {
                    return
                }
                // The container's own "default" track flag can make VLC auto-select a subtitle
                // track regardless of our previous command; force it back to what the user wants.
                Logger.info("VLC auto-selected text track \(selectedId), reverting to \(desiredTrackId)")
                if desiredTrackId == "none" {
                    player.deselectAllTextTracks()
                } else {
                    player.textTracks.first(where: { $0.trackId == desiredTrackId })?.isSelectedExclusively = true
                }
            }
        }

        func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
            Logger.debug("Player state changed: \(newState.rawValue)")
            Task { @MainActor [parent, weak playerEvents, weak viewController] in
                parent.playerState = newState
                if newState == .error {
                    parent.hadErrorState = true
                } else if newState == .opening {
                    parent.hadErrorState = false
                } else if newState == .playing {
                    parent.hadPlayingState = true
                    // Passing ":deinterlace"/":deinterlace-mode" as VLCMedia/VLCMediaPlayer
                    // startup options had no effect (confirmed via Instruments); the vout only
                    // exists once playback actually starts, so disable it via the runtime API instead.
                    viewController?.mediaPlayer.setDeinterlaceFilter(nil)
                    #if os(tvOS)
                    playerEvents?.videoOutputReady.send()
                    #endif
                }
            }
        }
        
        func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
            Logger.info("Track added: \(trackId) type \(trackType.rawValue)")
            Task { @MainActor [weak playerEvents] in
                playerEvents?.getTrackInfo.send(trackId)
            }
        }
        
        func mediaPlayerLengthChanged(_ length: Int64) {
            Logger.info("Length of media: \(length)")
        }
        
        func mediaPlayerTimeChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else {
                Logger.error("mediaPlayerTimeChanged: wrong notification object type")
                return
            }
            #if os(tvOS)
            // VLC posts this notification far more often than the UI can usefully consume;
            // throttling keeps the resulting MainActor/Combine/SwiftUI work off the hot path
            // so it can't compete with the player's own decode/render threads for CPU time.
            let now = Date()
            guard now.timeIntervalSince(lastTimeUpdate) >= 0.25 else {
                return
            }
            lastTimeUpdate = now
            #endif
            if let stats = player.media?.statistics {
                Task { @MainActor [weak playerEvents] in
                    playerEvents?.updateStats.send(stats)
                }
            }
            Task { @MainActor [weak playerEvents] in
                playerEvents?.updatePosition.send(PlaybackPosition(time: Int(player.time.intValue), position: player.position))
            }
        }
        
        func mediaDidFinishParsing(_ aMedia: VLCMedia) {
            Logger.info("Finished parsing media, status \(aMedia.parsedStatus.rawValue), length \(aMedia.length)")
        }
    }
}

class VLCPlayerViewController: UIViewController {
    var mediaPlayer = VLCMediaPlayer()
    let mediaParser = VLCMediaParser(library: .shared(), timeout: .max)
    var httpHeaders: [String: String]?
    var videoItem: VideoItem?
    var delegate: VLCPlayer.Coordinator?
    var playerEvents: PlayerEvents?
    
    var forceStrokeText: Bool = false
    var force16To9: Bool = false
    var videoAspectRatio: VideoAspectRatio = .sixteenNine
    var desiredTextTrackId: String = "none"

    #if os(iOS) || os(macOS)
    var liveTranslator: LiveSubtitleTranslator?
    var savedSubtitles: SavedSubtitles?
    /// Whether the next load reads the stream through the caption proxy.
    var readsCaptions = false
    /// The stream registered with the caption proxy for the current media.
    private var captionStreamID: String?
    private var loadTask: Task<Void, Never>?
    private var translationClock: Timer?
    private var captionClock = CaptionClock()
    #endif

    var videoView: UIView!
    var pipController: VLCPictureInPictureWindowControlling?
    var pipPossibleObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        #if os(macOS)
        videoView = DisabledView(frame: view.bounds)
        
        videoView.autoresizingMask = [.width, .height]
        mediaPlayer.drawable = videoView
        #elseif os(tvOS)
        videoView = UIView(frame: view.bounds)
        
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoView.isUserInteractionEnabled = false
        mediaPlayer.drawable = self
        #else
        videoView = UIView(frame: view.bounds)
        
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoView.isUserInteractionEnabled = false
        if let externalView = ExternalDisplayHelper.instance.delegate?.viewController.view {
            mediaPlayer.drawable = externalView
            playerEvents?.setExternalPlay.send(true)
        } else {
            mediaPlayer.drawable = self
            playerEvents?.setExternalPlay.send(false)
        }
        #endif
        mediaPlayer.audio?.passthrough = true
        mediaPlayer.delegate = delegate
        
        view.addSubview(videoView)

        // The VLCDiagnosticLogger install (VLCLibrary.shared().loggers = ...) used for the
        // stutter investigation is disabled for now: at .debug level libVLC calls its
        // handleMessage very frequently, and that callback overhead only exists on tvOS
        // (nothing similar runs on iOS/macOS), so it could itself be responsible for part
        // of the tvOS-only slowdown. Re-enable temporarily if more log evidence is needed.

        reload()
    }
    
    var togglePlayListener: AnyCancellable?
    var getTrackInfoListener: AnyCancellable?
    var enableTrackListener: AnyCancellable?
    var setPlaybackRateListener: AnyCancellable?
    var setPlaybackPositionListener: AnyCancellable?
    var setPlaybackTimeListener: AnyCancellable?
    #if os(tvOS)
    var setVideoAspectRatioListener: AnyCancellable?
    var videoOutputReadyListener: AnyCancellable?
    #endif
    var togglePIPModeListener: AnyCancellable?
    var reloadMediaListener: AnyCancellable?
    var externalDisplayObservation: NSKeyValueObservation?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let playerEvents else {
            Logger.fatal("playerEvents should not be nil")
        }
        togglePlayListener = playerEvents.togglePlay.sink(receiveValue: { [weak self] _ in
            guard let player = self?.mediaPlayer else {
                return
            }
            if player.isPlaying {
                if self?.videoItem?.type == .livestream {
                    player.stop()
                } else {
                    player.pause()
                }
            } else {
                player.play()
            }
        })
        getTrackInfoListener = playerEvents.getTrackInfo.sink(receiveValue: { [weak self] trackId in
            DispatchQueue.main.async {
                self?.reportTrack(trackId)
            }
        })
        enableTrackListener = playerEvents.enableTrack.sink(receiveValue: { [weak self] track in
            guard let self else {
                return
            }
            let player = self.mediaPlayer
            guard track.id != "none" else {
                Logger.info("Disabling track type \(track.name)")
                switch track.name {
                case "video":
                    player.videoTracks.forEach({ $0.isSelected = false })
                case "audio":
                    player.audioTracks.forEach({ $0.isSelected = false })
                case "text":
                    // Deselecting each track individually can cause VLC to fall back to another
                    // one internally; the dedicated API avoids that.
                    player.deselectAllTextTracks()
                    self.desiredTextTrackId = "none"
                default:
                    Logger.error("Unknown track type \(track.name)")
                }
                return
            }
            Logger.info("Enabling track \(track.id) \(track.name)")
            player.videoTracks.filter({ $0.trackId == track.id }).first?.isSelectedExclusively = true
            player.audioTracks.filter({ $0.trackId == track.id }).first?.isSelectedExclusively = true
            if let textTrack = player.textTracks.first(where: { $0.trackId == track.id }) {
                textTrack.isSelectedExclusively = true
                self.desiredTextTrackId = track.id
            }
        })
        setPlaybackRateListener = playerEvents.setPlaybackRate.sink(receiveValue: { [weak self] rate in
            guard let player = self?.mediaPlayer else {
                return
            }
            player.rate = rate
        })
        setPlaybackPositionListener = playerEvents.setPlaybackPosition.sink(receiveValue: { [weak self] position in
            guard position >= 0, let player = self?.mediaPlayer else {
                return
            }
            player.position = position
        })
        setPlaybackTimeListener = playerEvents.setPlaybackTime.sink(receiveValue: { [weak self] time in
            guard let player = self?.mediaPlayer else {
                return
            }
            player.time = VLCTime(int: Int32(time * 1000))
        })
        #if os(tvOS)
        setVideoAspectRatioListener = playerEvents.setVideoAspectRatio.sink(receiveValue: { [weak self] aspectRatio in
            self?.videoAspectRatio = aspectRatio
            self?.applyVideoAspectRatio()
        })
        videoOutputReadyListener = playerEvents.videoOutputReady.sink(receiveValue: { [weak self] _ in
            self?.applyVideoAspectRatio()
        })
        #endif
        reloadMediaListener = playerEvents.reloadMedia.sink(receiveValue: { [weak self] in
            // Let SwiftUI finish the update that asked for the reload, which also updates the settings of this controller.
            DispatchQueue.main.async {
                self?.reload()
            }
        })
        togglePIPModeListener = playerEvents.togglePIPMode.sink(receiveValue: { [weak self] enable in
            guard let pipController = self?.pipController else {
                return
            }
            if enable {
                pipController.startPictureInPicture()
            } else {
                pipController.stopPictureInPicture()
            }
        })
        #if !os(macOS) && !os(tvOS)
        externalDisplayObservation = ExternalDisplayHelper.instance.observe(\.delegate, options: [.old, .new], changeHandler: { [weak self] helper, change in
            Task { @MainActor in
                let newMediaPlayer = VLCMediaPlayer()
                newMediaPlayer.delegate = self?.delegate
                if let view = change.newValue??.viewController.view {
                    newMediaPlayer.drawable = view
                    self?.playerEvents?.setExternalPlay.send(true)
                } else {
                    newMediaPlayer.drawable = self
                    self?.playerEvents?.setExternalPlay.send(false)
                }
                guard let oldPosition = self?.mediaPlayer.position else {
                    return
                }
                newMediaPlayer.media = self?.mediaPlayer.media
//                newMediaPlayer.audioStereoMode = self?.mediaPlayer.audioStereoMode
                self?.mediaPlayer.stop()
                self?.mediaPlayer = newMediaPlayer
                self?.captionClock = CaptionClock()
                self?.mediaPlayer.play()
                self?.mediaPlayer.position = oldPosition
            }
        })
        #endif

        // Playback starts in viewDidLoad, so VLC may have added tracks before the listeners above existed.
        (mediaPlayer.videoTracks + mediaPlayer.audioTracks + mediaPlayer.textTracks).forEach { reportTrack($0.trackId) }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        if let media = mediaPlayer.media {
            mediaParser.cancelParsing(for: media)
        }
        mediaPlayer.stop()
        pipController?.invalidatePlaybackState()
        
        // Prevent VLC deadlock causing main thread blocking.
        Task(priority: .background) { [mediaPlayer] in
            // Bounded so a genuinely stuck player (state never reaching .stopped) can't leave
            // this polling forever, keeping a strong reference to mediaPlayer alive forever.
            for _ in 0..<50 where mediaPlayer.state != .stopped {
                Logger.warning("VLCPlayer not stopped")
                try await Task.sleep(for: .milliseconds(100))
            }
            Logger.warning(mediaPlayer.state == .stopped ? "VLCPlayer stopped" : "VLCPlayer still not stopped after 5s, giving up")
        }
        togglePlayListener?.cancel()
        getTrackInfoListener?.cancel()
        enableTrackListener?.cancel()
        setPlaybackRateListener?.cancel()
        setPlaybackPositionListener?.cancel()
        setPlaybackTimeListener?.cancel()
        #if os(tvOS)
        setVideoAspectRatioListener?.cancel()
        videoOutputReadyListener?.cancel()
        #endif
        togglePIPModeListener?.cancel()
        reloadMediaListener?.cancel()
        externalDisplayObservation?.invalidate()
        #if os(iOS) || os(macOS)
        stopReadingCaptions()
        #endif
    }
    
    func reload() {
        mediaPlayer.stop()
        playerEvents?.resetPlayer.send()
        #if os(iOS) || os(macOS)
        stopReadingCaptions()
        if let videoItem, readsCaptions, let liveTranslator {
            loadThroughCaptionProxy(videoItem, translator: liveTranslator)
            return
        }
        if let videoItem, videoItem.url.isFileURL, savedSubtitles != nil {
            captionClock = CaptionClock()
            startTranslationClock()
        }
        #endif
        if let videoItem {
            load(videoItem, url: videoItem.url)
        }
    }

    /// Plays a video from a URL, which is the URL of the video unless it is read through the caption proxy.
    private func load(_ videoItem: any VideoItem, url: URL, readsCaptions: Bool = false) {
        Logger.info("Media URL: \(pii: url.absoluteString)")
        let media = VLCMedia(url: url)
        media?.delegate = delegate
        if forceStrokeText {
            media?.addOption("aribcaption-force-stroke-text")
        }
        if readsCaptions && videoItem.type == .livestream {
            // Buffer the stream longer, so that the model has time to translate a caption before it is shown.
            media?.addOption(":network-caching=3000")
        }
        if videoItem.url.isFileURL {
            // VLC would otherwise pick up the translations saved next to the video and show the first one,
            // while they are drawn over the video when they are selected in the player.
            media?.addOption(":no-sub-autodetect-file")
        }
        // Nothing reads the parse result (duration comes from a separate API call,
        // tracks are discovered via mediaPlayerTrackAdded during playback), and forcing
        // a full parse right as playback starts competes with the decoder for CPU/IO,
        // which shows up as stutter in the first seconds - especially on formats without
        // hardware decode (e.g. AV1 falling back to software dav1d).
        mediaPlayer.media = media
        applyVideoAspectRatio()
        // The caption proxy sends the cookies and headers to the server itself.
        if let media, !readsCaptions {
            if let cookies = HTTPCookieStorage.shared.cookies(for: videoItem.url) {
                cookies.forEach { cookie in
                    media.storeCookie("\(cookie.name)=\(cookie.value)", forHost: cookie.domain, path: cookie.path)
                }
                Logger.info("Stored \(cookies.count) cookies for player")
            }
            if let httpHeaders {
                httpHeaders.forEach { (key: String, value: String) in
                    media.storeHeader(forName: key, value: value)
                }
                Logger.info("Stored \(httpHeaders.count) headers for player")
            }
        }
        mediaPlayer.play()
    }

    #if os(iOS) || os(macOS)
    /// Plays a video through the caption proxy, which passes the captions of the stream to the translator.
    private func loadThroughCaptionProxy(_ videoItem: any VideoItem, translator: LiveSubtitleTranslator) {
        let streamID = UUID().uuidString
        let stream = CaptionStreamProxy.Stream(id: streamID, upstreamURL: videoItem.url, headers: httpHeaders ?? [:], onCaption: { [weak translator] caption, connection in
            Task { @MainActor in
                translator?.receive(caption, connection: connection)
            }
        }, onStart: { [weak translator] in
            Task { @MainActor in
                translator?.streamStarted()
            }
        }, onSeek: { [weak self] time in
            Task { @MainActor in
                guard let self, self.captionStreamID == streamID else {
                    return
                }
                self.captionClock.seek(to: time)
            }
        }, onCaptionStream: { [weak translator] found in
            Task { @MainActor in
                translator?.captionStreamFound(found)
            }
        })
        captionStreamID = streamID
        captionClock = CaptionClock()
        translator.attach(isLive: videoItem.type == .livestream)
        startTranslationClock()
        loadTask = Task { [weak self] in
            let url: URL
            do {
                url = try await CaptionStreamProxy.shared.register(stream)
            } catch {
                Logger.error("Failed to start the caption proxy: \(error)")
                guard let self, !Task.isCancelled else {
                    return
                }
                // Playing without translation is better than not playing.
                self.stopReadingCaptions()
                self.load(videoItem, url: videoItem.url)
                return
            }
            guard let self, !Task.isCancelled, self.captionStreamID == streamID else {
                CaptionStreamProxy.shared.unregister(streamID)
                return
            }
            self.load(videoItem, url: url, readsCaptions: true)
        }
    }

    private func stopReadingCaptions() {
        loadTask?.cancel()
        loadTask = nil
        translationClock?.invalidate()
        translationClock = nil
        if let captionStreamID {
            CaptionStreamProxy.shared.unregister(captionStreamID)
            self.captionStreamID = nil
            liveTranslator?.detach()
        }
    }

    /// Tells the translator or the saved translation the playback time often enough to show each translation with its caption.
    private func startTranslationClock() {
        translationClock?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                // A stopped player reads the stream from its start again when it plays.
                if [.nothingSpecial, .stopping, .stopped].contains(self.mediaPlayer.state) {
                    self.captionClock = CaptionClock()
                }
                let time = self.captionClock.captionTime(atPlaybackTime: Int(self.mediaPlayer.time.intValue),
                                                         isPlaying: self.mediaPlayer.state == .playing, rate: self.mediaPlayer.rate)
                if self.captionStreamID != nil {
                    self.liveTranslator?.update(playbackTime: time)
                } else {
                    self.savedSubtitles?.update(playbackTime: time)
                }
            }
        }
        // Keep running while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        translationClock = timer
    }
    #endif

    /// Adds a track to the menus of the player. A track may be reported more than once.
    func reportTrack(_ trackId: String) {
        guard let playerEvents else {
            return
        }
        if let track = mediaPlayer.videoTracks.first(where: { $0.trackId == trackId }) {
            playerEvents.addVideoTrack.send(MediaTrack(id: trackId, name: track.trackName, codec: track.codecName))
        }
        if let track = mediaPlayer.audioTracks.first(where: { $0.trackId == trackId }) {
            playerEvents.addAudioTrack.send(MediaTrack(id: trackId, name: track.trackName, codec: track.codecName))
        }
        if let track = mediaPlayer.textTracks.first(where: { $0.trackId == trackId }) {
            playerEvents.addTextTrack.send(MediaTrack(id: trackId, name: track.trackName, codec: track.codecName))
        }
    }

    func applyVideoAspectRatio() {
        #if os(tvOS)
        mediaPlayer.videoAspectRatio = nil
        mediaPlayer.setCropRatioWithNumerator(0, denominator: 0)
        mediaPlayer.scaleFactor = 0
        if videoAspectRatio == .zoom {
            mediaPlayer.setCropRatioWithNumerator(16, denominator: 9)
        } else if let aspectRatio = videoAspectRatio.vlcValue {
            mediaPlayer.videoAspectRatio = aspectRatio
        }
        Logger.info("Applied video aspect ratio: \(videoAspectRatio.rawValue)")
        #else
        mediaPlayer.videoAspectRatio = force16To9 ? "16:9" : nil
        #endif
    }
}

#if os(macOS)
class DisabledView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
#endif

extension VLCPlayerViewController: @preconcurrency VLCDrawable {
    func addSubview(_ view: UIView!) {
        self.videoView.addSubview(view)
    }
    
    func bounds() -> CGRect {
        return videoView.bounds
    }
}

extension VLCPlayerViewController: @preconcurrency VLCPictureInPictureMediaControlling, @preconcurrency VLCPictureInPictureDrawable {
    
    func play() {
        mediaPlayer.play()
    }
    
    func pause() {
        if videoItem?.type == .livestream {
            mediaPlayer.stop()
        } else {
            mediaPlayer.pause()
        }
    }
    
    func seek(by offset: Int64) async {
        guard videoItem?.type != .livestream else {
            return
        }
        mediaPlayer.jump(withOffset: Int32(offset))
    }
    
    func mediaLength() -> Int64 {
        return videoItem?.type != .livestream ? Int64(mediaPlayer.media?.length.value?.intValue ?? 0) : 0
    }
    
    func mediaTime() -> Int64 {
        return videoItem?.type != .livestream ? Int64(mediaPlayer.time.intValue) : 0
    }
    
    func isMediaSeekable() -> Bool {
        return mediaPlayer.isSeekable && videoItem?.type != .livestream
    }
    
    func isMediaPlaying() -> Bool {
        return mediaPlayer.isPlaying
    }
    
    func mediaController() -> (any VLCPictureInPictureMediaControlling)! {
        return self
    }
    
    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)! {
        return { [weak self] pipController in
            pipController?.stateChangeEventHandler = { [weak self] started in
                self?.playerEvents?.setPIPEnabled.send(started)
            }
            self?.playerEvents?.setPIPSupported.send(true)
            self?.pipController = pipController
        }
    }
}

extension VLCMediaPlayer.Track {
    var codecName: String {
        if codecName() != "" {
            return codecName()
        }
        return String(bytes: withUnsafeBytes(of: codec.littleEndian, Array.init), encoding: .ascii) ?? "\(codec)"
    }
}

#if os(tvOS)
// Temporary diagnostic for the tvOS stutter investigation, see viewDidLoad.
private final class VLCDiagnosticLogger: NSObject, VLCLogging {
    var level: VLCLogLevel = .debug

    private static let keywords = [
        "hardware", "videotoolbox", "decoder", "decode", "late", "drop", "corrupt", "fallback",
        "vout", "chroma", "convert", "swscale", "opengl", "caopengllayer", "cvpx", "filter",
    ]

    private let startTime = Date()

    func handleMessage(_ message: String, logLevel level: VLCLogLevel, context: VLCLogContext?) {
        // Module selection (decoder, vout, chroma converter, ...) is only logged once at
        // startup and its exact wording isn't predictable, so log everything unfiltered for
        // the first few seconds, then fall back to keyword filtering to avoid a firehose.
        guard Date().timeIntervalSince(startTime) < 5 || Self.keywords.contains(where: { message.lowercased().contains($0) }) else {
            return
        }
        // Logger.debug is filtered out entirely in Release builds, so use .warning here
        // to guarantee this shows up when testing on a real device.
        Logger.warning("[VLC][\(context?.module ?? "?")] \(message)")
    }
}
#endif

