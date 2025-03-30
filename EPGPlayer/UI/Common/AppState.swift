//
//  AppState.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//

import SwiftUI
import OpenAPIRuntime

@Observable
final class AppState {
    var client = EPGClient()
    
    var serverVersion: String = ""
    var serverError = Text(verbatim: "")
    
    var isAuthenticating = false
    var clientState: ClientState = .notInitialized
    
    var selectedRecording: Components.Schemas.RecordedItem? = nil
}

enum ClientState {
    case notInitialized
    case initialized
    case authNeeded
}
