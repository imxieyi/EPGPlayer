//
//  TVTopActionBar.swift
//  EPGPlayer
//
//  SPDX-License-Identifier: MPL-2.0

#if os(tvOS)
import SwiftUI

/// Replaces `.toolbar` action buttons on tvOS: NavigationStack's toolbar bar is a
/// separate system-drawn row below the floating tab bar whose height/padding
/// can't be reduced via .labelStyle/.controlSize/.navigationTitle, so instead
/// this renders plain content positioned directly under the tab bar.
struct TVTopActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 24) {
            Spacer()
            content
        }
        .padding(.trailing, 48)
        .padding(.top, 8)
    }
}
#endif
