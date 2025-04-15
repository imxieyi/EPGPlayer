//
//  AsyncImageWithHeaders.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/15.
//

import SwiftUI
import CachedAsyncImage

struct AsyncImageWithHeaders<Content: View>: View {
    
    private let url: URL
    
    private let headers: [String: String]
    
    private let content: (AsyncImagePhase) -> Content
    
    init(url: URL, headers: [String: String], @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.headers = headers
        self.content = content
    }
    
    var body: some View {
        var request = URLRequest(url: url)
        headers.forEach { (key: String, value: String) in
            request.setValue(value, forHTTPHeaderField: key)
        }
        return CachedAsyncImage(urlRequest: request, urlCache: .imageCache, content: content)
    }
}
