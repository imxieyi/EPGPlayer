//
//  SearchView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/22.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import OpenAPIRuntime

public struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @Binding var searchQuery: SearchQuery?
    
    let channels: [SearchChannel]
    
    @State private var keyword: String = ""
    @State private var channel: SearchChannel? = nil
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Keyword", text: $keyword)
                    Picker("Channel", selection: $channel) {
                        Text("All")
                            .tag(nil as SearchChannel?)
                        Divider()
                        ForEach(channels) { channel in
                            Text(verbatim: channel.name)
                                .tag(channel as SearchChannel?)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Label("Query", systemImage: "magnifyingglass")
                }
                
                HStack {
                    Button(role: .destructive) {
                        searchQuery = nil
                        dismiss()
                    } label: {
                        Text("Reset")
                    }
                    #if !os(macOS)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    #endif
                    
                    Spacer()
                    
                    Button {
                        searchQuery = SearchQuery(keyword: keyword, channel: channel)
                        dismiss()
                    } label: {
                        Text("Search")
                    }
                    #if !os(macOS)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    #endif
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Search")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: appState.isOnMac ? .cancellationAction : .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if let searchQuery {
                keyword = searchQuery.keyword
                channel = searchQuery.channel
            }
        }
    }
}
