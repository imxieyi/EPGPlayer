//
//  DownloadsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/01.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import SwiftData

struct DownloadsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @Query(sort: \LocalRecordedItem.startTime, order: .reverse) var recorded: [LocalRecordedItem]
    @Query var localFiles: [LocalFile]
    
    @State var showActiveDownloads = false
    @State var showSearchView = false
    @State var searchQuery: SearchQuery? = nil
    
    @State var showErrorAlert = false
    @State var errorAlertRecordItem: LocalRecordedItem? = nil
    @State var errorAlertVideoItem: LocalVideoItem? = nil
    
    var body: some View {
        NavigationStack {
            Group {
                if let error = appState.downloadsSetupError {
                    ContentUnavailableView("Database setup failed", systemImage: "xmark.circle", description: Text(verbatim: error.localizedDescription))
                } else if recorded.isEmpty {
                    ContentUnavailableView("No downloaded video", systemImage: "folder.badge.questionmark")
                } else {
                    ScrollView {
                        #if os(macOS)
                        Spacer()
                            .frame(height: 10)
                        #endif
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15) {
                            let recorded = (
                                searchQuery == nil
                                ? recorded
                                : recorded.filter { $0.name.contains(searchQuery!.keyword == "" ? $0.name : searchQuery!.keyword) && $0.channelName == (searchQuery?.channel?.name ?? $0.channelName) }
                            )
                            ForEach(recorded) { item in
                                VStack(alignment: .center) {
                                    NavigationLink {
                                        RecordingDetailView(item: item)
                                    } label: {
                                        RecordingCell(item: item)
                                            .tint(.primary)
                                            .id(item)
                                    }
                                    .buttonStyle(.borderless)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            appState.activeDownloads.removeAll { $0.videoItem.recordedItem == item }
                                            context.delete(item)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    let localFailedItems = item._videoItems.filter({ $0.file.unavailableReason != nil })
                                    if !localFailedItems.isEmpty {
                                        GroupBox {
                                            ForEach(localFailedItems) { failedItem in
                                                HStack {
                                                    Text(verbatim: failedItem.name)
                                                        .bold()
                                                    Button {
                                                        errorAlertRecordItem = item
                                                        errorAlertVideoItem = failedItem
                                                        showErrorAlert.toggle()
                                                    } label: {
                                                        Text(verbatim: failedItem.file.unavailableReason ?? "Unknown")
                                                            .lineLimit(1)
                                                    }
                                                    .buttonStyle(.borderless)
                                                }
                                                .tint(.red)
                                            }
                                        } label: {
                                            Label("Errors", systemImage: "exclamationmark.circle")
                                        }
                                    }
                                    let downloadingItems = item._videoItems.filter({ item in
                                        appState.activeDownloads.contains(where: { $0.videoItem == item })
                                    })
                                    if !downloadingItems.isEmpty {
                                        GroupBox {
                                            HStack {
                                                VStack(alignment: .leading) {
                                                    ForEach(downloadingItems) { downloadingItem in
                                                        Text(verbatim: downloadingItem.name)
                                                    }
                                                }
                                                Spacer()
                                            }
                                        } label: {
                                            Label("Downloading", systemImage: "arrow.down")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .animation(.default, value: recorded)
                        
                        #if os(macOS)
                        Spacer()
                            .frame(height: 10)
                        #endif
                    }
                }
            }
            .navigationTitle("Downloads")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: appState.isOnMac ? .primaryAction : .topBarTrailing) {
                    Button {
                        showActiveDownloads.toggle()
                    } label: {
                        let errorCount = appState.activeDownloads.count(where: { $0.errorMessage != nil })
                        if errorCount > 0 {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.red)
                                .badge(errorCount)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSearchView.toggle()
                    } label: {
                        Label("Search", systemImage: searchQuery == nil ? "magnifyingglass" : "sparkle.magnifyingglass")
                    }
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button(role: .destructive) {
                    if let errorAlertRecordItem, errorAlertRecordItem.videoItems.count == 1 {
                        context.delete(errorAlertRecordItem)
                    } else {
                        context.delete(errorAlertVideoItem!)
                    }
                    appState.activeDownloads.removeAll { $0.videoItem == errorAlertVideoItem! }
                    errorAlertRecordItem = nil
                    errorAlertVideoItem = nil
                } label: {
                    Text("Delete")
                }
                Button(role: .cancel) {
                } label: {
                    Text("Close")
                }
            } message: {
                Text(verbatim: errorAlertVideoItem?.file.unavailableReason ?? "Unknown error")
            }
        }
        .sheet(isPresented: $showActiveDownloads, content: {
            ActiveDownloadsView()
        })
        .sheet(isPresented: $showSearchView) {
            SearchView(searchQuery: $searchQuery, channels: Array(Set(recorded.compactMap { $0.channelName }).map({ SearchChannel(name: $0, channelId: nil) })))
        }
        .onChange(of: localFiles, initial: false) { oldValue, newValue in
            let newSet = Set(newValue)
            let deletedFiles = oldValue.filter { !newSet.contains($0) }
            deletedFiles.forEach { file in
                guard file.available else {
                    return
                }
                do {
                    try LocalFileManager.shared.deleteFile(name: file.id.uuidString)
                } catch let error {
                    Logger.error("Failed to delete local file \(pii: file.id.uuidString): \(error.localizedDescription)")
                }
            }
        }
    }
}
