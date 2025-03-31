//
//  RecordingCell.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import SwiftUI
import OpenAPIRuntime

struct RecordingCell: View {
    @Environment(AppState.self) private var appState
    
    static private let startDateFormatStyle = Date.FormatStyle(
        date: .abbreviated,
        time: .shortened,
        locale: Locale(identifier: "ja_JP"),
        calendar: Calendar(identifier: .japanese),
        timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        .year(.omitted)
        .month(.twoDigits)
        .day(.twoDigits)
        .weekday(.abbreviated)
    
    static private let endDateFormatStyle = Date.FormatStyle(
        date: .omitted,
        time: .shortened,
        locale: Locale(identifier: "ja_JP"),
        calendar: Calendar(identifier: .japanese),
        timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    
    let item: Components.Schemas.RecordedItem
    
    var body: some View {
        VStack(alignment: .leading) {
            if let thumbnailId = item.thumbnails?.first {
                AsyncImage(url: appState.client.endpoint.appending(path: "thumbnails/\(thumbnailId)")) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }

            }
            Text(verbatim: item.name)
                .font(.headline)
                .lineLimit(1)
            if let channelId = item.channelId {
                Text(verbatim: appState.channelMap[channelId]?.name ?? "\(channelId)")
                    .font(.caption)
            }
            Text(verbatim: Date(timeIntervalSince1970: TimeInterval(item.startAt) / 1000).formatted(RecordingCell.startDateFormatStyle)
                 + " ~ "
                 + Date(timeIntervalSince1970: TimeInterval(item.endAt) / 1000).formatted(RecordingCell.endDateFormatStyle)
                 + " (\((item.endAt - item.startAt) / 60000)分)")
                .font(.caption)
            if let description = item.description {
                Text(verbatim: description)
                    .font(.footnote)
                    .lineLimit(1)
            }
        }
    }
}
