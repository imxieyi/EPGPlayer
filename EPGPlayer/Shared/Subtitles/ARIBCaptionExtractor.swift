//
//  ARIBCaptionExtractor.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/25.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import LibARIBCaption

/// A caption statement decoded from the ARIB STD-B24 caption stream of an MPEG-TS file.
struct ARIBCaption: Sendable {
    /// Presentation time in milliseconds, relative to the first PCR of the program.
    /// This matches VLC's playback time for a TS file.
    let time: Int
    /// Display duration in milliseconds, or nil if the caption stays until the next one.
    let duration: Int?
    /// Caption text with ruby excluded. Empty for statements that only clear the screen.
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
    private static let packetSize = 188
    private static let syncByte: UInt8 = 0x47
    /// Number of packets in a row that must start with the sync byte before the stream is trusted,
    /// so that other file formats are not mistaken for MPEG-TS by chance.
    private static let packetsToSync = 5
    private static let ptsMask: Int64 = (1 << 33) - 1

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
        let demuxer = CaptionDemuxer()

        var buffer = [UInt8]()
        var bytesRead = 0
        var foundSync = false
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: packetSize * 8192), !chunk.isEmpty else {
                break
            }
            bytesRead += chunk.count
            buffer.append(contentsOf: chunk)

            var offset = 0
            buffer.withUnsafeBufferPointer { bytes in
                while offset + packetSize <= bytes.count {
                    if bytes[offset] != syncByte {
                        // Resynchronize on the next position that looks like a packet boundary.
                        offset += 1
                        continue
                    }
                    if !foundSync {
                        guard offset + packetSize * (packetsToSync - 1) < bytes.count else {
                            break
                        }
                        guard (1..<packetsToSync).allSatisfy({ bytes[offset + packetSize * $0] == syncByte }) else {
                            offset += 1
                            continue
                        }
                        foundSync = true
                    }
                    demuxer.handlePacket(UnsafeBufferPointer(rebasing: bytes[offset..<offset + packetSize]))
                    offset += packetSize
                }
            }
            buffer.removeFirst(offset)
            if !foundSync && bytesRead > packetSize * 8192 * 4 {
                throw ARIBCaptionExtractorError.notTransportStream
            }
            if fileSize > 0 {
                progress(min(Double(bytesRead) / Double(fileSize), 1))
            }
        }
        demuxer.finish()
        guard foundSync else {
            throw ARIBCaptionExtractorError.notTransportStream
        }
        guard demuxer.foundCaptionStream else {
            throw ARIBCaptionExtractorError.noCaptionStream
        }
        return demuxer.captions
    }

    /// Demuxes the first ARIB caption stream of the first program and decodes its PES packets.
    private final class CaptionDemuxer {
        private var pmtPID: Int?
        private var pcrPID: Int?
        private var captionPID: Int?
        private var firstPCR: Int64?

        private var pes = [UInt8]()
        private var pesActive = false

        private let context: OpaquePointer
        private let decoder: OpaquePointer

        private(set) var captions: [ARIBCaption] = []
        var foundCaptionStream: Bool { captionPID != nil }

        init() {
            context = aribcc_context_alloc()
            decoder = aribcc_decoder_alloc(context)
            aribcc_decoder_initialize(decoder, ARIBCC_ENCODING_SCHEME_AUTO, ARIBCC_CAPTIONTYPE_CAPTION, ARIBCC_PROFILE_A, ARIBCC_LANGUAGEID_FIRST)
        }

        deinit {
            aribcc_decoder_free(decoder)
            aribcc_context_free(context)
        }

        func handlePacket(_ packet: UnsafeBufferPointer<UInt8>) {
            let payloadUnitStart = packet[1] & 0x40 != 0
            let pid = Int(packet[1] & 0x1F) << 8 | Int(packet[2])
            let adaptationFieldControl = (packet[3] >> 4) & 0x03
            var payloadOffset = 4
            if adaptationFieldControl & 0x02 != 0 {
                let adaptationLength = Int(packet[4])
                if pid == pcrPID, firstPCR == nil, adaptationLength >= 7, packet[5] & 0x10 != 0 {
                    firstPCR = Int64(packet[6]) << 25 | Int64(packet[7]) << 17 | Int64(packet[8]) << 9 | Int64(packet[9]) << 1 | Int64(packet[10]) >> 7
                }
                payloadOffset += 1 + adaptationLength
            }
            guard adaptationFieldControl & 0x01 != 0, payloadOffset < ARIBCaptionExtractor.packetSize else {
                return
            }
            let payload = UnsafeBufferPointer(rebasing: packet[payloadOffset...])

            if pid == 0 {
                if payloadUnitStart && pmtPID == nil {
                    parsePAT(payload)
                }
            } else if pid == pmtPID {
                if payloadUnitStart && captionPID == nil {
                    parsePMT(payload)
                }
            } else if pid == captionPID {
                guard firstPCR != nil else {
                    return
                }
                if payloadUnitStart {
                    flushPES()
                    pesActive = true
                }
                if pesActive {
                    pes.append(contentsOf: payload)
                }
            }
        }

        func finish() {
            flushPES()
        }

        /// Returns the section body (after the 3-byte section header) up to the CRC, if the section fits in this packet.
        private func section(_ payload: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8>? {
            guard payload.count > 1 else {
                return nil
            }
            let start = 1 + Int(payload[0])
            guard start + 3 <= payload.count else {
                return nil
            }
            let sectionLength = Int(payload[start + 1] & 0x0F) << 8 | Int(payload[start + 2])
            let end = start + 3 + sectionLength - 4
            guard sectionLength >= 4, end <= payload.count else {
                return nil
            }
            return UnsafeBufferPointer(rebasing: payload[(start + 3)..<end])
        }

        private func parsePAT(_ payload: UnsafeBufferPointer<UInt8>) {
            guard let body = section(payload), body.count >= 5 else {
                return
            }
            var offset = 5
            while offset + 4 <= body.count {
                let programNumber = Int(body[offset]) << 8 | Int(body[offset + 1])
                if programNumber != 0 {
                    pmtPID = Int(body[offset + 2] & 0x1F) << 8 | Int(body[offset + 3])
                    return
                }
                offset += 4
            }
        }

        private func parsePMT(_ payload: UnsafeBufferPointer<UInt8>) {
            guard let body = section(payload), body.count >= 9 else {
                return
            }
            pcrPID = Int(body[5] & 0x1F) << 8 | Int(body[6])
            let programInfoLength = Int(body[7] & 0x0F) << 8 | Int(body[8])
            var offset = 9 + programInfoLength
            while offset + 5 <= body.count {
                let streamType = body[offset]
                let pid = Int(body[offset + 1] & 0x1F) << 8 | Int(body[offset + 2])
                let infoLength = Int(body[offset + 3] & 0x0F) << 8 | Int(body[offset + 4])
                let infoEnd = min(offset + 5 + infoLength, body.count)
                var descriptor = offset + 5
                while descriptor + 2 <= infoEnd {
                    let tag = body[descriptor]
                    let length = Int(body[descriptor + 1])
                    // stream_identifier_descriptor with a component tag of an ARIB caption stream
                    if streamType == 0x06, tag == 0x52, length >= 1, descriptor + 2 < infoEnd,
                       (0x30...0x37).contains(body[descriptor + 2]) {
                        captionPID = pid
                        Logger.info("Found ARIB caption stream on PID \(pid)")
                        return
                    }
                    descriptor += 2 + length
                }
                offset = infoEnd
            }
        }

        private func flushPES() {
            defer {
                pes.removeAll(keepingCapacity: true)
                pesActive = false
            }
            guard pesActive, pes.count >= 14, let firstPCR,
                  pes[0] == 0, pes[1] == 0, pes[2] == 1, pes[7] & 0x80 != 0 else {
                return
            }
            let rawPTS = Int64(pes[9] & 0x0E) << 29 | Int64(pes[10]) << 22 | Int64(pes[11] & 0xFE) << 14 | Int64(pes[12]) << 7 | Int64(pes[13]) >> 1
            let relativePTS = (rawPTS - firstPCR) & ARIBCaptionExtractor.ptsMask
            // Timestamps just before the first PCR wrap around to huge values; skip them.
            guard relativePTS < 1 << 32 else {
                return
            }
            let time = Int(relativePTS / 90)
            let payloadOffset = 9 + Int(pes[8])
            guard payloadOffset < pes.count else {
                return
            }

            var caption = aribcc_caption_t()
            let status = pes.withUnsafeBufferPointer { bytes in
                aribcc_decoder_decode(decoder, bytes.baseAddress! + payloadOffset, bytes.count - payloadOffset, Int64(time), &caption)
            }
            guard status == ARIBCC_DECODE_STATUS_GOT_CAPTION else {
                if status == ARIBCC_DECODE_STATUS_ERROR {
                    Logger.warning("Failed to decode ARIB caption at \(time) ms")
                }
                return
            }
            defer {
                aribcc_caption_cleanup(&caption)
            }
            let hasDuration = caption.flags.rawValue & ARIBCC_CAPTIONFLAGS_WAITDURATION.rawValue != 0
                && caption.wait_duration != Int64.max
            let text = caption.text.map { String(cString: $0) } ?? ""
            captions.append(ARIBCaption(time: time, duration: hasDuration ? Int(caption.wait_duration) : nil, text: text))
        }
    }
}
