//
//  CustomTranslationModel.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/26.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import Foundation
import AnyLanguageModel

/// The API that a custom language model server speaks.
enum CustomModelAPIFormat: String, CaseIterable, Identifiable, Sendable {
    case openAIChatCompletions = "openai-chat-completions"
    case openAIResponses = "openai-responses"
    case anthropicMessages = "anthropic-messages"
    case gemini

    var id: String { rawValue }

    var name: String {
        switch self {
        case .openAIChatCompletions:
            return "OpenAI Chat Completions"
        case .openAIResponses:
            return "OpenAI Responses"
        case .anthropicMessages:
            return "Anthropic Messages"
        case .gemini:
            return "Google Gemini"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAIChatCompletions, .openAIResponses:
            return "https://api.openai.com/v1"
        case .anthropicMessages:
            return "https://api.anthropic.com"
        case .gemini:
            return "https://generativelanguage.googleapis.com"
        }
    }

    /// The path that the client appends to the base URL.
    func endpointPath(model: String) -> String {
        switch self {
        case .openAIChatCompletions:
            return "chat/completions"
        case .openAIResponses:
            return "responses"
        case .anthropicMessages:
            return "v1/messages"
        case .gemini:
            return "\(GeminiLanguageModel.defaultAPIVersion)/models/\(model.isEmpty ? "{model}" : model):generateContent"
        }
    }
}

/// The server, model and credentials of a custom language model.
struct CustomModelConfiguration: Sendable, Equatable {
    var format: CustomModelAPIFormat
    /// Base URL of the API, or empty for the default of the format.
    var baseURL: String
    var model: String
    /// May be empty for local servers that need no key.
    var apiKey: String

    var resolvedBaseURL: URL? {
        let string = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: string.isEmpty ? format.defaultBaseURL : string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else {
            return nil
        }
        return url
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespaces)
    }

    var isComplete: Bool {
        resolvedBaseURL != nil && !trimmedModel.isEmpty
    }

    /// The URL that requests are sent to, for showing in settings.
    var endpointURL: String? {
        guard let baseURL = resolvedBaseURL else {
            return nil
        }
        var string = baseURL.absoluteString
        if !string.hasSuffix("/") {
            string += "/"
        }
        return string + format.endpointPath(model: trimmedModel)
    }
}

/// Translates subtitles with a language model on a server that the user configured.
struct CustomTranslationModel: SubtitleTranslationModel {
    /// Large enough to send a typical episode in one request. Longer programs are split,
    /// and lines missing from a reply that hit the output limit of the model are sent again.
    let maxSourceCharactersPerRequest = 12_000
    /// Several minutes of captions. The cached turns cost little, and the context improves the translation.
    let maxConversationCharacters = 24_000

    /// Replies to a whole episode can take minutes without any data in between.
    private static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 900
        configuration.timeoutIntervalForResource = 1800
        return URLSession(configuration: configuration)
    }()

    let configuration: CustomModelConfiguration

    private func makeModel() throws -> any LanguageModel {
        guard let baseURL = configuration.resolvedBaseURL else {
            throw SubtitleTranslationModelError.fatal(String(localized: "The base URL of the custom model is invalid."))
        }
        let apiKey = configuration.apiKey
        let model = configuration.trimmedModel
        switch configuration.format {
        case .openAIChatCompletions:
            return OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey, model: model, apiVariant: .chatCompletions, session: Self.urlSession)
        case .openAIResponses:
            return OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey, model: model, apiVariant: .responses, session: Self.urlSession)
        case .anthropicMessages:
            return AnthropicLanguageModel(baseURL: baseURL, apiKey: apiKey, model: model, session: Self.urlSession)
        case .gemini:
            return GeminiLanguageModel(baseURL: baseURL, apiKey: apiKey, model: model, session: Self.urlSession)
        }
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        try await respond(session: LanguageModelSession(model: try makeModel(), instructions: instructions), prompt: prompt, conversationID: nil)
    }

    func respond(instructions: String, history: [SubtitleTranslationTurn], prompt: String, conversationID: String) async throws -> String {
        var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(segments: [.text(Transcript.TextSegment(content: instructions))], toolDefinitions: []))]
        for turn in history {
            entries.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: turn.prompt))])))
            entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: turn.reply))])))
        }
        let session = LanguageModelSession(model: try makeModel(), transcript: Transcript(entries: entries))
        return try await respond(session: session, prompt: prompt, conversationID: conversationID)
    }

    private func respond(session: LanguageModelSession, prompt: String, conversationID: String?) async throws -> String {
        // Anthropic requires a limit and defaults to 1,024 tokens. The other APIs default to the limit of the model,
        // and some compatible servers reject the parameter.
        var options = configuration.format == .anthropicMessages ? GenerationOptions(maximumResponseTokens: 16_384) : GenerationOptions()
        if let conversationID {
            addCacheOptions(to: &options, conversationID: conversationID)
        }
        let start = ContinuousClock.now
        do {
            let response = try await session.respond(to: prompt, options: options)
            if conversationID != nil {
                let input = response.usage.input
                Logger.info("Custom model replied in \(ContinuousClock.now - start), \(input.cachedTokenCount) of \(input.totalTokenCount) input tokens cached")
            }
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                throw SubtitleTranslationModelError.refused
            case .exceededContextWindowSize:
                throw SubtitleTranslationModelError.tooLong
            case .rateLimited, .concurrentRequests:
                throw SubtitleTranslationModelError.temporary(String(describing: error))
            default:
                throw SubtitleTranslationModelError.fatal(String(describing: error))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            if Self.temporaryNetworkErrors.contains(error.code) {
                throw SubtitleTranslationModelError.temporary(error.localizedDescription)
            }
            throw SubtitleTranslationModelError.fatal(error.localizedDescription)
        } catch {
            // The errors of AnyLanguageModel are internal, and only describe the status and the reply of the server.
            let description = String(describing: error)
            if Self.isTemporary(description) {
                throw SubtitleTranslationModelError.temporary(description)
            }
            throw SubtitleTranslationModelError.fatal(description)
        }
    }

    /// Network errors that a dropped connection or a server that restarts can cause. A host that doesn't exist is not one of them.
    private static let temporaryNetworkErrors: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed,
        .badServerResponse, .cannotParseResponse, .zeroByteResource, .resourceUnavailable,
        .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]

    /// HTTP statuses of a server that is busy, overloaded or restarting, including the 52x statuses of Cloudflare and
    /// the 529 status of Anthropic.
    private static let temporaryHTTPStatuses: Set<Int> = Set([408, 409, 425, 429, 500, 502, 503, 504]).union(520...529)

    /// Whether an error of AnyLanguageModel is a temporary HTTP status, a reply that is not JSON (e.g. the error page of a
    /// proxy), or a reply without a message.
    private static func isTemporary(_ description: String) -> Bool {
        if let match = description.firstMatch(of: /^HTTP error \(Status (\d+)\)/), let status = Int(match.1) {
            return temporaryHTTPStatuses.contains(status)
        }
        return description.hasPrefix("Decoding error") || description.hasPrefix("Invalid response")
            || description == "noResponseGenerated" || description == "No candidate in response"
    }

    /// Asks the official servers to cache the conversation. OpenAI and Gemini cache the start of a request that
    /// repeats an earlier one by themselves, but OpenAI routes the requests of a conversation to the same cache
    /// with a key, and Anthropic only caches when asked. Other servers get no extra parameters,
    /// since compatible servers may reject parameters they don't know.
    private func addCacheOptions(to options: inout GenerationOptions, conversationID: String) {
        guard let host = configuration.resolvedBaseURL?.host()?.lowercased() else {
            return
        }
        switch configuration.format {
        case .openAIChatCompletions, .openAIResponses:
            if host == "api.openai.com" {
                options[custom: OpenAILanguageModel.self] = OpenAILanguageModel.CustomGenerationOptions(promptCacheKey: conversationID)
            }
        case .anthropicMessages:
            if host == "api.anthropic.com" {
                // Caches everything up to the last message, which moves forward with each turn.
                options[custom: AnthropicLanguageModel.self] = AnthropicLanguageModel.CustomGenerationOptions(extraBody: ["cache_control": ["type": "ephemeral"]])
            }
        case .gemini:
            break
        }
    }
}
#endif
