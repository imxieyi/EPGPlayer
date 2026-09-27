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
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var appState
    
    @Binding var searchQuery: SearchQuery?
    
    let channels: [SearchChannel]
    var rules: [SearchRule] = []
    
    @State var keyword: String = ""
    @State var channel: SearchChannel? = nil
    @State var rule: SearchRule? = nil
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    searchFields
                } header: {
                    Label("Query", systemImage: "magnifyingglass")
                }
                searchActions
            }
            .formStyle(.grouped)
            .navigationTitle("Search")
            #if !os(macOS) && !os(tvOS)
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
        #if os(tvOS)
        // Widen the sheet without touching NavigationStack (which is required here for
        // tvOS's text-input/focus system to work at all - see repo memory notes).
        .presentationSizing(.form)
        .frame(width: 1100)
        #endif
        .onAppear {
            loadInitialQuery()
        }
    }
}

extension SearchView {
    var searchFields: some View {
        Group {
            TextField("Keyword", text: $keyword)
            // tvOS's .menu Picker style shows only the selected value, not the label
            // passed to Picker(_:selection:) - so show the field name explicitly.
            HStack {
                Text("Channel")
                Spacer()
                Picker(selection: $channel) {
                    Text("All")
                        .tag(nil as SearchChannel?)
                    Divider()
                    ForEach(channels) { channel in
                        Text(verbatim: channel.name)
                            .tag(channel as SearchChannel?)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if !rules.isEmpty {
                HStack {
                    Text("Tags")
                    Spacer()
                    Picker(selection: $rule) {
                        Text("All")
                            .tag(nil as SearchRule?)
                        Divider()
                        ForEach(rules) { rule in
                            Text(verbatim: rule.keyword)
                                .tag(rule as SearchRule?)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
    }
    
    var searchActions: some View {
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
                searchQuery = SearchQuery(keyword: keyword, channel: channel, rule: rule)
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
    
    func loadInitialQuery() {
        if let searchQuery {
            keyword = searchQuery.keyword
            channel = searchQuery.channel
            rule = searchQuery.rule
        }
    }
}
