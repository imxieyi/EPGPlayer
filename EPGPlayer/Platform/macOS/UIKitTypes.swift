//
//  UIKitTypes.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/16.
//

import AppKit
import SwiftUI

typealias UIApplication = NSApplication
typealias UIApplicationDelegateAdaptor = NSApplicationDelegateAdaptor
typealias UIView = NSView
typealias UIViewControllerRepresentable = NSViewControllerRepresentable
typealias UIViewRepresentable = NSViewRepresentable

class UIViewController: NSViewController {
    func viewWillAppear(_ animated: Bool) {
    }
    override func viewWillAppear() {
        self.viewWillAppear(true)
    }
    
    func viewDidDisappear(_ animated: Bool) {
    }
    override func viewDidDisappear() {
        self.viewDidDisappear(true)
    }
    
    func viewWillLayoutSubviews() {
    }
    override func viewDidLayout() {
        self.viewWillLayoutSubviews()
    }
}

extension ToolbarItemPlacement {
    static var topBarTrailing: ToolbarItemPlacement {
        return .navigation
    }
    static var topBarLeading: ToolbarItemPlacement {
        return .navigation
    }
}
