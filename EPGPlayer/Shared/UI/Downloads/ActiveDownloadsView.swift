//
//  ActiveDownloadsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/12.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct ActiveDownloadsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @State var monitoringTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            VStack {
                if appState.activeDownloads.isEmpty {
                    ContentUnavailableView("No downloading videos", systemImage: "questionmark.circle")
                } else {
                    List {
                        ForEach(appState.activeDownloads) { (download: ActiveDownload) in
                            VStack(alignment: .leading) {
                                if let recordName = download.videoItem.recordedItem?.name {
                                    Text(verbatim: recordName)
                                        .font(.headline)
                                }
                                HStack {
                                    download.videoItem.type.text
                                        .font(.subheadline.bold())
                                    Text(verbatim: download.videoItem.name)
                                        .font(.subheadline)
                                    Text(verbatim: ByteCountFormatter().string(fromByteCount: download.videoItem.fileSize))
                                        .font(.subheadline)
                                }
                                HStack {
                                    ProgressView(value: download.progress)
                                    Text("\(download.progress * 100, specifier: "%.1f")%")
                                        .font(.system(.subheadline).monospacedDigit())
                                }
                                if let errorMessage = download.errorMessage {
                                    HStack(alignment: .center) {
                                        Text(verbatim: errorMessage)
                                            .foregroundStyle(.red)
                                        if let index = appState.activeDownloads.firstIndex(where: { $0 == download }) {
                                            Spacer()
                                            Button {
                                                restartDownload(download, index: index)
                                            } label: {
                                                Image(systemName: "arrow.counterclockwise")
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.tint)
                                        }
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    cancelDownload(download)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    cancelDownload(download)
                                } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                            }
                        }
                    }
                }
                #if !os(macOS)
                HStack {
                    Spacer()
                    Text("Downloads will continue in the background. But killing the app will cancel all downloads.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                #endif
            }
            .navigationTitle("Downloading")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: appState.isOnMac ? .cancellationAction : .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                    }
                }
            }
            .onAppear {
                monitoringTask = Task.detached(priority: .background, operation: {
                    do {
                        while !Task.isCancelled {
                            await MainActor.run {
                                for i in 0..<appState.activeDownloads.count {
                                    appState.activeDownloads[i].progress = appState.activeDownloads[i].downloadTask.progress.fractionCompleted
                                }
                            }
                            try await Task.sleep(for: .seconds(1))
                        }
                    } catch { }
                })
            }
            .onDisappear {
                monitoringTask?.cancel()
            }
        }
        #if os(macOS)
        .presentationSizing(.form)
        #endif
    }
    
    func restartDownload(_ download: ActiveDownload, index: Int) {
        guard let downloadTask = DownloadManager.shared.startDownloading(url: download.url, expectedBytes: download.videoItem.fileSize, headers: appState.client.headers) else {
            appState.activeDownloads[index].errorMessage = "Failed to restart"
            return
        }
        appState.activeDownloads[index] = ActiveDownload(url: download.url, videoItem: download.videoItem, downloadTask: downloadTask)
        download.videoItem.file.unavailableReason = nil
    }
    
    func cancelDownload(_ download: ActiveDownload) {
        download.downloadTask.cancel()
        let recordItem = download.videoItem.recordedItem
        if let recordItem, recordItem.videoItems.count == 1 {
            context.delete(recordItem)
        } else {
            context.delete(download.videoItem)
        }
        appState.activeDownloads.removeAll(where: { $0 == download })
    }
}
