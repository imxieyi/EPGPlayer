//
//  SubtitleFonts.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/26.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS)
import CoreText
import Foundation

enum SubtitleFontError: Error {
    case unavailable
}

/// VLC renders translated subtitles with FreeType, which can't read the outlines of PingFang, the only built-in font
/// with simplified Chinese characters on iOS 27. Hiragino Sans GB is a system font that iOS downloads on demand
/// and FreeType can render, but only the process that activated it can use it, so it has to be activated in each launch.
enum SubtitleFonts {
    private static let chineseFontName = "HiraginoSansGB-W3"

    static func needsDownloadableFont(for language: Locale.Language) -> Bool {
        language.languageCode == .chinese
    }

    /// Activates the font for the translations saved in a directory, if any of them needs it.
    static func activateForTranslations(in directory: URL) {
        guard SubtitleTranslationStore.targetLanguages(in: directory).contains(where: needsDownloadableFont) else {
            return
        }
        Task(priority: .utility) {
            do {
                try await activate()
            } catch let error {
                Logger.error("Failed to activate the subtitle font: \(error)")
            }
        }
    }

    /// Activates the font, downloading it first if needed.
    static func activate() async throws {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: chineseFontName] as CFDictionary)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // The handler is called serially. Resume on the first failure, since a failed download may not finish.
            var resumed = false
            let started = CTFontDescriptorMatchFontDescriptorsWithProgressHandler([descriptor] as CFArray, nil) { state, parameters in
                guard !resumed else {
                    return true
                }
                let parameters = parameters as NSDictionary
                switch state {
                case .didFailWithError:
                    resumed = true
                    continuation.resume(throwing: parameters[kCTFontDescriptorMatchingError] as? Error ?? SubtitleFontError.unavailable)
                case .didFinish:
                    resumed = true
                    if let matched = parameters[kCTFontDescriptorMatchingResult] as? [CTFontDescriptor], !matched.isEmpty {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: SubtitleFontError.unavailable)
                    }
                default:
                    break
                }
                return true
            }
            if !started {
                continuation.resume(throwing: SubtitleFontError.unavailable)
            }
        }
        Logger.info("Activated subtitle font \(chineseFontName)")
    }
}
#endif
