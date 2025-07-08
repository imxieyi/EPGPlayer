//
//  EPGProgramView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/07/02.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct EPGProgramView: View {
    @Environment(AppState.self) private var appState
    
    let channel: Components.Schemas.ScheduleChannleItem
    let program: Components.Schemas.ScheduleProgramItem
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .center) {
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
                    .frame(height: 32)
                    Text(verbatim: channel.name)
                }
                Text(verbatim: program.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(verbatim: Date(timeIntervalSince1970: TimeInterval(program.startAt / 1000)).formatted(RecordingCell.startDateFormatStyle)
                     + " ~ "
                     + Date(timeIntervalSince1970: TimeInterval(program.endAt / 1000)).formatted(RecordingCell.endDateFormatStyle)
                     + " (\((program.endAt - program.startAt) / 60 / 1000)分)")
                if let description = program.description {
                    Divider()
                    Text(verbatim: description)
                        .multilineTextAlignment(.leading)
                }
                if let extended = program.extended {
                    Divider()
                    Text(verbatim: extended)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}
