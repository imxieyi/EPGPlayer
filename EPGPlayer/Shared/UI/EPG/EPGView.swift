//
//  EPGView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/07/01.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import OpenAPIRuntime

struct EPGView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    @Binding var activeTab: TabSelection
    
    @State var loadingState = LoadingState.loading
    @State var loadingMoreState = LoadingState.loaded
    
    @State var timeFormatter = DateFormatter()
    
    @State var liveStreamConfig: Components.Schemas.Config.StreamConfigPayload.LivePayload.TsPayload? = nil
    @State var schedules: Components.Schemas.Schedules = []
    @State var hourRulers: [String] = []
    @State var startAt: CGFloat = 0
    @State var endAt: CGFloat = 0
    @State var channelWidth: CGFloat = 200
    @State var heightOneDay: CGFloat = 5000
    
    var body: some View {
        NavigationStack {
            ClientContentView(activeTab: $activeTab, loadingState: $loadingState) { waitTime in
                refresh(waitTime: waitTime)
            } content: {
                if let liveStreamConfig {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .bottom, spacing: 0) {
                                ForEach(schedules) { schedule in
                                    Text(schedule.channel.name)
                                        .font(.headline)
                                        .frame(width: channelWidth)
                                }
                            }
                            Divider()
                            HStack(alignment: .top, spacing: 0) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(0..<hourRulers.count, id: \.self) { index in
                                        VStack {
                                            Text(verbatim: hourRulers[index])
                                                .font(.system(.headline, design: .monospaced))
                                            Spacer()
                                            Divider()
                                        }
                                        .frame(height: heightOneDay / 24)
                                    }
                                }
                                Divider()
                                ForEach(schedules) { schedule in
                                    ZStack {
                                        Spacer()
                                            .frame(width: channelWidth, height: heightOneDay)
                                        ForEach(schedule.programs) { program in
                                            let programStartAt = max(startAt, CGFloat(program.startAt))
                                            let programEndAt = min(endAt, CGFloat(program.endAt))
                                            if programStartAt < programEndAt {
                                                ZStack(alignment: .topLeading) {
                                                    VStack(alignment: .leading) {
                                                        Text(verbatim: program.name)
                                                            .multilineTextAlignment(.leading)
                                                            .layoutPriority(3)
                                                        Text(verbatim: timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(program.startAt / 1000))) + " - " + timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(program.endAt / 1000))))
                                                            .font(.caption)
                                                            .layoutPriority(2)
                                                        if let description = program.description {
                                                            Text(verbatim: description)
                                                                .font(.caption2)
                                                                .multilineTextAlignment(.leading)
                                                                .layoutPriority(1)
                                                        }
                                                    }
                                                    .frame(minWidth: channelWidth - 2, idealWidth: channelWidth - 2, maxWidth: channelWidth - 2, minHeight: 0, idealHeight: heightOneDay / (24 * 3600 * 1000) * (programEndAt - programStartAt), maxHeight: .infinity, alignment: .topLeading)
                                                }
                                                .background {
                                                    Color("Genre \(program.genre1 ?? 16)")
                                                        .padding(.all, 1)
                                                        .frame(width: channelWidth, height: heightOneDay / (24 * 3600 * 1000) * (programEndAt - programStartAt))
                                                }
                                                .padding(.all, 1)
                                                .fixedSize()
                                                .frame(width: channelWidth, height: heightOneDay / (24 * 3600 * 1000) * (programEndAt - programStartAt))
                                                .clipped()
                                                .position(x: channelWidth / 2, y: heightOneDay / (24 * 3600 * 1000) * ((programEndAt + programStartAt) / 2 - startAt))
                                            }
                                        }
                                    }
                                    .frame(width: channelWidth, height: heightOneDay)
                                }
                                Spacer()
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Failed to load live stream config", systemImage: "exclamationmark.triangle")
                }
            }
            #if os(macOS)
            .toolbar(content: {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            })
            #endif
            #if !os(tvOS)
            .navigationTitle("EPG")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #endif
        }
        .onAppear {
            if schedules.isEmpty || liveStreamConfig == nil {
                refresh()
            }
        }
    }
    
    func refresh(waitTime: Duration = .zero) {
        guard appState.clientState == .initialized else {
            return
        }
        schedules = []
        loadingState = .loading
        Task {
            do {
                try await Task.sleep(for: waitTime)
                guard let liveStreamConfig = try await appState.client.api.getConfig().ok.body.json.streamConfig.live?.ts else {
                    loadingState = .error(Text("Failed to load live stream config"))
                    return
                }
                self.liveStreamConfig = liveStreamConfig
                let startAt = Int(Date().timeIntervalSince1970) / 3600 * 3600 * 1000 // Round down to the nearest hour
                let endAt = startAt + (24 * 3600 * 1000) // 24 hours later
                let schedules = try await appState.client.api.getSchedules(query: Operations.GetSchedules.Input.Query(startAt: startAt, endAt: endAt, isHalfWidth: true, gr: true, bs: true, cs: true, sky: true)).ok.body.json
                self.schedules = schedules
                self.startAt = CGFloat(startAt)
                self.endAt = CGFloat(endAt)
                hourRulers = []
                let hourFormatter = DateFormatter()
                hourFormatter.dateFormat = "HH"
                hourFormatter.timeZone = TimeZone(abbreviation: "JST")
                for ts in stride(from: startAt, to: endAt, by: 3600 * 1000) {
                    let date = Date(timeIntervalSince1970: TimeInterval(ts / 1000))
                    hourRulers.append(hourFormatter.string(from: date))
                }
                timeFormatter.dateFormat = "HH:mm"
                timeFormatter.timeZone = TimeZone(abbreviation: "JST")
                loadingState = .loaded
                Logger.info("Loaded \(schedules.count) channels")
            } catch let error {
                Logger.error("Failed to load recordings: \(error)")
                loadingState = .error(Text(verbatim: error.localizedDescription))
            }
        }
    }
}

extension Components.Schemas.Schedule: Identifiable {
    var id: Int { channel.id }
}

extension Components.Schemas.ScheduleProgramItem: Identifiable {
}
