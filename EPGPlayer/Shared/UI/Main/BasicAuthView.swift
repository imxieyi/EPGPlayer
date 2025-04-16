//
//  BasicAuthView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/15.
//

import SwiftUI
import KeychainSwift

struct BasicAuthView: View {
    @Environment(\.dismiss) private var dismiss
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
                TextField("Password", text: $password)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Label("Login info", systemImage: "key")
            }
            Button {
                guard let base64 = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() else {
                    error = "Base64 encoding error"
                    return
                }
                KeychainSwift().set(base64, forKey: "basic:\(userSettings.serverUrl)")
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
