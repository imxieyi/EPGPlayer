//
//  CustomAuthView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/20.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct CustomAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    
    let authType: String
    
    @State private var authHeader: String = ""
    @State private var error: String? = nil
    
    var body: some View {
        Form {
            Section {
                ContentUnavailableView("Warning", systemImage: "lock.trianglebadge.exclamationmark", description: Text("The authentication method \(authType) is not supported. Please try signing in with a custom HTTP header."))
            }
            Section {
                TextField("Authorization", text: $authHeader)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Label("HTTP Header", systemImage: "key")
            }
            Button {
                guard appState.keychain.set(authHeader, forKey: "auth_header:\(userSettings.serverUrl)") else {
                    error = "Failed to store authentication info to keychain."
                    return
                }
                dismiss()
            } label: {
                Text("Login")
            }
            
            if let error {
                Text(verbatim: error)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}
