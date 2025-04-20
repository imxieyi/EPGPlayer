//
//  ExternalSceneDelegate.swift
//  JSCPlayer
//
//  Created by Yi Xie on 2023/11/01.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftUI

class ExternalSceneDelegate: NSObject, UISceneDelegate {
    var window: UIWindow?
    
    var viewController: UIViewController!
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else {
            return
        }
        ExternalDisplayHelper.instance.delegate = self
        window = UIWindow(windowScene: scene)
        viewController = UIViewController()
        window?.rootViewController = viewController
        window?.isHidden = false
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplayHelper.instance.delegate = nil
    }
    
}
