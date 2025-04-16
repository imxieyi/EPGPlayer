//
//  UIHelperImpl.swift
//  MacNativeHelper
//
//  Created by Yi Xie on 2023/01/03.
//  Copyright © 2023 xieyi. All rights reserved.
//

import Foundation
import CoreGraphics
import Dynamic

class MacNativeHelper {
    
    let appKitHandle: UnsafeMutableRawPointer
    let hideCursorHandle: UnsafeMutableRawPointer
    let showCursorHandle: UnsafeMutableRawPointer
    
    let sharedApplication: NSObject
    let firstWindow: NSObject
    
    init() throws {
        guard let appKitHandle = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_LAZY) else {
            throw MacNativeHelperError.dlopenFail("AppKit", String(cString: dlerror()))
        }
        guard let hideCursorHandle = dlsym(appKitHandle, "CGDisplayHideCursor") else {
            throw MacNativeHelperError.dlsymFail("CGDisplayHideCursor", String(cString: dlerror()))
        }
        guard let showCursorHandle = dlsym(appKitHandle, "CGDisplayShowCursor") else {
            throw MacNativeHelperError.dlsymFail("CGDisplayShowCursor", String(cString: dlerror()))
        }
        guard let sharedApplication = Dynamic.NSApplication.sharedApplication.asObject else {
            throw MacNativeHelperError.loadFailed("NSApplication.sharedApplication")
        }
        guard let firstWindow = Dynamic(sharedApplication).windows.asArray?.firstObject as? NSObject else {
            throw MacNativeHelperError.loadFailed("NSApplication.sharedApplication.windows.first")
        }
        self.appKitHandle = appKitHandle
        self.hideCursorHandle = hideCursorHandle
        self.showCursorHandle = showCursorHandle
        self.sharedApplication = sharedApplication
        self.firstWindow = firstWindow
    }
    
    private var mouseMonitor: NSObject?
    private var fullScreenMonitors: [any NSObjectProtocol] = []
    
    func startMonitorMouseMovement(_ callback: @escaping () -> Void) {
        stopMonitorMouseMovement()
        typealias ResultBlock = @convention(block) (_ event: NSObject) -> NSObject
        mouseMonitor = Dynamic.NSEvent.addLocalMonitorForEvents(matchingMask: NSEventMaskMouseMoved, handler: { event in
            callback()
            return event
        } as ResultBlock).asObject
    }
    
    func stopMonitorMouseMovement() {
        guard let mouseMonitor else {
            return
        }
        Dynamic.NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }
    
    func showMouseCursor() {
        CGDisplayShowCursorWrapper(showCursorHandle, kCGNullDirectDisplay)
    }
    
    func hideMouseCursor() {
        CGDisplayHideCursorWrapper(hideCursorHandle, kCGNullDirectDisplay)
    }
    
    @MainActor func isMousePointerInWindow() -> Bool {
        guard let frame = Dynamic(firstWindow).frame.asCGRect else {
            return false
        }
        guard let mouseLocation = Dynamic.NSEvent.mouseLocation.asCGPoint else {
            return false
        }
        return frame.contains(mouseLocation)
    }
    
    @MainActor func startObservingFullScreenChange(_ callback: @escaping @MainActor (Bool) -> Void) {
        fullScreenMonitors.append(NotificationCenter.default.addObserver(forName: Notification.Name("NSWindowWillEnterFullScreenNotification"), object: firstWindow, queue: .main) { notification in
            DispatchQueue.main.async {
                callback(true)
            }
        })
        fullScreenMonitors.append(NotificationCenter.default.addObserver(forName: Notification.Name("NSWindowWillExitFullScreenNotification"), object: firstWindow, queue: .main) { notification in
            DispatchQueue.main.async {
                callback(false)
            }
        })
        guard let presentationOptions = Dynamic(sharedApplication).presentationOptions.asUInt else {
            return
        }
        callback(((presentationOptions & NSApplicationPresentationFullScreen) != 0))
    }
    
    func stopObservingFullScreenChange() {
        fullScreenMonitors.forEach { NotificationCenter.default.removeObserver($0) }
        fullScreenMonitors.removeAll()
    }
    
    @MainActor func toggleFullscreen() {
        Dynamic(firstWindow).toggleFullScreen(self)
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
