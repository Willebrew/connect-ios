//
//  DevicesView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Device list and management
//

import SwiftUI
import os
import WidgetKit

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct DevicesView: View {
    @Environment(AppState.self) private var appState
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var deviceStats: [String: DeviceStats] = [:]
    @State private var isLoadingStats = false
    @State private var selectedDeviceForSnapshot: Device?
    @State private var selectedDeviceForSettings: Device?
    @State private var qrScannerTrigger: UUID?
    @State private var showingErrorAlert = false
    @State private var hasUserDismissedError = false
    @State private var showingOfflineAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Network error banner (inline)
                        if let error = appState.error, showingErrorAlert {
                            errorBanner(error)
                        }

                        if appState.devices.isEmpty && !appState.isLoadingDevices {
                            emptyState
                        } else if appState.devices.isEmpty && appState.isLoadingDevices {
                            // Show skeleton loaders on initial load
                            ForEach(0..<3, id: \.self) { _ in
                                DeviceRowSkeleton()
                            }
                        } else {
                            ForEach(appState.devices) { device in
                                DeviceRow(
                                    device: device,
                                    stats: deviceStats[device.dongleId],
                                    onSnapshotTapped: {
                                        selectedDeviceForSnapshot = device
                                    },
                                    onSettingsTapped: {
                                        selectedDeviceForSettings = device
                                    }
                                )
                                .onTapGesture {
                                    HapticManager.deviceSelection()
                                    appState.selectDevice(device.dongleId)
                                    Task {
                                        await appState.loadRoutes()
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable {
                    HapticManager.refresh()
                    await appState.loadDevices()
                    // loadAllStats() is called automatically by .task(id:) when devices update
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.buttonPress()
                        if networkMonitor.isConnected {
                            qrScannerTrigger = UUID()
                        } else {
                            showingOfflineAlert = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(networkMonitor.isConnected ? Color.themeGreen : Color.gray)
                    }
                }
            }
            .alert("No Internet Connection", isPresented: $showingOfflineAlert) {
                Button("OK", role: .cancel) {
                    HapticManager.buttonPress()
                }
            } message: {
                Text("You need an active internet connection to pair new devices. Please check your network settings and try again.")
            }
            .task(id: appState.devices.map(\.dongleId)) {
                await loadAllStats()
            }
            .onChange(of: appState.error?.localizedDescription) { _, newDescription in
                if newDescription != nil && !hasUserDismissedError {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showingErrorAlert = true
                    }

                    // Auto-dismiss after 4 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        withAnimation {
                            showingErrorAlert = false
                            hasUserDismissedError = true
                        }
                    }
                } else if newDescription == nil {
                    // Reset on successful load (no error)
                    hasUserDismissedError = false
                    showingErrorAlert = false
                }
            }
        }
        .sheet(item: $selectedDeviceForSnapshot) { device in
            SnapshotView(dongleId: device.dongleId, apiClient: appState.apiClient)
                .environment(appState)
                .environment(networkMonitor)
        }
        .sheet(item: $selectedDeviceForSettings) { device in
            DeviceSettingsSheet(
                device: device,
                apiClient: appState.apiClient,
                onDeviceUnpaired: {
                    // Remove unpaired device from widget data
                    WidgetDataStore.removeDeviceData(for: device.dongleId)
                    WidgetCenter.shared.reloadAllTimelines()

                    Task {
                        await appState.loadDevices()
                    }
                }
            )
            .environment(appState)
            .environment(networkMonitor)
        }
        .sheet(item: $qrScannerTrigger) { _ in
            QRScannerView(
                apiClient: appState.apiClient,
                onDevicePaired: { device in
                    Task {
                        await appState.loadDevices()
                        appState.selectDevice(device.dongleId)
                    }
                    qrScannerTrigger = nil // Dismiss sheet
                }
            )
            .environment(appState)
            .environment(networkMonitor)
        }
    }

    @MainActor
    private func loadAllStats() async {
        guard !appState.devices.isEmpty else {
            deviceStats = [:]
            return
        }
        isLoadingStats = true

        // Clean up widget data for devices that no longer exist (e.g., unpaired elsewhere)
        let currentDeviceIds = Set(appState.devices.map { $0.dongleId })
        let widgetDeviceIds = Set(WidgetDataStore.getAllDevices().keys)
        for staleId in widgetDeviceIds.subtracting(currentDeviceIds) {
            WidgetDataStore.removeDeviceData(for: staleId)
        }

        await withTaskGroup(of: (String, DeviceStats?).self) { group in
            for device in appState.devices {
                // Fetch stats for all devices (including read-only)
                group.addTask {
                    do {
                        let stats = try await appState.apiClient.fetchDeviceStats(dongleId: device.dongleId)
                        return (device.dongleId, stats)
                    } catch {
                        await Logger.data.error("Failed to fetch stats for device", error: error)
                        return (device.dongleId, nil)
                    }
                }
            }

            for await (dongleId, stats) in group {
                if let stats = stats {
                    deviceStats[dongleId] = stats

                    // Save to shared container for widget
                    if let device = appState.devices.first(where: { $0.dongleId == dongleId }) {
                        let widgetData = WidgetDeviceData(
                            dongleId: dongleId,
                            displayName: device.displayName,
                            distance: stats.all.distance,
                            drives: stats.all.routes,
                            hours: stats.all.hours
                        )
                        WidgetDataStore.saveDeviceData(widgetData)
                    }
                }
            }
        }

        // Save distance unit preference for widget and mark as logged in
        WidgetDataStore.saveDistanceUnit(appState.distanceUnit.rawValue)
        WidgetDataStore.setLoggedIn(true)

        // Reload all widgets after saving data
        WidgetCenter.shared.reloadAllTimelines()

        isLoadingStats = false
    }

    @ViewBuilder
    private func errorBanner(_ error: Error) -> some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Error")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(errorMessage(from: error))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    HapticManager.buttonPress()
                    withAnimation {
                        showingErrorAlert = false
                        hasUserDismissedError = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Error")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(errorMessage(from: error))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    HapticManager.buttonPress()
                    withAnimation {
                        showingErrorAlert = false
                        hasUserDismissedError = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func errorMessage(from error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Network request failed"
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection"
            case .timedOut:
                return "Request timed out"
            case .cancelled:
                return "Request was cancelled"
            default:
                return "Network error occurred"
            }
        }
        return error.localizedDescription
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "plus.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Devices Paired")
                    .font(.title2.bold())

                Text("Tap the + button above to add a new device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}

struct DeviceRow: View {
    let device: Device
    let stats: DeviceStats?
    let onSnapshotTapped: () -> Void
    let onSettingsTapped: () -> Void
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(device.displayName)
                            .font(.headline)

                        if device.prime {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }

                    Text(device.deviceTypePretty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    // Snapshot button for all devices
                    Button {
                        if device.isOnline {
                            HapticManager.buttonPress()
                            onSnapshotTapped()
                        } else {
                            HapticManager.actionError()
                        }
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .opacity(device.isOnline ? 1.0 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!device.isOnline)

                    // Only show settings button for owned devices
                    if !device.isReadOnly {
                        Button {
                            HapticManager.buttonPress()
                            onSettingsTapped()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.selectedDeviceId == device.dongleId {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.themeGreen)
                            .font(.title3)
                    }
                }
            }

            // Status indicator
            DeviceStatusIndicator(device: device)

            // Stats for all devices (including read-only)
            HStack(spacing: 24) {
                if let stats = stats {
                    StatItem(
                        icon: "location.fill",
                        value: stats.all.distance.formatDistanceCompact(unit: appState.distanceUnit),
                        label: "Distance"
                    )

                    StatItem(
                        icon: "car.fill",
                        value: "\(stats.all.routes)",
                        label: "Drives"
                    )

                    StatItem(
                        icon: "clock.fill",
                        value: "\(stats.all.hours)hr",
                        label: "Time"
                    )
                } else {
                    // Show skeleton stats while loading
                    DeviceStatSkeleton()
                    DeviceStatSkeleton()
                    DeviceStatSkeleton()
                }
            }

            // Read-only indicator below stats
            if device.isReadOnly {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Read-only access")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

#Preview {
    DevicesView()
        .environment(AppState.shared)
        .environment(NetworkMonitor.shared)
}
