//
//  RecordingDetailView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import SwiftData
import OpenAPIRuntime
import CachedAsyncImage
import VLCKit

struct RecordingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow // Add environment for opening windows
    #endif
    
    var item: RecordedItem
    var onDelete: (() -> Void)? = nil

    @State private var showDeleteConfirmation = false
    @State private var deleteInProgress = false
    @State private var deleteError: String? = nil
    #if os(tvOS)
    @State private var showActionMenu = false
    #endif
    @State private var translatingVideoItem: LocalVideoItem? = nil
    @State private var translatableVideoItems: [LocalVideoItem] = []

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .center) {
                if let thumbnail = item.thumbnail {
                    AsyncImageWithHeaders(url: thumbnail, headers: appState.client.headers) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 500)
                        } else if phase.error != nil {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 50))
                                .foregroundStyle(.placeholder)
                        } else {
                            ProgressView()
                                #if !os(tvOS)
                                .controlSize(.large)
                                #endif
                        }
                    }
                }
                Text(verbatim: item.name)
                    .font(.headline)
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
                if let channelName = item.channelName {
                    Text(verbatim: channelName)
                        .font(.subheadline)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                }
                Text(verbatim: item.startTime.formatted(RecordingCell.startDateFormatStyle)
                     + " ~ "
                     + item.endTime.formatted(RecordingCell.endDateFormatStyle)
                     + " (\(Int(item.endTime.timeIntervalSinceReferenceDate - item.startTime.timeIntervalSinceReferenceDate) / 60)分)")
                    .font(.subheadline)
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
                if !item.videoItems.isEmpty {
                    Divider()
                    HStack(alignment: .center, spacing: 20) {
                        Menu {
                            if item.videoItems.contains(where: { $0.type == .ts }) {
                                Section("TS") {
                                    ForEach(item.videoItems.filter({ $0.type == .ts }), id: \.epgId) { videoItem in
                                        Button {
                                            appState.playingItem = PlayerItem(videoItem: videoItem, title: item.name, subtitle: item.channelName, programDescription: [item.shortDesc, item.extendedDesc].compactMap { $0 }.joined(separator: "\n\n"), program: programInfo)
                                            #if os(macOS)
                                            openWindow(id: "player-window")
                                            #endif
                                        } label: {
                                            Text(verbatim: videoItem.name)
                                            Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                                        }
                                        .disabled(!videoItem.canPlay)
                                    }
                                }
                            }
                            if item.videoItems.contains(where: { $0.type == .encoded }) {
                                Section("Encoded") {
                                    ForEach(item.videoItems.filter({ $0.type == .encoded }), id: \.epgId) { videoItem in
                                        Button {
                                            appState.playingItem = PlayerItem(videoItem: videoItem, title: item.name, subtitle: item.channelName, programDescription: [item.shortDesc, item.extendedDesc].compactMap { $0 }.joined(separator: "\n\n"), program: programInfo)
                                            #if os(macOS)
                                            openWindow(id: "player-window")
                                            #endif
                                        } label: {
                                            Text(verbatim: videoItem.name)
                                            Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                                        }
                                        .disabled(!videoItem.canPlay)
                                    }
                                }
                            }
                        } label: {
                            HStack(alignment: .center) {
                                Image(systemName: "play")
                                    .font(.system(size: 25))
                                Text("Play")
                            }
                        }
                        #if !os(tvOS)
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        #endif
                        
                        #if !os(tvOS)
                        RecordingDownloadMenu(item: item)
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                        #endif

                        #if os(iOS) || os(macOS)
                        if !translatableVideoItems.isEmpty {
                            translateMenu(videoItems: translatableVideoItems)
                        }
                        #endif
                    }
                }
                
                if let shortDesc = item.shortDesc {
                    Divider()
                    Text(LocalizedStringKey(shortDesc))
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let extendedDesc = item.extendedDesc {
                    Divider()
                    Text(LocalizedStringKey(extendedDesc))
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                    .frame(height: 10)
            }
        }
        .navigationTitle(item.name)
        .toolbar {
            if onDelete != nil {
                ToolbarItem(placement: .primaryAction) {
                    if deleteInProgress {
                        ProgressView()
                    } else {
                        #if os(tvOS)
                        // Menu inside a toolbar item doesn't open reliably on tvOS, so use a confirmationDialog instead.
                        Button {
                            showActionMenu = true
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .controlSize(.small)
                        #else
                        Menu {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete recording", systemImage: "trash")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                        #endif
                    }
                }
            }
        }
        #if os(tvOS)
        .confirmationDialog("More", isPresented: $showActionMenu, titleVisibility: .hidden) {
            Button("Delete recording", role: .destructive) {
                showDeleteConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        }
        #endif
        .alert("Delete recording", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: item.name)
        }
        .alert("Delete error", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let deleteError {
                Text(verbatim: deleteError)
            }
        }
        #if os(tvOS)
        // Right after the player's fullScreenCover dismisses, tvOS sometimes fails to
        // recognize this view still has a NavigationStack to pop back into, and routes
        // the Menu button to "exit app" instead. Handle it explicitly so Back always
        // just pops back to the recordings list.
        .onExitCommand {
            dismiss()
        }
        #endif
        #if os(iOS) || os(macOS)
        .task(id: playableLocalVideoItems.map(\.id)) {
            // Encoded downloads can be in any container, while only MPEG-TS files carry ARIB subtitles.
            translatableVideoItems = playableLocalVideoItems.filter { ARIBCaptionExtractor.isTransportStream($0.url) }
        }
        .sheet(item: $translatingVideoItem) { videoItem in
            SubtitleTranslationView(videoURL: videoItem.url, recordingName: item.name, videoName: videoItem.name, program: programInfo)
        }
        #endif
    }

    /// The program information that helps translating the subtitles.
    var programInfo: SubtitleProgramInfo {
        SubtitleProgramInfo(title: item.name, descriptions: [item.shortDesc, item.extendedDesc])
    }

    #if os(iOS) || os(macOS)
    var playableLocalVideoItems: [LocalVideoItem] {
        (item as? LocalRecordedItem)?._videoItems.filter({ $0.canPlay }) ?? []
    }

    func translateMenu(videoItems: [LocalVideoItem]) -> some View {
        Menu {
            ForEach(videoItems) { videoItem in
                Button {
                    translatingVideoItem = videoItem
                } label: {
                    Text(verbatim: videoItem.name)
                    Text(verbatim: ByteCountFormatter().string(fromByteCount: videoItem.fileSize))
                }
            }
        } label: {
            HStack(alignment: .center) {
                Image(systemName: "translate")
                    .font(.system(size: 25))
                Text("Translate")
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
    }
    #endif

    func deleteRecording() {
        deleteInProgress = true
        deleteError = nil
        Task {
            do {
                let response = try await appState.client.api.deleteRecordedRecordedId(
                    path: .init(recordedId: item.epgId)
                )
                switch response {
                case .ok(_):
                    Logger.info("Deleted recording \(item.epgId)")
                    onDelete?()
                    dismiss()
                case .default(let statusCode, let error):
                    let message = try error.body.json.message
                    deleteError = message
                    Logger.error("Failed to delete recording \(item.epgId): \(statusCode) \(message)")
                }
            } catch {
                deleteError = error.localizedDescription
                Logger.error("Failed to delete recording \(item.epgId): \(error)")
            }
            deleteInProgress = false
        }
    }
}

extension Components.Schemas.VideoFile: Identifiable {
    
}
