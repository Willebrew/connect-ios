//
//  MainTabView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Main tab navigation
//

import SwiftUI
import os

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Drives", systemImage: "car.fill")
                }
                .tag(0)

            DevicesView()
                .tabItem {
                    Label("Devices", image: "comma_devices_icon")
                }
                .tag(1)

            DeviceLocatorView(apiClient: appState.apiClient)
                .tabItem {
                    Label("Find", systemImage: "location.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(Color.themeGreen)
        .onChange(of: selectedTab) { _, _ in
            HapticManager.selection()
        }
        .task(id: appState.authService.isAuthenticated) {
            // Load data when authenticated
            // This runs when isAuthenticated changes from false -> true (login)
            // or when the view first appears
            guard appState.authService.isAuthenticated else {
                Logger.ui.debug("MainTabView: Not authenticated, skipping data load")
                return
            }

            Logger.data.debug("MainTabView: Loading devices")
            await appState.loadDevices()

            if let deviceId = appState.selectedDeviceId {
                Logger.data.debug("MainTabView: Loading routes for device \(deviceId)")
                await appState.loadRoutes()
                Logger.data.debug("MainTabView: Loaded \(appState.routes.count) routes")
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState.shared)
}
