//
//  SubtitleTranslationView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/25.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import SwiftUI
@preconcurrency import Translation

/// Sheet that translates the ARIB subtitles of a downloaded video. It can only be closed with its own buttons,
/// since the translation session lives as long as the sheet.
@available(iOS 26.0, macOS 26.0, *)
struct SubtitleTranslationView: View {
    let videoURL: URL
    let recordingName: String
    let videoName: String

    @Environment(\.dismiss) private var dismiss
    @State private var job: SubtitleTranslationJob
    @State private var languages: [Locale.Language] = []
    @State private var source: Locale.Language?
    @State private var target: Locale.Language?
    @State private var status: LanguageAvailability.Status?
    @State private var existingTranslations: [SubtitleTranslation] = []
    @State private var configuration: TranslationSession.Configuration?

    init(videoURL: URL, recordingName: String, videoName: String) {
        self.videoURL = videoURL
        self.recordingName = recordingName
        self.videoName = videoName
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
                    if languages.isEmpty {
                        ProgressView()
                    } else {
                        languagePicker("From", selection: $source)
                        languagePicker("To", selection: $target)
                    }
                } header: {
                    Text("Languages")
                } footer: {
                    languageStatus
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
        .translationTask(configuration) { session in
            await job.run(session: session)
        }
        .task {
            await loadLanguages()
        }
        .task(id: [source, target]) {
            await updateStatus()
        }
    }

    private var isFinished: Bool {
        if case .finished = job.phase {
            return true
        }
        return false
    }

    private var canStart: Bool {
        guard let source, let target, source != target else {
            return false
        }
        return status == .installed || status == .supported
    }

    private func languagePicker(_ title: LocalizedStringKey, selection: Binding<Locale.Language?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(languages, id: \.self) { language in
                Text(verbatim: displayName(of: language))
                    .tag(Optional(language))
            }
        }
    }

    @ViewBuilder
    private var languageStatus: some View {
        if job.phase == .idle, let source, let target {
            if source == target {
                Text("Choose two different languages.")
            } else {
                if let status {
                    switch status {
                    case .installed:
                        Text("Ready to translate.")
                    case .supported:
                        Text("The languages will be downloaded when you start.")
                    case .unsupported:
                        Text("This language pair is not supported.")
                    @unknown default:
                        EmptyView()
                    }
                }
                if existingTranslations.contains(where: { $0.sourceLanguage.minimalIdentifier == source.minimalIdentifier && $0.targetLanguage.minimalIdentifier == target.minimalIdentifier }) {
                    Text("This video already has a translation for these languages. Starting will replace it.")
                }
            }
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
        case .preparingLanguages:
            ProgressView {
                Text("Preparing languages…")
            }
        case .translating(let completed, let total):
            ProgressView(value: Double(completed), total: Double(max(total, 1))) {
                Text("Translating \(completed) of \(total) sentences…")
            }
        case .finished(let count):
            Label("Translated \(count) sentences. Select the translation in the subtitle menu of the player.", systemImage: "checkmark.circle")
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

    private func start() {
        guard let source, let target else {
            return
        }
        job.prepare()
        configuration = TranslationSession.Configuration(source: source, target: target)
    }

    private func displayName(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    private func loadLanguages() async {
        existingTranslations = SubtitleTranslationStore.translations(forVideo: videoURL)
        let supported = await LanguageAvailability().supportedLanguages
        languages = supported.sorted { displayName(of: $0).localizedStandardCompare(displayName(of: $1)) == .orderedAscending }
        let defaultSource = bestMatch(for: Locale.Language(identifier: "ja"))
        var defaultTarget = bestMatch(for: Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
        if defaultTarget?.languageCode == defaultSource?.languageCode {
            defaultTarget = bestMatch(for: Locale.Language(identifier: "en"))
        }
        source = defaultSource
        target = defaultTarget
    }

    /// Finds the supported language that best matches a language such as "en" or "zh-Hans".
    private func bestMatch(for language: Locale.Language) -> Locale.Language? {
        let candidates = languages.filter {
            $0.languageCode == language.languageCode && (language.script == nil || $0.script == language.script)
        }
        return candidates.first(where: { $0.minimalIdentifier == language.minimalIdentifier })
            ?? candidates.first(where: { $0.region == Locale.current.region })
            ?? candidates.first
    }

    private func updateStatus() async {
        guard let source, let target, source != target else {
            status = nil
            return
        }
        status = await LanguageAvailability().status(from: source, to: target)
    }
}
#endif
