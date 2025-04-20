//
//  PlayerEvents.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//
//  SPDX-License-Identifier: MPL-2.0

@preconcurrency import Combine
import SwiftUI
import VLCKit

final class PlayerEvents: ObservableObject, Sendable {
    let togglePlay = PassthroughSubject<Void, Never>()
    let getTrackInfo = PassthroughSubject<String, Never>()
    let resetPlayer = PassthroughSubject<Void, Never>()
    
    let addVideoTrack = PassthroughSubject<MediaTrack, Never>()
    let addAudioTrack = PassthroughSubject<MediaTrack, Never>()
    let addTextTrack = PassthroughSubject<MediaTrack, Never>()
    
    let enableTrack = PassthroughSubject<MediaTrack, Never>()
    let setPlaybackRate = PassthroughSubject<Float, Never>()
    let setPlaybackPosition = PassthroughSubject<Double, Never>()
    let setPlaybackTime = PassthroughSubject<Double, Never>()
    
    let updatePosition = PassthroughSubject<PlaybackPosition, Never>()
    let updateStats = PassthroughSubject<VLCMedia.Stats, Never>()
    
    let setPIPSupported = CurrentValueSubject<Bool, Never>(false)
    let setPIPEnabled = PassthroughSubject<Bool, Never>()
    let togglePIPMode = PassthroughSubject<Bool, Never>()
    
    let setExternalPlay = CurrentValueSubject<Bool, Never>(false)
    
    let userInteracted = PassthroughSubject<Void, Never>()
    
    #if !os(macOS)
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleUserInteraction), name: .userActivityDetected, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleUserInteraction(_ notification: Notification) {
        userInteracted.send()
    }
    #endif
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
