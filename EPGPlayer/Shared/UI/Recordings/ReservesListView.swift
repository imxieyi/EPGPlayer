//
//  ReservesListView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/07/02.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct ReservesListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var activeTab: TabSelection

    @State var loadingState = LoadingState.loading
    @State var reserves: [Components.Schemas.ReserveItem] = []
    @State var deleteError: String? = nil
    @State var reserveToDelete: Components.Schemas.ReserveItem? = nil
    @State var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ClientContentView(activeTab: $activeTab, loadingState: $loadingState, refresh: { waitTime in
                refresh(waitTime: waitTime)
            }, content: {
                Group {
                    if reserves.isEmpty {
                        ContentUnavailableView("No reserves found", systemImage: "questionmark.circle")
                    } else {
                        List {
                            ForEach(reserves, id: \.id) { reserve in
                                ReserveCell(reserve: reserve)
                                    #if os(macOS)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            reserveToDelete = reserve
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Cancel reserve", systemImage: "trash")
                                        }
                                    }
                                    #endif
                            }
                            #if os(iOS)
                            .onDelete { indexSet in
                                if let first = indexSet.first {
                                    reserveToDelete = reserves[first]
                                    showDeleteConfirmation = true
                                }
                            }
                            #endif
                        }
                        .listStyle(.plain)
                    }
                }
                .refreshable {
                    refresh()
                }
            })
            #if !os(tvOS)
            .navigationTitle("Reserves")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #endif
            .toolbar {
                ToolbarItem(placement: appState.isOnMac ? .cancellationAction : .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
                #endif
            }
            .alert("Reserve error", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if let deleteError {
                    Text(verbatim: deleteError)
                }
            }
            .alert("Cancel reserve", isPresented: $showDeleteConfirmation) {
                Button("Cancel reserve", role: .destructive) {
                    if let reserve = reserveToDelete {
                        deleteReserve(reserveId: reserve.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let reserve = reserveToDelete {
                    Text(verbatim: reserve.name)
                }
            }
            .onAppear {
                if reserves.isEmpty {
                    refresh()
                }
            }
        }
        #if os(macOS)
        .presentationSizing(.page)
        #endif
    }

    func refresh(waitTime: Duration = .zero) {
        reserves = []
        loadingState = .loading
        Task {
            do {
                try await Task.sleep(for: waitTime)

                // Ensure channelMap is populated for channel name display
                if Components.Schemas.RecordedItem.channelMap.isEmpty {
                    let channels = try await appState.client.api.getChannels().ok.body.json
                    Components.Schemas.RecordedItem.channelMap = channels.reduce(into: [Int: Components.Schemas.ChannelItem]()) { map, item in
                        map[item.id] = item
                    }
                }

                var allReserves: [Components.Schemas.ReserveItem] = []
                var offset = 0
                let limit = 100
                let maxPages = 50
                for _ in 0..<maxPages {
                    let resp = try await appState.client.api.getReserves(
                        query: .init(offset: offset, limit: limit, isHalfWidth: true)
                    ).ok.body.json
                    allReserves.append(contentsOf: resp.reserves)
                    if allReserves.count >= resp.total {
                        break
                    }
                    offset += limit
                }
                reserves = allReserves.sorted { $0.startAt < $1.startAt }
                loadingState = .loaded
                Logger.info("Loaded \(reserves.count) reserves")
            } catch {
                Logger.error("Failed to load reserves: \(error)")
                loadingState = .error(Text(verbatim: error.localizedDescription))
            }
        }
    }

    func deleteReserve(reserveId: Int) {
        Task {
            do {
                let response = try await appState.client.api.deleteReservesReserveId(
                    path: .init(reserveId: reserveId)
                )
                switch response {
                case .ok(_):
                    reserves.removeAll { $0.id == reserveId }
                    Logger.info("Deleted reserve \(reserveId)")
                case .default(let statusCode, let error):
                    let message = try error.body.json.message
                    deleteError = message
                    Logger.error("Failed to delete reserve \(reserveId): \(statusCode) \(message)")
                }
            } catch {
                deleteError = error.localizedDescription
                Logger.error("Failed to delete reserve \(reserveId): \(error)")
            }
        }
    }
}

struct ReserveCell: View {
    let reserve: Components.Schemas.ReserveItem

    var body: some View {
        let startAt = Date(timeIntervalSince1970: TimeInterval(reserve.startAt / 1000))
        let endAt = Date(timeIntervalSince1970: TimeInterval(reserve.endAt / 1000))
        let durationMinutes = (reserve.endAt - reserve.startAt) / 60 / 1000

        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: reserve.name)
                .font(.headline)
                .lineLimit(2)
            Text(verbatim: channelName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: startAt.formatted(RecordingCell.startDateFormatStyle)
                 + " ~ "
                 + endAt.formatted(RecordingCell.endDateFormatStyle)
                 + " (\(durationMinutes)分)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let description = reserve.description {
                Text(verbatim: description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                if reserve.isConflict {
                    Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if reserve.isOverlap {
                    Label("Overlap", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if reserve.isSkip {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if reserve.ruleId != nil {
                    Label("Rule", systemImage: "gearshape")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    var channelName: String {
        Components.Schemas.RecordedItem.channelMap[reserve.channelId]?.name ?? "\(reserve.channelId)"
    }
}
