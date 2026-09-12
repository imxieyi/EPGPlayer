//
//  EPGProgramView+tvOS.swift
//  EPGPlayer
//
//  SPDX-License-Identifier: MPL-2.0

// NavigationStack doesn't honor an outer frame() proposal on tvOS - it always
// claims the sheet's full default size regardless, so the popup couldn't be
// resized through it. Build the tvOS popup without NavigationStack instead,
// with our own header row, so frame(width:) here actually takes effect.
#if os(tvOS)
import SwiftUI

extension EPGProgramView {
    var tvOSBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                AsyncImageWithHeaders(url: appState.client.endpoint.appending(path: "channels/\(channel.id)/logo"), headers: appState.client.headers) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else if phase.error != nil {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.placeholder)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 24)
                Text(channel.name)
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding(40)
            Divider()
            ScrollView(.vertical) {
                programInfoContent
            }
        }
        .frame(width: 900)
        .alert("Reserve error", isPresented: Binding(get: { reserveError != nil }, set: { if !$0 { reserveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let reserveError {
                Text(verbatim: reserveError)
            }
        }
    }
}
#endif
