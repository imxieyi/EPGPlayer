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
    @EnvironmentObject private var userSettings: UserSettings
    @Bindable var appState: AppState
    @Binding var activeTab: TabSelection
    
    @State var showSearchView: Bool = false
    @State var searchQuery: SearchQuery? = nil
    
    @State var loadingState = LoadingState.loading
    @State var loadingMoreState = LoadingState.loaded
    
    @State var totalCount = 0
    @State var channels: [Components.Schemas.ChannelItem] = []
    @State var recorded: [Components.Schemas.RecordedItem] = []
    @State var searchRules: [SearchRule] = []
    
    #if os(tvOS)
    @State var shelves: [RecordingShelf] = []
    @State var shelvesLoadingState = LoadingState.loading
    #endif
    
    var body: some View {
        NavigationStack {
            Group {
                #if os(tvOS)
                VStack(spacing: 0) {
                    TVTopActionBar(alignment: .leading) {
                        Button {
                            showSearchView.toggle()
                        } label: {
                            Image(systemName: searchQuery == nil ? "magnifyingglass" : "sparkle.magnifyingglass")
                        }
                        .controlSize(.small)
                    }
                    recordingsContent
                }
                #else
                recordingsContent
                #endif
            }
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
                #if !os(tvOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSearchView.toggle()
                    } label: {
                        Label("Search", systemImage: searchQuery == nil ? "magnifyingglass" : "sparkle.magnifyingglass")
                    }
                }
                #endif
            })
            #if !os(tvOS)
            .navigationTitle("Recordings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #else
            .toolbarTitleDisplayMode(.inline)
            #endif
        }
        .sheet(isPresented: $showSearchView) {
            SearchView(searchQuery: $searchQuery, channels: channels.map { SearchChannel(name: $0.name, channelId: $0.id) }, rules: searchRules)
        }
        .onChange(of: searchQuery, initial: true) { oldValue, newValue in
            if oldValue != newValue {
                refresh()
            }
        }
    }

    var recordingsContent: some View {
        ClientContentView(activeTab: $activeTab, loadingState: $loadingState, refresh: { waitTime in
            refresh(waitTime: waitTime)
        }, content: {
            ScrollView {
                #if os(macOS)
                Spacer()
                    .frame(height: 10)
                #endif

                #if os(tvOS)
                if searchQuery == nil {
                    shelvesSection
                } else {
                    recordingsGrid
                }
                #else
                recordingsGrid
                #endif

                #if os(macOS)
                Spacer()
                    .frame(height: 10)
                #endif
            }
            .refreshable {
                refresh()
            }
        })
        .onAppear {
            if recorded.isEmpty {
                refresh()
            }
        }
    }
    
    var recordingsGrid: some View {
        Group {
            if recorded.isEmpty {
                ContentUnavailableView("No recordings found", systemImage: "questionmark.circle")
            } else {
                #if os(tvOS)
                let gridItem = GridItem(.adaptive(minimum: 420), spacing: 15)
                #else
                let gridItem = GridItem(.adaptive(minimum: 300), spacing: 15)
                #endif
                LazyVGrid(columns: [gridItem], spacing: 15) {
                    ForEach(recorded) { item in
                        NavigationLink {
                            RecordingDetailView(item: item, onDelete: {
                                recorded.removeAll { $0.id == item.id }
                                totalCount -= 1
                            })
                        } label: {
                            RecordingCell(item: item)
                        }
                        #if os(tvOS)
                        .buttonStyle(.tvFlat)
                        .focusEffectDisabled()
                        #elseif os(macOS)
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
                #if !os(tvOS)
                .padding(.horizontal)
                #endif
            }

            if recorded.count < totalCount {
                if case .loading = loadingMoreState {
                    ProgressView()
                        #if !os(tvOS)
                        .controlSize(.large)
                        #endif
                } else if case .error(let message) = loadingMoreState {
                    ContentUnavailableView {
                        Label("Error loading content", systemImage: "xmark.circle")
                    } description: {
                        message
                    }
                }
            }
        }
    }
    
    #if os(tvOS)
    var shelvesSection: some View {
        Group {
            if case .loading = shelvesLoadingState, shelves.isEmpty {
                ProgressView()
            } else if shelves.isEmpty {
                ContentUnavailableView("No recordings found", systemImage: "questionmark.circle")
            } else {
                LazyVStack(alignment: .leading, spacing: 40) {
                    ForEach(shelves) { shelf in
                        recordingShelfRow(shelf)
                    }
                }
            }
        }
    }
    
    func recordingShelfRow(_ shelf: RecordingShelf) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: shelf.title)
                .font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(shelf.items) { item in
                        NavigationLink {
                            RecordingDetailView(item: item, onDelete: {
                                removeRecording(item)
                            })
                        } label: {
                            RecordingCell(item: item)
                        }
                        .buttonStyle(.tvFlat)
                        .focusEffectDisabled()
                        .tint(.primary)
                        .frame(width: 420)
                        .id(item.id)
                    }
                }
            }
            // Marks each horizontally-scrolling row as its own focus region, so the
            // focus engine reliably moves up/down between rows (and up and out to
            // TVTopActionBar's search button) instead of getting stuck inside one.
            .focusSection()
        }
    }
    #endif
    
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
                Logger.info("Loaded \(records?.count ?? 0) recordings (\(totalCount) total)")
            } catch let error {
                Logger.error("Failed to load recordings: \(error.localizedDescription)")
                loadingState = .error(Text(verbatim: error.localizedDescription))
                records = nil
            }
            
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
            #if DEBUG
            if userSettings.demoMode {
                Components.Schemas.RecordedItem.channelMap = self.recorded.reduce(into: [Int: Components.Schemas.ChannelItem](), { map, item in
                    if let channelId = item.channelId {
                        map[channelId] = Components.Schemas.ChannelItem(id: channelId, serviceId: 0, networkId: 0, name: "Blender Foundation", halfWidthName: "", hasLogoData: false, channelType: .gr, channel: "")
                    }
                })
            }
            #endif
            if searchRules.isEmpty {
                loadSearchRules()
            }
            #if os(tvOS)
            if searchQuery == nil {
                loadShelves()
            }
            #endif
        }
    }
    
    /// Fetches every recording rule that has a keyword, for the search sheet's "Recording
    /// rule" filter. Shared with loadShelves() below, which needs the same full rule list.
    func fetchAllRules() async throws -> [Components.Schemas.Rule] {
        var rules: [Components.Schemas.Rule] = []
        while true {
            let resp = try await appState.client.api.getRules(query: .init(offset: rules.count, limit: 100))
            let json = try resp.ok.body.json
            if json.rules.isEmpty {
                break
            }
            rules += json.rules
            if rules.count >= json.total {
                break
            }
        }
        return rules
    }
    
    func loadSearchRules() {
        Task {
            do {
                let rules = try await fetchAllRules()
                searchRules = rules.compactMap { rule in
                    guard let keyword = rule.value2.searchOption.keyword, !keyword.isEmpty else {
                        return nil
                    }
                    return SearchRule(id: rule.value1.id, keyword: keyword)
                }
            } catch let error {
                Logger.error("Failed to load search rules: \(error.localizedDescription)")
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
    
    #if os(tvOS)
    func removeRecording(_ item: Components.Schemas.RecordedItem) {
        recorded.removeAll { $0.id == item.id }
        totalCount -= 1
        shelves = shelves.compactMap { shelf in
            let items = shelf.items.filter { $0.id != item.id }
            return items.isEmpty ? nil : RecordingShelf(id: shelf.id, title: shelf.title, items: items)
        }
    }
    
    func loadShelves() {
        Task {
            shelvesLoadingState = .loading
            do {
                let rules = try await fetchAllRules()
                
                var ruleResults: [(ruleId: Int, keyword: String, total: Int, items: [Components.Schemas.RecordedItem])] = []
                for rule in rules {
                    let ruleId = rule.value1.id
                    guard let keyword = rule.value2.searchOption.keyword, !keyword.isEmpty else {
                        continue
                    }
                    // No isReverse here: the default (unspecified) order is already newest-first,
                    // matching "Recent Recordings" below - isReverse actually flips it to oldest-first.
                    let resp = try await appState.client.api.getRecorded(query: .init(isHalfWidth: true, limit: 20, ruleId: ruleId))
                    let json = try resp.ok.body.json
                    ruleResults.append((ruleId, keyword, json.total, json.records))
                }
                
                // Page through newest-first, bucketing into "last 30 days" vs "older", until
                // we have enough older items for that shelf too (or run out of data).
                let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
                var last30DaysItems: [Components.Schemas.RecordedItem] = []
                var olderItems: [Components.Schemas.RecordedItem] = []
                var offset = 0
                while offset < 500 {
                    let resp = try await appState.client.api.getRecorded(query: .init(isHalfWidth: true, offset: offset, limit: 100))
                    let json = try resp.ok.body.json
                    if json.records.isEmpty {
                        break
                    }
                    for record in json.records {
                        if record.startTime >= thirtyDaysAgo {
                            last30DaysItems.append(record)
                        } else {
                            olderItems.append(record)
                        }
                    }
                    offset += json.records.count
                    if olderItems.count >= 30 || offset >= json.total {
                        break
                    }
                }
                
                let recentShelf = RecordingShelf(id: "recent", title: String(localized: "Recent Recordings"), items: Array(last30DaysItems.prefix(30)))
                let olderShelf = RecordingShelf(id: "older", title: String(localized: "Older Recordings"), items: Array(olderItems.prefix(30)))
                let ruleShelves = ruleResults
                    .filter { $0.total > 0 }
                    .sorted { $0.total > $1.total }
                    .map { RecordingShelf(id: "rule-\($0.ruleId)", title: $0.keyword, items: $0.items) }
                
                Logger.info("Shelves: recent=\(recentShelf.items.count), older=\(olderShelf.items.count), rules=\(ruleShelves.count)")
                shelves = [recentShelf, olderShelf].filter { !$0.items.isEmpty } + ruleShelves
                shelvesLoadingState = .loaded
            } catch let error {
                Logger.error("Failed to load recording shelves: \(error.localizedDescription)")
                shelvesLoadingState = .error(Text(verbatim: error.localizedDescription))
            }
        }
    }
    #endif
}

extension Components.Schemas.RecordedItem: Identifiable {
}

#if os(tvOS)
struct RecordingShelf: Identifiable {
    let id: String
    let title: String
    let items: [Components.Schemas.RecordedItem]
}
#endif

