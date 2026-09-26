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

    /// Number of times a rate-limited request is retried.
    private static let rateLimitRetries = 3

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
        var retries = 0
        while true {
            let session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
            do {
                return try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2)).content
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
                    throw SubtitleTranslationModelError.fatal(String(localized: "Could not connect to Apple Intelligence. Check your network connection."))
                case .serviceUnavailable:
                    throw SubtitleTranslationModelError.fatal(String(localized: "Apple Intelligence is temporarily unavailable. Try again later."))
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
#endif
