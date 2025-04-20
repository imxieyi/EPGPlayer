//
//  UIHelperImpl.swift
//  MacNativeHelper
//
//  Created by Yi Xie on 2023/01/03.
//  Copyright © 2023 xieyi. All rights reserved.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import CoreGraphics
import AppKit

class MacHelper {
    
    let targetWindow: NSWindow
    
    @MainActor
    init(window id: String) throws {
        guard let firstWindow = (NSApplication.shared.windows.first { $0.identifier?.rawValue == id }) else {
            throw MacNativeHelperError.loadFailed("Unable to find window with identifier \(id)")
        }
        self.targetWindow = firstWindow
    }
    
    private var mouseMonitor: Any?
    private var fullScreenMonitors: [any NSObjectProtocol] = []
    
    @MainActor var isFullScreen: Bool {
        targetWindow.styleMask.contains(.fullScreen)
    }
    
    func startMonitorMouseMovement(_ callback: @escaping () -> Void) {
        stopMonitorMouseMovement()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            callback()
            return event
        })
    }
    
    func stopMonitorMouseMovement() {
        guard let mouseMonitor else {
            return
        }
        NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }
    
    func showMouseCursor() {
        CGDisplayShowCursor(kCGNullDirectDisplay)
    }
    
    func hideMouseCursor() {
        CGDisplayHideCursor(kCGNullDirectDisplay)
    }
    
    @MainActor func setWindowTitleBar(visible: Bool) {
        targetWindow.standardWindowButton(.closeButton)?.isHidden = !visible
        targetWindow.standardWindowButton(.miniaturizeButton)?.isHidden = !visible
        targetWindow.standardWindowButton(.zoomButton)?.isHidden = !visible
        targetWindow.titleVisibility = visible ? .visible : .hidden
        targetWindow.titlebarAppearsTransparent = !visible
    }
    
    @MainActor func isMousePointerInWindow() -> Bool {
        return targetWindow.frame.contains(NSEvent.mouseLocation)
    }
    
    @MainActor func toggleFullscreen() {
        targetWindow.toggleFullScreen(self)
    }
}

enum MacNativeHelperError: Error, LocalizedError {
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let name):
            "Failed to load \(name)"
        }
    }
}
