//
//  SubtitleTranslator.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/26.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import Foundation

/// Information about a program that helps the model understand its subtitles.
struct SubtitleProgramInfo: Sendable {
    var title: String
    var description: String
}

/// Why a request to a translation model failed.
enum SubtitleTranslationModelError: Error {
    /// The model refused the content. Sending fewer lines isolates the lines it refuses.
    case refused
    /// The request or the reply was too long for the model.
    case tooLong
    /// The model failed to reply for an unknown reason, which can also be caused by the content.
    case generationFailed(String)
    /// A failure that affects every request, such as a network error, a wrong API key or an exhausted quota.
    case fatal(String)
}

extension SubtitleTranslationModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .refused:
            return String(localized: "The model refused to translate the subtitles.")
        case .tooLong:
            return String(localized: "The subtitles are too long for the model.")
        case .generationFailed(let message), .fatal(let message):
            return message
        }
    }
}

/// A language model that translates subtitles.
protocol SubtitleTranslationModel: Sendable {
    /// The largest number of source characters to send in one request.
    var maxSourceCharactersPerRequest: Int { get }

    /// Returns the reply of the model to a prompt. Throws `SubtitleTranslationModelError` or `CancellationError`.
    func respond(instructions: String, prompt: String) async throws -> String
}

/// Translates subtitle lines with a language model.
///
/// The lines are sent as a JSON array of `{"id", "text"}` objects, and the model replies with a JSON array of
/// `{"id", "source", "translation"}` objects. The model copies each source text before translating it, so that its
/// translation stays attached to the right line. A reply entry is only accepted when its source matches the text of
/// its id. Lines that are missing from a reply are sent again.
struct SubtitleTranslator {
    struct UntranslatedLine: Hashable, Sendable {
        enum Reason: Sendable {
            /// The model refused the line.
            case refused
            /// The model failed to reply, or its replies never contained the line.
            case failed
        }

        let index: Int
        let text: String
        let reason: Reason
    }

    struct Result: Sendable {
        /// The translation of each line, or nil for a line that could not be translated.
        var translations: [String?]
        var untranslated: [UntranslatedLine]
    }

    /// Number of earlier lines sent with a request for context.
    private static let contextLineCount = 6
    /// Number of times a single line is tried before giving up on it.
    private static let attemptsPerLine = 3
    /// Number of replies in a row without any usable line before the model is considered unable to follow the format.
    private static let maxUnusableReplies = 3

    let model: any SubtitleTranslationModel
    let target: Locale.Language
    let program: SubtitleProgramInfo?

    /// Translates the lines, reporting the number of translated lines after each request.
    func translate(_ texts: [String], progress: @MainActor @Sendable (Int) -> Void) async throws -> Result {
        let instructions = Self.instructions(target: target, program: program)
        var translations = [String?](repeating: nil, count: texts.count)
        var untranslated: [UntranslatedLine] = []
        var translatedCount = 0
        var unusableReplies = 0
        var lastUnusableReply = ""

        func request(_ indices: [Int]) async throws -> [Int: String] {
            try Task.checkCancellation()
            let prompt = Self.prompt(for: indices, texts: texts, translations: translations)
            let reply = try await model.respond(instructions: instructions, prompt: prompt)
            let accepted = Self.acceptedTranslations(in: reply, indices: indices, texts: texts)
            if accepted.isEmpty {
                unusableReplies += 1
                lastUnusableReply = reply
                Logger.error("Translation reply for \(indices.count) lines has no usable lines: \(pii: String(reply.prefix(500)))")
                if unusableReplies >= Self.maxUnusableReplies && translatedCount == 0 {
                    let snippet = reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
                    throw SubtitleTranslationModelError.fatal(String(localized: "The reply of the model is not in the expected format: \(String(snippet))"))
                }
            } else {
                unusableReplies = 0
            }
            return accepted
        }

        func translate(_ indices: [Int], attempt: Int) async throws {
            do {
                let accepted = try await request(indices)
                for (index, translation) in accepted {
                    translations[index] = translation
                }
                translatedCount += accepted.count
                await progress(translatedCount)
                let missing = indices.filter { translations[$0] == nil }
                guard !missing.isEmpty else {
                    return
                }
                if !accepted.isEmpty {
                    // A long reply may be cut off. Continue with the lines that are still missing.
                    try await translate(missing, attempt: 1)
                } else if missing.count > 1 {
                    try await split(missing)
                } else if attempt < Self.attemptsPerLine {
                    try await translate(missing, attempt: attempt + 1)
                } else {
                    giveUp(missing[0], reason: .failed)
                }
            } catch let error as SubtitleTranslationModelError {
                switch error {
                case .fatal:
                    throw error
                case .refused, .tooLong, .generationFailed:
                    Logger.info("Translation request for \(indices.count) lines failed: \(error)")
                    if indices.count > 1 {
                        try await split(indices)
                    } else if attempt < Self.attemptsPerLine {
                        try await translate(indices, attempt: attempt + 1)
                    } else {
                        if case .refused = error {
                            giveUp(indices[0], reason: .refused)
                        } else {
                            giveUp(indices[0], reason: .failed)
                        }
                    }
                }
            }
        }

        func split(_ indices: [Int]) async throws {
            let half = indices.count / 2
            try await translate(Array(indices[..<half]), attempt: 1)
            try await translate(Array(indices[half...]), attempt: 1)
        }

        func giveUp(_ index: Int, reason: UntranslatedLine.Reason) {
            Logger.error("Giving up translating line \(index + 1): \(reason)")
            untranslated.append(UntranslatedLine(index: index, text: texts[index], reason: reason))
        }

        for chunk in Self.chunks(of: texts, maxCharacters: model.maxSourceCharactersPerRequest) {
            try await translate(chunk, attempt: 1)
        }
        if translatedCount == 0, !texts.isEmpty, !lastUnusableReply.isEmpty {
            let snippet = lastUnusableReply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
            throw SubtitleTranslationModelError.fatal(String(localized: "The reply of the model is not in the expected format: \(String(snippet))"))
        }
        return Result(translations: translations, untranslated: untranslated.sorted { $0.index < $1.index })
    }

    // MARK: - Requests

    private static func instructions(target: Locale.Language, program: SubtitleProgramInfo?) -> String {
        var instructions = """
        You are a professional subtitle translator. Translate the Japanese closed captions of a TV program into natural \(englishName(of: target)) subtitles.

        The input is a JSON array of caption lines, each with an "id" and a "text". Reply with only a JSON array that has one object {"id": id, "source": text, "translation": translation} for every input line, in the same order. The "source" is the input text of that line, copied exactly.

        Rules for the translation:
        - A line break in a text separates the words of different speakers. Keep the line breaks.
        - A speaker name or a sound description in parentheses, such as (田中) or (拍手), belongs to the caption. Translate it and keep the parentheses.
        - Keep symbols such as ⚟ and ♪ unchanged.
        - Use the names that viewers already know for characters, people, places and titles.
        - Translate onomatopoeia and interjections into natural ones instead of transliterating them.
        - A sentence may be split across several lines. Use the surrounding lines to understand it, but translate each line on its own.
        """
        if let program {
            instructions += "\n\nProgram information:\n\(program.title)"
            if !program.description.isEmpty {
                instructions += "\n\(program.description)"
            }
        }
        return instructions
    }

    /// Returns the English name of a language, including the script of Chinese, e.g. "Chinese, Simplified".
    static func englishName(of language: Locale.Language) -> String {
        guard let languageCode = language.languageCode else {
            return language.minimalIdentifier
        }
        var identifier = languageCode.identifier
        if languageCode == .chinese {
            identifier += "-\(language.script?.identifier ?? "Hans")"
        } else if let region = language.region {
            identifier += "-\(region.identifier)"
        }
        return Locale(identifier: "en").localizedString(forIdentifier: identifier) ?? identifier
    }

    private struct InputLine: Encodable {
        let id: Int
        let text: String
    }

    private struct ContextLine: Encodable {
        let text: String
        let translation: String?
    }

    private static func prompt(for indices: [Int], texts: [String], translations: [String?]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var prompt = ""
        if let first = indices.first, first > 0 {
            let context = texts.indices[max(0, first - contextLineCount)..<first].map {
                ContextLine(text: texts[$0], translation: translations[$0])
            }
            if let data = try? encoder.encode(context) {
                prompt += "Earlier lines, for context only. Do not include them in the reply:\n"
                prompt += String(decoding: data, as: UTF8.self) + "\n\n"
            }
        }
        let lines = indices.map { InputLine(id: $0 + 1, text: texts[$0]) }
        let data = (try? encoder.encode(lines)) ?? Data()
        prompt += "Translate these caption lines:\n" + String(decoding: data, as: UTF8.self)
        return prompt
    }

    /// Splits the lines into requests of similar size that each fit the character budget.
    static func chunks(of texts: [String], maxCharacters: Int) -> [[Int]] {
        let total = texts.reduce(0) { $0 + $1.count }
        guard total > maxCharacters else {
            return texts.isEmpty ? [] : [Array(texts.indices)]
        }
        let chunkCount = (total + maxCharacters - 1) / maxCharacters
        let target = Double(total) / Double(chunkCount)
        var chunks: [[Int]] = []
        var current: [Int] = []
        var currentCharacters = 0
        for (index, text) in texts.enumerated() {
            current.append(index)
            currentCharacters += text.count
            if Double(currentCharacters) >= target && chunks.count < chunkCount - 1 {
                chunks.append(current)
                current = []
                currentCharacters = 0
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    // MARK: - Replies

    private struct ReplyEntry: Decodable {
        let id: Int
        let source: String?
        let translation: String?

        enum CodingKeys: String, CodingKey {
            case id, source, translation
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let id = try? container.decode(Int.self, forKey: .id) {
                self.id = id
            } else if let id = Int(try container.decode(String.self, forKey: .id).trimmingCharacters(in: .whitespaces)) {
                self.id = id
            } else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Invalid id")
            }
            source = try container.decodeIfPresent(String.self, forKey: .source)
            translation = try container.decodeIfPresent(String.self, forKey: .translation)
        }
    }

    /// Returns the translations in a reply whose source matches the line of their id, by line index.
    static func acceptedTranslations(in reply: String, indices: [Int], texts: [String]) -> [Int: String] {
        let wanted = Set(indices)
        var accepted: [Int: String] = [:]
        for entry in replyEntries(in: reply) {
            let index = entry.id - 1
            guard wanted.contains(index), accepted[index] == nil,
                  let source = entry.source, sourceMatches(source, texts[index]),
                  let translation = entry.translation?.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                  !translation.isEmpty else {
                continue
            }
            accepted[index] = translation
        }
        return accepted
    }

    /// Decodes every complete JSON object in a reply, so that code fences, extra text and a cut-off end are ignored.
    private static func replyEntries(in reply: String) -> [ReplyEntry] {
        let bytes = Array(reply.utf8)
        let decoder = JSONDecoder()
        var entries: [ReplyEntry] = []
        var depth = 0
        var start = 0
        var inString = false
        var escaped = false
        for (offset, byte) in bytes.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"):
                if depth == 0 {
                    start = offset
                }
                depth += 1
            case UInt8(ascii: "}"):
                guard depth > 0 else {
                    continue
                }
                depth -= 1
                if depth == 0, let entry = try? decoder.decode(ReplyEntry.self, from: Data(bytes[start...offset])) {
                    entries.append(entry)
                }
            default:
                break
            }
        }
        return entries
    }

    /// Whether the source copied by the model is the text of the line, ignoring differences in width, spaces and
    /// wave dashes, and allowing one other difference per 10 characters. Short lines must match exactly,
    /// since neighboring lines such as "ん?" and "え?" often differ in a single character.
    static func sourceMatches(_ source: String, _ text: String) -> Bool {
        let copied = comparable(source)
        let original = comparable(text)
        if copied == original {
            return true
        }
        let tolerance = original.count / 10
        guard tolerance > 0, abs(copied.count - original.count) <= tolerance else {
            return false
        }
        return editDistance(copied, original, limit: tolerance) <= tolerance
    }

    private static func comparable(_ text: String) -> [Character] {
        Array(text.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace && !"~〜～ー-".contains($0) })
    }

    /// Levenshtein distance, stopping early once it exceeds the limit.
    private static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        guard !a.isEmpty, !b.isEmpty else {
            return max(a.count, b.count)
        }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + [Int](repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            if current.min()! > limit {
                return limit + 1
            }
            previous = current
        }
        return previous[b.count]
    }
}
#endif
