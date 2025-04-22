//
//  RecordingsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/25.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import OpenAPIRuntime
import OpenAPIURLSession

struct RecordingsView: View {
    @Bindable var appState: AppState
    @Binding var activeTab: TabSelection
    
    @State var showSearchView: Bool = false
    @State var searchQuery: SearchQuery? = nil
    
    @State var loadingState = LoadingState.loading
    @State var loadingMoreState = LoadingState.loaded
    
    @State var totalCount = 0
    @State var channels: [Components.Schemas.ChannelItem] = []
    @State var recorded: [Components.Schemas.RecordedItem] = []
    
    var body: some View {
        NavigationStack {
            ClientContentView(activeTab: $activeTab, loadingState: $loadingState, refresh: { waitTime in
                refresh(waitTime: waitTime)
            }, content: {
                ScrollView {
                    #if os(macOS)
                    Spacer()
                        .frame(height: 10)
                    #endif
                    
                    if recorded.isEmpty {
                        ContentUnavailableView("No recordings found", systemImage: "questionmark.circle")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15)], spacing: 15) {
                            ForEach(recorded) { item in
                                NavigationLink {
                                    RecordingDetailView(item: item)
                                } label: {
                                    RecordingCell(item: item)
                                }
                                #if os(macOS)
                                .buttonStyle(.borderless)
                                #endif
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
                    }
                    
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
                    
                    #if os(macOS)
                    Spacer()
                        .frame(height: 10)
                    #endif
                }
                .refreshable {
                    refresh()
                }
            })
            .toolbar(content: {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSearchView.toggle()
                    } label: {
                        Label("Search", systemImage: searchQuery == nil ? "magnifyingglass" : "sparkle.magnifyingglass")
                    }
                }
            })
            .navigationTitle("Recordings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .onAppear {
            if recorded.isEmpty {
                refresh()
            }
        }
        .sheet(isPresented: $showSearchView) {
            SearchView(searchQuery: $searchQuery, channels: channels.map { SearchChannel(name: $0.name, channelId: $0.id) })
        }
        .onChange(of: searchQuery, initial: true) { oldValue, newValue in
            if oldValue != newValue {
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
            let records: [Components.Schemas.RecordedItem]?
            do {
                try await Task.sleep(for: waitTime)
                let resp = try await appState.client.api.getRecorded(query: searchQuery?.apiQuery() ?? Operations.GetRecorded.Input.Query(isHalfWidth: true))
                let json = try resp.ok.body.json
                totalCount = json.total
                records = json.records
                Logger.info("Loaded \(recorded.count) recordings (\(totalCount) total)")
            } catch let error {
                Logger.error("Failed to load recordings: \(error.localizedDescription)")
                loadingState = .error(Text(verbatim: error.localizedDescription))
                records = nil
            }
            Components.Schemas.RecordedItem.endpoint = appState.client.endpoint
            
            do {
                let resp = try await appState.client.api.getChannels()
                let channels = try resp.ok.body.json
                Components.Schemas.RecordedItem.channelMap = channels.reduce(into: [Int: Components.Schemas.ChannelItem]()) { map, item in
                    map[item.id] = item
                }
                self.channels = channels
            } catch let error {
                Logger.error("Failed to load channels: \(error.localizedDescription)")
            }
            if let records {
                self.recorded = records
                loadingState = .loaded
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
                Logger.info("Loading more with offset \(recorded.count)")
                let resp = try await appState.client.api.getRecorded(query: searchQuery?.apiQuery(offset: recorded.count) ?? Operations.GetRecorded.Input.Query(isHalfWidth: true, offset: recorded.count))
                let json = try resp.ok.body.json
                recorded += json.records
                totalCount = json.total
                loadingMoreState = .loaded
                Logger.info("Loaded \(recorded.count) recordings (\(totalCount) total)")
            } catch let error {
                Logger.error("Failed to load more recordings: \(error.localizedDescription)")
                loadingMoreState = .error(Text(verbatim: error.localizedDescription))
            }
        }
    }
}

extension Components.Schemas.RecordedItem: Identifiable {
}
