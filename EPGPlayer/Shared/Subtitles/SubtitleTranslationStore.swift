//
//  SubtitleTranslationStore.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/25.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation

/// A translated subtitle file saved next to a downloaded video.
struct SubtitleTranslation: Sendable, Hashable {
    let url: URL
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
    let modificationDate: Date

    /// Name of the subtitle track in the player, e.g. "English (Translated)".
    var trackName: String {
        let language = Locale.current.localizedString(forIdentifier: targetLanguage.minimalIdentifier) ?? targetLanguage.minimalIdentifier
        return String(localized: "\(language) (Translated)")
    }
}

/// Translations are stored as `<video file name>.<source>_<target>.srt` in the same directory as the video,
/// so they need no database entry and can be found from the video URL alone.
enum SubtitleTranslationStore {
    static func fileURL(forVideo videoURL: URL, source: Locale.Language, target: Locale.Language) -> URL {
        videoURL.deletingLastPathComponent()
            .appending(path: "\(videoURL.lastPathComponent).\(source.minimalIdentifier)_\(target.minimalIdentifier).srt")
    }

    /// Returns the translations of a video, newest first.
    static func translations(forVideo videoURL: URL) -> [SubtitleTranslation] {
        let prefix = videoURL.lastPathComponent + "."
        let contents = (try? FileManager.default.contentsOfDirectory(at: videoURL.deletingLastPathComponent(), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return contents.compactMap { url -> SubtitleTranslation? in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), url.pathExtension == "srt" else {
                return nil
            }
            let languages = name.dropFirst(prefix.count).dropLast(".srt".count).split(separator: "_")
            guard languages.count == 2 else {
                return nil
            }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return SubtitleTranslation(url: url, sourceLanguage: Locale.Language(identifier: String(languages[0])), targetLanguage: Locale.Language(identifier: String(languages[1])), modificationDate: date)
        }
        .sorted { $0.modificationDate > $1.modificationDate }
    }

    static func save(_ cues: [SubtitleCue], forVideo videoURL: URL, source: Locale.Language, target: Locale.Language) throws {
        let url = fileURL(forVideo: videoURL, source: source, target: target)
        try SubtitleCue.srt(from: cues).write(to: url, atomically: true, encoding: .utf8)
        Logger.info("Saved \(cues.count) translated subtitles to \(pii: url.lastPathComponent)")
    }

    static func deleteTranslations(forVideo videoURL: URL) {
        for translation in translations(forVideo: videoURL) {
            do {
                try FileManager.default.removeItem(at: translation.url)
            } catch let error {
                Logger.error("Failed to delete subtitle translation \(pii: translation.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
