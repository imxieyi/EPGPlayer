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
    
    @State var schedules: Components.Schemas.Schedules = []
    @State var hourRulers: [String] = []
    @State var startAt: CGFloat = 0
    @State var endAt: CGFloat = 0
    @State var channelWidth: CGFloat = 200
    @State var heightOneDay: CGFloat = 5000
    @State var borderWidth: CGFloat = 20
    @State var viewSize = CGSize.zero
    @State var safeAreaInsets = EdgeInsets()
    @State var scrollOffset = CGPoint.zero
    // Preload the cell before appearing
    @State var preloadBuffer: CGFloat = 50
    
    let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    @State var nowPosition: CGFloat = 0
    
    @State var selectedProgram: EPGProgram? = nil
    
    var body: some View {
        NavigationStack {
            ClientContentView(activeTab: $activeTab, loadingState: $loadingState) { waitTime in
                refresh(waitTime: waitTime)
            } content: {
                if !schedules.isEmpty {
                    GeometryReader { outerProxy in
                        ScrollView([.horizontal, .vertical]) {
                            ZStack(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Spacer()
                                        .frame(height: borderWidth)
                                    HStack(alignment: .top, spacing: 0) {
                                        Spacer()
                                            .frame(width: borderWidth)
                                        epgGrid
                                    }
                                }
                                Color.red
                                    .frame(width: channelWidth * CGFloat(schedules.count), height: 2)
                                    .position(x: borderWidth + channelWidth * CGFloat(schedules.count) / 2, y: borderWidth + nowPosition)
                                hourRuler
                                    .background(.regularMaterial)
                                    .offset(x: -scrollOffset.x)
                                channelHeader
                                    .background(.regularMaterial)
                                    .offset(y: -scrollOffset.y)
                            }
                            .frame(width: borderWidth + channelWidth * CGFloat(schedules.count), height: borderWidth + heightOneDay * (endAt - startAt) / (24 * 3600 * 1000))
                            .background(GeometryReader { (proxy: GeometryProxy) -> Color in
                                viewSize = outerProxy.size
                                safeAreaInsets = outerProxy.safeAreaInsets
                                scrollOffset = proxy.frame(in: .named("outer")).origin
                                return Color.clear
                            })
                        }
                        .refreshable {
                            refresh()
                        }
                        .onReceive(timer) { _ in
                            updateNowPosition()
                        }
                    }
                } else {
                    ContentUnavailableView("No schedule available", systemImage: "exclamationmark.triangle")
                }
            }
            .coordinateSpace(name: "outer")
            .toolbar(content: {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                #endif
            })
            #if !os(tvOS)
            .navigationTitle("EPG")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #endif
            .sheet(item: $selectedProgram) { program in
                EPGProgramView(channel: program.channel, program: program.program)
                    #if os(macOS)
                    .presentationSizing(.page)
                    #endif
            }
        }
        .onAppear {
            if schedules.isEmpty {
                refresh()
            }
        }
    }
    
    var channelHeader: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer()
                .frame(width: borderWidth)
            ForEach(schedules) { schedule in
                Text(schedule.channel.name)
                    .font(.headline)
                    .frame(width: channelWidth)
            }
        }
        .frame(height: borderWidth)
    }
    
    var hourRuler: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Spacer()
                .frame(height: borderWidth)
            ForEach(0..<hourRulers.count, id: \.self) { index in
                VStack {
                    Text(verbatim: hourRulers[index])
                        .font(.system(.headline, design: .monospaced))
                    Spacer()
                }
                .frame(height: heightOneDay / 24)
            }
        }
        .frame(width: borderWidth)
    }
    
    var epgGrid: some View {
        ForEach(0..<schedules.count, id: \.self) { index in
            let channelX = channelWidth * (CGFloat(index) + 0.5)
            if !(channelX - channelWidth / 2 > viewSize.width - scrollOffset.x + safeAreaInsets.trailing + preloadBuffer // Cell left > View right
                 || channelX + channelWidth / 2 < -scrollOffset.x - safeAreaInsets.leading - preloadBuffer // Cell right < View left
            ) {
                ZStack {
                    ForEach(schedules[index].programs) { program in
                        let programStartAt = max(startAt, CGFloat(program.startAt))
                        let programEndAt = min(endAt, CGFloat(program.endAt))
                        let channelHeight = heightOneDay / (24 * 3600 * 1000) * (programEndAt - programStartAt)
                        let channelY = heightOneDay / (24 * 3600 * 1000) * ((programEndAt + programStartAt) / 2 - startAt)
                        if programStartAt < programEndAt && !(
                            channelY - channelHeight / 2 > viewSize.height - scrollOffset.y + safeAreaInsets.bottom + preloadBuffer // Cell top > View bottom
                            || channelY + channelHeight / 2 < -scrollOffset.y - safeAreaInsets.top - preloadBuffer // Cell bottom < View top
                        ) {
                            Button {
                                selectedProgram = EPGProgram(channel: schedules[index].channel, program: program)
                            } label: {
                                ZStack(alignment: .topLeading) {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: program.name)
                                            .font(.headline)
                                            .multilineTextAlignment(.leading)
                                            .layoutPriority(3)
                                        Text(verbatim: timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(program.startAt / 1000))) + " ~ " + timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(program.endAt / 1000))))
                                            .font(.caption)
                                            .layoutPriority(2)
                                        if let description = program.description {
                                            Text(verbatim: description)
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
                            }
                            #if os(macOS) || os(tvOS)
                            .buttonStyle(.borderless)
                            #endif
                            .tint(.primary)
                            .padding(.all, 0.5)
                            .fixedSize()
                            .frame(width: channelWidth, height: heightOneDay / (24 * 3600 * 1000) * (programEndAt - programStartAt))
                            .clipped()
                            .position(x: channelWidth / 2, y: channelY)
                        }
                    }
                }
                .frame(width: channelWidth, height: heightOneDay * (endAt - startAt) / (24 * 3600 * 1000))
            } else {
                Spacer()
                    .frame(width: channelWidth, height: heightOneDay * (endAt - startAt) / (24 * 3600 * 1000))
            }
        }
    }
    
    func updateNowPosition() {
        nowPosition = (CGFloat(Date.now.timeIntervalSince1970 * 1000) - startAt) / (24 * 3600 * 1000) * heightOneDay
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
                let startAt = Int(Date().timeIntervalSince1970) / 3600 * 3600 * 1000 // Round down to the nearest hour
                let endAt = startAt + (24 * 3600 * 1000) // 24 hours later
                let schedules = try await appState.client.api.getSchedules(query: Operations.GetSchedules.Input.Query(startAt: startAt, endAt: endAt, isHalfWidth: true, gr: true, bs: true, cs: true, sky: false)).ok.body.json
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
                updateNowPosition()
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
