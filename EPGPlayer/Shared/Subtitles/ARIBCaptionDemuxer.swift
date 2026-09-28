//
//  ARIBCaptionDemuxer.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/28.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import LibARIBCaption

/// The first PCR of an MPEG-TS stream, from which the captions are timed, and the PIDs of its program map.
/// Readers that start in the middle of a stream share them with the reader that started at its beginning.
final class ARIBCaptionTimeBase: @unchecked Sendable {
    struct ProgramMap {
        let pmtPID: Int
        let pcrPID: Int
        let captionPID: Int?
    }

    private static let timestampMask: Int64 = (1 << 33) - 1

    private let lock = NSLock()
    private var pcr: Int64?
    private var map: ProgramMap?

    var firstPCR: Int64? {
        get {
            lock.withLock { pcr }
        }
        set {
            lock.withLock { pcr = newValue }
        }
    }

    var programMap: ProgramMap? {
        get {
            lock.withLock { map }
        }
        set {
            lock.withLock { map = newValue }
        }
    }

    /// Returns the time of a PCR or PTS in milliseconds from the first PCR, if that is known.
    func time(of timestamp: Int64) -> Int? {
        guard let firstPCR else {
            return nil
        }
        let relative = (timestamp - firstPCR) & Self.timestampMask
        // Timestamps just before the first PCR wrap around to huge values.
        guard relative < 1 << 32 else {
            return nil
        }
        return Int(relative / 90)
    }
}

/// Reads the MPEG-TS packets of a byte stream, demuxes the first ARIB caption stream of the first program
/// and decodes its PES packets with libaribcaption.
final class ARIBCaptionDemuxer {
    static let packetSize = 188
    private static let syncByte: UInt8 = 0x47
    /// Number of packets in a row that must start with the sync byte before the stream is trusted,
    /// so that other file formats are not mistaken for MPEG-TS by chance.
    static let packetsToSync = 5

    /// Called with each decoded caption, in stream order.
    var onCaption: ((ARIBCaption) -> Void)?

    /// Whether the packets of the stream have been found.
    private(set) var foundSync = false
    /// Whether the program map of the stream has been read, which tells whether it has a caption stream.
    private(set) var foundProgramMap = false
    var foundCaptionStream: Bool { captionPID != nil }

    private let timeBase: ARIBCaptionTimeBase
    /// Whether this reader starts at the beginning of the stream and sets the time base from its first PCR.
    let setsTimeBase: Bool
    /// The first PCR that this reader has read.
    private(set) var firstPCR: Int64?

    private var buffer = [UInt8]()

    private var pmtPID: Int?
    private var pcrPID: Int?
    private var captionPID: Int?
    /// The start of the PAT or PMT section on each PID, which may continue in the following packets.
    /// The PMT of a broadcast with many data components, such as NHK, doesn't fit in one packet.
    private var sections = [Int: [UInt8]]()

    private var pes = [UInt8]()
    private var pesActive = false

    private let context: OpaquePointer
    private let decoder: OpaquePointer

    init(timeBase: ARIBCaptionTimeBase = ARIBCaptionTimeBase(), setsTimeBase: Bool = true) {
        self.timeBase = timeBase
        self.setsTimeBase = setsTimeBase
        // A reader from the middle of the stream reads the PCR and captions from its first packets,
        // instead of waiting for the next program map, like VLC after a seek.
        if !setsTimeBase, let programMap = timeBase.programMap {
            pmtPID = programMap.pmtPID
            pcrPID = programMap.pcrPID
            captionPID = programMap.captionPID
            foundProgramMap = true
        }
        context = aribcc_context_alloc()
        decoder = aribcc_decoder_alloc(context)
        aribcc_decoder_initialize(decoder, ARIBCC_ENCODING_SCHEME_AUTO, ARIBCC_CAPTIONTYPE_CAPTION, ARIBCC_PROFILE_A, ARIBCC_LANGUAGEID_FIRST)
    }

    deinit {
        aribcc_decoder_free(decoder)
        aribcc_context_free(context)
    }

    /// Reads the next bytes of the stream. A packet that is split between two calls is kept until the rest arrives.
    func feed(_ data: Data) {
        buffer.append(contentsOf: data)
        var offset = 0
        buffer.withUnsafeBufferPointer { bytes in
            while offset + Self.packetSize <= bytes.count {
                if bytes[offset] != Self.syncByte {
                    // Resynchronize on the next position that looks like a packet boundary.
                    offset += 1
                    continue
                }
                if !foundSync {
                    guard offset + Self.packetSize * (Self.packetsToSync - 1) < bytes.count else {
                        break
                    }
                    guard (1..<Self.packetsToSync).allSatisfy({ bytes[offset + Self.packetSize * $0] == Self.syncByte }) else {
                        offset += 1
                        continue
                    }
                    foundSync = true
                }
                handlePacket(UnsafeBufferPointer(rebasing: bytes[offset..<offset + Self.packetSize]))
                offset += Self.packetSize
            }
        }
        buffer.removeFirst(offset)
    }

    /// Decodes the caption that is still being collected at the end of the stream.
    func finish() {
        flushPES()
    }

    private func handlePacket(_ packet: UnsafeBufferPointer<UInt8>) {
        let payloadUnitStart = packet[1] & 0x40 != 0
        let pid = Int(packet[1] & 0x1F) << 8 | Int(packet[2])
        let adaptationFieldControl = (packet[3] >> 4) & 0x03
        var payloadOffset = 4
        if adaptationFieldControl & 0x02 != 0 {
            let adaptationLength = Int(packet[4])
            if pid == pcrPID, firstPCR == nil, adaptationLength >= 7, packet[5] & 0x10 != 0 {
                let pcr = Int64(packet[6]) << 25 | Int64(packet[7]) << 17 | Int64(packet[8]) << 9 | Int64(packet[9]) << 1 | Int64(packet[10]) >> 7
                firstPCR = pcr
                if setsTimeBase {
                    timeBase.firstPCR = pcr
                }
            }
            payloadOffset += 1 + adaptationLength
        }
        guard adaptationFieldControl & 0x01 != 0, payloadOffset < Self.packetSize else {
            return
        }
        let payload = UnsafeBufferPointer(rebasing: packet[payloadOffset...])

        if pid == 0 {
            if pmtPID == nil, let body = section(pid: pid, payload: payload, payloadUnitStart: payloadUnitStart) {
                parsePAT(body)
            }
        } else if pid == pmtPID {
            if captionPID == nil, let body = section(pid: pid, payload: payload, payloadUnitStart: payloadUnitStart) {
                parsePMT(body)
            }
        } else if pid == captionPID {
            guard timeBase.firstPCR != nil else {
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

    /// Collects the section on a PID and returns its body (after the 3-byte section header) up to the CRC
    /// once all of its packets have arrived.
    private func section(pid: Int, payload: UnsafeBufferPointer<UInt8>, payloadUnitStart: Bool) -> [UInt8]? {
        guard payloadUnitStart else {
            guard sections[pid] != nil else {
                return nil
            }
            sections[pid]!.append(contentsOf: payload)
            return completedSection(pid: pid)
        }
        let start = 1 + Int(payload[0])
        if sections[pid] != nil, start > 1 {
            // The bytes before the pointer finish the section of the previous packets. The section that starts
            // after them is dropped, since the tables repeat.
            sections[pid]!.append(contentsOf: payload[1..<min(start, payload.count)])
            if let body = completedSection(pid: pid) {
                return body
            }
        }
        guard start < payload.count else {
            sections[pid] = nil
            return nil
        }
        sections[pid] = Array(payload[start...])
        return completedSection(pid: pid)
    }

    private func completedSection(pid: Int) -> [UInt8]? {
        guard let bytes = sections[pid], bytes.count >= 3 else {
            return nil
        }
        let sectionLength = Int(bytes[1] & 0x0F) << 8 | Int(bytes[2])
        guard sectionLength >= 4, sectionLength <= 1021 else {
            sections[pid] = nil
            return nil
        }
        guard bytes.count >= 3 + sectionLength else {
            return nil
        }
        sections[pid] = nil
        return Array(bytes[3..<(3 + sectionLength - 4)])
    }

    private func parsePAT(_ body: [UInt8]) {
        guard body.count >= 5 else {
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

    private func parsePMT(_ body: [UInt8]) {
        guard body.count >= 9 else {
            return
        }
        let pcrPID = Int(body[5] & 0x1F) << 8 | Int(body[6])
        self.pcrPID = pcrPID
        foundProgramMap = true
        defer {
            if setsTimeBase, let pmtPID {
                timeBase.programMap = ARIBCaptionTimeBase.ProgramMap(pmtPID: pmtPID, pcrPID: pcrPID, captionPID: captionPID)
            }
        }
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
        guard pesActive, pes.count >= 14, pes[0] == 0, pes[1] == 0, pes[2] == 1, pes[7] & 0x80 != 0 else {
            return
        }
        let rawPTS = Int64(pes[9] & 0x0E) << 29 | Int64(pes[10]) << 22 | Int64(pes[11] & 0xFE) << 14 | Int64(pes[12]) << 7 | Int64(pes[13]) >> 1
        guard let time = timeBase.time(of: rawPTS) else {
            return
        }
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
        onCaption?(ARIBCaption(time: time, duration: hasDuration ? Int(caption.wait_duration) : nil, text: Self.text(of: caption)))
    }

    /// Returns the text of a caption without ruby, with the words of each speaker on a separate line.
    /// The text that libaribcaption provides only breaks lines on APR, but broadcasters usually place each row
    /// with APS, which glues the lines of different speakers together. Speakers are told apart by the text color,
    /// so a row in the same color continues the sentence of the previous one.
    private static func text(of caption: aribcc_caption_t) -> String {
        var lines: [String] = []
        var lineColor: aribcc_color_t?
        for regionIndex in 0..<Int(caption.region_count) {
            let region = caption.regions[regionIndex]
            guard !region.is_ruby else {
                continue
            }
            for charIndex in 0..<Int(region.char_count) {
                let char = region.chars[charIndex]
                // Like libaribcaption's text, show a geta mark for a DRCS character without alternative text.
                let string = char.type == ARIBCC_CHARTYPE_DRCS ? "〓" : withUnsafeBytes(of: char.u8str) { bytes in
                    String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
                }
                // Spaces between the lines of two speakers may have either color.
                if !string.allSatisfy(\.isWhitespace), char.text_color != lineColor {
                    lines.append("")
                    lineColor = char.text_color
                }
                if lines.isEmpty {
                    lines.append("")
                }
                lines[lines.count - 1] += string
            }
        }
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
