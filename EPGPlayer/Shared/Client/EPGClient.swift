//
//  EPGClient.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/27.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import OpenAPIURLSession

class EPGClient: ObservableObject {
    private let apiClient: (any APIProtocol)?
    var api: any APIProtocol {
        get throws {
            if let apiClient {
                return apiClient
            }
            throw EPGClientError.notInitialized
        }
    }
    
    let endpoint: URL!
    let headers: [String: String]
    
    init(endpoint: URL? = nil, headers: [String: String] = [:]) {
        self.headers = headers
        guard let endpoint else {
            apiClient = nil
            self.endpoint = nil
            return
        }
        self.endpoint = endpoint
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = headers
        let session = URLSession(configuration: configuration, delegate: Delegate(), delegateQueue: OperationQueue.main)
        apiClient = Client(serverURL: endpoint, transport: URLSessionTransport(configuration: URLSessionTransport.Configuration(session: session)))
    }
    
    final class Delegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
            return nil
        }
    }
    
}

enum EPGClientError: LocalizedError {
    case notInitialized
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "EPGClient not initialized."
        }
    }
}
