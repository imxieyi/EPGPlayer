//
//  AppDelegate.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/04.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import UIKit
import SwiftUI

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    
    private weak var _windowScene: UIWindowScene?
    var windowScene: UIWindowScene? {
        if let _windowScene {
            return _windowScene
        }
        if let windowS = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            _windowScene = windowS
            return windowS
        }
        return nil
    }
    
    private weak var _rootViewController: UIViewController?
    var rootViewController: UIViewController? {
        if let _rootViewController {
            return _rootViewController
        }
        if let rootVC = _windowScene?.windows.first?.rootViewController {
            _rootViewController = rootVC
            return rootVC
        }
        return nil
    }
    
    var orientationLock = UIInterfaceOrientationMask.allButUpsideDown
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        LocalFileManager.shared.deleteOrphans()
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window:UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }
    
    var backgroundCompletionHandler: (() -> Void)?
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
    }
    
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        
        builder.remove(menu: .file)
        builder.remove(menu: .edit)
        builder.remove(menu: .view)
        builder.remove(menu: .format)
        builder.remove(menu: .help)
    }
}
