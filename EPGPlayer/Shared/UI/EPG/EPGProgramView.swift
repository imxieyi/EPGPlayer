//
//  EPGProgramView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/07/02.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct EPGProgramView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    
    let channel: Components.Schemas.ScheduleChannleItem
    let program: Components.Schemas.ScheduleProgramItem
    
    #if !os(tvOS)
    @Binding var notifier: EPGNotifier
    #endif
    
    @State var showNotifyPermissionAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .center) {
                    Text(verbatim: program.name)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                    Text(verbatim: Date(timeIntervalSince1970: TimeInterval(program.startAt / 1000)).formatted(RecordingCell.startDateFormatStyle)
                         + " ~ "
                         + Date(timeIntervalSince1970: TimeInterval(program.endAt / 1000)).formatted(RecordingCell.endDateFormatStyle)
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
                    #if !os(tvOS)
                    Divider()
                    HStack {
                        Spacer()
                        if notifier.setProgramIds.contains(String(program.id)) {
                            Button {
                                notifier.removeProgram(program: program)
                            } label: {
                                HStack(alignment: .center) {
                                    Image(systemName: "calendar.badge.minus")
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
                                    Image(systemName: "calendar.badge.plus")
                                        .font(.system(size: 25))
                                    Text("Add notification")
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                    }
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
                                image
                                    .resizable()
                                    .scaledToFit()
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
