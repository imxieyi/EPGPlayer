//
//  PrivateCloudComputeTranslationModel.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/26.
//
//  SPDX-License-Identifier: MPL-2.0

#if (os(iOS) || os(macOS)) && compiler(>=6.4) && canImport(FoundationModels)
import Foundation
import FoundationModels

/// Translates subtitles with Apple Foundation Models running on Private Cloud Compute.
@available(iOS 27.0, macOS 27.0, *)
struct PrivateCloudComputeTranslationModel: SubtitleTranslationModel {
    /// Replies repeat the source text and fail when they get much longer than 7,000 characters,
    /// so about 100 caption lines fit in one request.
    let maxSourceCharactersPerRequest = 1_500
    /// Keeps the conversation well within the context of the model, next to the instructions and the program information.
    let maxConversationCharacters = 4_000

    /// Number of times a rate-limited request is retried.
    private static let rateLimitRetries = 3

    /// The session of the conversation continued last, so that its next turn is sent on the same session.
    private static let conversationSession = ConversationSession()

    static var availabilityMessage: String? {
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            return String(localized: "Apple Intelligence is not supported on this device.")
        case .unavailable(.systemNotReady):
            return String(localized: "Apple Intelligence is not ready. Make sure it is turned on in Settings.")
        case .unavailable:
            return String(localized: "Apple Intelligence is not available.")
        }
        if model.quotaUsage.isLimitReached {
            return quotaMessage(resetDate: model.quotaUsage.resetDate)
        }
        return nil
    }

    /// Returns the codes of the languages that the model supports. Only the codes are comparable,
    /// since the model reports languages such as "zh" and "zh-TW".
    static func supportedLanguageCodes() async -> Set<Locale.LanguageCode>? {
        guard let languages = try? await PrivateCloudComputeLanguageModel().supportedLanguages else {
            return nil
        }
        return Set(languages.compactMap(\.languageCode))
    }

    private static func quotaMessage(resetDate: Date?) -> String {
        if let resetDate {
            return String(localized: "You have reached the usage limit of Apple Intelligence. It resets \(resetDate.formatted(.relative(presentation: .named))).")
        }
        return String(localized: "You have reached the usage limit of Apple Intelligence.")
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        try await respond(to: prompt) { _ in
            LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
        }.reply
    }

    func respond(instructions: String, history: [SubtitleTranslationTurn], prompt: String, conversationID: String) async throws -> String {
        let key = ConversationSession.Key(conversationID: conversationID, instructions: instructions, turnCount: history.count)
        let (reply, session) = try await respond(to: prompt) { attempt in
            if attempt == 0, let session = Self.conversationSession.take(key) {
                return session
            }
            // A session that failed may or may not have recorded the prompt, so start over from the history.
            return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), transcript: Self.transcript(instructions: instructions, history: history))
        }
        Self.conversationSession.keep(session, for: ConversationSession.Key(conversationID: conversationID, instructions: instructions, turnCount: history.count + 1))
        return reply
    }

    private static func transcript(instructions: String, history: [SubtitleTranslationTurn]) -> Transcript {
        var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(segments: [.text(Transcript.TextSegment(content: instructions))], toolDefinitions: []))]
        for turn in history {
            entries.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: turn.prompt))])))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: turn.reply))])))
        }
        return Transcript(entries: entries)
    }

    /// Sends a prompt on the session that `makeSession` returns for each attempt.
    private func respond(to prompt: String, makeSession: (Int) -> LanguageModelSession) async throws -> (reply: String, session: LanguageModelSession) {
        var retries = 0
        while true {
            let session = makeSession(retries)
            do {
                let start = ContinuousClock.now
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2))
                let input = response.usage.input
                Logger.info("Private Cloud Compute replied in \(ContinuousClock.now - start), \(input.cachedTokenCount) of \(input.totalTokenCount) input tokens cached")
                return (response.content, session)
            } catch let error as LanguageModelError {
                switch error {
                case .guardrailViolation, .refusal:
                    throw SubtitleTranslationModelError.refused
                case .contextSizeExceeded:
                    throw SubtitleTranslationModelError.tooLong
                case .rateLimited(let info):
                    guard retries < Self.rateLimitRetries else {
                        throw SubtitleTranslationModelError.fatal(String(localized: "Apple Intelligence is receiving too many requests. Try again later."))
                    }
                    retries += 1
                    let delay = info.resetDate.map { max(1, min($0.timeIntervalSinceNow, 60)) } ?? 10
                    Logger.info("Private Cloud Compute is rate limited, retrying in \(delay)s")
                    try await Task.sleep(for: .seconds(delay))
                case .unsupportedLanguageOrLocale:
                    throw SubtitleTranslationModelError.fatal(String(localized: "Apple Intelligence does not support this language."))
                default:
                    throw SubtitleTranslationModelError.generationFailed(error.localizedDescription)
                }
            } catch let error as PrivateCloudComputeLanguageModel.Error {
                switch error {
                case .quotaLimitReached(let info):
                    throw SubtitleTranslationModelError.fatal(Self.quotaMessage(resetDate: info.resetDate))
                case .networkFailure:
                    throw SubtitleTranslationModelError.temporary(String(localized: "Could not connect to Apple Intelligence. Check your network connection."))
                case .serviceUnavailable:
                    throw SubtitleTranslationModelError.temporary(String(localized: "Apple Intelligence is temporarily unavailable. Try again later."))
                @unknown default:
                    throw SubtitleTranslationModelError.fatal(error.localizedDescription)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Replies that the output safety check stops end with an unspecific error.
                Logger.error("Private Cloud Compute request failed: \(error)")
                throw SubtitleTranslationModelError.generationFailed(error.localizedDescription)
            }
        }
    }
}
/// Holds the session of the last turn of a conversation until its next turn.
@available(iOS 27.0, macOS 27.0, *)
private final class ConversationSession: @unchecked Sendable {
    struct Key: Equatable {
        let conversationID: String
        let instructions: String
        /// Number of turns in the transcript of the session.
        let turnCount: Int
    }

    private let lock = NSLock()
    private var key: Key?
    private var session: LanguageModelSession?

    /// Returns the kept session if it continues the conversation at the given turn, and forgets it.
    func take(_ key: Key) -> LanguageModelSession? {
        lock.withLock {
            defer {
                self.key = nil
                session = nil
            }
            return self.key == key ? session : nil
        }
    }

    func keep(_ session: LanguageModelSession, for key: Key) {
        lock.withLock {
            self.key = key
            self.session = session
        }
    }
}
#endif
