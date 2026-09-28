//
//  ARIBCaptionExtractor.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/25.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation

/// A caption statement decoded from the ARIB STD-B24 caption stream of an MPEG-TS file.
struct ARIBCaption: Sendable {
    /// Presentation time in milliseconds, relative to the first PCR of the program.
    /// This matches VLC's playback time for a TS file.
    let time: Int
    /// Display duration in milliseconds, or nil if the caption stays until the next one.
    let duration: Int?
    /// Caption text with ruby excluded and the words of each speaker on a separate line.
    /// Empty for statements that only clear the screen.
    let text: String
}

enum ARIBCaptionExtractorError: LocalizedError {
    case notTransportStream
    case noCaptionStream

    var errorDescription: String? {
        switch self {
        case .notTransportStream:
            return String(localized: "The video file is not an MPEG-TS file.")
        case .noCaptionStream:
            return String(localized: "The video file has no ARIB subtitles.")
        }
    }
}

/// Extracts all ARIB captions from a local MPEG-TS file by demuxing the caption PES packets
/// and decoding them with libaribcaption.
enum ARIBCaptionExtractor {
    private static let packetSize = ARIBCaptionDemuxer.packetSize
    private static let syncByte: UInt8 = 0x47
    private static let packetsToSync = ARIBCaptionDemuxer.packetsToSync

    /// Checks whether a file starts like an MPEG-TS stream, the only container that carries ARIB captions.
    static func isTransportStream(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer {
            try? handle.close()
        }
        guard let head = try? handle.read(upToCount: packetSize * packetsToSync), head.count == packetSize * packetsToSync else {
            return false
        }
        return (0..<packetsToSync).allSatisfy { head[head.startIndex + packetSize * $0] == syncByte }
    }

    /// Reads the whole file and returns its captions in presentation order.
    /// Blocks the calling thread, so call it off the main actor. Checks for task cancellation between reads.
    static func extract(from url: URL, progress: (Double) -> Void) throws -> [ARIBCaption] {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let demuxer = ARIBCaptionDemuxer()
        var captions: [ARIBCaption] = []
        demuxer.onCaption = { captions.append($0) }

        var bytesRead = 0
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: packetSize * 8192), !chunk.isEmpty else {
                break
            }
            bytesRead += chunk.count
            demuxer.feed(chunk)
            if !demuxer.foundSync && bytesRead > packetSize * 8192 * 4 {
                throw ARIBCaptionExtractorError.notTransportStream
            }
            if fileSize > 0 {
                progress(min(Double(bytesRead) / Double(fileSize), 1))
            }
        }
        demuxer.finish()
        guard demuxer.foundSync else {
            throw ARIBCaptionExtractorError.notTransportStream
        }
        guard demuxer.foundCaptionStream else {
            throw ARIBCaptionExtractorError.noCaptionStream
        }
        return captions
    }
}
