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
                                NavigationLink {
                                    RecordingDetailView(item: item)
                                } label: {
                                    RecordingCell(item: item)
                                        .tint(.primary)
                                        .id(item)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        context.delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showActiveDownloads.toggle()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
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
