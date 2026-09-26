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
}

/// Sheet that translates the ARIB subtitles of a downloaded video. It can only be closed with its own buttons,
/// so that the translation is not stopped by accident.
@available(iOS 26.0, macOS 26.0, *)
struct SubtitleTranslationView: View {
    /// Languages that subtitles can be translated to.
    private static let targetLanguageIdentifiers = ["en", "zh-Hans", "zh-Hant", "ko", "fr", "de", "es", "it", "pt-BR", "nl", "ru", "vi", "th", "id"]

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
                    Picker("Translate to", selection: $target) {
                        ForEach(targetLanguages, id: \.self) { identifier in
                            Text(verbatim: displayName(of: identifier))
                                .tag(identifier)
                        }
                    }
                } footer: {
                    if job.phase == .idle {
                        engineStatus
                    }
                }
                .disabled(job.phase != .idle)

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
                        .disabled(!canStart)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            await load()
        }
        .onChange(of: engine) {
            // The target is empty until the languages are loaded.
            if !target.isEmpty, !targetLanguages.contains(target), let first = targetLanguages.first {
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

    private var customConfiguration: CustomModelConfiguration {
        CustomModelConfiguration(settings: userSettings, keychain: appState.keychain)
    }

    private var targetLanguages: [String] {
        var identifiers = Self.targetLanguageIdentifiers
        if engine == .appleIntelligence, let codes = appleIntelligenceLanguages {
            identifiers = identifiers.filter { Locale.Language(identifier: $0).languageCode.map(codes.contains) ?? false }
        }
        return identifiers.sorted { displayName(of: $0).localizedStandardCompare(displayName(of: $1)) == .orderedAscending }
    }

    private var canStart: Bool {
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
        if existingTranslations.contains(where: { $0.targetLanguage.minimalIdentifier == Locale.Language(identifier: target).minimalIdentifier }) {
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
            Label("Translated \(count) sentences. Select the translation in the subtitle menu of the player.", systemImage: "checkmark.circle")
            if !untranslated.isEmpty {
                untranslatedLines(untranslated)
            }
        case .failed(let message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
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

    private func start() {
        let model: any SubtitleTranslationModel
        switch engine {
        case .appleIntelligence:
            #if compiler(>=6.4) && canImport(FoundationModels)
            guard #available(iOS 27.0, macOS 27.0, *) else {
                return
            }
            model = PrivateCloudComputeTranslationModel()
            #else
            return
            #endif
        case .customModel:
            model = CustomTranslationModel(configuration: customConfiguration)
        }
        userSettings.translationEngine = engine.rawValue
        userSettings.translationTargetLanguage = target
        job.start(model: model, target: Locale.Language(identifier: target), program: program)
    }

    private func displayName(of identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
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
        target = defaultTarget()
    }

    /// The language translated to last time, or the language of the app unless it is Japanese.
    private func defaultTarget() -> String {
        let languages = targetLanguages
        if languages.contains(userSettings.translationTargetLanguage) {
            return userSettings.translationTargetLanguage
        }
        let preferred = Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let match = languages.first { identifier in
            let language = Locale.Language(identifier: identifier)
            return language.languageCode == preferred.languageCode && (preferred.script == nil || language.script == preferred.script)
        }
        return match ?? (languages.contains("en") ? "en" : languages.first ?? "")
    }
}
#endif
