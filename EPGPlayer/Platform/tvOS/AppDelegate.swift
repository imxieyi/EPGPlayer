//
//  AppDelegate.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/23.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        LocalFileManager.shared.deleteOrphans()
    }
}
