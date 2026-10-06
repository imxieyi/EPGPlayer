//
//  UserSettings.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/30.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

enum VideoAspectRatio: String, CaseIterable, Identifiable {
    // Leaves the source's own aspect ratio untouched; explicitly forcing a ratio
    // (even one matching the source) makes libVLC engage an extra per-frame
    // scale/canvas pass that isn't needed otherwise.
    case auto
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case zoom

    var id: Self { self }
    var vlcValue: String? { self == .zoom || self == .auto ? nil : rawValue }
    var label: String {
        switch self {
        case .auto:
            String(localized: "Auto")
        case .zoom:
            String(localized: "Zoom")
        default:
            rawValue
        }
    }
}

@MainActor
class UserSettings: ObservableObject {

    // Server Settings
    @AppStorage("server_url") var serverUrl: String = ""
    
    // Player Settings
    @AppStorage("enable_subtitles") var enableSubtitles = false
    @AppStorage("force_stroke_text") var forceStrokeText = false
    @AppStorage("video_aspect_ratio") var videoAspectRatio: VideoAspectRatio = .sixteenNine
    @AppStorage("force_16_9") var force16To9 = false
    @AppStorage("force_landscape") var forceLandscape = false
    @AppStorage("show_player_stats") var showPlayerStats = false
    @AppStorage("inactive_timer") var inactiveTimer = 5
    
    // EPG Settings
    @AppStorage("epg_show_gr") var epgShowGR = true
    @AppStorage("epg_show_bs") var epgShowBS = true
    @AppStorage("epg_show_cs") var epgShowCS = true
    @AppStorage("epg_show_sky") var epgShowSKY = true
    @AppStorage("epg_genres") var epgGenres = Data()
    @AppStorage("epg_notify_time_diff") var epgNotifyTimeDiff: TimeInterval = -600
    
    // Live Settings
    @AppStorage("live_show_gr") var liveShowGR = true
    @AppStorage("live_show_bs") var liveShowBS = true
    @AppStorage("live_show_cs") var liveShowCS = true
    @AppStorage("live_show_sky") var liveShowSKY = true
    
    #if os(tvOS)
    // tvOS skips the per-tap format/quality menu; channel selection and the
    // in-player channel switcher both use this fixed default instead.
    @AppStorage("tv_live_default_format") var tvLiveDefaultFormat: String = "m2ts"
    @AppStorage("tv_live_default_mode") var tvLiveDefaultMode: Int = 0
    #endif

    // Translation Settings
    @AppStorage("translation_engine") var translationEngine = ""
    @AppStorage("translation_target_language") var translationTargetLanguage = ""
    /// Translate the subtitles of online videos and live streams while they play.
    @AppStorage("live_translation") var liveTranslation = false
    @AppStorage("custom_model_api_format") var customModelAPIFormat = ""
    @AppStorage("custom_model_base_url") var customModelBaseURL = ""
    @AppStorage("custom_model_name") var customModelName = ""

    /// Keychain key of the API key of the custom translation model.
    static let customModelAPIKeyKeychainKey = "custom_model_api_key"
    
    // Debug Settings
    #if DEBUG
    @Published var demoMode = false
    #endif
    
    init() {
        let defaults = UserDefaults.standard
        if let storedAspectRatio = defaults.string(forKey: "video_aspect_ratio") {
            if storedAspectRatio == "fill_screen" {
                defaults.set(VideoAspectRatio.zoom.rawValue, forKey: "video_aspect_ratio")
            } else if VideoAspectRatio(rawValue: storedAspectRatio) == nil {
                defaults.set(VideoAspectRatio.sixteenNine.rawValue, forKey: "video_aspect_ratio")
            }
        } else {
            videoAspectRatio = .sixteenNine
        }
    }

    func reset() {
        serverUrl = ""
        enableSubtitles = true
        videoAspectRatio = .sixteenNine
        forceLandscape = false
        showPlayerStats = false
        inactiveTimer = 5
    }
}
