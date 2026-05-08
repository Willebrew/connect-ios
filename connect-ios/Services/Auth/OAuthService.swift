//
//  OAuthService.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  OAuth authentication service for Google, Apple, and GitHub
//

import Foundation
import AuthenticationServices
import Combine
import UIKit

class OAuthService: NSObject, ObservableObject {
    // MARK: - Properties
    private var currentProvider: String?
    private var authSession: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<OAuthResult, Error>?

    // MARK: - Types

    struct OAuthResult {
        let code: String
        let provider: String
        let state: String?
    }

    enum OAuthError: LocalizedError {
        case cancelled
        case invalidURL
        case invalidResponse
        case missingCode
        case stateMismatch
        case appleSignInFailed(Error)
        case webAuthFailed(Error)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Authentication was cancelled"
            case .invalidURL:
                return "Invalid authentication URL"
            case .invalidResponse:
                return "Invalid response from authentication server"
            case .missingCode:
                return "No authorization code received"
            case .stateMismatch:
                return "State parameter mismatch - possible security issue"
            case .appleSignInFailed(let error):
                return "Apple Sign In failed: \(error.localizedDescription)"
            case .webAuthFailed(let error):
                return "Authentication failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Google OAuth

    /// Initiates Google OAuth flow
    func signInWithGoogle() async throws -> OAuthResult {
        Logger.auth.debug("Starting Google OAuth flow")

        let state = OAuthConstants.googleState
        let authURL = OAuthConstants.googleOAuthURL(state: state)

        currentProvider = OAuthConstants.googleProvider

        // Use embedded web view with custom user agent to bypass Google's restriction
        return try await presentEmbeddedOAuthWebView(
            url: authURL,
            provider: OAuthConstants.googleProvider,
            expectedState: state
        )
    }

    // MARK: - Apple OAuth

    /// Initiates Apple OAuth flow
    func signInWithApple() async throws -> OAuthResult {
        Logger.auth.debug("Starting Apple OAuth flow")

        let state = OAuthConstants.appleState
        let authURL = OAuthConstants.appleOAuthURL(state: state)

        currentProvider = OAuthConstants.appleProvider

        return try await presentEmbeddedOAuthWebView(
            url: authURL,
            provider: OAuthConstants.appleProvider,
            expectedState: state
        )
    }

    // MARK: - GitHub OAuth

    /// Initiates GitHub OAuth flow
    func signInWithGitHub() async throws -> OAuthResult {
        Logger.auth.debug("Starting GitHub OAuth flow")

        let state = OAuthConstants.githubState
        let authURL = OAuthConstants.githubOAuthURL(state: state)

        currentProvider = OAuthConstants.githubProvider

        return try await presentEmbeddedOAuthWebView(
            url: authURL,
            provider: OAuthConstants.githubProvider,
            expectedState: state
        )
    }

    // MARK: - Web Authentication

    private func performWebAuthentication(
        url: URL,
        callbackURLScheme: String,
        provider: String,
        expectedState: String?
    ) async throws -> OAuthResult {
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                if let error = error {
                    if case ASWebAuthenticationSessionError.canceledLogin = error {
                        continuation.resume(throwing: OAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.webAuthFailed(error))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OAuthError.invalidResponse)
                    return
                }

                Logger.auth.debug("OAuth callback received: \(Logger.redactURL(callbackURL))")

                // Parse callback URL for code and state
                if let result = self?.parseOAuthCallback(
                    url: callbackURL,
                    provider: provider,
                    expectedState: expectedState
                ) {
                    do {
                        let oauthResult = try result.get()
                        continuation.resume(returning: oauthResult)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: OAuthError.invalidResponse)
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false // Allow SSO

            self.authSession = session
            DispatchQueue.main.async {
                session.start()
            }
        }
    }

    private func presentEmbeddedOAuthWebView(
        url: URL,
        provider: String,
        expectedState: String?
    ) async throws -> OAuthResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                guard let presenter = Self.topViewController() else {
                    continuation.resume(throwing: OAuthError.invalidResponse)
                    return
                }

                let controller = OAuthWebViewController(
                    startURL: url,
                    shouldHandleURL: { [weak self] callbackURL in
                        guard let self else { return false }
                        return self.shouldHandleCallback(url: callbackURL)
                    }
                )

                let navigationController = UINavigationController(rootViewController: controller)
                navigationController.modalPresentationStyle = .formSheet
                navigationController.isModalInPresentation = true

                controller.completion = { [weak self, weak navigationController] result in
                    guard let self else { return }
                    navigationController?.dismiss(animated: true) {
                        switch result {
                        case .success(let callbackURL):
                            Logger.auth.debug("OAuth callback intercepted by WebView: \(Logger.redactURL(callbackURL))")

                            let parseResult = self.parseOAuthCallback(
                                url: callbackURL,
                                provider: provider,
                                expectedState: expectedState
                            )
                            continuation.resume(
                                with: parseResult.mapError { $0 }
                            )
                        case .failure(let error):
                            if let oauthError = error as? OAuthError {
                                continuation.resume(throwing: oauthError)
                            } else {
                                continuation.resume(throwing: OAuthError.webAuthFailed(error))
                            }
                        }
                    }
                }
                presenter.present(navigationController, animated: true)
            }
        }
    }

    private func shouldHandleCallback(url: URL) -> Bool {
        // Handle custom URL scheme
        if url.scheme == OAuthConstants.urlScheme {
            return true
        }

        guard let host = url.host else {
            return false
        }

        // Intercept any comma.ai domain with a code parameter
        let isCommaDomain = host.contains("comma.ai")
        guard isCommaDomain else {
            return false
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            return false
        }

        return queryItems.contains(where: { $0.name == "code" })
    }

    private static func topViewController(from root: UIViewController? = nil) -> UIViewController? {
        let rootController: UIViewController?
        if let root {
            rootController = root
        } else {
            rootController = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        }

        if let navigationController = rootController as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabController = rootController as? UITabBarController,
           let selected = tabController.selectedViewController {
            return topViewController(from: selected)
        }

        if let presented = rootController?.presentedViewController {
            return topViewController(from: presented)
        }

        return rootController
    }

    // MARK: - Callback Parsing

    /// Parses OAuth callback URL and extracts code
    func parseOAuthCallback(
        url: URL,
        provider: String,
        expectedState: String? = nil
    ) -> Result<OAuthResult, OAuthError> {
        // Extract query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            return .failure(.invalidResponse)
        }

        // Get code parameter
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            return .failure(.missingCode)
        }

        // Get state and provider from query (comma.ai returns these)
        let receivedState = queryItems.first(where: { $0.name == "state" })?.value
        let receivedProvider = queryItems.first(where: { $0.name == "provider" })?.value

        // Verify state if expected and provided
        // If state is missing but provider matches, allow it (comma.ai's Apple OAuth quirk)
        if let expectedState = expectedState {
            if let receivedState = receivedState {
                // State present - verify it matches
                if receivedState != expectedState {
                    Logger.auth.error("State mismatch: expected '\(expectedState)', got '\(receivedState)'")
                    return .failure(.stateMismatch)
                }
            } else {
                // State missing - check if provider matches as fallback verification
                let expectedProvider = provider == OAuthConstants.appleProvider ? "a" :
                                     provider == OAuthConstants.googleProvider ? "g" :
                                     provider == OAuthConstants.githubProvider ? "h" : nil

                if receivedProvider != expectedProvider {
                    Logger.auth.error("State missing and provider mismatch: expected '\(expectedProvider ?? "nil")', got '\(receivedProvider ?? "nil")'")
                    return .failure(.stateMismatch)
                } else {
                    Logger.auth.debug("State missing but provider '\(receivedProvider ?? "nil")' matches - allowing (comma.ai quirk)")
                }
            }
        }

        return .success(OAuthResult(
            code: code,
            provider: provider,
            state: receivedState
        ))
    }
}

// MARK: - ASAuthorizationControllerDelegate (Apple Sign In)

extension OAuthService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            // Extract authorization code from Apple credential
            guard let authorizationCode = appleIDCredential.authorizationCode,
                  let codeString = String(data: authorizationCode, encoding: .utf8) else {
                continuation?.resume(throwing: OAuthError.missingCode)
                continuation = nil
                return
            }

            let result = OAuthResult(
                code: codeString,
                provider: OAuthConstants.appleProvider,
                state: appleIDCredential.state
            )

            continuation?.resume(returning: result)
            continuation = nil
        } else {
            continuation?.resume(throwing: OAuthError.invalidResponse)
            continuation = nil
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                continuation?.resume(throwing: OAuthError.cancelled)
            default:
                continuation?.resume(throwing: OAuthError.appleSignInFailed(error))
            }
        } else {
            continuation?.resume(throwing: OAuthError.appleSignInFailed(error))
        }
        continuation = nil
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    @objc func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        // Fallback: return any available window
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension OAuthService: ASAuthorizationControllerPresentationContextProviding {
    @objc func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the key window for Apple Sign In
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        // Fallback: return any available window
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}
