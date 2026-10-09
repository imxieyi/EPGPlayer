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
        window = UIWindow(windowScene: scene)
        viewController = UIViewController()
        viewController.view.backgroundColor = .black
        window?.rootViewController = viewController
        window?.isHidden = false
        // Publish only after the drawable is attached to the external scene.
        ExternalDisplayHelper.instance.delegate = self
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        if ExternalDisplayHelper.instance.delegate === self {
            ExternalDisplayHelper.instance.delegate = nil
        }
        window = nil
    }
    
}
