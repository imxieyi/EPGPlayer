//
//  RecordingCell.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import SwiftUI
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
    
    let item: RecordedItem
    
    var body: some View {
        VStack {
            ZStack {
                if let thumbnail = item.thumbnail {
                    CachedAsyncImage(url: thumbnail, urlCache: .imageCache) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFit()
                        } else if phase.error != nil {
                            ZStack(alignment: .top) {
                                Color.clear
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 100))
                                    .foregroundStyle(.placeholder)
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16/9, contentMode: .fit)
                        } else {
                            ZStack(alignment: .center) {
                                Color.clear
                                ProgressView()
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16/9, contentMode: .fit)
                        }
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
                    VStack {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: item.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                if let channelName = item.channelName {
                                    Text(verbatim: channelName)
                                        .font(.caption)
                                }
                                Text(verbatim: item.startTime.formatted(RecordingCell.startDateFormatStyle)
                                     + " ~ "
                                     + item.endTime.formatted(RecordingCell.endDateFormatStyle)
                                     + " (\(Int(item.endTime.timeIntervalSinceReferenceDate - item.startTime.timeIntervalSinceReferenceDate) / 60)分)")
                                    .font(.caption)
                                if let shortDesc = item.shortDesc {
                                    Text(verbatim: shortDesc)
                                        .font(.footnote)
                                        .lineLimit(1)
                                }
                            }
                            .layoutPriority(1)
                            Spacer()
                        }
                    }
                    .padding(.all, 4)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
            .shadow(radius: 3)
        }
    }
}
