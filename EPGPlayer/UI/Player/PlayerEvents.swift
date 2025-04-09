//
//  PlayerEvents.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import Combine
import VLCKit

class PlayerEvents: ObservableObject {
    let togglePlay = PassthroughSubject<Void, Never>()
    let getTrackInfo = PassthroughSubject<String, Never>()
    
    let addVideoTrack = PassthroughSubject<MediaTrack, Never>()
    let addAudioTrack = PassthroughSubject<MediaTrack, Never>()
    let addTextTrack = PassthroughSubject<MediaTrack, Never>()
    
    let enableTrack = PassthroughSubject<MediaTrack, Never>()
    let setPlaybackRate = PassthroughSubject<Float, Never>()
    let setPlaybackPosition = PassthroughSubject<Double, Never>()
    let setPlaybackTime = PassthroughSubject<Double, Never>()
    
    let updatePosition = PassthroughSubject<PlaybackPosition, Never>()
    let updateStats = PassthroughSubject<VLCMedia.Stats, Never>()
    
    let userInteracted = PassthroughSubject<Void, Never>()
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleUserInteraction), name: .userActivityDetected, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleUserInteraction(_ notification: Notification) {
        userInteracted.send()
    }
}

struct MediaTrack: Hashable, Identifiable {
    let id: String
    let name: String
    let codec: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PlaybackPosition {
    let time: Int
    let position: Double
}
