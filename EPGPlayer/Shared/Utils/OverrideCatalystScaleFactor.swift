//
//  OverrideCatalystScaleFactor.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/10.
//
//  https://gist.github.com/JunyuKuang/75fcb81fd6046c0bf31933d85043d04b

import Foundation

extension AppDelegate {
    func overrideCatalystScaleFactor() {
        guard let sceneViewClass = NSClassFromString("UINSSceneView") as? NSObject.Type else {
            return
        }
        if sceneViewClass.instancesRespond(to: NSSelectorFromString("scaleFactor")) {
            // old
            swizzleInstanceMethod(
                class: sceneViewClass,
                originalSelector: NSSelectorFromString("scaleFactor"),
                swizzledSelector: #selector(swizzle_scaleFactor)
            )
        } else {
            // macOS 11.3 Beta 3+
            swizzleInstanceMethod(
                class: sceneViewClass,
                originalSelector: NSSelectorFromString("sceneToSceneViewScaleFactor"),
                swizzledSelector: #selector(swizzle_scaleFactor)
            )
            swizzleInstanceMethod(
                class: sceneViewClass,
                originalSelector: NSSelectorFromString("fixedSceneToSceneViewScaleFactor"),
                swizzledSelector: #selector(swizzle_scaleFactor2)
            )
            swizzleInstanceMethod(
                class: NSClassFromString("UINSSceneContainerView"),
                originalSelector: NSSelectorFromString("sceneToSceneViewScaleForLayout"),
                swizzledSelector: #selector(swizzle_scaleFactor3)
            )
        }
    }
}

@objc private extension NSObject {
    func swizzle_scaleFactor() -> CGFloat { 1 }
    func swizzle_scaleFactor2() -> CGFloat { 1 }
    func swizzle_scaleFactor3() -> CGFloat { 1 }
}
