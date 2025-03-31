//
//  VLCPlayer.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//
import VLCKit
import SwiftUI
import Combine

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
    
    @MainActor
    class Coordinator: NSObject, @preconcurrency VLCMediaPlayerDelegate {
        let parent: VLCPlayer
        weak var playerEvents: PlayerEvents?
        
        init(parent: VLCPlayer, playerEvents: PlayerEvents) {
            self.parent = parent
            self.playerEvents = playerEvents
        }
        
        func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
            parent.playerState = newState
        }
        
        func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
            print("Track added:", trackId, trackType.rawValue)
            playerEvents?.getTrackInfo.send(trackId)
        }
    }
}

class VLCPlayerViewController: UIViewController {
    var mediaPlayer = VLCMediaPlayer()
    var videoURL: URL?
    var delegate: VLCMediaPlayerDelegate? = nil
    var playerEvents: PlayerEvents?

    override func viewDidLoad() {
        super.viewDidLoad()

        let videoView = UIView(frame: view.bounds)
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(videoView)

        mediaPlayer.drawable = videoView
        mediaPlayer.delegate = delegate

        if let url = videoURL {
            let media = VLCMedia(url: url)
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
                if let textTrack = player.textTracks.filter({ $0.trackId == trackId }).first {
                    playerEvents.addTextTrack.send(MediaTrack(id: trackId, name: textTrack.trackName, codec: textTrack.codecName()))
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
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        mediaPlayer.stop()
        togglePlayListener?.cancel()
        getTrackInfoListener?.cancel()
        enableTrackListener?.cancel()
    }
    
    func reload() {
        if let url = videoURL {
            let media = VLCMedia(url: url)
            mediaPlayer.media = media
            mediaPlayer.play()
        } else {
            mediaPlayer.stop()
        }
    }
}
