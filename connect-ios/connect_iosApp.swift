//
//  connect_iosApp.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//

import SwiftUI
import os

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait // Default to portrait-only

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

// MARK: - App

@main
struct connect_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState.shared
    @State private var networkMonitor = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(networkMonitor)
                .preferredColorScheme(.dark) // Force dark mode for glass morphism
                .onOpenURL { url in
                    handleOAuthCallback(url: url)
                }
        }
    }

    // MARK: - OAuth Callback Handling

    private func handleOAuthCallback(url: URL) {
        Logger.auth.debug("Received OAuth callback")

        // Check if this is our OAuth callback
        guard url.scheme == OAuthConstants.urlScheme else {
            Logger.auth.debug("Unknown URL scheme: \(url.scheme ?? "nil")")
            return
        }

        // Parse the callback
        let oauthService = OAuthService()

        // Extract provider from URL path or query
        // The URL should be like: commaconnect://oauth-callback?code=XXX&state=YYY&provider=google
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            Logger.auth.error("Failed to parse URL components")
            return
        }

        // Get provider from query parameter
        guard let provider = queryItems.first(where: { $0.name == "provider" })?.value else {
            Logger.auth.error("No provider in callback URL")
            return
        }

        // Parse the OAuth result
        let result = oauthService.parseOAuthCallback(
            url: url,
            provider: provider
        )

        switch result {
        case .success(let oauthResult):
            Logger.auth.debug("Parsed OAuth callback for \(oauthResult.provider)")
            // Exchange code for token
            Task {
                await exchangeTokenAndLogin(
                    code: oauthResult.code,
                    provider: oauthResult.provider,
                    state: oauthResult.state
                )
            }
        case .failure(let error):
            Logger.auth.error("Failed to parse OAuth callback", error: error)
        }
    }

    private func exchangeTokenAndLogin(code: String, provider: String, state: String?) async {
        do {
            Logger.auth.debug("Exchanging authorization code for token")

            // Exchange authorization code for JWT token
            let token = try await appState.apiClient.authenticate(code: code, provider: provider, state: state)

            // Always switch to production client when logging in with OAuth
            // This ensures we're not using demo client after logout
            let productionClient: ProductionAPIClient
            if let existingClient = appState.apiClient as? ProductionAPIClient {
                productionClient = existingClient
            } else {
                Logger.auth.debug("Switching from demo to production client for OAuth login")
                productionClient = ProductionAPIClient()
                await MainActor.run {
                    appState.apiClient = productionClient
                }
            }

            // Set up unauthorized handler
            productionClient.setUnauthorizedHandler { [weak appState] in
                DispatchQueue.main.async {
                    Logger.auth.debug("Unauthorized access detected - logging out")
                    appState?.handleUnauthorized()
                }
            }

            // Set the auth token and fetch profile
            productionClient.setAuthToken(token)
            let profile = try await productionClient.getProfile()
            try AuthService.shared.login(withToken: token)
            AuthService.shared.setProfile(profile)
            let displayName = profile.username ?? profile.email ?? profile.id
            Logger.auth.debug("Fetched user profile: \(displayName)")

        } catch {
            Logger.auth.error("Authentication failed", error: error)
            await MainActor.run {
                // Show error to user
            }
        }
    }
}
