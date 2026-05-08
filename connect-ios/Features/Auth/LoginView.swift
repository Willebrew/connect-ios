//
//  LoginView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Login view with OAuth provider buttons
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @StateObject private var oauthService = OAuthService()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top section with logo
                VStack(spacing: 20) {
                    Spacer()
                        .frame(height: 80)

                    Image("comma-ai-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)

                    Text("Comma Connect")
                        .font(.system(size: 32, weight: .thin))
                        .foregroundStyle(.white)
                        .tracking(2)

                    Text("Sign in to access your devices")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)

                    Spacer()
                        .frame(height: 60)
                }

                // OAuth Provider Buttons
                VStack(spacing: 14) {
                    // Google Sign In
                    Button {
                        HapticManager.buttonPress()
                        Task {
                            await signIn(with: .google)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image("google-logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .frame(width: 20)
                            Text("Continue with Google")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.white, in: RoundedRectangle(cornerRadius: 28))
                        .foregroundStyle(.black)
                    }
                    .disabled(isLoading)

                    // Sign in with Apple
                    Button {
                        HapticManager.buttonPress()
                        Task {
                            await signIn(with: .apple)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image("apple-logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .frame(width: 20)
                                .offset(x: -5)
                            Text("Continue with Apple")
                                .font(.system(size: 17, weight: .semibold))
                                .offset(x: -5)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.white, in: RoundedRectangle(cornerRadius: 28))
                        .foregroundStyle(.black)
                    }
                    .disabled(isLoading)

                    // GitHub Sign In
                    Button {
                        HapticManager.buttonPress()
                        Task {
                            await signIn(with: .github)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image("github-logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .frame(width: 20)
                            Text("Continue with GitHub")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.white, in: RoundedRectangle(cornerRadius: 28))
                        .foregroundStyle(.black)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal, 32)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, 24)
                }

                Spacer()
                    .frame(height: 40)

                // Divider
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(height: 1)
                    Text("or")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 40)

                // Demo Mode Button
                Button {
                    HapticManager.buttonPress()
                    Task {
                        await loginWithDemoAccount()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "eye")
                            .font(.system(size: 17, weight: .medium))
                        Text("Explore Demo Mode")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 28))
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .disabled(isLoading)
                .padding(.horizontal, 32)

                // Info Text
                Text("Try the app with sample data without signing in")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 48)

                Spacer()

                // Close button
                Button {
                    HapticManager.buttonPress()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.05), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .disabled(isLoading)
                .padding(.bottom, 40)
            }
        }
        .alert("Authentication Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: - Authentication Methods

    enum Provider {
        case google, apple, github
    }

    @MainActor
    private func signIn(with provider: Provider) async {
        Logger.auth.debug("Sign in button tapped for provider: \(provider)")
        isLoading = true
        errorMessage = nil

        do {
            Logger.auth.debug("Starting OAuth flow for \(provider)")
            let result: OAuthService.OAuthResult

            switch provider {
            case .google:
                result = try await oauthService.signInWithGoogle()
            case .apple:
                result = try await oauthService.signInWithApple()
            case .github:
                result = try await oauthService.signInWithGitHub()
            }

            Logger.auth.debug("OAuth returned code (prefix: \(result.code.prefix(20))...) for provider: \(result.provider)")

            // Exchange code for token
            await exchangeTokenAndLogin(code: result.code, provider: result.provider, state: result.state)

        } catch {
            Logger.auth.error("OAuth error in signIn()", error: error)
            await MainActor.run {
                isLoading = false
                HapticManager.actionError()
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil

        do {
            let authorization = try result.get()

            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let authorizationCode = appleIDCredential.authorizationCode,
                  let codeString = String(data: authorizationCode, encoding: .utf8) else {
                throw OAuthService.OAuthError.missingCode
            }

            // Exchange code for token
            await exchangeTokenAndLogin(
                code: codeString,
                provider: OAuthConstants.appleProvider,
                state: OAuthConstants.appleState
            )

        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func exchangeTokenAndLogin(code: String, provider: String, state: String?) async {
        Logger.auth.debug("Starting token exchange - provider: \(provider), state: \(state ?? "none")")

        do {
            // Apple: code is already processed, use exchangeToken()
            // Google/GitHub: code is raw from provider, use authenticate()
            let token: String
            if provider == OAuthConstants.appleProvider {
                token = try await appState.apiClient.exchangeToken(code: code, provider: provider)
            } else {
                token = try await appState.apiClient.authenticate(code: code, provider: provider, state: state)
            }
            Logger.auth.debug("Got token (prefix: \(token.prefix(20))...)")

            if let productionClient = appState.apiClient as? ProductionAPIClient {
                productionClient.setAuthToken(token)
                let profile = try await productionClient.getProfile()

                // Save token and update auth state only after profile succeeds
                try AuthService.shared.login(withToken: token)
                AuthService.shared.setProfile(profile)
            } else {
                try AuthService.shared.login(withToken: token)
            }

            await MainActor.run {
                isLoading = false
                HapticManager.actionSuccess()
                dismiss()
            }

        } catch {
            Logger.auth.error("Token exchange failed", error: error)
            await MainActor.run {
                isLoading = false
                HapticManager.actionError()
                errorMessage = "Failed to authenticate: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    @MainActor
    private func loginWithDemoAccount() async {
        Logger.auth.info("Logging in with demo account")
        isLoading = true
        errorMessage = nil

        do {
            let token = AppConstants.demoToken

            // Always use production client for demo mode
            let productionClient: ProductionAPIClient
            if let existingClient = appState.apiClient as? ProductionAPIClient {
                productionClient = existingClient
            } else {
                Logger.auth.debug("Switching to production client for demo login")
                productionClient = ProductionAPIClient()
                appState.apiClient = productionClient
            }

            // Set up unauthorized handler
            productionClient.setUnauthorizedHandler { [weak appState] in
                DispatchQueue.main.async {
                    Logger.auth.error("Unauthorized access detected - logging out")
                    appState?.handleUnauthorized()
                }
            }

            // Set the demo token and fetch profile
            productionClient.setAuthToken(token)
            let profile = try await productionClient.getProfile()
            try AuthService.shared.login(withToken: token)
            AuthService.shared.setProfile(profile)

            Logger.auth.info("Demo account login successful")

            await MainActor.run {
                isLoading = false
                HapticManager.actionSuccess()
                dismiss()
            }

        } catch {
            Logger.auth.error("Demo login error", error: error)
            await MainActor.run {
                isLoading = false
                HapticManager.actionError()
                errorMessage = "Failed to login with demo account: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState.shared)
}
