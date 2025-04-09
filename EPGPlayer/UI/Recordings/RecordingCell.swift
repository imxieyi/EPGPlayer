//
//  RecordingCell.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import SwiftUI
import OpenAPIRuntime
import CachedAsyncImage

struct RecordingCell: View {
    @Environment(AppState.self) private var appState
    
    static let startDateFormatStyle = Date.FormatStyle(
        date: .abbreviated,
        time: .shortened,
        locale: Locale(identifier: "ja_JP"),
        calendar: Calendar(identifier: .japanese),
        timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        .year(.omitted)
        .month(.twoDigits)
        .day(.twoDigits)
        .weekday(.abbreviated)
    
    static let endDateFormatStyle = Date.FormatStyle(
        date: .omitted,
        time: .shortened,
        locale: Locale(identifier: "ja_JP"),
        calendar: Calendar(identifier: .japanese),
        timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    
    let item: Components.Schemas.RecordedItem
    
    var body: some View {
        ZStack {
            if let thumbnailId = item.thumbnails?.first {
                CachedAsyncImage(url: appState.client.endpoint.appending(path: "thumbnails/\(thumbnailId)"), urlCache: .imageCache) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ZStack(alignment: .center) {
                        Color.clear
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fit)
                }
            } else {
                ZStack(alignment: .center) {
                    Color.clear
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.placeholder)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16/9, contentMode: .fit)
            }
            VStack(alignment: .leading) {
                Spacer()
                HStack {
                    VStack(alignment: .leading) {
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
                    .layoutPriority(1)
                    Spacer()
                }
                .padding(.all, 4)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
        .shadow(radius: 3)
    }
}
