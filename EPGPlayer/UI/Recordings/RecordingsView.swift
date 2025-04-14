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
            ClientContentView(activeTab: $activeTab, loadingState: $loadingState, refresh: { waitTime in
                refresh(waitTime: waitTime)
            }, content: {
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
                                .controlSize(.large)
                        } else if case .error(let message) = loadingMoreState {
                            ContentUnavailableView {
                                Label("Error loading content", systemImage: "xmark.circle")
                            } description: {
                                message
                            }
                        }
                    }
                    
                    if appState.isOnMac {
                        Spacer()
                            .frame(height: 10)
                    }
                }
                .refreshable {
                    refresh()
                }
            })
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if recorded.isEmpty {
                refresh()
            }
        }
    }
    
    func refresh(waitTime: Duration = .zero) {
        guard appState.clientState == .initialized else {
            return
        }
        recorded = []
        loadingState = .loading
        Task {
            let records: [Components.Schemas.RecordedItem]
            do {
                try await Task.sleep(for: waitTime)
                let resp = try await appState.client.api.getRecorded(query: Operations.GetRecorded.Input.Query(isHalfWidth: true))
                let json = try resp.ok.body.json
                records = json.records
                totalCount = json.total
                self.recorded = records
                loadingState = .loaded
                print("Loaded \(recorded.count) recordings (\(totalCount) total)")
            } catch let error {
                print("Failed to load recordings: \(error)")
                loadingState = .error(Text(verbatim: error.localizedDescription))
                records = []
            }
            Components.Schemas.RecordedItem.endpoint = appState.client.endpoint
            
            do {
                let resp = try await appState.client.api.getChannels()
                let channels = try resp.ok.body.json
                Components.Schemas.RecordedItem.channelMap = channels.reduce(into: [Int: Components.Schemas.ChannelItem]()) { map, item in
                    map[item.id] = item
                }
            } catch let error {
                print("Failed to load channels: \(error)")
            }
        }
    }
    
    func loadMore() {
        if case .loading = loadingMoreState {
            return
        }
        loadingMoreState = .loading
        Task {
            while case .loading = loadingState {
                try await Task.sleep(for: .milliseconds(300))
            }
            if case .error(_) = loadingState {
                return
            }
            do {
                print("Loading more with offset \(recorded.count)")
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

extension Components.Schemas.RecordedItem: Identifiable {
}
