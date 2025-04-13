//
//  LicenseView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/14.
//

import SwiftUI

struct LicenseView: View {
    let name: String
    let url: URL
    
    @State var content: String? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    if let content {
                        HStack {
                            VStack {
                                Text(content)
                                    .font(.system(.footnote, design: .monospaced))
                                    .id(name)
                                Spacer()
                            }
                            .frame(minHeight: geometry.size.height)
                            Spacer()
                        }
                        .frame(minWidth: geometry.size.width)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
                .navigationTitle(name)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    Task {
                        content = getContent()
                        proxy.scrollTo(name, anchor: .topLeading)
                    }
                }
            }
        }
    }
    
    func getContent() -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch let error {
            return "Failed to load \(name) license: \(error.localizedDescription)"
        }
    }
}
