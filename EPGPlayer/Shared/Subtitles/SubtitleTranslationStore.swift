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

    /// Name of the language of the translation in the player, e.g. "English".
    var languageName: String {
        let identifier = Self.displayIdentifier(of: targetLanguage)
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Names Chinese by its script, since the file names of Chinese translations are "zh" and "zh-TW".
    private static func displayIdentifier(of language: Locale.Language) -> String {
        if language.languageCode == .chinese, let script = Locale.Language(identifier: language.maximalIdentifier).script {
            return "zh-\(script.identifier)"
        }
        return language.minimalIdentifier
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
            guard url.lastPathComponent.hasPrefix(prefix), let (source, target) = languages(of: url) else {
                return nil
            }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return SubtitleTranslation(url: url, sourceLanguage: source, targetLanguage: target, modificationDate: date)
        }
        .sorted { $0.modificationDate > $1.modificationDate }
    }

    private static func languages(of url: URL) -> (source: Locale.Language, target: Locale.Language)? {
        guard url.pathExtension == "srt" else {
            return nil
        }
        // Language identifiers such as "zh-Hans" contain no dots.
        let languages = url.deletingPathExtension().pathExtension.split(separator: "_")
        guard languages.count == 2 else {
            return nil
        }
        return (Locale.Language(identifier: String(languages[0])), Locale.Language(identifier: String(languages[1])))
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
