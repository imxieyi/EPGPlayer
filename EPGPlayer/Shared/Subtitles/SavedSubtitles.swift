//
//  SavedSubtitles.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/28.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import Foundation
import Observation

/// Shows a translation saved next to a downloaded video, in the same way as the live translation of a stream.
@MainActor
@Observable
final class SavedSubtitles {
    /// The translation to show, or nil when the translation is off.
    private(set) var translation: SubtitleTranslation?
    /// The translation of the captions shown at the current playback time.
    private(set) var visibleText: String?

    @ObservationIgnored private var cues: [SubtitleCue] = []
    @ObservationIgnored private var playbackTime = 0

    func show(_ translation: SubtitleTranslation?) {
        guard translation != self.translation else {
            return
        }
        self.translation = translation
        cues = []
        if let translation {
            do {
                cues = SubtitleCue.cues(fromSRT: try String(contentsOf: translation.url, encoding: .utf8))
                Logger.info("Loaded \(cues.count) translated subtitles from \(pii: translation.url.lastPathComponent)")
            } catch let error {
                Logger.error("Failed to read translated subtitles \(pii: translation.url.lastPathComponent): \(error)")
            }
        }
        update(playbackTime: playbackTime)
    }

    func update(playbackTime: Int) {
        self.playbackTime = playbackTime
        let lines = cues.filter { $0.start <= playbackTime && playbackTime < $0.end }.map(\.text)
        let text = lines.isEmpty ? nil : lines.joined(separator: "\n")
        if text != visibleText {
            visibleText = text
        }
    }
}
#endif
