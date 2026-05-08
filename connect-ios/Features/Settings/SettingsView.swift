//
//  SettingsView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  App settings and preferences
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingSignOutConfirmation = false
    @AppStorage("haptic_feedback_enabled") private var hapticFeedbackEnabled = true
    @AppStorage("map_lock_north") private var mapLockNorth = false
    @AppStorage("map_color_coded_route") private var mapColorCodedRoute = false

    var body: some View {
        NavigationStack {
            List {
                // Preferences Section
                Section("Preferences") {
                    Toggle("Haptic Feedback", isOn: Binding(
                        get: { hapticFeedbackEnabled },
                        set: { newValue in
                            hapticFeedbackEnabled = newValue
                            // Provide haptic when enabling (not when disabling)
                            if newValue {
                                HapticManager.toggle()
                            }
                        }
                    ))
                }

                // Drive Viewer Section
                Section {
                    Toggle("Lock Map to North", isOn: Binding(
                        get: { mapLockNorth },
                        set: { newValue in
                            HapticManager.toggle()
                            mapLockNorth = newValue
                        }
                    ))

                    Toggle("Color-Coded Route", isOn: Binding(
                        get: { mapColorCodedRoute },
                        set: { newValue in
                            HapticManager.toggle()
                            mapColorCodedRoute = newValue
                        }
                    ))
                } header: {
                    Text("Drive Viewer")
                } footer: {
                    Text("These settings apply to the drive viewer map. Color-Coded Route shows engagement status colors on the route path.")
                }

                // Units Section
                Section("Units") {
                    Picker("Distance", selection: Binding(
                        get: { appState.distanceUnit },
                        set: { newValue in
                            HapticManager.selection()
                            appState.distanceUnit = newValue
                            appState.saveSettings()
                        }
                    )) {
                        Text("Miles").tag(AppConstants.DistanceUnit.miles)
                        Text("Kilometers").tag(AppConstants.DistanceUnit.kilometers)
                    }
                }

                // Account Section
                Section("Account") {
                    if let profile = appState.authService.currentProfile {
                        // Only show fields that have values
                        if let email = profile.email, !email.isEmpty {
                            LabeledContent("Email", value: email)
                        }
                        if let username = profile.username, !username.isEmpty {
                            LabeledContent("Username", value: username)
                        }
                        if let userId = profile.userId, !userId.isEmpty {
                            LabeledContent("User ID", value: userId)
                        }
                    }

                    Button(role: .destructive) {
                        HapticManager.buttonPress()
                        showingSignOutConfirmation = true
                    } label: {
                        Label("Sign Out", systemImage: "arrow.right.square")
                            .foregroundStyle(.red)
                    }
                }

                // About Section
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")

                    Link(destination: URL(string: "https://comma.ai")!) {
                        HStack {
                            Text("comma.ai")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .alert(
                "Are you sure you want to sign out?",
                isPresented: $showingSignOutConfirmation
            ) {
                Button("Sign Out", role: .destructive) {
                    HapticManager.delete()
                    appState.logout()
                }
                Button("Cancel", role: .cancel) {
                    HapticManager.cancel()
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState.shared)
}
