//
//  WebViewOAuthHandler.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  WKWebView-based OAuth handler for intercepting web redirects
//

import SwiftUI
import WebKit
import Combine
import os

class WebViewOAuthHandler: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var isLoading = false
    @Published var webView: WKWebView?

    private var completion: ((Result<OAuthResult, Error>) -> Void)?
    private let targetHost = "connect.comma.ai"

    struct OAuthResult {
        let code: String
        let provider: String
    }

    enum OAuthError: LocalizedError {
        case cancelled
        case missingCode
        case webViewFailed(Error)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Authentication was cancelled"
            case .missingCode:
                return "No authorization code received"
            case .webViewFailed(let error):
                return "Authentication failed: \(error.localizedDescription)"
            }
        }
    }

    func startOAuth(url: URL, completion: @escaping (Result<OAuthResult, Error>) -> Void) {
        Logger.auth.debug("Starting OAuth")

        self.completion = completion

        // Create WebView on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            self.webView = webView

            self.isLoading = true

            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    func cancel() {
        Logger.auth.debug("OAuth cancelled")
        webView?.stopLoading()
        completion?(.failure(OAuthError.cancelled))
        cleanup()
    }

    private func cleanup() {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.stopLoading()
            self?.webView?.navigationDelegate = nil
            self?.webView = nil
            self?.completion = nil
            self?.isLoading = false
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let urlHost = url.host

        Logger.auth.debug("WebView navigation")

        // Check if this is the redirect to connect.comma.ai with the code
        if urlHost == targetHost {
            Logger.auth.debug("Intercepted redirect to \(targetHost)")

            // Parse the code from query parameters
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  let queryItems = components.queryItems,
                  let code = queryItems.first(where: { $0.name == "code" })?.value else {
                Logger.auth.error("No code found in URL")
                decisionHandler(.cancel)

                // Call completion on main thread after a delay to avoid crashes
                DispatchQueue.main.async { [weak self] in
                    self?.completion?(.failure(OAuthError.missingCode))
                    self?.cleanup()
                }
                return
            }

            let provider = queryItems.first(where: { $0.name == "provider" })?.value ?? "github"

            Logger.auth.debug("Found authorization code for provider: \(provider)")

            // Don't load the website - we have what we need
            decisionHandler(.cancel)

            let result = OAuthResult(code: code, provider: provider)

            // Call completion on main thread after a delay to avoid crashes
            DispatchQueue.main.async { [weak self] in
                self?.completion?(.success(result))
                self?.cleanup()
            }
            return
        }

        // Allow all other navigation
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.auth.debug("WebView page finished loading")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.auth.error("WebView navigation failed", error: error)
        completion?(.failure(OAuthError.webViewFailed(error)))
        cleanup()
    }
}

// SwiftUI wrapper
struct WebViewOAuth: UIViewRepresentable {
    @ObservedObject var handler: WebViewOAuthHandler

    func makeUIView(context: Context) -> WKWebView {
        // Return the handler's webView, or create an empty placeholder
        if let webView = handler.webView {
            return webView
        } else {
            // Placeholder - will be replaced when webView is ready
            return WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        }
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // SwiftUI will call this when @Published webView changes
        // But we can't swap out the underlying UIView, so we ensure
        // makeUIView gets the right instance on first call
    }
}
