//
//  DownloadsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/01.
//

import SwiftUI

struct DownloadsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        NavigationStack {
            if appState.downloads.isEmpty {
                ContentUnavailableView("No downloaded video", systemImage: "folder.badge.questionmark")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15) {
                        ForEach(appState.downloads) { download in
                            RecordingCell(item: download.item, localVideo: download)
                                .tint(.primary)
                                .id(download.id)
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
