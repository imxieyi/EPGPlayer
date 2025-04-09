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
    @Binding var activeTab: TabSelection
    
    @State var loadingState = LoadingState.loading
    @State var loadingMoreState = LoadingState.loaded
    
    @State var totalCount = 0
    @State var recorded: [Components.Schemas.RecordedItem] = []
    
    var body: some View {
        NavigationStack {
            Group {
                if case .loading = loadingState {
                    ProgressView()
                        .padding()
                } else if case .loaded = loadingState {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15)], spacing: 15) {
                            ForEach(recorded) { item in
                                NavigationLink {
                                    RecordingDetailView(item: item)
                                } label: {
                                    RecordingCell(item: item)
                                }
                                .tint(.primary)
                                .id(item.id)
                            }
                            if case .loaded = loadingMoreState, recorded.count < totalCount {
                                Spacer()
                                    .onAppear {
                                        loadMore()
                                    }
                            }
                        }
                        .padding(.horizontal)
                        if recorded.count < totalCount {
                            if case .loading = loadingMoreState {
                                ProgressView()
                            } else if case .error(let message) = loadingMoreState {
                                ContentUnavailableView {
                                    Label("Error loading content", systemImage: "xmark.circle")
                                } description: {
                                    message
                                }
                            }
                        }
                    }
                    .refreshable {
                        refresh()
                    }
                } else if case .error(let message) = loadingState {
                    ContentUnavailableView {
                        if appState.clientState == .setupNeeded {
                            Label("Setup needed", systemImage: "exclamationmark.triangle")
                        } else if appState.clientState == .authNeeded {
                            Label("Authentication required", systemImage: "exclamationmark.triangle")
                        } else {
                            Label("Error loading content", systemImage: "xmark.circle")
                        }
                    } description: {
                        message
                    } actions: {
                        if appState.clientState == .authNeeded {
                            Button("Login") {
                                appState.isAuthenticating = true
                            }
                        } else if appState.clientState == .setupNeeded {
                            Button("Go to settings") {
                                activeTab = .settings
                            }
                        }
                    }
                } else {
                    EmptyView()
                }
            }
            .navigationTitle("EPGPlayer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: appState.isAuthenticating) { oldValue, newValue in
            if oldValue && !newValue {
                refresh(waitTime: .seconds(1))
            }
        }
        .onChange(of: appState.clientState) { _, newValue in
            if newValue == .initialized {
                refresh()
            } else if newValue == .authNeeded {
                loadingState = .error(Text("Redirection detected"))
            } else if newValue == .setupNeeded {
                loadingState = .error(Text("Please set EPGStation URL"))
            }
        }
    }
    
    func refresh(waitTime: Duration = .zero) {
        guard appState.clientState == .initialized else {
            loadingState = .error(appState.serverError)
            return
        }
        recorded = []
        Task {
            do {
                try await Task.sleep(for: waitTime)
                let resp = try await appState.client.api.getRecorded(query: Operations.GetRecorded.Input.Query(isHalfWidth: true))
                let json = try resp.ok.body.json
                recorded = json.records
                totalCount = json.total
                loadingState = .loaded
                print("Loaded \(recorded.count) recordings (\(totalCount) total)")
            } catch let error {
                print("Failed to load recordings: \(error)")
                if let error = error as? ClientError, error.response?.status.kind == .redirection {
                    appState.clientState = .authNeeded
                    loadingState = .error(Text("Redirection detected"))
                    return
                }
                loadingState = .error(Text(verbatim: error.localizedDescription))
            }
            
            do {
                let resp = try await appState.client.api.getChannels()
                let channels = try resp.ok.body.json
                appState.channelMap = channels.reduce(into: [Int: Components.Schemas.ChannelItem]()) { map, item in
                    map[item.id] = item
                }
            } catch let error {
                print("Failed to load channels: \(error)")
            }
        }
    }
    
    func loadMore() {
        Task {
            do {
                let resp = try await appState.client.api.getRecorded(query: Operations.GetRecorded.Input.Query(isHalfWidth: true, offset: recorded.count))
                let json = try resp.ok.body.json
                recorded += json.records
                totalCount = json.total
                loadingMoreState = .loaded
                print("Loaded \(recorded.count) recordings (\(totalCount) total)")
            } catch let error {
                print("Failed to load more recordings: \(error)")
                loadingMoreState = .error(Text(verbatim: error.localizedDescription))
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
