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
@preconcurrency import Translation
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
        case preparingLanguages
        case translating(completed: Int, total: Int)
        case finished(count: Int)
        case failed(message: String)
        case cancelled
    }

    private(set) var phase = Phase.idle

    var isRunning: Bool {
        switch phase {
        case .readingSubtitles, .preparingLanguages, .translating:
            return true
        default:
            return false
        }
    }

    /// Number of sentences sent in one batch request, so that progress updates often and cancellation is quick.
    private static let batchSize = 25

    private let videoURL: URL
    @ObservationIgnored private var session: TranslationSession?
    @ObservationIgnored private var extractionTask: Task<[ARIBCaption], Error>?
    @ObservationIgnored private var isCancelled = false

    init(videoURL: URL) {
        self.videoURL = videoURL
    }

    /// Marks the job as started so that the UI switches to the progress view before the session is ready.
    func prepare() {
        phase = .readingSubtitles(progress: 0)
    }

    /// Runs the whole job with a session provided by `translationTask`. The session must not outlive this call.
    func run(session: TranslationSession) async {
        guard let source = session.sourceLanguage, let target = session.targetLanguage else {
            phase = .failed(message: String(localized: "Choose two different languages."))
            return
        }
        self.session = session
        isCancelled = false
        let wakeLock = acquireWakeLock()
        defer {
            releaseWakeLock(wakeLock)
            self.session = nil
            extractionTask = nil
        }
        do {
            phase = .readingSubtitles(progress: 0)
            let videoURL = self.videoURL
            let task = Task.detached(priority: .userInitiated) { [weak self] in
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
            extractionTask = task
            let captions = try await task.value
            try checkCancelled()

            let sentences = SubtitleCue.sentences(from: SubtitleCue.cues(from: captions))
            guard !sentences.isEmpty else {
                throw SubtitleTranslationError.noSubtitles
            }
            Logger.info("Translating \(sentences.count) subtitle sentences from \(source.minimalIdentifier) to \(target.minimalIdentifier)")

            phase = .preparingLanguages
            try await session.prepareTranslation()
            try checkCancelled()
            #if os(iOS)
            if SubtitleFonts.needsDownloadableFont(for: target) {
                do {
                    try await SubtitleFonts.activate()
                } catch let error {
                    // The translation is still useful without the font, which is activated again in the next launch.
                    Logger.error("Failed to activate the subtitle font: \(error)")
                }
                try checkCancelled()
            }
            #endif

            var translated = sentences
            var completed = 0
            phase = .translating(completed: 0, total: sentences.count)
            for batchStart in stride(from: 0, to: sentences.count, by: Self.batchSize) {
                let requests = (batchStart..<min(batchStart + Self.batchSize, sentences.count)).map {
                    TranslationSession.Request(sourceText: sentences[$0].text, clientIdentifier: String($0))
                }
                for try await response in session.translate(batch: requests) {
                    guard let identifier = response.clientIdentifier, let index = Int(identifier) else {
                        continue
                    }
                    translated[index].text = response.targetText
                    completed += 1
                    phase = .translating(completed: completed, total: sentences.count)
                }
                try checkCancelled()
            }

            try SubtitleTranslationStore.save(translated, forVideo: videoURL, source: source, target: target)
            phase = .finished(count: sentences.count)
        } catch {
            if isCancelled || error is CancellationError {
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
        isCancelled = true
        extractionTask?.cancel()
        session?.cancel()
        phase = .cancelled
    }

    private func updateReadingProgress(_ progress: Double) {
        if case .readingSubtitles = phase {
            phase = .readingSubtitles(progress: progress)
        }
    }

    private func checkCancelled() throws {
        if isCancelled {
            throw CancellationError()
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
