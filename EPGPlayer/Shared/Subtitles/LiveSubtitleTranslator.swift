//
//  LiveSubtitleTranslator.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/28.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import Foundation
import Observation

/// Translates the ARIB captions of a stream while it plays, to show the translation over the video.
///
/// The captions reach the translator while VLC buffers the stream, a few seconds before they are shown.
/// They are sent to the model as they arrive, in one conversation that only grows at its end, so that the server
/// can reuse its cache of the instructions and the earlier turns and only has to process the new lines.
@MainActor
@Observable
final class LiveSubtitleTranslator {
    enum Status: Equatable {
        case off
        /// Translating, or waiting for captions.
        case active
        /// The model can't be used, e.g. because it is not set up.
        case unavailable(String)
        /// The stream has no caption stream.
        case noSubtitles
        /// The last request failed. Translation continues after a pause.
        case failed(String)
    }

    /// The translation of the captions shown at the current playback time.
    private(set) var visibleText: String?
    private(set) var status = Status.off
    /// A problem to show over the video for a while.
    private(set) var notice: String?
    /// Whether the stream is read through the caption proxy, which is needed to translate it.
    private(set) var isAttached = false

    /// How long before its start a caption that continues in the next one waits for the rest of its sentence.
    private static let continuationWait = 1_500
    /// How long a caption stays when no later caption ends it.
    private static let openCueDuration = 8_000
    /// The least time a translation that arrives after its caption started is shown.
    private static let lateDisplayDuration = 2_000
    /// Captions further ahead than this are not translated yet, e.g. when VLC reads the end of a recording.
    private static let lookahead = 120_000
    /// Most lines in one request, which only grows when requests fall behind.
    private static let maxLinesPerRequest = 20
    private static let attemptsPerLine = 3
    /// The least time to wait for a reply. A server that doesn't answer would otherwise hold up the translation
    /// until the connection times out, which takes many minutes.
    private static let minRequestTimeout = Duration.seconds(5)
    private static let maxRequestTimeout = Duration.seconds(60)
    /// Temporary failures in a row before they are shown, since the translation usually goes on after one.
    private static let temporaryFailuresBeforeNotice = 3
    /// Captions of a live stream that ended this long ago are dropped.
    private static let liveRetention = 600_000

    private struct Cue {
        enum State {
            case pending
            case sending
            case done
            case failed
        }

        /// The id of the line in the conversation with the model.
        let id: Int
        let start: Int
        /// Nil until a later caption ends it.
        var end: Int?
        var text: String
        /// Whether the caption ends with the continuation arrow, so that its sentence continues in the next caption.
        var continues: Bool
        var state = State.pending
        var translation: String?
        var attempts = 0
        /// Send the line alone, after the model refused a request with it.
        var sendAlone = false
        /// The playback time until which a translation that arrived late is shown.
        var lateUntil: Int?
    }

    /// The settings that the model was created with.
    private struct ModelSettings: Equatable {
        let engine: SubtitleTranslationEngine
        let target: String
        let customConfiguration: CustomModelConfiguration?
    }

    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var model: (any SubtitleTranslationModel)?
    @ObservationIgnored private var target = Locale.Language(identifier: "en")
    @ObservationIgnored private var modelSettings: ModelSettings?
    @ObservationIgnored private var program: SubtitleProgramInfo?
    @ObservationIgnored private var isLive = false

    /// Sorted by start time.
    @ObservationIgnored private var cues: [Cue] = []
    @ObservationIgnored private var nextLineID = 1
    /// The cue of each caption that was received, by time and text, so that captions read again after a seek are recognized.
    @ObservationIgnored private var captionCueIDs: [String: Int] = [:]
    /// The cue of the last caption of each connection of the proxy.
    @ObservationIgnored private var lastCueIDs: [Int: Int] = [:]

    /// A request to the model that has not replied yet.
    private struct Request {
        let id: Int
        let lineIDs: [Int]
        let start: ContinuousClock.Instant
        let task: Task<Void, Never>
    }

    @ObservationIgnored private var conversationID = UUID().uuidString
    @ObservationIgnored private var history: [SubtitleTranslationTurn] = []
    @ObservationIgnored private var request: Request?
    @ObservationIgnored private var nextRequestID = 1
    /// How long a reply usually takes, to tell a server that doesn't answer from a model that is slow.
    @ObservationIgnored private var typicalReplyDuration = Duration.seconds(5)
    @ObservationIgnored private var consecutiveTimeouts = 0
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var retryDate: Date?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    @ObservationIgnored private var playbackTime = 0

    // MARK: - Configuration

    /// Applies the settings of the player. Changing the model or the language discards the translations so far.
    /// - Parameter problem: why the model can't be used, if it can't.
    func configure(enabled: Bool, engine: SubtitleTranslationEngine, target: String, customConfiguration: CustomModelConfiguration, problem: String?) {
        let settings = ModelSettings(engine: engine, target: target, customConfiguration: engine == .customModel ? customConfiguration : nil)
        if settings != modelSettings {
            modelSettings = settings
            model = engine.makeModel(customConfiguration: customConfiguration)
            self.target = Locale.Language(identifier: target)
            discardTranslations()
        }
        isEnabled = enabled
        if !enabled {
            cancelRequest()
            visibleText = nil
            setStatus(.off)
        } else if let problem {
            setStatus(.unavailable(problem))
        } else if model == nil {
            setStatus(.unavailable(String(localized: "Set up the custom model in Settings first.")))
        } else if case .noSubtitles = status {
            // Stays until the stream has captions.
        } else {
            setStatus(.active)
        }
        sendIfNeeded()
    }

    /// Uses the information of another program, e.g. when a live channel moves on to the next one.
    func updateProgram(_ program: SubtitleProgramInfo?) {
        guard program != self.program else {
            return
        }
        self.program = program
        // The instructions change, so the conversation starts over.
        history = []
        conversationID = UUID().uuidString
    }

    // MARK: - Stream

    /// Starts translating a stream that the player reads through the caption proxy.
    func attach(isLive: Bool) {
        self.isLive = isLive
        isAttached = true
        resetTimeline()
    }

    func detach() {
        isAttached = false
        cancelRequest()
        visibleText = nil
    }

    /// Called when a connection reads the stream from its beginning. A live stream then starts over with new times.
    func streamStarted() {
        if isLive {
            resetTimeline()
        }
    }

    func captionStreamFound(_ found: Bool) {
        if !found {
            if isEnabled {
                setStatus(.noSubtitles)
            }
        } else if case .noSubtitles = status {
            setStatus(isEnabled ? .active : .off)
        }
    }

    /// Adds a caption read by the proxy on the given connection.
    func receive(_ caption: ARIBCaption, connection: Int) {
        let text = SubtitleCue.normalize(caption.text)
        Logger.debug("Caption at \(caption.time) ms on connection \(connection), \(caption.time - playbackTime) ms ahead of playback: \(pii: text)")
        let lastIndex = lastCueIDs[connection].flatMap(index(ofCue:))
        let captionKey = "\(caption.time)|\(text)"
        if !text.isEmpty, let id = captionCueIDs[captionKey] {
            // Read again after a seek.
            lastCueIDs[connection] = id
            return
        }
        guard !text.isEmpty else {
            // A caption without text clears the screen.
            if let lastIndex {
                end(lastIndex, at: caption.time)
            }
            return
        }
        var piece = text
        let continues = piece.hasSuffix(SubtitleCue.continuationMark)
        if continues {
            piece = String(piece.dropLast(SubtitleCue.continuationMark.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let end = caption.duration.map { caption.time + $0 }
        if let lastIndex, cues[lastIndex].continues, cues[lastIndex].state == .pending,
           caption.time >= cues[lastIndex].start, caption.time - cues[lastIndex].start < 30_000 {
            // The rest of a sentence, which is translated together with its beginning.
            cues[lastIndex].text = [cues[lastIndex].text, piece].filter { !$0.isEmpty }.joined(separator: " ")
            cues[lastIndex].continues = continues
            cues[lastIndex].end = end
            captionCueIDs[captionKey] = cues[lastIndex].id
        } else {
            if let lastIndex {
                self.end(lastIndex, at: caption.time)
            }
            let cue = Cue(id: nextLineID, start: caption.time, end: end, text: piece, continues: continues)
            nextLineID += 1
            let index = cues.firstIndex { $0.start > cue.start } ?? cues.endIndex
            cues.insert(cue, at: index)
            captionCueIDs[captionKey] = cue.id
            lastCueIDs[connection] = cue.id
        }
        sendIfNeeded()
    }

    /// Updates the translation on screen and sends the captions that are due.
    func update(playbackTime: Int) {
        self.playbackTime = playbackTime
        if isLive, let first = cues.first, first.start < playbackTime - Self.liveRetention {
            dropOldCues()
        }
        let text = isEnabled ? visibleTranslation(at: playbackTime) : nil
        if text != visibleText {
            visibleText = text
        }
        sendIfNeeded()
    }

    // MARK: - Cues

    private func index(ofCue id: Int) -> Int? {
        cues.firstIndex { $0.id == id }
    }

    /// Ends a cue when the next caption replaces it.
    private func end(_ index: Int, at time: Int) {
        guard cues[index].start < time, time - cues[index].start < 60_000 else {
            return
        }
        if cues[index].end.map({ $0 > time }) ?? true {
            cues[index].end = time
        }
    }

    private func displayEnd(of cue: Cue) -> Int {
        max(cue.end ?? cue.start + Self.openCueDuration, cue.lateUntil ?? 0)
    }

    private func visibleTranslation(at time: Int) -> String? {
        let lines = cues.filter { $0.translation != nil && $0.start <= time && time < displayEnd(of: $0) }.compactMap(\.translation)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func dropOldCues() {
        let limit = playbackTime - Self.liveRetention
        let dropped = Set(cues.prefix { displayEnd(of: $0) < limit && $0.state != .sending }.map(\.id))
        guard !dropped.isEmpty else {
            return
        }
        cues.removeAll { dropped.contains($0.id) }
        captionCueIDs = captionCueIDs.filter { !dropped.contains($0.value) }
    }

    /// Forgets all captions, since the times of a new stream start over.
    private func resetTimeline() {
        cancelRequest()
        cues = []
        captionCueIDs = [:]
        lastCueIDs = [:]
        history = []
        conversationID = UUID().uuidString
        visibleText = nil
        retryDate = nil
        consecutiveFailures = 0
        consecutiveTimeouts = 0
        if case .noSubtitles = status {
            setStatus(isEnabled ? .active : .off)
        }
    }

    private func discardTranslations() {
        cancelRequest()
        for index in cues.indices {
            cues[index].state = .pending
            cues[index].translation = nil
            cues[index].attempts = 0
            cues[index].sendAlone = false
            cues[index].lateUntil = nil
        }
        history = []
        conversationID = UUID().uuidString
        visibleText = nil
        retryDate = nil
        consecutiveFailures = 0
        consecutiveTimeouts = 0
    }

    // MARK: - Requests

    private func sendIfNeeded() {
        guard isEnabled, isAttached, let model, status != .noSubtitles else {
            return
        }
        if case .unavailable = status {
            return
        }
        if let request {
            let timeout = requestTimeout
            guard ContinuousClock.now - request.start > timeout else {
                return
            }
            Logger.error("Live translation of \(request.lineIDs.count) lines got no reply in \(timeout)")
            cancelRequest()
            consecutiveTimeouts += 1
            // The lines have waited long enough, so they are sent again right away.
            countTemporaryFailure(String(localized: "The model did not reply in time."))
        }
        if let retryDate, retryDate > .now {
            return
        }
        var batch: [Int] = []
        var characters = 0
        for index in cues.indices where cues[index].state == .pending {
            let cue = cues[index]
            guard cue.start <= playbackTime + Self.lookahead else {
                break
            }
            // Captions that are over by now are not worth translating.
            guard displayEnd(of: cue) >= playbackTime else {
                continue
            }
            // Wait for the rest of the sentence unless the caption is about to be shown.
            // Later lines wait as well, so that the model gets the lines in order.
            if cue.continues, cue.start - playbackTime > Self.continuationWait {
                break
            }
            if cue.sendAlone && !batch.isEmpty {
                break
            }
            batch.append(index)
            characters += cue.text.count
            if cue.sendAlone || batch.count >= Self.maxLinesPerRequest || characters >= model.maxSourceCharactersPerRequest {
                break
            }
        }
        guard !batch.isEmpty else {
            return
        }
        let lines = batch.map { (id: cues[$0].id, text: cues[$0].text) }
        for index in batch {
            cues[index].state = .sending
        }
        let instructions = SubtitleTranslator.instructions(target: target, program: program, live: true)
        let prompt = SubtitleTranslator.livePrompt(for: lines)
        let history = history
        let conversationID = conversationID
        let requestID = nextRequestID
        nextRequestID += 1
        let start = ContinuousClock.now
        let task = Task {
            let result: Result<String, any Error>
            do {
                result = .success(try await model.respond(instructions: instructions, history: history, prompt: prompt, conversationID: conversationID))
            } catch {
                // A cancelled request can also fail with the error of its connection.
                result = .failure(Task.isCancelled ? CancellationError() : error)
            }
            // The reply of a request that was cancelled, e.g. because it took too long, is ignored.
            guard request?.id == requestID else {
                return
            }
            request = nil
            handle(result, lines: lines, prompt: prompt, duration: ContinuousClock.now - start)
            sendIfNeeded()
        }
        request = Request(id: requestID, lineIDs: lines.map(\.id), start: start, task: task)
    }

    /// Three times as long as a usual reply, and twice as long after each timeout in a row, so that a slow model
    /// still gets to reply.
    private var requestTimeout: Duration {
        min(Self.maxRequestTimeout, max(Self.minRequestTimeout, typicalReplyDuration * 3) * (1 << min(consecutiveTimeouts, 3)))
    }

    /// Stops the request that is being sent. Its lines are sent again when they are due.
    private func cancelRequest() {
        guard let request else {
            return
        }
        request.task.cancel()
        self.request = nil
        for index in request.lineIDs.compactMap(index(ofCue:)) where cues[index].state == .sending {
            cues[index].state = .pending
        }
    }

    /// Counts a failure that may not happen again, and shows it once it keeps happening.
    private func countTemporaryFailure(_ message: String) {
        consecutiveFailures += 1
        if consecutiveFailures >= Self.temporaryFailuresBeforeNotice {
            setStatus(.failed(message))
        }
    }

    private func handle(_ result: Result<String, any Error>, lines: [(id: Int, text: String)], prompt: String, duration: Duration) {
        let ids = lines.map(\.id)
        switch result {
        case .success(let reply):
            let accepted = SubtitleTranslator.acceptedTranslations(in: reply, lines: Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.text) }))
            for id in ids {
                guard let index = index(ofCue: id) else {
                    continue
                }
                if let translation = accepted[id] {
                    cues[index].translation = translation
                    cues[index].state = .done
                    if playbackTime > cues[index].start {
                        cues[index].lateUntil = playbackTime + Self.lateDisplayDuration
                    }
                } else {
                    retryLater(index)
                }
            }
            if accepted.isEmpty {
                Logger.error("Live translation reply has no usable lines: \(pii: String(reply.prefix(300)))")
            } else {
                // A reply in another format would lead the model astray in the next turns.
                history.append(SubtitleTranslationTurn(prompt: prompt, reply: reply))
                trimHistory()
            }
            Logger.info("Translated \(accepted.count) of \(lines.count) live subtitle lines in \(duration), lead \((lines.first.flatMap { index(ofCue: $0.id) }.map { cues[$0].start - playbackTime }) ?? 0) ms")
            typicalReplyDuration = (typicalReplyDuration * 3 + duration) / 4
            consecutiveTimeouts = 0
            consecutiveFailures = 0
            retryDate = nil
            if case .failed = status {
                setStatus(.active)
            }
            if isEnabled {
                visibleText = visibleTranslation(at: playbackTime)
            }
        case .failure(let error):
            if error is CancellationError {
                for index in ids.compactMap(index(ofCue:)) where cues[index].state == .sending {
                    cues[index].state = .pending
                }
                return
            }
            Logger.error("Live translation of \(lines.count) lines failed: \(error)")
            switch error as? SubtitleTranslationModelError {
            case .refused?, .generationFailed?:
                if lines.count > 1 {
                    // Find the lines that the model refuses by sending them one by one.
                    for index in ids.compactMap(index(ofCue:)) {
                        cues[index].state = .pending
                        cues[index].sendAlone = true
                    }
                } else if let index = index(ofCue: ids[0]) {
                    retryLater(index)
                }
            case .tooLong?:
                history = []
                for index in ids.compactMap(index(ofCue:)) {
                    retryLater(index)
                }
            case .temporary(let message)?:
                for index in ids.compactMap(index(ofCue:)) {
                    cues[index].state = .pending
                }
                countTemporaryFailure(message)
                // Send again after a short pause, which grows a little while the failures go on. Even the longest pause
                // is about as long as a caption, so that the translation goes on soon after the server recovers.
                retryDate = .now + TimeInterval(min(4, 1 << (consecutiveFailures - 1)))
            case .fatal?, nil:
                for index in ids.compactMap(index(ofCue:)) {
                    cues[index].state = .pending
                }
                consecutiveFailures += 1
                // Keep trying at longer intervals, in case the problem is fixed, e.g. an exhausted quota that is reset.
                let delay = min(30, 2 << min(consecutiveFailures, 4))
                // The player updates the translator several times a second, which sends again once the time has come.
                retryDate = .now + TimeInterval(delay)
                setStatus(.failed(error.localizedDescription))
            }
        }
    }

    private func retryLater(_ index: Int) {
        cues[index].attempts += 1
        cues[index].state = cues[index].attempts >= Self.attemptsPerLine ? .failed : .pending
    }

    /// Drops the oldest turns once the conversation is too long. Dropping many at once keeps the new start of the
    /// conversation the same for many requests, since the server has to process it again each time it changes.
    private func trimHistory() {
        guard let model else {
            return
        }
        var characters = history.reduce(0) { $0 + $1.prompt.count + $1.reply.count }
        guard characters > model.maxConversationCharacters else {
            return
        }
        while characters > model.maxConversationCharacters / 2, !history.isEmpty {
            characters -= history[0].prompt.count + history[0].reply.count
            history.removeFirst()
        }
        Logger.info("Shortened the live translation conversation to \(history.count) turns")
    }

    // MARK: - Status

    private func setStatus(_ status: Status) {
        guard status != self.status else {
            return
        }
        self.status = status
        let message: String?
        switch status {
        case .off, .active:
            message = nil
        case .unavailable(let problem):
            message = problem
        case .noSubtitles:
            message = String(localized: "This video has no subtitles to translate.")
        case .failed(let error):
            message = String(localized: "Translation failed: \(error)")
        }
        notice = message
        noticeTask?.cancel()
        if message != nil {
            noticeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else {
                    return
                }
                self?.notice = nil
            }
        }
    }

    /// Describes the status in the menu of the player.
    var statusMessage: String? {
        switch status {
        case .off, .active:
            return nil
        case .unavailable(let problem):
            return problem
        case .noSubtitles:
            return String(localized: "This video has no subtitles to translate.")
        case .failed(let error):
            return String(localized: "Translation failed: \(error)")
        }
    }
}
#endif
