//
//  DownloadEvents.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/12.
//

import Foundation
@preconcurrency import Combine

final class DownloadEvents: ObservableObject, Sendable {
    let downloadSuccess = PassthroughSubject<URL, Never>()
    let downloadFailure = PassthroughSubject<(URL, String), Never>()
}
