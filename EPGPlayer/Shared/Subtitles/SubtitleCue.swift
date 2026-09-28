//
//  SubtitleCue.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/25.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation

/// A piece of subtitle text with its display interval in milliseconds of playback time.
struct SubtitleCue: Sendable, Equatable {
    var start: Int
    var end: Int
    var text: String

    /// Arrow that ARIB captions put at the end of a line whose sentence continues in the next caption
    /// (U+FFEB, which becomes U+2192 after compatibility normalization).
    static let continuationMark = "→"
    /// How long the last caption stays on screen when it has no duration of its own.
    private static let defaultLastDuration = 5000

    /// Converts decoded captions to display cues. A caption stays on screen for its own duration if it has one,
    /// but never past the next caption. Empty captions only clear the screen and produce no cue.
    static func cues(from captions: [ARIBCaption]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for (index, caption) in captions.enumerated() {
            let text = normalize(caption.text)
            guard !text.isEmpty else {
                continue
            }
            let nextStart = captions[(index + 1)...].first(where: { $0.time > caption.time })?.time
            var end = nextStart ?? caption.time + (caption.duration ?? defaultLastDuration)
            if let duration = caption.duration {
                end = min(end, caption.time + duration)
            }
            if let last = cues.last, last.start == caption.time {
                // Statements with the same timestamp are shown together.
                cues[cues.count - 1].text += "\n" + text
                cues[cues.count - 1].end = max(last.end, end)
            } else {
                cues.append(SubtitleCue(start: caption.time, end: end, text: text))
            }
        }
        return cues
    }

    /// Merges consecutive cues that are linked by the continuation arrow, so that each cue holds complete sentences.
    /// A merged cue spans from the start of its first piece to the end of its last piece.
    static func sentences(from cues: [SubtitleCue]) -> [SubtitleCue] {
        var sentences: [SubtitleCue] = []
        var pending: SubtitleCue?
        for cue in cues {
            var piece = cue
            let continues = piece.text.hasSuffix(continuationMark)
            if continues {
                piece.text = String(piece.text.dropLast(continuationMark.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if var merged = pending {
                // Japanese has no spaces between words, but joining without a separator glues
                // unrelated words together (e.g. a name and the next place name).
                merged.text = [merged.text, piece.text].filter { !$0.isEmpty }.joined(separator: " ")
                merged.end = piece.end
                pending = merged
            } else {
                pending = piece
            }
            if !continues, let merged = pending {
                sentences.append(merged)
                pending = nil
            }
        }
        if let pending {
            sentences.append(pending)
        }
        return sentences
    }

    /// Applies compatibility normalization (half-width katakana and punctuation, full-width digits)
    /// and trims surrounding whitespace.
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Serializes cues in SubRip format.
    static func srt(from cues: [SubtitleCue]) -> String {
        var output = ""
        var index = 0
        for cue in cues {
            // A blank line ends an SRT cue, so drop empty lines inside the text.
            let text = cue.text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !text.isEmpty else {
                continue
            }
            index += 1
            output += "\(index)\n\(srtTime(cue.start)) --> \(srtTime(cue.end))\n\(text)\n\n"
        }
        return output
    }

    private static func srtTime(_ milliseconds: Int) -> String {
        let ms = max(milliseconds, 0)
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    /// Parses cues in SubRip format, as written by `srt(from:)`.
    static func cues(fromSRT srt: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var current: SubtitleCue?
        for line in srt.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if var cue = current {
                // A blank line ends the cue.
                guard !line.isEmpty else {
                    cues.append(cue)
                    current = nil
                    continue
                }
                cue.text += cue.text.isEmpty ? line : "\n" + line
                current = cue
            } else if let arrow = line.range(of: "-->"),
                      let start = milliseconds(fromSRTTime: line[..<arrow.lowerBound]),
                      let end = milliseconds(fromSRTTime: line[arrow.upperBound...]) {
                current = SubtitleCue(start: start, end: end, text: "")
            }
        }
        if let current {
            cues.append(current)
        }
        return cues.filter { !$0.text.isEmpty }
    }

    /// Reads a time like "01:02:03,456", which may be followed by the position of the cue.
    private static func milliseconds(fromSRTTime text: Substring) -> Int? {
        let time = text.trimmingCharacters(in: .whitespaces).prefix { !$0.isWhitespace }
        let parts = time.split(whereSeparator: { $0 == ":" || $0 == "," || $0 == "." })
        guard parts.count == 4, let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Int(parts[2]), let ms = Int(parts[3]) else {
            return nil
        }
        return ((hours * 60 + minutes) * 60 + seconds) * 1000 + ms
    }
}
