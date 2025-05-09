//
//  URLCache+imageCache.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/31.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation

extension URLCache {
    static let imageCache = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
}
