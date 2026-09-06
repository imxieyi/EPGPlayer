//
//  TVFocusCard.swift
//  EPGPlayer
//
//  SPDX-License-Identifier: MPL-2.0

#if os(tvOS)
import SwiftUI

/// Highlights the enclosing focusable control (Button/Menu/NavigationLink) so the
/// current Siri Remote focus position is clearly visible in grid layouts.
private struct TVFocusCardModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? Color.white : .clear, lineWidth: 4)
            )
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: isFocused ? 16 : 0, y: isFocused ? 8 : 0)
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

extension View {
    func tvOSFocusCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(TVFocusCardModifier(cornerRadius: cornerRadius))
    }
}
#endif
