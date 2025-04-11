//
//  UIHelperImpl.swift
//  MacNativeHelper
//
//  Created by Yi Xie on 2023/01/03.
//  Copyright © 2023 xieyi. All rights reserved.
//

import Foundation
import AppKit
import CoreGraphics

class UIHelperImpl: NSObject, UIHelper {
    
    required override init() {
    }
    
    private var mouseMonitor: Any?
    private var fullScreenMonitors: [any NSObjectProtocol] = []
    
    func startMonitorMouseMovement(_ callback: @escaping () -> Void) {
        stopMonitorMouseMovement()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            callback()
            return event
        }
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
    
    @MainActor func isMousePointerInWindow() -> Bool {
        return !NSApplication.shared.windows.filter { window in
            window.frame.contains(NSEvent.mouseLocation)
        }.isEmpty
    }
    
    @MainActor func startObservingFullScreenChange(_ callback: @escaping @MainActor (Bool) -> Void) {
        fullScreenMonitors.append(NotificationCenter.default.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: NSApplication.shared.windows.first, queue: .main) { notification in
            DispatchQueue.main.async {
                callback(true)
            }
        })
        fullScreenMonitors.append(NotificationCenter.default.addObserver(forName: NSWindow.willExitFullScreenNotification, object: NSApplication.shared.windows.first, queue: .main) { notification in
            DispatchQueue.main.async {
                callback(false)
            }
        })
        callback(NSApplication.shared.presentationOptions.contains(.fullScreen))
    }
    
    func stopObservingFullScreenChange() {
        fullScreenMonitors.forEach { NotificationCenter.default.removeObserver($0) }
        fullScreenMonitors.removeAll()
    }
    
    @MainActor func toggleFullscreen() {
        NSApplication.shared.windows.first?.toggleFullScreen(self)
    }
}

