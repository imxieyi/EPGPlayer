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
struct CustomModelConfiguration: Sendable {
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
        let session = LanguageModelSession(model: try makeModel(), instructions: instructions)
        // Anthropic requires a limit and defaults to 1,024 tokens. The other APIs default to the limit of the model,
        // and some compatible servers reject the parameter.
        let options = configuration.format == .anthropicMessages ? GenerationOptions(maximumResponseTokens: 16_384) : GenerationOptions()
        do {
            return try await session.respond(to: prompt, options: options).content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                throw SubtitleTranslationModelError.refused
            case .exceededContextWindowSize:
                throw SubtitleTranslationModelError.tooLong
            default:
                throw SubtitleTranslationModelError.fatal(String(describing: error))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw SubtitleTranslationModelError.fatal(error.localizedDescription)
        } catch {
            // The HTTP errors of AnyLanguageModel only describe the status and the reply of the server in their description.
            throw SubtitleTranslationModelError.fatal(String(describing: error))
        }
    }
}
#endif
