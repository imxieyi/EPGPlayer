//
//  DownloadManager.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/10.
//

import os
import Foundation
import UIKit

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EPGPlayer", category: "downloader")

@MainActor
final class DownloadManager: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    
    static let shared = DownloadManager()
    
    private var urlSession: URLSession!
    private(set) var downloadTasks: [Int : URLSessionDownloadTask] = [:]
    
    private override init() {}
    
    func initialize() {
        let config = URLSessionConfiguration.background(withIdentifier: "EPGSession")
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func startDownloading(id: Int, url: URL, extectedBytes: Int64) {
        guard downloadTasks[id] == nil else {
            logger.warning("File id \(id) already started downloading")
            return
        }
        let backgroundTask = urlSession.downloadTask(with: url)
        backgroundTask.countOfBytesClientExpectsToReceive = extectedBytes
        backgroundTask.resume()
        downloadTasks[id] = backgroundTask
    }
    
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                  let backgroundCompletionHandler = appDelegate.backgroundCompletionHandler else {
                return
            }
            backgroundCompletionHandler()
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            logger.error("downloadTask.response is not HTTPURLResponse")
            return
        }
        guard response.statusCode == 200 else {
            logger.error("HTTP status code is not 200")
            return
        }
        print(response.statusCode)
        print(response.mimeType)
        print(response.suggestedFilename)
        print(location)
    }
    
}
