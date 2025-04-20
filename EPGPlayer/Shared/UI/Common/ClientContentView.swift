//
//  ClientContentView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/15.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct ClientContentView<Content: View>: View {
    @Environment(AppState.self) private var appState
    
    @Binding var activeTab: TabSelection
    @Binding var loadingState: LoadingState
    let refresh: (Duration) -> Void
    let content: Content
    
    init(activeTab: Binding<TabSelection>, loadingState: Binding<LoadingState>, refresh: @escaping (Duration) -> Void, @ViewBuilder content: () -> Content) {
        self._activeTab = activeTab
        self._loadingState = loadingState
        self.refresh = refresh
        self.content = content()
    }
    
    var body: some View {
        Group {
            if appState.clientState != .initialized && appState.clientState != .notInitialized {
                ContentUnavailableView {
                    if appState.clientState == .setupNeeded {
                        Label("Setup needed", systemImage: "exclamationmark.triangle")
                    } else if appState.clientState == .authNeeded {
                        Label("Authentication required", systemImage: "exclamationmark.triangle")
                    } else {
                        Label("Error loading content", systemImage: "xmark.circle")
                    }
                } description: {
                    if appState.clientState == .setupNeeded {
                        Text("Please set EPGStation URL")
                    } else if let clientError = appState.clientError {
                        clientError
                    }
                } actions: {
                    if appState.clientState == .authNeeded {
                        Button("Login") {
                            appState.isAuthenticating = true
                        }
                    } else if appState.clientState == .setupNeeded {
                        Button("Go to settings") {
                            activeTab = .settings
                        }
                    }
                }
            } else {
                if appState.clientState == .notInitialized {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                } else if case .loading = loadingState {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                } else if case .loaded = loadingState {
                    content
                } else if case .error(let message) = loadingState {
                    ContentUnavailableView {
                        Label("Error loading content", systemImage: "xmark.circle")
                    } description: {
                        message
                    }
                } else {
                    EmptyView()
                }
            }
        }
        .onChange(of: appState.isAuthenticating) { oldValue, newValue in
            if oldValue && !newValue {
                refresh(.seconds(1))
            }
        }
        .onChange(of: appState.clientState, initial: true) { oldValue, newValue in
            guard oldValue != newValue else {
                return
            }
            switch newValue {
            case .notInitialized:
                loadingState = .loading
            case .initialized:
                refresh(.zero)
            case .authNeeded:
                loadingState = .error(appState.clientError ?? Text("Authentication required"))
            case .setupNeeded:
                loadingState = .error(Text("Please set EPGStation URL"))
            case .error:
                loadingState = .error(appState.clientError ?? Text("Unknown error"))
            }
        }
    }
}

enum LoadingState {
    case loading
    case error(Text)
    case loaded
}
