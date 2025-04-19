//
//  DownloadsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/01.
//

import SwiftUI
import SwiftData

struct DownloadsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @Query(sort: \LocalRecordedItem.startTime, order: .reverse) var recorded: [LocalRecordedItem]
    @Query var localFiles: [LocalFile]
    
    @State var showActiveDownloads = false
    
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15) {
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
                                }
                            }
                        }
                        .padding(.horizontal)
                        .animation(.default, value: recorded)
                        
                        if appState.isOnMac {
                            Spacer()
                                .frame(height: 10)
                        }
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
                    print("Failed to delete local file \(file.id.uuidString): \(error.localizedDescription)")
                }
            }
        }
    }
}
