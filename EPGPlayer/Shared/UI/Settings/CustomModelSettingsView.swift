//
//  CustomModelSettingsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/26.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import SwiftUI
import KeychainSwift

extension CustomModelConfiguration {
    /// Reads the configuration saved in the settings and the API key saved in the keychain.
    @MainActor
    init(settings: UserSettings, keychain: KeychainSwift?) {
        self.init(format: CustomModelAPIFormat(rawValue: settings.customModelAPIFormat) ?? .openAIChatCompletions,
                  baseURL: settings.customModelBaseURL,
                  model: settings.customModelName,
                  apiKey: keychain?.get(UserSettings.customModelAPIKeyKeychainKey) ?? "")
    }
}

private extension View {
    /// Shows a text field as the value of a labeled row.
    func fieldInLabeledContent() -> some View {
        labelsHidden()
            .multilineTextAlignment(.trailing)
    }
}

/// Settings of the language model on a server of the user's choice for translating subtitles.
struct CustomModelSettingsView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings

    private enum TestResult {
        case success(translation: String, duration: Duration)
        case failure(String)
    }

    /// A caption line that also shows whether the model keeps the speaker name in parentheses.
    private static let sampleLine = "(のび太)ドラえもん、助けてよ!"

    @State private var apiKey = ""
    @State private var testTask: Task<Void, Never>?
    @State private var testResult: TestResult?

    private var format: CustomModelAPIFormat {
        CustomModelAPIFormat(rawValue: userSettings.customModelAPIFormat) ?? .openAIChatCompletions
    }

    private var configuration: CustomModelConfiguration {
        CustomModelConfiguration(format: format, baseURL: userSettings.customModelBaseURL, model: userSettings.customModelName,
                                 apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        Form {
            Section {
                Picker("API format", selection: Binding(get: { format }, set: { userSettings.customModelAPIFormat = $0.rawValue })) {
                    ForEach(CustomModelAPIFormat.allCases) { format in
                        Text(verbatim: format.name)
                            .tag(format)
                    }
                }
                // Forms on iOS don't show the labels of text fields.
                LabeledContent("Base URL") {
                    TextField("Base URL", text: userSettings.$customModelBaseURL, prompt: Text(verbatim: format.defaultBaseURL))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .fieldInLabeledContent()
                }
                LabeledContent("API key") {
                    SecureField("API key", text: $apiKey, prompt: Text("Optional for local servers"))
                        .autocorrectionDisabled()
                        .fieldInLabeledContent()
                }
                LabeledContent("Model") {
                    TextField("Model", text: userSettings.$customModelName, prompt: Text("Model ID"))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .fieldInLabeledContent()
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let endpoint = configuration.endpointURL {
                        Text("Requests are sent to \(endpoint)")
                    } else {
                        Text("The base URL is invalid.")
                            .foregroundStyle(.red)
                    }
                    Text("Leave the base URL empty to use the official server. Any server that is compatible with the API format works.")
                    Text("When you translate with the custom model, the subtitles and the program information are sent to this server.")
                }
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test Connection")
                        if testTask != nil {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!configuration.isComplete || testTask != nil)
                if let testResult {
                    testResultView(testResult)
                }
            } footer: {
                Text("Translates a sample caption line to check the settings.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Custom Model")
        .onAppear {
            apiKey = appState.keychain?.get(UserSettings.customModelAPIKeyKeychainKey) ?? ""
        }
        .onDisappear {
            resetTest()
        }
        .onChange(of: [userSettings.customModelAPIFormat, userSettings.customModelBaseURL, userSettings.customModelName, apiKey]) {
            // A result is only meaningful for the settings it was tested with.
            resetTest()
        }
        .onChange(of: apiKey) { _, newValue in
            guard let keychain = appState.keychain else {
                return
            }
            let key = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                keychain.delete(UserSettings.customModelAPIKeyKeychainKey)
            } else if !keychain.set(key, forKey: UserSettings.customModelAPIKeyKeychainKey) {
                Logger.error("Failed to save the API key of the custom model")
            }
        }
    }

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        switch result {
        case .success(let translation, let duration):
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The model replied in \(duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))).")
                    Text(verbatim: "\(Self.sampleLine) → \(translation)")
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        case .failure(let message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private func testConnection() {
        let model = CustomTranslationModel(configuration: configuration)
        let target = Locale.Language(identifier: SubtitleTranslationTarget.defaultIdentifier(saved: userSettings.translationTargetLanguage))
        testResult = nil
        testTask = Task {
            let translator = SubtitleTranslator(model: model, target: target, program: nil)
            let clock = ContinuousClock()
            let start = clock.now
            let result: TestResult
            do {
                let translation = try await translator.translateSample(Self.sampleLine)
                result = .success(translation: translation, duration: clock.now - start)
            } catch {
                result = .failure(error.localizedDescription)
            }
            // A cancelled test belongs to settings that were changed since.
            guard !Task.isCancelled else {
                return
            }
            testResult = result
            testTask = nil
        }
    }

    private func resetTest() {
        testTask?.cancel()
        testTask = nil
        testResult = nil
    }
}
#endif
