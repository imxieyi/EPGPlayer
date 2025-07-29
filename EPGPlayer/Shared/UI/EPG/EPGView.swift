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
    
    @State var showSettings = false
    @State var startDates: [Date] = []
    @State var startDate = Date(timeIntervalSince1970: 0)
    @State var startHour: Int = -1
    @State var enableGenre: [Bool] = []
    
    #if !os(tvOS)
    @State var notifier = EPGNotifier()
    #endif
    
    static let startDateFormatStyle = Date.FormatStyle(
        date: .abbreviated,
        time: .omitted,
        locale: Locale(identifier: "ja_JP"),
        calendar: Calendar(identifier: .japanese),
        timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        .year(.omitted)
        .month(.twoDigits)
        .day(.twoDigits)
        .weekday(.abbreviated)
    
    var body: some View {
        NavigationStack {
            ClientContentView(activeTab: $activeTab, loadingState: $loadingState) { waitTime in
                refresh(waitTime: waitTime, manual: false)
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
                            refresh(manual: false)
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
                        refresh(manual: false)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings.toggle()
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            })
            #if !os(tvOS)
            .navigationTitle("EPG")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #endif
            .sheet(item: $selectedProgram) { program in
                #if !os(tvOS)
                EPGProgramView(channel: program.channel, program: program.program, notifier: $notifier)
                    #if os(macOS)
                    .presentationSizing(.page)
                    #endif
                #else
                EPGProgramView(channel: program.channel, program: program.program)
                #endif
            }
            .sheet(isPresented: $showSettings) {
                settings
            }
        }
        .onAppear {
            if schedules.isEmpty {
                refresh(manual: false)
            }
            #if !os(tvOS)
            Task {
                await notifier.updateSetProgramIds()
            }
            #endif
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
                        if enableGenre[program.genre1 ?? 0xf] {
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
                                            #if !os(tvOS)
                                            .border(notifier.setProgramIds.contains(String(program.id)) ? Color.red : Color.clear, width: 3)
                                            #endif
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
                }
                .frame(width: channelWidth, height: heightOneDay * (endAt - startAt) / (24 * 3600 * 1000))
            } else {
                Spacer()
                    .frame(width: channelWidth, height: heightOneDay * (endAt - startAt) / (24 * 3600 * 1000))
            }
        }
    }
    
    var settings: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: userSettings.$epgShowGR) {
                        Text(verbatim: "GR")
                    }
                    Toggle(isOn: userSettings.$epgShowBS) {
                        Text(verbatim: "BS")
                    }
                    Toggle(isOn: userSettings.$epgShowCS) {
                        Text(verbatim: "CS")
                    }
                    Toggle(isOn: userSettings.$epgShowSKY) {
                        Text(verbatim: "SKY")
                    }
                } header: {
                    Label {
                        Text("Broadcast type")
                    } icon: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                }
                Section {
                    Picker(selection: $startDate) {
                        ForEach(startDates) { startDate in
                            Text(startDate.formatted(EPGView.startDateFormatStyle))
                                .tag(startDate)
                        }
                    } label: {
                        Text("Date")
                    }
                    .pickerStyle(.menu)
                    Picker(selection: $startHour) {
                        ForEach(0...23, id: \.self) { startHour in
                            Text(String(format: "%02d:00", startHour))
                                .tag(startHour)
                        }
                    } label: {
                        Text("Time")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Label {
                        Text("Start time")
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                }
                Section {
                    ForEach(0..<enableGenre.count, id: \.self) { index in
                        Toggle(isOn: $enableGenre[index]) {
                            Text(EPGGenre[index]!)
                        }
                    }
                } header: {
                    Label {
                        Text("Genres")
                    } icon: {
                        Image(systemName: "bookmark")
                    }
                }
            }
            .formStyle(.grouped)
            #if !os(tvOS)
            .navigationTitle("Filter")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #endif
            .toolbar {
                ToolbarItem(placement: appState.isOnMac ? .cancellationAction : .topBarTrailing) {
                    Button("Close") {
                        showSettings = false
                    }
                }
            }
        }
        .onChange(of: userSettings.epgShowGR) { _, _ in
            refresh(manual: true)
        }
        .onChange(of: userSettings.epgShowBS) { _, _ in
            refresh(manual: true)
        }
        .onChange(of: userSettings.epgShowCS) { _, _ in
            refresh(manual: true)
        }
        .onChange(of: userSettings.epgShowSKY) { _, _ in
            refresh(manual: true)
        }
        .onChange(of: startDate) { oldValue, newValue in
            if oldValue != newValue {
                refresh(manual: true)
            }
        }
        .onChange(of: startHour) { oldValue, newValue in
            if oldValue != newValue {
                refresh(manual: true)
            }
        }
        .onChange(of: enableGenre) { _, newValue in
            do {
                userSettings.epgGenres = try JSONEncoder().encode(enableGenre)
            } catch let error {
                Logger.error("Failed to encode enabled genres: \(error.localizedDescription)")
            }
        }
    }
    
    func updateNowPosition() {
        nowPosition = (CGFloat(Date.now.timeIntervalSince1970 * 1000) - startAt) / (24 * 3600 * 1000) * heightOneDay
    }
    
    func refresh(waitTime: Duration = .zero, manual: Bool) {
        guard appState.clientState == .initialized else {
            return
        }
        schedules = []
        loadingState = .loading
        let nowTime = Date(timeIntervalSince1970: TimeInterval(Int(Date.now.timeIntervalSince1970) / 3600 * 3600)) // Round down to the nearest hour
        var calendar = Calendar(identifier: .japanese)
        calendar.timeZone = TimeZone(abbreviation: "JST")!
        startDates = []
        for day in 0..<7 {
            startDates.append(nowTime.addingTimeInterval(24 * 3600 * TimeInterval(day)))
        }
        if startDate.timeIntervalSince1970 == 0 || !manual {
            startDate = nowTime
        }
        if startHour == -1 || !manual {
            startHour = calendar.component(.hour, from: nowTime)
        }
        let startTime = calendar.date(from: DateComponents(
            year: calendar.component(.year, from: startDate),
            month: calendar.component(.month, from: startDate),
            day: calendar.component(.day, from: startDate),
            hour: startHour,
            minute: 0,
            second: 0
        ))!
        if enableGenre.isEmpty {
            if userSettings.epgGenres.isEmpty {
                enableGenre = [Bool](repeating: true, count: EPGGenre.count)
            } else {
                do {
                    enableGenre = try JSONDecoder().decode([Bool].self, from: userSettings.epgGenres)
                } catch let error {
                    Logger.error("Failed to decode enabled genres: \(error.localizedDescription)")
                    enableGenre = [Bool](repeating: true, count: EPGGenre.count)
                }
            }
        }
        Task {
            do {
                try await Task.sleep(for: waitTime)
                let startAt = Int(startTime.timeIntervalSince1970) * 1000
                let endAt = startAt + (24 * 3600 * 1000) // 24 hours later
                let schedules = try await appState.client.api.getSchedules(query: Operations.GetSchedules.Input.Query(startAt: startAt, endAt: endAt, isHalfWidth: true, gr: userSettings.epgShowGR, bs: userSettings.epgShowBS, cs: userSettings.epgShowCS, sky: userSettings.epgShowSKY)).ok.body.json
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

extension Date: @retroactive Identifiable {
    public var id: TimeInterval {
        timeIntervalSince1970
    }
}

extension Components.Schemas.Schedule: Identifiable {
    var id: Int { channel.id }
}

extension Components.Schemas.ScheduleProgramItem: Identifiable {
}
