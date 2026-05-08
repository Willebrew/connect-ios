//
//  WelcomeView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Welcome screen with demo mode and login options
//

import SwiftUI
import os

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingLogin = false
    @State private var isLoadingDemo = false

    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo and title
                VStack(spacing: 24) {
                    Image("comma-ai-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)

                    VStack(spacing: 8) {
                        Text("Comma Connect")
                            .font(.system(size: 36, weight: .thin))
                            .foregroundStyle(.white)
                            .tracking(2)

                        Text("Your openpilot companion")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    Button {
                        HapticManager.buttonPress()
                        isShowingLogin = true
                    } label: {
                        Text("Sign In")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.white, in: RoundedRectangle(cornerRadius: 28))
                            .foregroundStyle(.black)
                    }

                    Button {
                        HapticManager.buttonPress()
                        Task {
                            await loginWithDemoAccount()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isLoadingDemo {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text("Explore Demo")
                                .font(.system(size: 17, weight: .medium))
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
                    .disabled(isLoadingDemo)
                }
                .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 100)
            }
        }
        .fullScreenCover(isPresented: $isShowingLogin) {
            LoginView()
                .environment(appState)
        }
    }

    @MainActor
    private func loginWithDemoAccount() async {
        Logger.auth.debug("Logging in with demo account")
        isLoadingDemo = true

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
                    Logger.auth.debug("Unauthorized access detected - logging out")
                    appState?.handleUnauthorized()
                }
            }

            // Set the demo token and fetch profile
            productionClient.setAuthToken(token)
            let profile = try await productionClient.getProfile()
            try AuthService.shared.login(withToken: token)
            AuthService.shared.setProfile(profile)

            HapticManager.actionSuccess()

        } catch {
            Logger.auth.error("Demo login failed", error: error)
            HapticManager.actionError()
        }
        isLoadingDemo = false
    }
}

#Preview {
    WelcomeView()
        .environment(AppState.shared)
}
