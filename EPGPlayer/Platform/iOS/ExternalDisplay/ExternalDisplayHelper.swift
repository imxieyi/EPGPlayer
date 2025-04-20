//
//  ExternalDisplayHelper.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/10.
//
//  SPDX-License-Identifier: MPL-2.0

import UIKit

class ExternalDisplayHelper: NSObject {
    @MainActor static var instance = ExternalDisplayHelper()
    @objc dynamic var delegate: ExternalSceneDelegate?
}
