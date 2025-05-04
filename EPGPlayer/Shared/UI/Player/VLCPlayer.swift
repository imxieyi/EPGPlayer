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
    
    @Binding var playerState: VLCMediaPlayerState
    @Binding var hadErrorState: Bool
    @Binding var hadPlayingState: Bool
    
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
        playerVC.playerEvents = playerEvents
        playerVC.videoItem = videoItem
        playerVC.httpHeaders = httpHeaders
        return playerVC
    }

    func updateViewController(_ uiViewController: VLCPlayerViewController, context: Context) {
        guard uiViewController.videoItem?.epgId != videoItem.epgId else {
            return
        }
        uiViewController.videoItem = videoItem
        uiViewController.httpHeaders = httpHeaders
        uiViewController.forceStrokeText = forceStrokeText
        uiViewController.reload()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, playerEvents: playerEvents)
    }
    
    class Coordinator: NSObject, VLCMediaPlayerDelegate, VLCMediaDelegate {
        let parent: VLCPlayer
        weak var playerEvents: PlayerEvents?
        
        init(parent: VLCPlayer, playerEvents: PlayerEvents) {
            self.parent = parent
            self.playerEvents = playerEvents
        }
        
        func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
            Logger.debug("Player state changed: \(newState.rawValue)")
            Task { @MainActor [parent] in
                parent.playerState = newState
                if newState == .error {
                    parent.hadErrorState = true
                } else if newState == .opening {
                    parent.hadErrorState = false
                } else if newState == .playing {
                    parent.hadPlayingState = true
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
    var httpHeaders: [String: String]?
    var videoItem: VideoItem?
    var delegate: VLCPlayer.Coordinator?
    var playerEvents: PlayerEvents?
    
    var forceStrokeText: Bool = false
    
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

        reload()
    }
    
    var togglePlayListener: AnyCancellable?
    var getTrackInfoListener: AnyCancellable?
    var enableTrackListener: AnyCancellable?
    var setPlaybackRateListener: AnyCancellable?
    var setPlaybackPositionListener: AnyCancellable?
    var setPlaybackTimeListener: AnyCancellable?
    var togglePIPModeListener: AnyCancellable?
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
            guard let player = self?.mediaPlayer else {
                return
            }
            DispatchQueue.main.async {
                if let track = player.videoTracks.filter({ $0.trackId == trackId }).first {
                    playerEvents.addVideoTrack.send(MediaTrack(id: trackId, name: track.trackName, codec: track.codecName))
                }
                if let track = player.audioTracks.filter({ $0.trackId == trackId }).first {
                    playerEvents.addAudioTrack.send(MediaTrack(id: trackId, name: track.trackName, codec: track.codecName))
                }
                if let track = player.textTracks.filter({ $0.trackId == trackId }).first {
                    playerEvents.addTextTrack.send(MediaTrack(id: trackId, name: track.trackName, codec: track.codecName))
                }
            }
        })
        enableTrackListener = playerEvents.enableTrack.sink(receiveValue: { [weak self] track in
            guard let player = self?.mediaPlayer else {
                return
            }
            guard track.id != "none" else {
                Logger.info("Disabling track type \(track.name)")
                switch track.name {
                case "video":
                    player.videoTracks.forEach({ $0.isSelected = false })
                case "audio":
                    player.audioTracks.forEach({ $0.isSelected = false })
                case "text":
                    player.textTracks.forEach({ $0.isSelected = false })
                default:
                    Logger.error("Unknown track type \(track.name)")
                }
                return
            }
            Logger.info("Enabling track \(track.id) \(track.name)")
            player.videoTracks.filter({ $0.trackId == track.id }).first?.isSelectedExclusively = true
            player.audioTracks.filter({ $0.trackId == track.id }).first?.isSelectedExclusively = true
            player.textTracks.filter({ $0.trackId == track.id }).first?.isSelectedExclusively = true
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
                self?.mediaPlayer.stop()
                self?.mediaPlayer = newMediaPlayer
                self?.mediaPlayer.play()
                self?.mediaPlayer.position = oldPosition
            }
        })
        #endif
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        mediaPlayer.media?.parseStop()
        mediaPlayer.stop()
        pipController?.invalidatePlaybackState()
        
        // Prevent VLC deadlock causing main thread blocking.
        Task(priority: .background) { [mediaPlayer] in
            while mediaPlayer.state != .stopped {
                Logger.warning("VLCPlayer not stopped")
                try await Task.sleep(for: .milliseconds(100))
            }
            Logger.warning("VLCPlayer stopped")
        }
        togglePlayListener?.cancel()
        getTrackInfoListener?.cancel()
        enableTrackListener?.cancel()
        setPlaybackRateListener?.cancel()
        setPlaybackPositionListener?.cancel()
        setPlaybackTimeListener?.cancel()
        togglePIPModeListener?.cancel()
        externalDisplayObservation?.invalidate()
    }
    
    func reload() {
        mediaPlayer.stop()
        playerEvents?.resetPlayer.send()
        if let videoItem {
            Logger.info("Media URL: \(pii: videoItem.url.absoluteString)")
            let media = VLCMedia(url: videoItem.url)
            media?.delegate = delegate
            if forceStrokeText {
                media?.addOption("aribcaption-force-stroke-text")
            }
            if videoItem.type != .livestream {
                media?.parse(options: [.parseForced], timeout: .max)
            }
            mediaPlayer.media = media
            if let media {
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
