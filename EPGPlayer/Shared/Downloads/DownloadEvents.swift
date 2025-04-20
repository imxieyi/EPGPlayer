//
//  DownloadEvents.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/12.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
@preconcurrency import Combine

final class DownloadEvents: ObservableObject, Sendable {
    let downloadSuccess = PassthroughSubject<URL, Never>()
    let downloadFailure = PassthroughSubject<(URL, URLSessionDownloadTask, String), Never>()
}
