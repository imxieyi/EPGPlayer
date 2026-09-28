//
//  SubtitleOverlay.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/28.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import SwiftUI

/// Shows a translation at the bottom of the video. VLC draws the video and the broadcast subtitles,
/// but it can't show text that changes while the stream plays, so the translation is drawn on top of it.
struct SubtitleOverlay: View {
    let text: String?
    /// A problem to show above the text.
    var notice: String? = nil
    /// The top of the player controls in the coordinate space of the player, which the translation stays above,
    /// or nil when the controls are hidden.
    let controlsTop: CGFloat?

    nonisolated static let coordinateSpace = "player"

    var body: some View {
        GeometryReader { geometry in
            let video = Self.videoFrame(in: geometry.size)
            let fontSize = min(max(video.height * 0.05, 13), 44)
            let bottom = controlsTop.map { min(video.maxY - video.height * 0.04, $0 - geometry.frame(in: .named(Self.coordinateSpace)).minY - 8) }
                ?? video.maxY - video.height * 0.04
            VStack(spacing: fontSize * 0.3) {
                if let notice {
                    Text(verbatim: notice)
                        .font(.system(size: max(fontSize * 0.6, 12)))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                if let text {
                    Text(verbatim: text)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, fontSize * 0.35)
                        .padding(.vertical, fontSize * 0.12)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: fontSize * 0.2))
                }
            }
            .frame(maxWidth: video.width * 0.9)
            .frame(width: geometry.size.width, height: max(bottom, 0), alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    /// The frame of a 16:9 video fitted in the player, like VLC draws a broadcast.
    static func videoFrame(in size: CGSize) -> CGRect {
        var width = size.width
        var height = width * 9 / 16
        if height > size.height {
            height = size.height
            width = height * 16 / 9
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}
#endif
