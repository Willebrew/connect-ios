//
//  DeviceSettingsSheet.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Device settings with unpair functionality
//

import SwiftUI

struct DeviceSettingsSheet: View {
    let device: Device
    let apiClient: APIClient
    let onDeviceUnpaired: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var deviceName: String
    @State private var isSavingName = false
    @State private var showingSaveSuccess = false
    @State private var showingUnpairConfirmation = false
    @State private var isUnpairing = false
    @State private var errorMessage: String?
    @State private var subscription: Subscription?
    @State private var isLoadingSubscription = false
    @State private var showingPrimeManagement = false
    @State private var showingOfflineAlert = false
    @State private var shareEmail: String = ""
    @State private var isSharingDevice = false
    @State private var showingSharingSuccess = false
    @State private var sharingErrorMessage: String?

    init(device: Device, apiClient: APIClient, onDeviceUnpaired: @escaping () -> Void) {
        self.device = device
        self.apiClient = apiClient
        self.onDeviceUnpaired = onDeviceUnpaired
        _deviceName = State(initialValue: device.alias)
    }

    var body: some View {
        NavigationStack {
            settingsContent
        }
        .sheet(isPresented: $showingPrimeManagement) {
            SafariView(url: URL(string: "https://connect.comma.ai")!)
        }
    }

    private var settingsContent: some View {
        List {
                Section {
                    HStack {
                        TextField("Device name", text: $deviceName)
                            .textFieldStyle(.plain)
                            .disabled(isSavingName)

                        if hasNameChanged {
                            if isSavingName {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Button {
                                    HapticManager.buttonPress()
                                    saveDeviceName()
                                } label: {
                                    Image(systemName: showingSaveSuccess ? "checkmark.circle.fill" : "checkmark.circle")
                                        .foregroundStyle(showingSaveSuccess ? .green : .themeGreen)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Device Name")
                } footer: {
                    if showingSaveSuccess {
                        Text("Name saved successfully")
                            .foregroundStyle(.green)
                    }
                }

                // Share Device Section - only for owners
                if device.isOwner {
                    Section {
                        HStack {
                            TextField("Email or User ID", text: $shareEmail)
                                .textFieldStyle(.plain)
                                .disabled(isSharingDevice)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)

                            if !shareEmail.isEmpty || showingSharingSuccess {
                                if isSharingDevice {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Button {
                                        HapticManager.buttonPress()
                                        shareDeviceWithUser()
                                    } label: {
                                        Image(systemName: showingSharingSuccess ? "checkmark.circle.fill" : "paperplane.fill")
                                            .foregroundStyle(showingSharingSuccess ? .green : .themeGreen)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        Text("Share Device")
                    } footer: {
                        if showingSharingSuccess {
                            Text("Device shared successfully")
                                .foregroundStyle(.green)
                        } else if let error = sharingErrorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                        } else {
                            Text("Give another user read access to this device")
                        }
                    }
                }

                Section("Device Information") {
                    LabeledContent("Type", value: device.deviceTypePretty)
                    LabeledContent("Dongle ID", value: device.dongleId)

                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(device.isOnline ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(device.isOnline ? "Online" : "Offline")
                        }
                        .foregroundStyle(device.isOnline ? .green : .secondary)
                    }
                }

                Section("Ownership") {
                    HStack {
                        Text("Owner")
                        Spacer()
                        if device.isOwner {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("You")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Shared with you")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // comma prime Subscription
                Section("comma prime") {
                    if isLoadingSubscription {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let sub = subscription {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Plan")
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(sub.planDisplayName)
                                        .fontWeight(.medium)
                                    Text(sub.planSubtext)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack {
                                Text("Amount")
                                Spacer()
                                Text(sub.formattedAmount)
                            }

                            HStack {
                                Text("Joined")
                                Spacer()
                                Text(sub.subscribedAt.formatted(date: .abbreviated, time: .omitted))
                            }

                            if let cancelAt = sub.cancelAt {
                                HStack {
                                    Text("Subscription End")
                                    Spacer()
                                    Text(cancelAt.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(.orange)
                                }
                            } else if let nextCharge = sub.nextChargeAt {
                                HStack {
                                    Text("Next Payment")
                                    Spacer()
                                    Text(nextCharge.formatted(date: .abbreviated, time: .omitted))
                                }
                            }
                        }

                        Button {
                            HapticManager.buttonPress()
                            showingPrimeManagement = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(sub.cancelAt != nil ? "Renew Subscription" : "Manage Subscription")
                                Spacer()
                            }
                        }
                    } else {
                        Button {
                            HapticManager.buttonPress()
                            showingPrimeManagement = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Subscribe to comma prime")
                                Spacer()
                            }
                        }

                        Text("Get 24/7 connectivity, remote snapshots, 1 year video storage, and more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        HapticManager.buttonPress()
                        if networkMonitor.isConnected {
                            showingUnpairConfirmation = true
                        } else {
                            showingOfflineAlert = true
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isUnpairing {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Text("Unpair Device")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isUnpairing)
                } footer: {
                    if device.isOwner {
                        Text("Unpairing this device will remove it from your account. This cannot be undone.")
                    } else {
                        Text("This will remove your access to this device.")
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Device Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        HapticManager.buttonPress()
                        dismiss()
                    } label: {
                        Text("Close")
                    }
                }
            }
            .alert("Unpair Device", isPresented: $showingUnpairConfirmation) {
                Button("Unpair", role: .destructive) {
                    HapticManager.delete()
                    unpairDevice()
                }
                Button("Cancel", role: .cancel) {
                    HapticManager.cancel()
                }
            } message: {
                Text("Are you sure you want to unpair \(device.displayName)? This cannot be undone.")
            }
            .alert("No Internet Connection", isPresented: $showingOfflineAlert) {
                Button("OK", role: .cancel) {
                    HapticManager.buttonPress()
                }
            } message: {
                Text("You need an active internet connection to unpair devices. Please check your network settings and try again.")
            }
        .task {
            await loadSubscription()
        }
    }

    private var hasNameChanged: Bool {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines) != device.alias
    }

    private func shareDeviceWithUser() {
        let trimmedEmail = shareEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            return
        }

        // Check if in demo mode
        if AuthService.shared.isDemoMode {
            sharingErrorMessage = "Cannot share devices in demo mode. Please sign in with your own account."
            HapticManager.actionError()
            return
        }

        Task {
            isSharingDevice = true
            sharingErrorMessage = nil
            showingSharingSuccess = false

            do {
                try await apiClient.shareDevice(dongleId: device.dongleId, userIdentifier: trimmedEmail)

                // Success
                await MainActor.run {
                    HapticManager.actionSuccess()
                    isSharingDevice = false
                    showingSharingSuccess = true
                    shareEmail = ""

                    // Hide success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showingSharingSuccess = false
                    }
                }
            } catch let error as APIError {
                await MainActor.run {
                    isSharingDevice = false
                    if case .serverError(404, _) = error {
                        sharingErrorMessage = "Could not find user"
                    } else {
                        sharingErrorMessage = error.errorDescription ?? "Unable to share device"
                    }
                    HapticManager.actionError()
                }
            } catch {
                await MainActor.run {
                    isSharingDevice = false
                    sharingErrorMessage = "Unable to share device: \(error.localizedDescription)"
                    HapticManager.actionError()
                }
            }
        }
    }

    private func saveDeviceName() {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if in demo mode
        if AuthService.shared.isDemoMode {
            errorMessage = "Cannot rename devices in demo mode. Please sign in with your own account."
            HapticManager.actionError()
            return
        }

        Task {
            isSavingName = true
            errorMessage = nil
            showingSaveSuccess = false

            do {
                let updatedDevice = try await apiClient.setDeviceAlias(dongleId: device.dongleId, alias: trimmedName)

                // Success - update AppState with new device
                await MainActor.run {
                    HapticManager.actionSuccess()
                    appState.updateDevice(updatedDevice)
                    isSavingName = false
                    showingSaveSuccess = true

                    // Hide success message after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showingSaveSuccess = false
                    }
                }
            } catch let error as APIError {
                await MainActor.run {
                    isSavingName = false
                    errorMessage = error.errorDescription ?? "Failed to save device name"
                }
            } catch {
                await MainActor.run {
                    isSavingName = false
                    errorMessage = "Failed to save device name: \(error.localizedDescription)"
                }
            }
        }
    }

    private func unpairDevice() {
        // Check if in demo mode
        if AuthService.shared.isDemoMode {
            errorMessage = "Cannot unpair devices in demo mode. Please sign in with your own account."
            HapticManager.actionError()
            return
        }

        // Check if device has internet connection
        if !networkMonitor.isConnected {
            errorMessage = "You need an active internet connection to unpair devices."
            HapticManager.actionError()
            return
        }

        Task {
            isUnpairing = true
            errorMessage = nil

            do {
                try await apiClient.unpairDevice(dongleId: device.dongleId)

                // Success
                await MainActor.run {
                    HapticManager.actionSuccess()
                    isUnpairing = false
                    onDeviceUnpaired()
                    dismiss()
                }
            } catch let error as APIError {
                await MainActor.run {
                    isUnpairing = false
                    errorMessage = error.errorDescription ?? "Failed to unpair device"
                }
            } catch {
                await MainActor.run {
                    isUnpairing = false
                    errorMessage = "Failed to unpair device: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadSubscription() async {
        // Skip fetching subscription for read-only devices (matches web app behavior)
        if device.isReadOnly {
            subscription = nil
            await MainActor.run {
                isLoadingSubscription = false
            }
            return
        }

        isLoadingSubscription = true

        do {
            subscription = try await apiClient.getSubscription(dongleId: device.dongleId)
        } catch {
            // No subscription or error loading - that's okay
            subscription = nil
        }

        await MainActor.run {
            isLoadingSubscription = false
        }
    }
}

#Preview {
    DeviceSettingsSheet(
        device: Device(
            dongleId: "0123456789abcdef",
            alias: "My comma 3X",
            deviceType: "threex",
            createTime: Date().addingTimeInterval(-365*24*3600),
            lastAthenaPing: Date().addingTimeInterval(-30),
            prime: true
        ),
        apiClient: ProductionAPIClient(),
        onDeviceUnpaired: {
            Logger.ui.info("Device unpaired")
        }
    )
    .environment(NetworkMonitor.shared)
}
