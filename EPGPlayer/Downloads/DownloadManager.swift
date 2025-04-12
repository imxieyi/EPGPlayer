//
//  DownloadManager.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/10.
//

import os
import Foundation
import SwiftData
import UIKit
import VLCKit

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EPGPlayer", category: "downloader")

@MainActor
final class DownloadManager: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    
    let events = DownloadEvents()
    var container: ModelContainer!
    private var urlSession: URLSession!
    private(set) var downloads = Set<URL>()
    
    private override init() {}
    
    func initialize() {
        let config = URLSessionConfiguration.background(withIdentifier: "EPGSession")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        Task(priority: .background) {
            downloads = await Set(urlSession.allTasks.compactMap { $0.originalRequest?.url })
        }
    }
    
    func getActiveDownloads() async throws -> [ActiveDownload] {
        try await urlSession.allTasks.compactMap { task -> ActiveDownload? in
            guard let url = task.originalRequest?.url, task.state != .completed else {
                return nil
            }
            guard let videoItem = try container.mainContext.fetch(FetchDescriptor<LocalVideoItem>(predicate: #Predicate { $0.originalUrl == url })).first,
                  let downloadTask = task as? URLSessionDownloadTask else {
                task.cancel()
                return nil
            }
            return ActiveDownload(url: url, videoItem: videoItem, downloadTask: downloadTask)
        }
    }
    
    func startDownloading(url: URL, expectedBytes: Int64) -> URLSessionDownloadTask? {
        guard !downloads.contains(url) else {
            logger.warning("URL \(url) already started downloading")
            return nil
        }
        let backgroundTask = urlSession.downloadTask(with: url)
        backgroundTask.countOfBytesClientExpectsToReceive = expectedBytes
        backgroundTask.resume()
        downloads.insert(url)
        return backgroundTask
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
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let task = task as? URLSessionDownloadTask else {
            return
        }
        guard let errorDesc = error?.localizedDescription else {
            return
        }
        print("Task completed with error: \(errorDesc)")
        guard let url = task.originalRequest?.url else {
            logger.error("Cannot get original request URL")
            return
        }
        Task { @MainActor [self] in
            downloads.remove(url)
            events.downloadFailure.send((url, task, errorDesc))
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let url = downloadTask.originalRequest?.url else {
            logger.error("Cannot get original request URL")
            return
        }
        Task { @MainActor [self] in
            downloads.remove(url)
        }
        guard let response = downloadTask.response as? HTTPURLResponse else {
            logger.error("downloadTask.response is not HTTPURLResponse")
            sendError(url, task: downloadTask, message: "downloadTask.response is not HTTPURLResponse")
            return
        }
        guard response.statusCode == 200 else {
            logger.error("HTTP status code is not 200, but is \(response.statusCode)")
            sendError(url, task: downloadTask, message: "HTTP status code is not 200, but is \(response.statusCode)")
            return
        }
        do {
            guard let videoItem = try DispatchQueue.main.sync(execute: {
                try container.mainContext.fetch(FetchDescriptor<LocalVideoItem>(predicate: #Predicate { $0.originalUrl == url })).first
            }) else {
                logger.error("Cannot find video item associated with \(url)")
                sendError(url, task: downloadTask, message: "Cannot find video item associated with \(url)")
                return
            }
            if videoItem.duration == nil, let media = VLCMedia(url: location) {
                media.parse(options: .parseLocal)
                if let length = media.lengthWait(until: .now.advanced(by: 60)).value?.doubleValue {
                    videoItem.duration = length / 1000
                }
            }
            let localFileManager = DispatchQueue.main.sync { LocalFileManager.shared }
            try localFileManager.moveFile(name: videoItem.file.id.uuidString, url: location)
            videoItem.file.available = true
            Task { @MainActor [self] in
                events.downloadSuccess.send(url)
            }
            logger.info("Download succeeded for \(url)")
        } catch let error {
            logger.error("Failed to fetch video item associated with \(url): \(error)")
            sendError(url, task: downloadTask, message: "Failed to fetch video item associated with \(url): \(error)")
            return
        }
    }
    
    nonisolated func sendError(_ url: URL, task: URLSessionDownloadTask, message: String) {
        Task { @MainActor [self] in
            events.downloadFailure.send((url, task, message))
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        return nil
    }
    
}
