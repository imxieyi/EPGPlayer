//
//  AuthWebView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/28.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import WebKit

struct AuthWebView: UIViewRepresentable {
    let url: URL
    let expectedContentType: String
    
    @Binding var isAuthenticaing: Bool
    
    #if !os(macOS)
    func makeUIView(context: Context) -> WKWebView {
        return makeView(context: context)
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
    #else
    func makeNSView(context: Context) -> WKWebView {
        return makeView(context: context)
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
    }
    #endif
    
    func makeView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, expectedUrl: url, expectedContentType: expectedContentType)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AuthWebView
        let expectedUrl: URL
        let expectedContentType: String
        
        private var contentType: String?
        
        init(parent: AuthWebView, expectedUrl: URL, expectedContentType: String) {
            self.parent = parent
            self.expectedUrl = expectedUrl
            self.expectedContentType = expectedContentType
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            contentType = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
            return .allow
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let contentType else {
                return
            }
            print("Webview content type: \(contentType)")
            if webView.url == expectedUrl && contentType.lowercased().hasPrefix(expectedContentType) {
                parent.isAuthenticaing = false
            }
        }
    }
    
}
