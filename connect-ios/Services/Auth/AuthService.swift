//
//  AuthService.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Authentication service handling login and token management
//

import Foundation
import os

@Observable
final class AuthService {
    static let shared = AuthService()

    var isAuthenticated = false
    var currentToken: String?
    var currentProfile: UserProfile?

    private let keychainKey = "comma_auth_token"
    private let profileKey = "user_profile"

    /// Returns true if currently using the demo account (read-only mode)
    var isDemoMode: Bool {
        guard let token = currentToken else { return false }
        return token == AppConstants.demoToken
    }

    private init() {
        loadSavedState()
    }

    private func loadSavedState() {
        // Try to load saved token
        do {
            let token = try KeychainHelper.shared.readString(forKey: keychainKey)
            currentToken = token
            isAuthenticated = true

            // Load saved profile if available
            if let profileData = UserDefaults.standard.data(forKey: profileKey),
               let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
                currentProfile = profile
                let displayName = profile.email ?? profile.username ?? profile.userId ?? "unknown"
                Logger.auth.debug("Loaded saved user profile: \(displayName)")
            }
        } catch {
            isAuthenticated = false
        }
    }

    func login(withToken token: String) throws {
        currentToken = token
        isAuthenticated = true

        if let payload = try? JWTHelper.parseToken(token) {
            let identity = payload["identity"] ?? payload["sub"] ?? "unknown"
            let exp = payload["exp"] ?? "unknown"
            Logger.auth.debug("Login token identity: \(identity), exp: \(exp)")
        }

        // Save to keychain
        try KeychainHelper.shared.save(token, forKey: keychainKey)
    }

    func logout() {
        isAuthenticated = false
        currentToken = nil
        currentProfile = nil

        // Clear keychain and saved profile
        try? KeychainHelper.shared.delete(forKey: keychainKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
    }

    func setProfile(_ profile: UserProfile) {
        currentProfile = profile

        // Persist profile to UserDefaults
        if let profileData = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(profileData, forKey: profileKey)
            let displayName = profile.email ?? profile.username ?? profile.userId ?? "unknown"
            Logger.auth.debug("Saved user profile: \(displayName)")
        }
    }
}
