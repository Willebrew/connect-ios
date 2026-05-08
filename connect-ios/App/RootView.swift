//
//  RootView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Root view handling authentication state
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var isLoading = true

    var body: some View {
        ZStack {
            // Main content
            Group {
                if appState.authService.isAuthenticated {
                    MainTabView()
                } else {
                    WelcomeView()
                }
            }
            .opacity(isLoading ? 0 : 1)

            // Loading splash screen
            if isLoading {
                Color.black
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    Image("comma-ai-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)

                    Spacer()

                    Text("Comma Connect")
                        .font(.system(size: 24, weight: .thin))
                        .foregroundStyle(.white)
                        .tracking(2)
                        .padding(.bottom, 60)
                }
            }
        }
        .task {
            // Show splash for minimum 1 second
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            withAnimation(.easeInOut(duration: 0.4)) {
                isLoading = false
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState.shared)
}
