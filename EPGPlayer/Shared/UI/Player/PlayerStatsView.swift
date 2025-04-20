//
//  PlayerStatsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/10.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct PlayerStatsView: View {
    @EnvironmentObject private var playerEvents: PlayerEvents
    
    @State var inputBitrate: Double = 0
    @State var demuxBitrate: Double = 0
    @State var demuxCorrupted: Int = 0
    @State var displayedPictures: Int = 0
    @State var lostPictures: Int = 0
    @State var readBytes: Double = 0
    
    let style = Measurement.FormatStyle.ByteCount(style: .binary,
                                                  allowedUnits: .all,
                                                  spellsOutZero: false,
                                                  includesActualByteCount: false,
                                                  locale: Locale(identifier: "en_US"))
    
    public var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: "Input: \(style.format(Measurement(value: inputBitrate, unit: .bytes)))/s")
            Text(verbatim: "Demux: \(style.format(Measurement(value: demuxBitrate, unit: .bytes)))/s")
            Text(verbatim: "Corrupted: \(demuxCorrupted) packets")
            Text(verbatim: "Dropped: \(lostPictures)/\(displayedPictures + lostPictures)")
            Text(verbatim: "Total read: \(style.format(Measurement(value: readBytes, unit: .bytes)))")
        }
        .font(.caption.monospacedDigit())
        .padding(10)
        .background(.black.opacity(0.7))
        .onReceive(playerEvents.updateStats) { stats in
            inputBitrate = Double(stats.inputBitrate) * 1000 * 1000
            demuxBitrate = Double(stats.demuxBitrate) * 1000 * 1000
            demuxCorrupted = Int(stats.demuxCorrupted)
            displayedPictures = Int(stats.displayedPictures)
            lostPictures = Int(stats.lostPictures)
            readBytes = Double(stats.readBytes)
        }
    }
}
