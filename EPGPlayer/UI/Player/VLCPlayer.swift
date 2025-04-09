//
//  VLCPlayer.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//

import os
import AVKit
@preconcurrency import VLCKit
import SwiftUI
import Combine

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EPGPlayer", category: "player")

struct VLCPlayer: UIViewControllerRepresentable {
    let videoURL: URL
    let playerEvents: PlayerEvents
    
    @Binding var playerState: VLCMediaPlayerState

    func makeUIViewController(context: Context) -> VLCPlayerViewController {
        let playerVC = VLCPlayerViewController()
        playerVC.delegate = context.coordinator
        playerVC.playerEvents = playerEvents
        playerVC.videoURL = videoURL
        return playerVC
    }

    func updateUIViewController(_ uiViewController: VLCPlayerViewController, context: Context) {
        guard uiViewController.videoURL != videoURL else {
            return
        }
        uiViewController.videoURL = videoURL
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
            logger.debug("Player state changed: \(newState.rawValue)")
            Task { @MainActor [parent] in
                parent.playerState = newState
            }
        }
        
        func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
            logger.info("Track added: \(trackId) type \(trackType.rawValue)")
            Task { @MainActor [weak playerEvents] in
                playerEvents?.getTrackInfo.send(trackId)
            }
        }
        
        func mediaPlayerLengthChanged(_ length: Int64) {
            print("Length: \(length)")
        }
        
        func mediaPlayerTimeChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else {
                print("mediaPlayerTimeChanged: wrong object type")
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
            logger.info("Finished parsing media, status \(aMedia.parsedStatus.rawValue), length \(aMedia.length)")
        }
    }
}

class VLCPlayerViewController: UIViewController {
    var mediaPlayer = VLCMediaPlayer()
    var videoURL: URL?
    var delegate: VLCPlayer.Coordinator?
    var playerEvents: PlayerEvents?
    
    var videoView: UIView!
    var pipController: VLCPictureInPictureWindowControlling?
    var pipPossibleObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        videoView = UIView(frame: view.bounds)
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoView.isUserInteractionEnabled = false
        view.addSubview(videoView)
        
        if let externalView = ExternalDisplayHelper.instance.delegate?.viewController.view {
            mediaPlayer.drawable = externalView
            playerEvents?.setExternalPlay.send(true)
        } else {
            mediaPlayer.drawable = self
            playerEvents?.setExternalPlay.send(false)
        }
        mediaPlayer.delegate = delegate

        if let url = videoURL {
            logger.debug("Media URL: \(url.absoluteString)")
            let media = VLCMedia(url: url)
            media?.delegate = delegate
            media?.parse(options: [.parseForced], timeout: .max)
            mediaPlayer.media = media
            HTTPCookieStorage.shared.cookies?.forEach { cookie in
                media?.storeCookie("\(cookie.name)=\(cookie.value)", forHost: cookie.domain, path: cookie.path)
            }
            mediaPlayer.play()
        }
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
            fatalError("playerEvents should not be nil")
        }
        togglePlayListener = playerEvents.togglePlay.sink(receiveValue: { [weak self] _ in
            guard let player = self?.mediaPlayer else {
                return
            }
            if player.isPlaying {
                player.pause()
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
                print("Disabling track type \(track.name)")
                switch track.name {
                case "video":
                    player.videoTracks.forEach({ $0.isSelected = false })
                case "audio":
                    player.audioTracks.forEach({ $0.isSelected = false })
                case "text":
                    player.textTracks.forEach({ $0.isSelected = false })
                default:
                    print("Unknown track type \(track.name)")
                }
                return
            }
            print("Enabling track \(track.id) \(track.name)")
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
            guard let player = self?.mediaPlayer else {
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
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        mediaPlayer.stop()
        pipController?.invalidatePlaybackState()
        Task.detached(priority: .background) { [mediaPlayer] in
            while mediaPlayer.state != .stopped {
                logger.warning("VLCPlayer not stopped")
                try await Task.sleep(for: .milliseconds(100))
            }
            logger.warning("VLCPlayer stopped")
        }
        togglePlayListener?.cancel()
        getTrackInfoListener?.cancel()
        enableTrackListener?.cancel()
        setPlaybackRateListener?.cancel()
        setPlaybackPositionListener?.cancel()
        setPlaybackTimeListener?.cancel()
        togglePIPModeListener?.cancel()
    }
    
    func reload() {
        if let url = videoURL {
            let media = VLCMedia(url: url)
            media?.delegate = delegate
            mediaPlayer.media = media
            mediaPlayer.play()
        } else {
            mediaPlayer.stop()
        }
    }
}

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
        mediaPlayer.pause()
    }
    
    func seek(by offset: Int64) async {
        mediaPlayer.jump(withOffset: Int32(offset))
    }
    
    func mediaLength() -> Int64 {
        return Int64(mediaPlayer.media?.length.value?.intValue ?? 0)
    }
    
    func mediaTime() -> Int64 {
        return Int64(mediaPlayer.time.intValue)
    }
    
    func isMediaSeekable() -> Bool {
        return mediaPlayer.isSeekable
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
