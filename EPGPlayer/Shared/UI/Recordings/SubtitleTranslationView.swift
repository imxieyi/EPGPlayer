//
//  SubtitleTranslationView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/25.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import SwiftUI

/// The language model that translates subtitles.
enum SubtitleTranslationEngine: String, CaseIterable, Identifiable {
    /// Apple Foundation Models on Private Cloud Compute.
    case appleIntelligence = "apple-intelligence"
    /// A language model on a server that the user configured in settings.
    case customModel = "custom-model"

    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .customModel:
            return "Custom model"
        }
    }

    /// Whether the app and the system support the engine at all.
    static var supported: [SubtitleTranslationEngine] {
        #if compiler(>=6.4) && canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return [.appleIntelligence, .customModel]
        }
        #endif
        return [.customModel]
    }

    /// Creates the model, or returns nil when the system doesn't support it or the custom model is not set up.
    func makeModel(customConfiguration: CustomModelConfiguration) -> (any SubtitleTranslationModel)? {
        switch self {
        case .appleIntelligence:
            #if compiler(>=6.4) && canImport(FoundationModels)
            if #available(iOS 27.0, macOS 27.0, *) {
                return PrivateCloudComputeTranslationModel()
            }
            #endif
            return nil
        case .customModel:
            return customConfiguration.isComplete ? CustomTranslationModel(configuration: customConfiguration) : nil
        }
    }
}

/// Languages that subtitles can be translated to.
enum SubtitleTranslationTarget {
    static let identifiers = ["en", "zh-Hans", "zh-Hant", "ko", "fr", "de", "es", "it", "pt-BR", "nl", "ru", "vi", "th", "id"]

    /// The language translated to last time, or the language of the app unless it is Japanese.
    static func defaultIdentifier(saved: String, available: [String] = identifiers) -> String {
        if available.contains(saved) {
            return saved
        }
        let preferred = Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let match = available.first { identifier in
            let language = Locale.Language(identifier: identifier)
            return language.languageCode == preferred.languageCode && (preferred.script == nil || language.script == preferred.script)
        }
        return match ?? (available.contains("en") ? "en" : available.first ?? "")
    }

    /// The languages that a model can translate to, sorted by their names.
    /// - Parameter appleIntelligenceLanguages: the languages that Apple Intelligence supports, if known.
    static func identifiers(for engine: SubtitleTranslationEngine, appleIntelligenceLanguages: Set<Locale.LanguageCode>?) -> [String] {
        var identifiers = identifiers
        if engine == .appleIntelligence, let codes = appleIntelligenceLanguages {
            identifiers = identifiers.filter { Locale.Language(identifier: $0).languageCode.map(codes.contains) ?? false }
        }
        return identifiers.sorted { displayName(of: $0).localizedStandardCompare(displayName(of: $1)) == .orderedAscending }
    }

    static func displayName(of identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}

/// Sheet that translates the ARIB subtitles of a downloaded video. It can only be closed with its own buttons,
/// so that the translation is not stopped by accident.
struct SubtitleTranslationView: View {
    let videoURL: URL
    let recordingName: String
    let videoName: String
    let program: SubtitleProgramInfo?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    @State private var job: SubtitleTranslationJob
    @State private var engine = SubtitleTranslationEngine.supported[0]
    @State private var target = ""
    /// Why Apple Intelligence can't be used, or nil when it can.
    @State private var appleIntelligenceProblem: String?
    @State private var appleIntelligenceLanguages: Set<Locale.LanguageCode>?
    @State private var existingTranslations: [SubtitleTranslation] = []

    init(videoURL: URL, recordingName: String, videoName: String, program: SubtitleProgramInfo?) {
        self.videoURL = videoURL
        self.recordingName = recordingName
        self.videoName = videoName
        self.program = program
        _job = State(initialValue: SubtitleTranslationJob(videoURL: videoURL))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: recordingName)
                    Text(verbatim: videoName)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Model", selection: $engine) {
                        ForEach(SubtitleTranslationEngine.supported) { engine in
                            Text(engine.name)
                                .tag(engine)
                        }
                    }
                    // A retry can continue with another model, but not in another language.
                    .disabled(job.phase != .idle && !canRetry)
                    Picker("Translate to", selection: $target) {
                        ForEach(pickerLanguages, id: \.self) { identifier in
                            Text(verbatim: displayName(of: identifier))
                                .tag(identifier)
                        }
                    }
                    .disabled(job.phase != .idle)
                } footer: {
                    if job.phase == .idle || canRetry {
                        engineStatus
                    }
                }

                if job.phase != .idle {
                    Section {
                        progress
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Translate Subtitles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if job.isRunning {
                        Button("Cancel", role: .destructive) {
                            job.cancel()
                            dismiss()
                        }
                    } else if !isFinished {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isFinished {
                        Button("Done") {
                            dismiss()
                        }
                    } else if job.phase == .idle {
                        Button("Start") {
                            start()
                        }
                        .disabled(!canTranslate)
                    } else if canRetry {
                        Button("Retry") {
                            retry()
                        }
                        .disabled(!canTranslate)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            await load()
        }
        .onChange(of: engine) {
            // The target is empty until the languages are loaded, and can't change for a retry.
            if job.phase == .idle, !target.isEmpty, !targetLanguages.contains(target), let first = targetLanguages.first {
                target = first
            }
        }
    }

    private var isFinished: Bool {
        if case .finished = job.phase {
            return true
        }
        return false
    }

    private var canRetry: Bool {
        if case .failed(_, canRetry: true) = job.phase {
            return true
        }
        return false
    }

    private var customConfiguration: CustomModelConfiguration {
        CustomModelConfiguration(settings: userSettings, keychain: appState.keychain)
    }

    private var targetLanguages: [String] {
        SubtitleTranslationTarget.identifiers(for: engine, appleIntelligenceLanguages: appleIntelligenceLanguages)
    }

    /// The languages of the selected model, and the language of a failed translation even if the model doesn't support it.
    private var pickerLanguages: [String] {
        let languages = targetLanguages
        if !target.isEmpty, !languages.contains(target) {
            return languages + [target]
        }
        return languages
    }

    /// Whether the selected model can translate to the selected language.
    private var canTranslate: Bool {
        guard targetLanguages.contains(target) else {
            return false
        }
        switch engine {
        case .appleIntelligence:
            return appleIntelligenceProblem == nil
        case .customModel:
            return customConfiguration.isComplete
        }
    }

    @ViewBuilder
    private var engineStatus: some View {
        switch engine {
        case .appleIntelligence:
            if let appleIntelligenceProblem {
                Text(verbatim: appleIntelligenceProblem)
                    .foregroundStyle(.red)
            } else if !target.isEmpty, !targetLanguages.contains(target) {
                Text("Apple Intelligence does not support \(displayName(of: target)).")
                    .foregroundStyle(.red)
            } else {
                Text("The subtitles are translated by Apple Foundation Models on Private Cloud Compute.")
            }
        case .customModel:
            let configuration = customConfiguration
            if configuration.isComplete {
                Text("The subtitles and the program information are sent to \(configuration.resolvedBaseURL?.host() ?? "") and translated by \(configuration.trimmedModel).")
            } else {
                Text("Set up the custom model in Settings first.")
                    .foregroundStyle(.red)
            }
        }
        if job.phase == .idle, existingTranslations.contains(where: { $0.targetLanguage.minimalIdentifier == Locale.Language(identifier: target).minimalIdentifier }) {
            Text("This video already has a translation to this language. Starting will replace it.")
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch job.phase {
        case .idle:
            EmptyView()
        case .readingSubtitles(let progress):
            ProgressView(value: progress) {
                Text("Reading subtitles…")
            }
        case .translating(let completed, let total):
            ProgressView(value: Double(completed), total: Double(max(total, 1))) {
                Text("Translating \(completed) of \(total) sentences…")
            }
        case .finished(let count, let untranslated):
            Label("Translated \(count) sentences. Select the translation in the Translation menu of the player.", systemImage: "checkmark.circle")
            if !untranslated.isEmpty {
                untranslatedLines(untranslated)
            }
        case .failed(let message, let canRetry):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if canRetry, let translatedCount = job.progress?.translatedCount, translatedCount > 0 {
                Text("\(translatedCount) of \(job.sentences.count) sentences are translated. Retry continues with the rest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .cancelled:
            Text("Translation cancelled.")
        }
        if job.isRunning {
            Text("Keep the app open until the translation finishes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func untranslatedLines(_ lines: [SubtitleTranslator.UntranslatedLine]) -> some View {
        let refusedCount = lines.filter { $0.reason == .refused }.count
        let failedCount = lines.count - refusedCount
        Label {
            VStack(alignment: .leading, spacing: 4) {
                if refusedCount > 0 {
                    Text("The model refused to translate \(refusedCount) sentences.")
                }
                if failedCount > 0 {
                    Text("The model failed to translate \(failedCount) sentences.")
                }
                Text("They are kept in Japanese:")
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        ForEach(lines, id: \.index) { line in
            Text(verbatim: line.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Creates the selected model with its current settings.
    private func makeModel() -> (any SubtitleTranslationModel)? {
        engine.makeModel(customConfiguration: customConfiguration)
    }

    private func start() {
        guard let model = makeModel() else {
            return
        }
        userSettings.translationEngine = engine.rawValue
        userSettings.translationTargetLanguage = target
        job.start(model: model, target: Locale.Language(identifier: target), program: program)
    }

    private func retry() {
        guard let model = makeModel() else {
            return
        }
        userSettings.translationEngine = engine.rawValue
        job.retry(model: model)
    }

    private func displayName(of identifier: String) -> String {
        SubtitleTranslationTarget.displayName(of: identifier)
    }

    private func load() async {
        existingTranslations = SubtitleTranslationStore.translations(forVideo: videoURL)
        if let saved = SubtitleTranslationEngine(rawValue: userSettings.translationEngine), SubtitleTranslationEngine.supported.contains(saved) {
            engine = saved
        }
        #if compiler(>=6.4) && canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            appleIntelligenceProblem = PrivateCloudComputeTranslationModel.availabilityMessage
            if appleIntelligenceProblem == nil {
                appleIntelligenceLanguages = await PrivateCloudComputeTranslationModel.supportedLanguageCodes()
            }
        }
        #endif
        target = SubtitleTranslationTarget.defaultIdentifier(saved: userSettings.translationTargetLanguage, available: targetLanguages)
    }
}
#endif
