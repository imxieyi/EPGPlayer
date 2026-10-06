//
//  PlayerView+tvOS.swift
//  EPGPlayer
//
//  SPDX-License-Identifier: MPL-2.0

// tvOS-only PlayerView members, split out since the Idle/Transport/Scrubbing/
// Settings/channel-switcher state machine has no equivalent on iOS/macOS.
#if os(tvOS)
import SwiftUI

extension PlayerView {
    var programInfoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: item.title)
                .font(.title2.bold())
                .lineLimit(2)
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let programDescription = item.programDescription, !programDescription.isEmpty {
                Text(verbatim: programDescription)
                    .font(.body)
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
            } else {
                Text("No program information")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 56)
        .padding(.vertical, 22)
        .background(.black.opacity(0.68))
    }

    var channelSwitcherPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(channelSwitcherSchedules, id: \.channel.id) { schedule in
                    Button {
                        switchChannel(to: schedule)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: schedule.channel.name)
                                .font(.system(size: 16, weight: .bold))
                                .lineLimit(1)
                            if let program = schedule.programs.first {
                                Text(verbatim: program.name)
                                    .font(.system(size: 14))
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                                Text(verbatim: Self.channelSwitcherTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(program.startAt / 1000))) + " ~ " + Self.channelSwitcherTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(program.endAt / 1000))))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                if let description = program.description, !description.isEmpty {
                                    Text(verbatim: description)
                                        .font(.system(size: 12))
                                        .lineLimit(3)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .tvOSFocusCard(cornerRadius: 8, scale: 1.02)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: 480, maxHeight: .infinity)
        .background(.black.opacity(0.75))
    }
    
    var channelCategorySwitcherPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(channelSwitcherAvailableCategories, id: \.self) { category in
                Button {
                    selectCategory(category)
                } label: {
                    Text(verbatim: category.rawValue.uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .tvOSFocusCard(cornerRadius: 8, scale: 1.02)
            }
        }
        .padding(24)
        .frame(maxWidth: 240, maxHeight: .infinity, alignment: .top)
        .background(.black.opacity(0.75))
    }
    
    var tvOSPlaybackSettings: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(VideoAspectRatio.allCases) { aspectRatio in
                    Button {
                        userSettings.videoAspectRatio = aspectRatio
                    } label: {
                        if userSettings.videoAspectRatio == aspectRatio {
                            Label(aspectRatio.label, systemImage: "checkmark")
                        } else {
                            Text(verbatim: aspectRatio.label)
                        }
                    }
                }
            } label: {
                playbackSettingLabel("Aspect", value: userSettings.videoAspectRatio.label, systemImage: "aspectratio", setting: .aspect)
            }
            .focused($focusedPlaybackSetting, equals: .aspect)
            .buttonStyle(.plain)
            .focusEffectDisabled()

            if item.videoItem.type != .livestream {
                Menu {
                    ForEach(PlaybackSpeed.all) { speed in
                        Button {
                            playbackSpeed = speed
                        } label: {
                            if playbackSpeed == speed {
                                Label(speed.text, systemImage: "checkmark")
                            } else {
                                Text(verbatim: speed.text)
                            }
                        }
                    }
                } label: {
                    // "gauge.with.dots.needle.67percent" has baked-in shading that ignores symbolRenderingMode; use a flat glyph instead.
                    playbackSettingLabel("Speed", value: playbackSpeed.text, systemImage: "gauge", setting: .speed)
                }
                .focused($focusedPlaybackSetting, equals: .speed)
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }

            Menu {
                ForEach(videoTracks) { track in
                    Button {
                        activeVideoTrack = track
                    } label: {
                        if activeVideoTrack == track {
                            Label(track.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: track.name)
                        }
                    }
                }
            } label: {
                playbackSettingLabel("Video", value: activeVideoTrack.id == "none" ? String(localized: "None") : activeVideoTrack.name, systemImage: "film", setting: .video)
            }
            .disabled(videoTracks.isEmpty)
            .focused($focusedPlaybackSetting, equals: .video)
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Menu {
                ForEach(audioTracks) { track in
                    Button {
                        activeAudioTrack = track
                    } label: {
                        if activeAudioTrack == track {
                            Label(track.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: track.name)
                        }
                    }
                }
            } label: {
                playbackSettingLabel("Audio", value: activeAudioTrack.id == "none" ? String(localized: "None") : activeAudioTrack.name, systemImage: "waveform", setting: .audio)
            }
            .disabled(audioTracks.isEmpty)
            .focused($focusedPlaybackSetting, equals: .audio)
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Menu {
                Button {
                    activeTextTrack = MediaTrack(id: "none", name: "text", codec: "")
                } label: {
                    if activeTextTrack.id == "none" {
                        Label("None", systemImage: "checkmark")
                    } else {
                        Text("None")
                    }
                }
                ForEach(textTracks) { track in
                    Button {
                        activeTextTrack = track
                    } label: {
                        if activeTextTrack == track {
                            Label(track.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: track.name)
                        }
                    }
                }
            } label: {
                playbackSettingLabel("Subtitle", value: activeTextTrack.id == "none" ? String(localized: "None") : activeTextTrack.name, systemImage: "captions.bubble", setting: .subtitle)
            }
            .disabled(textTracks.isEmpty)
            .focused($focusedPlaybackSetting, equals: .subtitle)
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(10)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
    }

    func playbackSettingLabel(_ title: LocalizedStringKey, value: String, systemImage: String, setting: PlaybackSetting) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout)
                .frame(width: 24)
                // SF Symbols default to hierarchical rendering, which draws part of
                // the glyph at a different opacity than the surrounding text.
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(.footnote)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(
            focusedPlaybackSetting == setting ? Color.white.opacity(0.28) : Color.white.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    func closeProgramInfo() {
        withAnimation(.easeOut(duration: 0.2)) {
            isProgramInfoPresented = false
        }
        // The wake surface remounts and reclaims focus via its own onAppear.
        resetIdleTimer()
    }
    
    /// Fetches all currently-broadcasting channels and opens the left-edge channel
    /// switcher overlay, defaulting to the currently playing channel's category.
    func openChannelSwitcher() {
        guard let currentLive = item.videoItem as? EPGLiveStreamItem else {
            return
        }
        channelSwitcherCategory = currentLive.channel.channelType
        isChannelSwitcherPresented = true
        Task {
            do {
                channelSwitcherAllSchedules = try await appState.client.api.getSchedulesBroadcasting(query: Operations.GetSchedulesBroadcasting.Input.Query(isHalfWidth: true)).ok.body.json
            } catch let error {
                Logger.error("Failed to load channel list: \(error)")
            }
        }
    }
    
    var channelSwitcherSchedules: [Components.Schemas.Schedule] {
        channelSwitcherAllSchedules.filter { $0.channel.channelType == channelSwitcherCategory }
    }
    
    var channelSwitcherAvailableCategories: [Components.Schemas.ChannelType] {
        let present = Set(channelSwitcherAllSchedules.map { $0.channel.channelType })
        return [
            (Components.Schemas.ChannelType.gr, userSettings.liveShowGR),
            (.bs, userSettings.liveShowBS),
            (.cs, userSettings.liveShowCS),
            (.sky, userSettings.liveShowSKY),
        ].filter { present.contains($0.0) && $0.1 }.map(\.0)
    }
    
    /// Swiping further left while the channel list is open reveals the category list.
    func openCategorySwitcher() {
        isChannelCategoryStageActive = true
    }
    
    func selectCategory(_ category: Components.Schemas.ChannelType) {
        channelSwitcherCategory = category
        isChannelCategoryStageActive = false
    }
    
    /// Commits the currently highlighted row: reassigns appState.playingItem, which
    /// VLCPlayer detects via the changed epgId and reloads without leaving PlayerView.
    func switchChannel(to schedule: Components.Schemas.Schedule) {
        guard item.videoItem is EPGLiveStreamItem else {
            return
        }
        let program = schedule.programs.first
        appState.playingItem = PlayerItem(
            videoItem: EPGLiveStreamItem(channel: schedule.channel, format: userSettings.tvLiveDefaultFormat, mode: userSettings.tvLiveDefaultMode, audioComponentType: program?.audioComponentType),
            title: program?.name ?? schedule.channel.name,
            subtitle: schedule.channel.name,
            programDescription: [program?.description, program?.extended].compactMap { $0 }.joined(separator: "\n\n")
        )
        isChannelSwitcherPresented = false
        resetIdleTimer()
    }
    
    /// Select cycles Idle -> Transport -> Scrubbing -> commit; see body's wake surface.
    func handleSelect() {
        if playerUIOpacity == 0 {
            showPlayerUI()
            resetIdleTimer()
            return
        }
        guard item.videoItem.type != .livestream else {
            return
        }
        if !isScrubbing {
            isScrubbing = true
            if playerState.isPlaying {
                playerEvents.togglePlay.send()
            }
        } else {
            playerEvents.setPlaybackPosition.send(playbackPosition)
            if !playerState.isPlaying {
                playerEvents.togglePlay.send()
            }
            isScrubbing = false
        }
        resetIdleTimer()
    }
}

enum PlaybackSetting: Hashable {
    case aspect
    case speed
    case video
    case audio
    case subtitle
}
#endif
