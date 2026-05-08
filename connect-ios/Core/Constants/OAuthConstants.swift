//
//  OAuthConstants.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  OAuth configuration for comma.ai authentication
//  Matches webapp @commaai/my-comma-auth configuration
//

import Foundation

enum OAuthConstants {
    // Custom URL scheme for OAuth callbacks
    static let urlScheme = "commaconnect"
    static let redirectPath = "oauth-callback"
    static let redirectURI = "\(urlScheme)://\(redirectPath)"
    private static let serviceHost = "connect.comma.ai"
    static let serviceState = "service,\(serviceHost)"

    // OAuth endpoints
    static let authPath = "/auth/"

    // MARK: - Google OAuth
    static let googleClientID = "45471411055-ornt4svd2miog6dnopve7qtmh5mnu6id.apps.googleusercontent.com"
    static let googleAuthEndpoint = "https://accounts.google.com/o/oauth2/auth"
    static let googleRedirectURI = "https://api.comma.ai/v2/auth/g/redirect/"
    static let googleScope = "openid email profile"
    static let googleProvider = "google"
    static let googleState = serviceState

    // MARK: - Apple OAuth
    static let appleClientID = "ai.comma.login"
    static let appleAuthEndpoint = "https://appleid.apple.com/auth/authorize"
    static let appleRedirectURI = "https://api.comma.ai/v2/auth/a/redirect/"
    static let appleScopes = "name email"
    static let appleProvider = "apple"
    static let appleState = serviceState

    // MARK: - GitHub OAuth
    static let githubClientID = "28c4ecb54bb7272cb5a4"
    static let githubAuthEndpoint = "https://github.com/login/oauth/authorize"
    static let githubRedirectURI = "https://api.comma.ai/v2/auth/h/redirect/"
    static let githubScope = "read:user user:email"
    static let githubProvider = "github"
    static let githubState = serviceState

    // MARK: - Token Exchange
    // Token exchange endpoint (matches webapp)
    static let tokenExchangeEndpoint = "/v2/auth/"

    // MARK: - OAuth URL Construction

    /// Builds Google OAuth URL
    static func googleOAuthURL(state: String = googleState) -> URL {
        var components = URLComponents(string: googleAuthEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: googleClientID),
            URLQueryItem(name: "redirect_uri", value: googleRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: googleScope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        return components.url!
    }

    /// Builds Apple OAuth URL
    static func appleOAuthURL(state: String = appleState) -> URL {
        var components = URLComponents(string: appleAuthEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appleClientID),
            URLQueryItem(name: "redirect_uri", value: appleRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: appleScopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_mode", value: "form_post")
            // Apple requires form_post when requesting name/email scopes
            // comma.ai server converts POST to GET redirect with query params
        ]
        return components.url!
    }

    /// Builds GitHub OAuth URL
    static func githubOAuthURL(state: String = githubState) -> URL {
        var components = URLComponents(string: githubAuthEndpoint)!
        let queryItems = [
            URLQueryItem(name: "client_id", value: githubClientID),
            URLQueryItem(name: "redirect_uri", value: githubRedirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: githubScope)
        ]

        components.queryItems = queryItems
        return components.url!
    }
}
