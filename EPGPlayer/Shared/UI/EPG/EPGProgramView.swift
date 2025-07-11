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
    
    let channel: Components.Schemas.ScheduleChannleItem
    let program: Components.Schemas.ScheduleProgramItem
    
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
                    if let description = program.description {
                        Divider()
                        Text(verbatim: description)
                            .multilineTextAlignment(.leading)
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let extended = program.extended {
                        Divider()
                        Text(verbatim: extended)
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
