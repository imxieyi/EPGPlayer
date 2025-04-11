//
//  UIHelper.swift
//  waifu2x-ios
//
//  Created by Yi Xie on 2023/01/03.
//  Copyright © 2023 xieyi. All rights reserved.
//

import Foundation

@objc(UIHelper)
protocol UIHelper: NSObjectProtocol {
    init()
    func startMonitorMouseMovement(_ callback: @escaping () -> Void)
    func stopMonitorMouseMovement()
    func showMouseCursor()
    func hideMouseCursor()
    @MainActor func isMousePointerInWindow() -> Bool
    @MainActor func startObservingFullScreenChange(_ callback: @escaping @MainActor (Bool) -> Void)
    func stopObservingFullScreenChange()
    @MainActor func toggleFullscreen()
}
