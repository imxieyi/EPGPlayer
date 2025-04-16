//
//  UIHelperImpl.swift
//  MacNativeHelper
//
//  Created by Yi Xie on 2023/01/03.
//  Copyright © 2023 xieyi. All rights reserved.
//

import Foundation
import CoreGraphics
import AppKit

class MacNativeHelper {
    
    let firstWindow: NSWindow
    
    @MainActor
    init() throws {
        guard let firstWindow = NSApplication.shared.windows.first else {
            throw MacNativeHelperError.loadFailed("NSApplication.sharedApplication.windows.first")
        }
        self.firstWindow = firstWindow
    }
    
    private var mouseMonitor: Any?
    private var fullScreenMonitors: [any NSObjectProtocol] = []
    
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
    
    @MainActor func isMousePointerInWindow() -> Bool {
        return firstWindow.frame.contains(NSEvent.mouseLocation)
    }
    
    @MainActor func startObservingFullScreenChange(_ callback: @escaping @MainActor (Bool) -> Void) {
        fullScreenMonitors.append(NotificationCenter.default.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: firstWindow, queue: .main) { notification in
            DispatchQueue.main.async {
                callback(true)
            }
        })
        fullScreenMonitors.append(NotificationCenter.default.addObserver(forName: NSWindow.willExitFullScreenNotification, object: firstWindow, queue: .main) { notification in
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
        firstWindow.toggleFullScreen(self)
    }
}

enum MacNativeHelperError: Error, LocalizedError {
    case dlopenFail(String, String)
    case dlsymFail(String, String)
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .dlopenFail(let name, let error):
            "dlopen() failed for \(name): \(error)"
        case .dlsymFail(let name, let error):
            "dlsym() failed for \(name): \(error)"
        case .loadFailed(let name):
            "Failed to load \(name)"
        }
    }
}
