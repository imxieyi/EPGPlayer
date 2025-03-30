//
//  RecordingsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//

import SwiftUI
import OpenAPIRuntime
import OpenAPIURLSession

struct RecordingsView: View {
    @Bindable var appState: AppState
    
    @State var loadingState = LoadingState.loading
    
    @State var recorded: [Components.Schemas.RecordedItem] = []
    
    var body: some View {
        Group {
            if case .loading = loadingState {
                ProgressView()
                    .padding()
            } else if case .loaded = loadingState {
                List(selection: $appState.selectedRecording) {
                    ForEach(recorded) { item in
                        Text(item.name)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
                .refreshable {
                    refresh()
                }
            } else if case .error(let message) = loadingState {
                ContentUnavailableView {
                    if appState.clientState == .notInitialized {
                        Label("No EPGStation client", systemImage: "exclamationmark.triangle")
                    } else if appState.clientState == .authNeeded {
                        Label("Authentication required", systemImage: "exclamationmark.triangle")
                    } else {
                        Label("Error loading content", systemImage: "xmark.circle")
                    }
                } description: {
                    if appState.clientState == .notInitialized {
                        Text("Please set EPGStation URL")
                    } else {
                        message
                    }
                } actions: {
                    if appState.clientState == .authNeeded {
                        Button("Login") {
                            appState.isAuthenticating = true
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
        .onAppear {
            refresh()
        }
        .onChange(of: appState.isAuthenticating) { oldValue, newValue in
            if oldValue && !newValue {
                refresh(waitTime: .seconds(1))
            }
        }
    }
    
    func refresh(waitTime: Duration = .zero) {
        guard appState.clientState == .initialized else {
            loadingState = .error(appState.serverError)
            return
        }
        loadingState = .loading
        Task {
            do {
                try await Task.sleep(for: waitTime)
                let resp = try await appState.client.api.getRecorded(query: Operations.GetRecorded.Input.Query(isHalfWidth: true))
                recorded = try resp.ok.body.json.records
                loadingState = .loaded
            } catch let error {
                if let error = error as? ClientError, error.response?.status.kind == .redirection {
                    appState.clientState = .authNeeded
                    loadingState = .error(Text("Redirection detected"))
                    return
                }
                loadingState = .error(Text(verbatim: error.localizedDescription))
            }
        }
    }
}

enum LoadingState {
    case loading
    case error(Text)
    case loaded
}

extension Components.Schemas.RecordedItem: Identifiable {
}
