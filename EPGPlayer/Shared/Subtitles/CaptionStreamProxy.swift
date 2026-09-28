//
//  CaptionStreamProxy.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2026/09/28.
//
//  SPDX-License-Identifier: MPL-2.0

#if os(iOS) || os(macOS)
import Foundation
import Network

/// Serves streams of the server to VLC on the loopback interface and reads the ARIB captions of the bytes that pass
/// through, since VLC doesn't expose the text of the subtitles it decodes. VLC still sees an ordinary HTTP stream,
/// so seeking with range requests and the buffering of live streams work as without the proxy.
final class CaptionStreamProxy: NSObject, @unchecked Sendable {
    static let shared = CaptionStreamProxy()

    /// A stream registered with the proxy. The handlers are called on the queue of the proxy.
    struct Stream: Sendable {
        let id: String
        let upstreamURL: URL
        let headers: [String: String]
        /// Shared by all connections to the stream, since only a connection from the start of the stream sees its first PCR.
        let timeBase = ARIBCaptionTimeBase()
        /// Called with each caption and the ID of the connection that it was read from.
        let onCaption: @Sendable (ARIBCaption, Int) -> Void
        /// Called when a connection starts reading the stream from its beginning.
        let onStart: @Sendable () -> Void
        /// Called with the caption time of the first PCR of a connection that VLC opened to seek.
        let onSeek: @Sendable (Int) -> Void
        /// Called when a connection finds out whether the stream has a caption stream.
        let onCaptionStream: @Sendable (Bool) -> Void
    }

    enum ProxyError: LocalizedError {
        case listenerFailed(String)

        var errorDescription: String? {
            switch self {
            case .listenerFailed(let message):
                return message
            }
        }
    }

    /// Bytes waiting to be sent to VLC, above which the download from the server is paused.
    private static let maxPendingBytes = 8 << 20
    /// Bytes waiting to be sent to VLC, below which a paused download is resumed.
    private static let resumePendingBytes = 2 << 20

    private let queue = DispatchQueue(label: "com.imxieyi.EPGPlayer.CaptionStreamProxy")
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var portWaiters: [CheckedContinuation<NWEndpoint.Port, Error>] = []
    private var streams: [String: Stream] = [:]
    private var connections: [Int: Connection] = [:]
    private var connectionsByTask: [Int: Connection] = [:]
    private var nextConnectionID = 1

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // A video is far too large for the cache, and live streams never end.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // The download is paused for as long as VLC doesn't read, e.g. while the playback is paused,
        // and a paused task would time out like a stalled one. A live stream can't be opened again where it stopped.
        configuration.timeoutIntervalForRequest = 7 * 24 * 3600
        configuration.timeoutIntervalForResource = 7 * 24 * 3600
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }()

    /// Registers a stream and returns the URL on the loopback interface that VLC should open instead.
    func register(_ stream: Stream) async throws -> URL {
        let port = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.streams[stream.id] = stream
                self.waitForPort(continuation)
            }
        }
        // Keep the last path component, which tells the format to VLC.
        return URL(string: "http://127.0.0.1:\(port.rawValue)/\(stream.id)/")!.appending(path: stream.upstreamURL.lastPathComponent)
    }

    /// Stops serving a stream and closes its connections.
    func unregister(_ id: String) {
        queue.async {
            self.streams[id] = nil
            for connection in self.connections.values where connection.stream.id == id {
                self.close(connection)
            }
        }
    }

    // MARK: - Listener

    private func waitForPort(_ continuation: CheckedContinuation<NWEndpoint.Port, Error>) {
        if let port {
            continuation.resume(returning: port)
            return
        }
        portWaiters.append(continuation)
        guard listener == nil else {
            return
        }
        let parameters = NWParameters.tcp
        // Only accept connections from this device. Listening on all interfaces would also ask for the permission to use the local network on iOS.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            failPortWaiters(error.localizedDescription)
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, listener === self.listener else {
                return
            }
            switch state {
            case .ready:
                guard let port = listener.port else {
                    return
                }
                Logger.info("Caption proxy listening on port \(port.rawValue)")
                self.port = port
                let waiters = self.portWaiters
                self.portWaiters = []
                waiters.forEach { $0.resume(returning: port) }
            case .failed(let error):
                Logger.error("Caption proxy listener failed: \(error)")
                listener.cancel()
                self.listener = nil
                self.port = nil
                self.failPortWaiters(error.localizedDescription)
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func failPortWaiters(_ message: String) {
        let waiters = portWaiters
        portWaiters = []
        waiters.forEach { $0.resume(throwing: ProxyError.listenerFailed(message)) }
    }

    // MARK: - Connections

    /// Only used on the queue of the proxy.
    private final class Connection: @unchecked Sendable {
        let id: Int
        let nwConnection: NWConnection
        var stream: Stream!
        var request = Data()
        var task: URLSessionDataTask?
        var demuxer: ARIBCaptionDemuxer?
        var demuxedBytes = 0
        var reportedCaptionStream: Bool?
        var reportedSeek = false
        var pendingBytes = 0
        var isDownloadPaused = false
        var isClosed = false

        init(id: Int, nwConnection: NWConnection) {
            self.id = id
            self.nwConnection = nwConnection
        }
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = Connection(id: nextConnectionID, nwConnection: nwConnection)
        nextConnectionID += 1
        connections[connection.id] = connection
        nwConnection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else {
                return
            }
            switch state {
            case .failed, .cancelled:
                self.close(connection)
            default:
                break
            }
        }
        nwConnection.start(queue: queue)
        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: Connection) {
        connection.nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self, !connection.isClosed else {
                return
            }
            if let data {
                connection.request.append(data)
            }
            if let end = connection.request.range(of: Data("\r\n\r\n".utf8)) {
                self.handleRequest(String(decoding: connection.request[..<end.lowerBound], as: UTF8.self), connection: connection)
            } else if isComplete || error != nil || connection.request.count > 65536 {
                self.close(connection)
            } else {
                self.receiveRequest(connection)
            }
        }
    }

    /// Notices when VLC closes the connection, e.g. to seek, since it sends nothing after the request.
    private func watchForClose(_ connection: Connection) {
        connection.nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] _, _, isComplete, error in
            guard let self, !connection.isClosed else {
                return
            }
            if isComplete || error != nil {
                self.close(connection)
            } else {
                self.watchForClose(connection)
            }
        }
    }

    private func handleRequest(_ head: String, connection: Connection) {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2, requestLine[0] == "GET" || requestLine[0] == "HEAD" else {
            respond(connection, status: "405 Method Not Allowed")
            return
        }
        let method = String(requestLine[0])
        let streamID = requestLine[1].split(separator: "/").first.map(String.init) ?? ""
        guard let stream = streams[streamID] else {
            respond(connection, status: "404 Not Found")
            return
        }
        connection.stream = stream
        var request = URLRequest(url: stream.upstreamURL)
        request.httpMethod = method
        for (name, value) in stream.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        // A compressed response would not match its content length and range.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                continue
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            if name.caseInsensitiveCompare("Range") == .orderedSame {
                request.setValue(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces), forHTTPHeaderField: "Range")
            }
        }
        Logger.info("Caption proxy connection \(connection.id): \(method) \(request.value(forHTTPHeaderField: "Range") ?? "whole stream")")
        let task = session.dataTask(with: request)
        connection.task = task
        connectionsByTask[task.taskIdentifier] = connection
        task.resume()
        watchForClose(connection)
    }

    /// Sends a response without a body and closes the connection.
    private func respond(_ connection: Connection, status: String) {
        let head = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.nwConnection.send(content: Data(head.utf8), isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.close(connection)
        })
    }

    private func close(_ connection: Connection) {
        guard !connection.isClosed else {
            return
        }
        connection.isClosed = true
        if let task = connection.task {
            task.cancel()
            connectionsByTask[task.taskIdentifier] = nil
        }
        connection.nwConnection.cancel()
        connections[connection.id] = nil
    }

    private func forward(_ data: Data, connection: Connection) {
        if let demuxer = connection.demuxer {
            demuxer.feed(data)
            connection.demuxedBytes += data.count
            if !demuxer.setsTimeBase, !connection.reportedSeek, let pcr = demuxer.firstPCR,
               let time = connection.stream.timeBase.time(of: pcr) {
                connection.reportedSeek = true
                Logger.info("Caption proxy connection \(connection.id) starts at \(time) ms")
                connection.stream.onSeek(time)
            }
            if demuxer.foundProgramMap {
                if connection.reportedCaptionStream != demuxer.foundCaptionStream {
                    connection.reportedCaptionStream = demuxer.foundCaptionStream
                    Logger.info("Caption proxy connection \(connection.id) \(demuxer.foundCaptionStream ? "has" : "has no") caption stream")
                    connection.stream.onCaptionStream(demuxer.foundCaptionStream)
                }
            } else if !demuxer.foundSync, connection.demuxedBytes > 1 << 20 {
                // Another container, such as MP4.
                Logger.info("Caption proxy connection \(connection.id) is not MPEG-TS")
                connection.demuxer = nil
                connection.stream.onCaptionStream(false)
            } else if connection.reportedCaptionStream == nil, connection.demuxedBytes > 16 << 20 {
                // The program map repeats several times a second, so it can't be read.
                Logger.info("Caption proxy connection \(connection.id) has no readable program map")
                connection.reportedCaptionStream = false
                connection.stream.onCaptionStream(false)
            }
        }
        connection.pendingBytes += data.count
        connection.nwConnection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !connection.isClosed else {
                return
            }
            if error != nil {
                self.close(connection)
                return
            }
            connection.pendingBytes -= data.count
            if connection.isDownloadPaused, connection.pendingBytes < Self.resumePendingBytes {
                connection.isDownloadPaused = false
                connection.task?.resume()
            }
        })
        // VLC stops reading when its buffer is full, e.g. while paused. Stop downloading instead of keeping the video in memory.
        if !connection.isDownloadPaused, connection.pendingBytes > Self.maxPendingBytes {
            connection.isDownloadPaused = true
            connection.task?.suspend()
        }
    }

    private func responseHead(for response: HTTPURLResponse) -> String {
        let reason: String
        switch response.statusCode {
        case 200:
            reason = "OK"
        case 206:
            reason = "Partial Content"
        case 416:
            reason = "Range Not Satisfiable"
        default:
            reason = "Error"
        }
        var head = "HTTP/1.1 \(response.statusCode) \(reason)\r\n"
        for name in ["Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"] {
            if let value = response.value(forHTTPHeaderField: name) {
                head += "\(name): \(value)\r\n"
            }
        }
        // Without a content length, the end of the connection ends the body.
        head += "Connection: close\r\n\r\n"
        return head
    }
}

extension CaptionStreamProxy: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let connection = connectionsByTask[dataTask.taskIdentifier], !connection.isClosed,
              let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        let status = response.statusCode
        let range = response.value(forHTTPHeaderField: "Content-Range") ?? ""
        Logger.info("Caption proxy connection \(connection.id): server replied \(status) \(range)")
        if dataTask.originalRequest?.httpMethod == "GET", status == 200 || status == 206 {
            let fromStart = status == 200 || range.hasPrefix("bytes 0-")
            if fromStart {
                connection.stream.onStart()
            }
            let stream: Stream = connection.stream
            let connectionID = connection.id
            let demuxer = ARIBCaptionDemuxer(timeBase: stream.timeBase, setsTimeBase: fromStart)
            demuxer.onCaption = { caption in
                stream.onCaption(caption, connectionID)
            }
            connection.demuxer = demuxer
        }
        connection.nwConnection.send(content: Data(responseHead(for: response).utf8), completion: .contentProcessed { _ in })
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let connection = connectionsByTask[dataTask.taskIdentifier], !connection.isClosed else {
            return
        }
        forward(data, connection: connection)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let connection = connectionsByTask[task.taskIdentifier], !connection.isClosed else {
            return
        }
        connectionsByTask[task.taskIdentifier] = nil
        connection.task = nil
        if let error {
            Logger.error("Caption proxy connection \(connection.id) failed: \(error.localizedDescription)")
            close(connection)
            return
        }
        connection.demuxer?.finish()
        Logger.info("Caption proxy connection \(connection.id) finished")
        connection.nwConnection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.close(connection)
        })
    }
}
#endif
