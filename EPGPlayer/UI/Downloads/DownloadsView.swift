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
    @Environment(AppState.self) private var appState
    
    @Query(sort: \LocalRecordedItem.startTime, order: .reverse) var recorded: [LocalRecordedItem]
    
    var body: some View {
        NavigationStack {
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
                        }
                    }
                    .padding(.horizontal)
                    
                    if appState.isOnMac {
                        Spacer()
                            .frame(height: 10)
                    }
                }
            }
        }
    }
}
