//
//  BasicAuthView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/15.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct BasicAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var userSettings: UserSettings
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var error: String? = nil
    
    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Label("Login info", systemImage: "key")
            }
            Button {
                guard let base64 = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() else {
                    error = "Base64 encoding error"
                    return
                }
                guard appState.keychain.set("Basic \(base64)", forKey: "auth_header:\(userSettings.serverUrl)") else {
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
