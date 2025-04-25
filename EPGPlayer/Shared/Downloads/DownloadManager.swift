//
//  DownloadManager.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/10.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData
import VLCKit

@MainActor
final class DownloadManager: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    
    let events = DownloadEvents()
    var container: ModelContainer!
    private var urlSession: URLSession!
    private(set) var downloads = Set<URL>()
    
    private override init() {}
    
    func initialize() {
        #if os(macOS)
        let config = URLSessionConfiguration.default
        #else
        let config = URLSessionConfiguration.background(withIdentifier: "EPGSession")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        #endif
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
    
    func startDownloading(url: URL, expectedBytes: Int64, headers: [String: String]?) -> URLSessionDownloadTask? {
        guard !downloads.contains(url) else {
            Logger.warning("URL \(url) already started downloading")
            return nil
        }
        var request = URLRequest(url: url)
        headers?.forEach { (key: String, value: String) in
            request.setValue(value, forHTTPHeaderField: key)
        }
        let downloadTask = urlSession.downloadTask(with: request)
        downloadTask.countOfBytesClientExpectsToReceive = expectedBytes
        downloadTask.resume()
        downloads.insert(url)
        return downloadTask
    }
    
    #if os(macOS)
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        downloadTask.progress.totalUnitCount = totalBytesExpectedToWrite
        downloadTask.progress.completedUnitCount = totalBytesWritten
    }
    #endif

    #if !os(macOS) && !os(tvOS)
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                  let backgroundCompletionHandler = appDelegate.backgroundCompletionHandler else {
                return
            }
            backgroundCompletionHandler()
        }
    }
    #endif
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let task = task as? URLSessionDownloadTask else {
            return
        }
        guard let errorDesc = error?.localizedDescription else {
            return
        }
        guard let url = task.originalRequest?.url else {
            Logger.error("Cannot get original request URL")
            return
        }
        Logger.error("Download task for URL \(pii: url.absoluteString) completed with error: \(errorDesc)")
        Task { @MainActor [self] in
            downloads.remove(url)
            events.downloadFailure.send((url, task, errorDesc))
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let url = downloadTask.originalRequest?.url else {
            Logger.error("Cannot get original request URL")
            return
        }
        Task { @MainActor [self] in
            downloads.remove(url)
        }
        guard let response = downloadTask.response as? HTTPURLResponse else {
            Logger.error("downloadTask.response for url \(pii: url.absoluteString) is not HTTPURLResponse")
            sendError(url, task: downloadTask, message: "downloadTask.response is not HTTPURLResponse")
            return
        }
        guard response.statusCode == 200 else {
            Logger.error("HTTP status code for url \(pii: url.absoluteString) is not 200, but is \(response.statusCode)")
            sendError(url, task: downloadTask, message: "HTTP status code is not 200, but is \(response.statusCode)")
            return
        }
        do {
            guard let videoItem = try DispatchQueue.main.sync(execute: {
                try container.mainContext.fetch(FetchDescriptor<LocalVideoItem>(predicate: #Predicate { $0.originalUrl == url })).first
            }) else {
                Logger.error("Cannot find video item associated with \(pii: url.absoluteString)")
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
            Logger.info("Download succeeded for \(pii: url.absoluteString)")
        } catch let error {
            Logger.error("Failed to fetch video item associated with \(pii: url.absoluteString): \(error.localizedDescription)")
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
