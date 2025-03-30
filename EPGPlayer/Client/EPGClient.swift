//
//  EPGClient.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/27.
//
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
    
    init(endpoint: URL? = nil) {
        guard let endpoint else {
            apiClient = nil
            self.endpoint = nil
            return
        }
        self.endpoint = endpoint
        let session = URLSession(configuration: .default, delegate: Delegate(), delegateQueue: OperationQueue.main)
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
