//
//  UIHelperImpl.swift
//  MacNativeHelper
//
//  Created by Yi Xie on 2023/01/03.
//  Copyright © 2023 xieyi. All rights reserved.
//

import Foundation
import AppKit

class UIHelperImpl: NSObject, UIHelper {
    
    required override init() {
    }
    
    private var mouseMonitor: Any?
    
    func startMonitorMouseMovement(_ callback: @escaping () -> Void) {
        if let mouseMonitor {
            stopMonitorMouseMovement()
        }
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
    }
    
}

