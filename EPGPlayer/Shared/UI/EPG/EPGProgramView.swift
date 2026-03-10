//
//  EPGProgramView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/07/02.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS)
import EventKit
#endif
import SwiftUI

struct EPGProgramView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings

    let channel: Components.Schemas.ScheduleChannleItem
    let program: Components.Schemas.ScheduleProgramItem

    /// programId -> reserveId mapping, shared with EPGView
    @Binding var reservedPrograms: [Int: Int]

    #if !os(tvOS)
    @Binding var notifier: EPGNotifier
    #endif

    @State var showNotifyPermissionAlert = false
    @State var showEventEditView = false
    @State var reserveInProgress = false
    @State var reserveError: String? = nil
    #if os(iOS)
    @State var event: EKEvent? = nil
    @State var store = EKEventStore()
    #endif
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .center) {
                    let startAt = Date(timeIntervalSince1970: TimeInterval(program.startAt / 1000))
                    let endAt = Date(timeIntervalSince1970: TimeInterval(program.endAt / 1000))
                    Text(verbatim: program.name)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                    Text(verbatim: startAt.formatted(RecordingCell.startDateFormatStyle)
                         + " ~ "
                         + endAt.formatted(RecordingCell.endDateFormatStyle)
                         + " (\((program.endAt - program.startAt) / 60 / 1000)分)")
                    if let genre = program.genre1, let genreStr = EPGGenre[genre],
                       let subGenre = program.subGenre1, let subGenreStr = EPGSubGenre[genre]?[subGenre] {
                        Text(genreStr + " / " + subGenreStr)
                            .font(.subheadline)
                    }
                    if let genre = program.genre2, let genreStr = EPGGenre[genre],
                       let subGenre = program.subGenre2, let subGenreStr = EPGSubGenre[genre]?[subGenre] {
                        Text(genreStr + " / " + subGenreStr)
                            .font(.subheadline)
                    }
                    if let genre = program.genre3, let genreStr = EPGGenre[genre],
                       let subGenre = program.subGenre3, let subGenreStr = EPGSubGenre[genre]?[subGenre] {
                        Text(genreStr + " / " + subGenreStr)
                            .font(.subheadline)
                    }
                    Divider()
                    reserveSection
                    #if !os(tvOS)
                    Divider()
                    HStack {
                        Spacer()
                        if notifier.setProgramIds.contains(String(program.id)) {
                            Button {
                                notifier.removeProgram(program: program)
                            } label: {
                                HStack(alignment: .center) {
                                    Image(systemName: "bell.badge.slash")
                                        .font(.system(size: 25))
                                    Text("Remove notification")
                                }
                            }
                            .tint(.red)
                            .buttonStyle(.borderless)
                        } else {
                            Picker("Notification time", selection: userSettings.$epgNotifyTimeDiff) {
                                Text("Start time")
                                    .tag(TimeInterval(0))
                                ForEach([1, 5, 10, 15, 30, 60], id: \.self) { minutes in
                                    Text("\(minutes) minute ago")
                                        .tag(-60 * TimeInterval(minutes))
                                }
                            }
                            .pickerStyle(.menu)
                            .buttonStyle(.borderless)
                            Button {
                                Task {
                                    if !(await notifier.requestPermission()) {
                                        showNotifyPermissionAlert.toggle()
                                        return
                                    }
                                    await notifier.addProgram(channel: channel, program: program, timeDiff: userSettings.epgNotifyTimeDiff)
                                }
                            } label: {
                                HStack(alignment: .center) {
                                    Image(systemName: "bell.badge")
                                        .font(.system(size: 25))
                                    Text("Add notification")
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tint)
                        }
                        Spacer()
                    }
                    #if os(iOS)
                    Divider()
                    HStack {
                        Spacer()
                            Button {
                                let event = EKEvent(eventStore: store)
                                event.title = program.name
                                event.location = channel.name
                                event.notes = program.description
                                event.startDate = startAt
                                event.endDate = endAt
                                event.timeZone = TimeZone(abbreviation: "JST")
                                self.event = event
                                showEventEditView.toggle()
                            } label: {
                                HStack(alignment: .center) {
                                    Image(systemName: "calendar.badge.plus")
                                        .font(.system(size: 25))
                                    Text("Add to calendar")
                                }
                            }
                            .buttonStyle(.borderless)
                        Spacer()
                    }
                    #endif
                    #endif
                    if let description = program.description {
                        Divider()
                        Text(LocalizedStringKey(description))
                            .multilineTextAlignment(.leading)
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let extended = program.extended {
                        Divider()
                        Text(LocalizedStringKey(extended))
                            .multilineTextAlignment(.leading)
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    if let videoComponentType = program.videoComponentType,
                       let videoComponentTypeStr = EPGVideoComponentType[videoComponentType] {
                        Text(videoComponentTypeStr)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let audioComponentType = program.audioComponentType,
                       let audioComponentTypeStr = EPGAudioComponentType[audioComponentType] {
                        Text(audioComponentTypeStr)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let audioSamplingRate = program.audioSamplingRate?.rawValue,
                       let audioSamplingRateStr = EPGAudioSamplingRate[audioSamplingRate] {
                        Text(audioSamplingRateStr)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(verbatim: program.isFree ? "無料放送" : "有料放送")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            #if !os(tvOS)
            .navigationTitle(channel.name)
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
                ToolbarItem(placement: .principal) {
                    HStack(alignment: .center) {
                        AsyncImageWithHeaders(url: appState.client.endpoint.appending(path: "channels/\(channel.id)/logo"), headers: appState.client.headers) { phase in
                            if let image = phase.image {
                                #if DEBUG
                                if userSettings.demoMode {
                                    Image(systemName: "inset.filled.tv")
                                } else {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                }
                                #else
                                image
                                    .resizable()
                                    .scaledToFit()
                                #endif
                            } else if phase.error != nil {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .foregroundStyle(.placeholder)
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(height: 24)
                        Text(channel.name)
                            .font(.headline)
                    }
                }
            }
            .alert("Reserve error", isPresented: Binding(get: { reserveError != nil }, set: { if !$0 { reserveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if let reserveError {
                    Text(verbatim: reserveError)
                }
            }
            .alert("Notification permission is disabled", isPresented: $showNotifyPermissionAlert) {
                Button {
                    #if os(macOS)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    #else
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    #endif
                } label: {
                    Text("Open Settings")
                }
                Button(role: .cancel) {
                } label: {
                    Text("Close")
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showEventEditView) {
               EventEditView(event: $event, eventStore: store)
            }
            #endif
        }
    }
}

extension EPGProgramView {
    var reserveSection: some View {
        HStack {
            Spacer()
            if reserveInProgress {
                ProgressView()
            } else if let reserveId = reservedPrograms[program.id] {
                Button(role: .destructive) {
                    deleteReserve(reserveId: reserveId)
                } label: {
                    HStack(alignment: .center) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 25))
                        Text("Cancel reserve")
                    }
                }
                .tint(.red)
                .buttonStyle(.borderless)
            } else {
                Button {
                    addReserve()
                } label: {
                    HStack(alignment: .center) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 25))
                        Text("Add reserve")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
            }
            Spacer()
        }
    }

    func addReserve() {
        reserveInProgress = true
        reserveError = nil
        Task {
            do {
                let response = try await appState.client.api.postReserves(
                    body: .json(.init(
                        value1: .init(allowEndLack: true),
                        value2: .init(programId: program.id)
                    ))
                )
                switch response {
                case .created(let created):
                    let reserveId = try created.body.json.reserveId
                    reservedPrograms[program.id] = reserveId
                    Logger.info("Reserved program \(program.id) with reserveId \(reserveId)")
                case .default(let statusCode, let error):
                    let message = try error.body.json.message
                    Logger.error("Failed to reserve program \(program.id): \(statusCode) \(message)")
                    // Refresh reserves - the program may already be reserved by a rule
                    await refreshReservedPrograms()
                    if reservedPrograms[program.id] == nil {
                        reserveError = message
                    }
                }
            } catch {
                reserveError = error.localizedDescription
                Logger.error("Failed to reserve program \(program.id): \(error)")
            }
            reserveInProgress = false
        }
    }

    func refreshReservedPrograms() async {
        do {
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
            var mapping: [Int: Int] = [:]
            for reserve in allReserves {
                if let programId = reserve.programId {
                    mapping[programId] = reserve.id
                }
            }
            reservedPrograms = mapping
        } catch {
            Logger.error("Failed to refresh reserves: \(error)")
        }
    }

    func deleteReserve(reserveId: Int) {
        reserveInProgress = true
        reserveError = nil
        Task {
            do {
                let response = try await appState.client.api.deleteReservesReserveId(
                    path: .init(reserveId: reserveId)
                )
                switch response {
                case .ok(_):
                    reservedPrograms.removeValue(forKey: program.id)
                    Logger.info("Deleted reserve \(reserveId) for program \(program.id)")
                case .default(let statusCode, let error):
                    let message = try error.body.json.message
                    reserveError = message
                    Logger.error("Failed to delete reserve \(reserveId): \(statusCode) \(message)")
                }
            } catch {
                reserveError = error.localizedDescription
                Logger.error("Failed to delete reserve \(reserveId): \(error)")
            }
            reserveInProgress = false
        }
    }
}

struct EPGProgram: Identifiable {
    let channel: Components.Schemas.ScheduleChannleItem
    let program: Components.Schemas.ScheduleProgramItem
    
    var id: Int {
        return channel.id << 32 | program.id
    }
}
