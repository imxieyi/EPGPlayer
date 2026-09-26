//
//  SubtitleTranslationJob.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/25.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

enum SubtitleTranslationError: LocalizedError {
    case noSubtitles

    var errorDescription: String? {
        switch self {
        case .noSubtitles:
            return String(localized: "The video file has no ARIB subtitles.")
        }
    }
}

/// Extracts the ARIB subtitles of a downloaded video, translates them and saves the result as an SRT file.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
@Observable
final class SubtitleTranslationJob {
    enum Phase: Equatable {
        case idle
        case readingSubtitles(progress: Double)
        case translating(completed: Int, total: Int)
        /// Lines that could not be translated are saved in Japanese and listed.
        case finished(count: Int, untranslated: [SubtitleTranslator.UntranslatedLine])
        case failed(message: String)
        case cancelled
    }

    /// ARIB subtitles are always in Japanese.
    static let sourceLanguage = Locale.Language(identifier: "ja")

    private(set) var phase = Phase.idle

    var isRunning: Bool {
        switch phase {
        case .readingSubtitles, .translating:
            return true
        default:
            return false
        }
    }

    private let videoURL: URL
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var extractionTask: Task<[ARIBCaption], Error>?

    init(videoURL: URL) {
        self.videoURL = videoURL
    }

    func start(model: any SubtitleTranslationModel, target: Locale.Language, program: SubtitleProgramInfo?) {
        guard !isRunning else {
            return
        }
        phase = .readingSubtitles(progress: 0)
        task = Task {
            await run(model: model, target: target, program: program)
        }
    }

    private func run(model: any SubtitleTranslationModel, target: Locale.Language, program: SubtitleProgramInfo?) async {
        let wakeLock = acquireWakeLock()
        defer {
            releaseWakeLock(wakeLock)
            extractionTask = nil
            task = nil
        }
        do {
            let videoURL = self.videoURL
            let extraction = Task.detached(priority: .userInitiated) { [weak self] in
                var lastReported = 0.0
                return try ARIBCaptionExtractor.extract(from: videoURL) { progress in
                    guard progress - lastReported >= 0.01 || progress == 1 else {
                        return
                    }
                    lastReported = progress
                    Task { @MainActor in
                        self?.updateReadingProgress(progress)
                    }
                }
            }
            extractionTask = extraction
            let captions = try await withTaskCancellationHandler {
                try await extraction.value
            } onCancel: {
                extraction.cancel()
            }
            try Task.checkCancellation()

            var sentences = SubtitleCue.sentences(from: SubtitleCue.cues(from: captions))
            guard !sentences.isEmpty else {
                throw SubtitleTranslationError.noSubtitles
            }
            Logger.info("Translating \(sentences.count) subtitle sentences to \(target.minimalIdentifier)")

            #if os(iOS)
            if SubtitleFonts.needsDownloadableFont(for: target) {
                do {
                    try await SubtitleFonts.activate()
                } catch let error {
                    // The translation is still useful without the font, which is activated again in the next launch.
                    Logger.error("Failed to activate the subtitle font: \(error)")
                }
                try Task.checkCancellation()
            }
            #endif

            let total = sentences.count
            phase = .translating(completed: 0, total: total)
            let translator = SubtitleTranslator(model: model, target: target, program: program)
            let result = try await translator.translate(sentences.map(\.text)) { [weak self] completed in
                guard let self, case .translating = self.phase else {
                    return
                }
                self.phase = .translating(completed: completed, total: total)
            }
            try Task.checkCancellation()
            for (index, translation) in result.translations.enumerated() {
                if let translation {
                    sentences[index].text = translation
                }
            }

            try SubtitleTranslationStore.save(sentences, forVideo: videoURL, source: Self.sourceLanguage, target: target)
            phase = .finished(count: total, untranslated: result.untranslated)
        } catch {
            if Task.isCancelled || error is CancellationError {
                Logger.info("Subtitle translation cancelled")
                phase = .cancelled
            } else {
                Logger.error("Subtitle translation failed: \(error)")
                phase = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Stops the job and discards everything translated so far.
    func cancel() {
        guard isRunning else {
            return
        }
        task?.cancel()
        extractionTask?.cancel()
        phase = .cancelled
    }

    private func updateReadingProgress(_ progress: Double) {
        if case .readingSubtitles = phase {
            phase = .readingSubtitles(progress: progress)
        }
    }

    /// Keeps the device awake while translating, since the job stops when the app is suspended.
    private func acquireWakeLock() -> NSObjectProtocol? {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        return nil
        #else
        return ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Translating subtitles")
        #endif
    }

    private func releaseWakeLock(_ activity: NSObjectProtocol?) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #else
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        #endif
    }
}
#endif
