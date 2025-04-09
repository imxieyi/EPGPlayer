//
//  AppDelegate.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/04.
//

import Foundation
import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    
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
        if ProcessInfo().isiOSAppOnMac {
            overrideCatalystScaleFactor()
        }
        return true
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window:UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }
}
