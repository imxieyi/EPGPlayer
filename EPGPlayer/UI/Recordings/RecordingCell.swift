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
    let localVideo: LocalVideo?
    
    var body: some View {
        VStack {
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
                    VStack {
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
            
            if let localVideo, !localVideo.videoFiles.isEmpty {
                VStack(alignment: .videoTypeNameAlignmentGuide) {
                    ForEach(localVideo.videoFiles) { videoFile in
                        Button {
                        } label: {
                            HStack {
                                Group {
                                    if videoFile._type == .ts {
                                        Text("TS")
                                    } else if videoFile._type == .encoded {
                                        Text("Encoded")
                                    }
                                }
                                .alignmentGuide(.videoTypeNameAlignmentGuide) { context in
                                    context[.leading]
                                }
                                Text(verbatim: videoFile.name)
                                    .alignmentGuide(.videoFileNameAlignmentGuide) { context in
                                        context[.leading]
                                    }
                                Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(videoFile.size)))
                                    .alignmentGuide(.videoFileSizeAlignmentGuide) { context in
                                        context[.leading]
                                    }
                                Spacer()
                                Image(systemName: "play")
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom], 4)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
            }
        }
    }
}

fileprivate extension HorizontalAlignment {
    private struct VideoTypeNameAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.leading]
        }
    }
    static let videoTypeNameAlignmentGuide = HorizontalAlignment(VideoTypeNameAlignment.self)
    
    private struct VideoFileNameAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.leading]
        }
    }
    static let videoFileNameAlignmentGuide = HorizontalAlignment(VideoFileNameAlignment.self)
    
    private struct VideoFileSizeAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.leading]
        }
    }
    static let videoFileSizeAlignmentGuide = HorizontalAlignment(VideoFileSizeAlignment.self)
}
