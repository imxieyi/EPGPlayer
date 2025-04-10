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
}
