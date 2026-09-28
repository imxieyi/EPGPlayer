//
//  CaptionClock.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/28.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import Foundation

/// Converts the playback time of VLC to the time of the captions that the caption proxy reads.
///
/// VLC counts the time from the first PCR that it reads, and keeps counting from there until the playback stops.
/// The captions are timed from the first PCR of the stream. The two differ when VLC seeks before it has read
/// a PCR, which happens when the saved position is restored as soon as the playback starts.
/// VLC then counts from the first PCR after the seek.
///
/// VLC also only updates the playback time about once a second, so the time in between is counted from the last update.
/// An update can put the time a little behind that count, so the time doesn't go back by that much while VLC plays.
/// Otherwise the previous caption would show again for a moment when a caption changes.
struct CaptionClock {
    /// Longer than the time between the updates of VLC, but short enough to stay close to a stream that stalls.
    private static let maxTimeSinceUpdate = 1_200

    private var seekTime: Int?
    /// The first playback time after the clock started, which VLC keeps reporting until it shows the video.
    private var initialTime: Int?
    private var hasShownVideo = false
    private var offset = 0
    /// The last playback time that VLC reported, and when it was reported.
    private var lastUpdate: (time: Int, date: TimeInterval)?
    /// The latest caption time returned while VLC plays.
    private var latestCaptionTime: Int?

    /// Called with the caption time where a connection that VLC opened to seek starts.
    mutating func seek(to time: Int) {
        // Once VLC shows the video, it has read a PCR and its time stays in step with the captions.
        if !hasShownVideo {
            seekTime = time
        }
    }

    /// Returns the caption time of the video that VLC shows at a playback time, or 0 before it shows the video.
    mutating func captionTime(atPlaybackTime time: Int, isPlaying: Bool, rate: Float) -> Int {
        let timeSinceUpdate = self.timeSinceUpdate(to: time, isPlaying: isPlaying, rate: rate)
        guard hasShownVideo || startsVideo(atPlaybackTime: time) else {
            return 0
        }
        let captionTime = time + offset + timeSinceUpdate
        // Going back further than the count can run ahead is a seek.
        if isPlaying, let latestCaptionTime, captionTime < latestCaptionTime, latestCaptionTime - captionTime <= Self.maxTimeSinceUpdate {
            return latestCaptionTime
        }
        latestCaptionTime = captionTime
        return captionTime
    }

    private mutating func timeSinceUpdate(to time: Int, isPlaying: Bool, rate: Float) -> Int {
        let now = ProcessInfo.processInfo.systemUptime
        guard isPlaying, let lastUpdate, lastUpdate.time == time else {
            // VLC reported a new time, or the time stands still because the player doesn't play.
            lastUpdate = (time, now)
            return 0
        }
        return min(Int((now - lastUpdate.date) * 1000 * Double(rate)), Self.maxTimeSinceUpdate)
    }

    private mutating func startsVideo(atPlaybackTime time: Int) -> Bool {
        // Until VLC shows the video, it reports 0 or the time where the previous playback stopped.
        guard let initialTime else {
            initialTime = time
            return false
        }
        // VLC also reports 0 while it seeks.
        guard time != initialTime, time != 0 else {
            return false
        }
        hasShownVideo = true
        // Counting from the first PCR of the stream, VLC shows about the time of the seek.
        // Counting from the first PCR after the seek, it shows about 0.
        if let seekTime, time < seekTime / 2 {
            offset = seekTime
            Logger.info("VLC counts the playback time from \(seekTime) ms of the stream")
        }
        return true
    }
}
#endif
