//
//  LiveChannelsView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/12.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import CachedAsyncImage
import OpenAPIRuntime

struct LiveChannelsView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    @Binding var activeTab: TabSelection
    
    @State var loadingState = LoadingState.loading
    @State var loadingMoreState = LoadingState.loaded
    
    @State var liveStreamConfig: Components.Schemas.Config.StreamConfigPayload.LivePayload.TsPayload? = nil
    @State var schedules: [Components.Schemas.Schedule] = []
    
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State var progressMap: [Components.Schemas.ProgramId : Double] = [:]
    
    @State var timeFormatter = DateFormatter()
    
    var body: some View {
        NavigationStack {
            ClientContentView(activeTab: $activeTab, loadingState: $loadingState) { waitTime in
                refresh(waitTime: waitTime)
            } content: {
                if let liveStreamConfig {
                    #if os(tvOS)
                    let gridItem = GridItem(.adaptive(minimum: 600), spacing: 15)
                    #else
                    let gridItem = GridItem(.adaptive(minimum: 300), spacing: 15)
                    #endif
                    ScrollView {
                        #if os(macOS)
                        Spacer()
                            .frame(height: 10)
                        #endif
                        LazyVGrid(columns: [gridItem], spacing: 15) {
                            ForEach(schedules) { schedule in
                                Menu {
                                    if let m2ts = liveStreamConfig.m2ts?.map({ $0.name }), !m2ts.isEmpty {
                                        LiveStreamSelectionMenu(channel: schedule.channel, format: "m2ts", formatName: "M2TS", selections: m2ts)
                                    }
                                    if let m2tsll = liveStreamConfig.m2tsll, !m2tsll.isEmpty {
                                        LiveStreamSelectionMenu(channel: schedule.channel, format: "m2tsll", formatName: "M2TS-LL", selections: m2tsll)
                                    }
                                    if let webm = liveStreamConfig.webm, !webm.isEmpty {
                                        LiveStreamSelectionMenu(channel: schedule.channel, format: "webm", formatName: "WebM", selections: webm)
                                    }
                                    if let mp4 = liveStreamConfig.mp4, !mp4.isEmpty {
                                        LiveStreamSelectionMenu(channel: schedule.channel, format: "mp4", formatName: "MP4", selections: mp4)
                                    }
                                } label: {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            AsyncImageWithHeaders(url: appState.client.endpoint.appending(path: "channels/\(schedule.channel.id)/logo"), headers: appState.client.headers) { phase in
                                                if let image = phase.image {
                                                    #if DEBUG
                                                    if userSettings.demoMode {
                                                        Image(systemName: "inset.filled.tv")
                                                    } else {
                                                        image
                                                            .resizable()
                                                            .scaledToFit()
                                                    }
                                                    #else
                                                    image
                                                        .resizable()
                                                        .scaledToFit()
                                                    #endif
                                                } else if phase.error != nil {
                                                    Image(systemName: "photo.badge.exclamationmark")
                                                        .foregroundStyle(.placeholder)
                                                } else {
                                                    ProgressView()
                                                }
                                            }
                                            .frame(height: 20)
                                            Text(schedule.channel.name)
                                            Spacer()
                                            Text(schedule.channel.channelType.rawValue.uppercased())
                                                .foregroundStyle(.secondary)
                                        }
                                        if let program = schedule.programs.first {
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
                                            Spacer()
                                            ProgramProgressView(progress: $progressMap[program.id])
                                        } else {
                                            Spacer()
                                        }
                                    }
                                    .padding(.all, 6)
                                    .background(Color("Genre \(schedule.programs.first?.genre1 ?? 16)"))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(2.5, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                                    .shadow(radius: 3)
                                }
                                .id(schedule.channel.id)
                                #if !os(tvOS)
                                .menuStyle(.button)
                                .buttonStyle(.plain)
                                #endif
                                .tint(.primary)
                            }
                        }
                        #if !os(tvOS)
                        .padding(.horizontal)
                        #endif
                    }
                    .refreshable {
                        refresh()
                    }
                    .onReceive(timer) { _ in
                        updateProgress()
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
            .navigationTitle("Live")
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
    
    func updateProgress() {
        let currentTimestamp = Date.now.timeIntervalSince1970 * 1000
        for schedule in schedules {
            guard let program = schedule.programs.first else {
                continue
            }
            let progress = (currentTimestamp - TimeInterval(program.startAt)) / (TimeInterval(program.endAt) - TimeInterval(program.startAt))
            if progress > 1 {
                refresh(timer: true)
                return
            }
            progressMap[program.id] = progress
        }
    }
    
    func refresh(waitTime: Duration = .zero, timer: Bool = false) {
        guard appState.clientState == .initialized else {
            return
        }
        if !timer {
            loadingState = .loading
            timeFormatter.dateFormat = "HH:mm"
            timeFormatter.timeZone = TimeZone(abbreviation: "JST")
        }
        Task {
            do {
                try await Task.sleep(for: waitTime)
                if !timer {
                    guard let liveStreamConfig = try await appState.client.api.getConfig().ok.body.json.streamConfig.live?.ts else {
                        loadingState = .error(Text("Failed to load live stream config"))
                        return
                    }
                    self.liveStreamConfig = liveStreamConfig
                }
                schedules = try await appState.client.api.getSchedulesBroadcasting(query: Operations.GetSchedulesBroadcasting.Input.Query(isHalfWidth: true)).ok.body.json
                updateProgress()
                loadingState = .loaded
                Logger.info("Loaded \(schedules.count) channels")
            } catch let error {
                Logger.error("Failed to load recordings: \(error)")
                if !timer {
                    loadingState = .error(Text(verbatim: error.localizedDescription))
                }
            }
        }
    }
}

extension Components.Schemas.ChannelItem: Identifiable {
    
}

struct ProgramProgressView: View {
    @Binding var progress: TimeInterval?
    
    var body: some View {
        ProgressView(value: progress)
            .progressViewStyle(.linear)
    }
}
