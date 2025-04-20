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
        #if !os(macOS)
        // Override UA to workaround Google's restricted_client error.
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/135.0.7049.83 Mobile/15E148 Safari/604.1"
        #endif
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
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
            Logger.info("Webview content type: \(contentType)")
            if (webView.url?.absoluteString.hasPrefix(expectedUrl.absoluteString) ?? false) && contentType.lowercased().hasPrefix(expectedContentType) {
                parent.isAuthenticaing = false
            }
        }
    }
    
}
