//
//  LicenseList.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/20.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI

public struct LicenseList: View {
    @State private var licenseTitles: [String]? = nil
    @State private var selectedLicense: String? = nil
    
    public var body: some View {
        Group {
            if let licenseTitles {
                List(licenseTitles, id: \.self) { title in
                    Button {
                        selectedLicense = title
                    } label: {
                        HStack {
                            Text(verbatim: title)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .tint(.primary)
                }
                .selectionDisabled()
                .navigationDestination(item: $selectedLicense) { title in
                    LicenseView(name: title)
                }
            } else {
                ProgressView()
                    #if !os(tvOS)
                    .controlSize(.large)
                    #endif
                    .onAppear {
                        Task {
                            let urls = Bundle.main.urls(forResourcesWithExtension: "license", subdirectory: nil)
                            licenseTitles = urls?.map { $0.lastPathComponent.replacingOccurrences(of: ".license", with: "") }.sorted()
                        }
                    }
            }
        }
        .navigationTitle("Licenses")
    }
}
