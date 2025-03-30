//
//  AuthWebView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/03/28.
//
import SwiftUI
import WebKit

struct AuthWebView: UIViewRepresentable {

    let url: URL
    
    @Binding var isAuthenticaing: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, expectedUrl: url)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        
        let parent: AuthWebView
        let expectedUrl: URL
        
        init(parent: AuthWebView, expectedUrl: URL) {
            self.parent = parent
            self.expectedUrl = expectedUrl
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if webView.url == expectedUrl {
                parent.isAuthenticaing = false
            }
        }
    }
    
}
