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
/// When the translation stops with an error, it can be retried without losing the lines translated so far.
@MainActor
@Observable
final class SubtitleTranslationJob {
    enum Phase: Equatable {
        case idle
        case readingSubtitles(progress: Double)
        case translating(completed: Int, total: Int)
        /// Lines that could not be translated are saved in Japanese and listed.
        case finished(count: Int, untranslated: [SubtitleTranslator.UntranslatedLine])
        /// Only a failure after the subtitles were read can be retried, since reading them again gives the same result.
        case failed(message: String, canRetry: Bool)
        case cancelled
    }

    /// ARIB subtitles are always in Japanese.
    static let sourceLanguage = Locale.Language(identifier: "ja")

    private(set) var phase = Phase.idle
    /// The subtitles to translate, kept for a retry.
    private(set) var sentences: [SubtitleCue] = []
    /// The progress of the translation, kept for a retry.
    private(set) var progress: SubtitleTranslator.Progress?

    var isRunning: Bool {
        switch phase {
        case .readingSubtitles, .translating:
            return true
        default:
            return false
        }
    }

    private let videoURL: URL
    @ObservationIgnored private var target = SubtitleTranslationJob.sourceLanguage
    @ObservationIgnored private var program: SubtitleProgramInfo?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var extractionTask: Task<[ARIBCaption], Error>?

    init(videoURL: URL) {
        self.videoURL = videoURL
    }

    func start(model: any SubtitleTranslationModel, target: Locale.Language, program: SubtitleProgramInfo?) {
        guard !isRunning else {
            return
        }
        self.target = target
        self.program = program
        sentences = []
        progress = nil
        phase = .readingSubtitles(progress: 0)
        task = Task {
            await run(model: model)
        }
    }

    /// Continues a failed translation with the lines that are not translated yet, possibly with another model.
    func retry(model: any SubtitleTranslationModel) {
        guard case .failed(_, canRetry: true) = phase else {
            return
        }
        phase = .translating(completed: progress?.translatedCount ?? 0, total: sentences.count)
        task = Task {
            await run(model: model)
        }
    }

    private func run(model: any SubtitleTranslationModel) async {
        let wakeLock = acquireWakeLock()
        defer {
            releaseWakeLock(wakeLock)
            extractionTask = nil
            task = nil
        }
        do {
            if sentences.isEmpty {
                try await readSubtitles()
            }
        } catch {
            fail(error, canRetry: false)
            return
        }
        do {
            try await translate(model: model)
        } catch {
            fail(error, canRetry: true)
        }
    }

    private func fail(_ error: any Error, canRetry: Bool) {
        if Task.isCancelled || error is CancellationError {
            Logger.info("Subtitle translation cancelled")
            phase = .cancelled
        } else {
            Logger.error("Subtitle translation failed: \(error)")
            phase = .failed(message: error.localizedDescription, canRetry: canRetry)
        }
    }

    private func readSubtitles() async throws {
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

        let sentences = SubtitleCue.sentences(from: SubtitleCue.cues(from: captions))
        guard !sentences.isEmpty else {
            throw SubtitleTranslationError.noSubtitles
        }
        self.sentences = sentences
    }

    private func translate(model: any SubtitleTranslationModel) async throws {
        let total = sentences.count
        Logger.info("Translating \(total - (progress?.translatedCount ?? 0)) of \(total) subtitle sentences to \(target.minimalIdentifier)")
        phase = .translating(completed: progress?.translatedCount ?? 0, total: total)
        let translator = SubtitleTranslator(model: model, target: target, program: program)
        let result = try await translator.translate(sentences.map(\.text), resumingFrom: progress) { [weak self] progress in
            guard let self, case .translating = self.phase else {
                return
            }
            self.progress = progress
            self.phase = .translating(completed: progress.translatedCount, total: total)
        }
        try Task.checkCancellation()
        progress = result
        var translated = sentences
        for (index, translation) in result.translations.enumerated() {
            if let translation {
                translated[index].text = translation
            }
        }

        try SubtitleTranslationStore.save(translated, forVideo: videoURL, source: Self.sourceLanguage, target: target)
        phase = .finished(count: total, untranslated: result.untranslated)
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
