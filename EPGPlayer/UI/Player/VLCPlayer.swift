//
//  VLCPlayer.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//
import VLCKit
import SwiftUI

struct VLCPlayerView: UIViewControllerRepresentable {
    let videoURL: URL

    func makeUIViewController(context: Context) -> VLCPlayerViewController {
        let playerVC = VLCPlayerViewController()
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
}

class VLCPlayerViewController: UIViewController {
    var mediaPlayer = VLCMediaPlayer()
    var videoURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()

        let videoView = UIView(frame: view.bounds)
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(videoView)

        mediaPlayer.drawable = videoView

        if let url = videoURL {
            let media = VLCMedia(url: url)
            mediaPlayer.media = media
            HTTPCookieStorage.shared.cookies?.forEach { cookie in
                media?.storeCookie("\(cookie.name)=\(cookie.value)", forHost: cookie.domain, path: cookie.path)
            }
            mediaPlayer.play()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Delay to allow tracks to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.enableSubtitles()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        mediaPlayer.stop()
    }
    
    func reload() {
        if let url = videoURL {
            let media = VLCMedia(url: url)
            mediaPlayer.media = media
            mediaPlayer.play()
            
            // Delay to allow tracks to load
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.enableSubtitles()
            }
        } else {
            mediaPlayer.stop()
        }
    }

    func enableSubtitles() {
        for track in mediaPlayer.textTracks {
            print(track)
            if track.type == VLCMedia.TrackType.text {
                track.isSelected = true
                break
            }
        }
        print(mediaPlayer.textTracks)
    }
}
