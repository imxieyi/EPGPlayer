//
//  AppDelegate.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/16.
//
//  SPDX-License-Identifier: MPL-2.0

import AppKit

class AppDelegate: NSResponder, NSApplicationDelegate, ObservableObject {
    
    func applicationWillTerminate(_ notification: Notification) {
        LocalFileManager.shared.deleteOrphans()
    }
    
}
