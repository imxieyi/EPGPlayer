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
}

struct MediaTrack: Hashable, Identifiable {
    let id: String
    let name: String
    let codec: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
