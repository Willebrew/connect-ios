//
//  OAuthWebViewController.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Lightweight in-app browser for OAuth providers that don't support custom schemes.
//

import UIKit
import WebKit

final class OAuthWebViewController: UIViewController {
    typealias Completion = (Result<URL, Error>) -> Void
    typealias URLPredicate = (URL) -> Bool

    private let startURL: URL
    private let shouldHandleURL: URLPredicate
    var completion: Completion?

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Set custom user agent to bypass Google's embedded WebView restriction
        // Use Safari's user agent to appear as a regular browser
        configuration.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = true
        return view
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private var didFinish = false

    init(startURL: URL, shouldHandleURL: @escaping URLPredicate) {
        self.startURL = startURL
        self.shouldHandleURL = shouldHandleURL
        super.init(nibName: nil, bundle: nil)
        title = "Sign In"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationItems()
        layoutWebView()
        loadInitialRequest()
    }

    private func setupNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .done,
            target: self,
            action: #selector(closeTapped)
        )

        let reloadButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(reloadTapped)
        )
        reloadButton.tintColor = .label
        navigationItem.rightBarButtonItem = reloadButton
    }

    private func layoutWebView() {
        view.addSubview(webView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadInitialRequest() {
        activityIndicator.startAnimating()
        webView.load(URLRequest(url: startURL))
    }

    @objc private func closeTapped() {
        finish(with: .failure(OAuthService.OAuthError.cancelled))
    }

    @objc private func reloadTapped() {
        webView.reload()
    }

    private func finish(with result: Result<URL, Error>) {
        guard !didFinish else { return }
        didFinish = true
        completion?(result)
    }
}

extension OAuthWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if shouldHandleURL(url) {
            decisionHandler(.cancel)
            finish(with: .success(url))
        } else {
            decisionHandler(.allow)
        }
    }
}
