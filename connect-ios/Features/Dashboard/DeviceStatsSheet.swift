//
//  DeviceStatsSheet.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Device statistics and health info sheet
//

import SwiftUI

struct DeviceStatsSheet: View {
    let device: Device
    @State private var athenaService: AthenaService
    @State private var carHealth: CarHealth?
    @State private var isLoading = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(device: Device, apiClient: APIClient) {
        self.device = device
        self._athenaService = State(initialValue: AthenaService(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            List {
                // Device Info Section
                Section("Device Information") {
                    LabeledContent("Name", value: device.displayName)
                    LabeledContent("Type", value: device.deviceTypePretty)

                    if device.prime {
                        HStack {
                            Text("Status")
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                Text("comma prime")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }

                    if let lastAthenaPing = device.lastAthenaPing {
                        LabeledContent("Last Seen", value: lastAthenaPing.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                // Car Health Section
                Section("Car Health") {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let error = error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if let health = carHealth {
                        let voltage = health.peripheralState.voltageInVolts

                        // Battery Voltage
                        HStack {
                            Label("12V Battery", systemImage: "bolt.fill")
                            Spacer()
                            Text(String(format: "%.2fV", voltage))
                                .fontWeight(.semibold)
                                .foregroundStyle(batteryColor(voltage: voltage))
                        }

                        // Battery Health Indicator
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Battery Health")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ProgressView(value: batteryHealthPercentage(voltage: voltage), total: 1.0)
                                .tint(batteryColor(voltage: voltage))

                            Text(batteryHealthText(voltage: voltage))
                                .font(.caption)
                                .foregroundStyle(batteryColor(voltage: voltage))
                        }

                        // Current draw
                        LabeledContent("Current", value: String(format: "%.2fA", Double(health.peripheralState.current) / 1000.0))
                    } else {
                        Button {
                            HapticManager.buttonPress()
                            Task {
                                await loadCarHealth()
                            }
                        } label: {
                            Label("Check Car Health", systemImage: "waveform.path.ecg")
                        }
                    }
                }
            }
            .navigationTitle("Device Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        HapticManager.buttonPress()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticManager.refresh()
                        Task {
                            await loadCarHealth()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadCarHealth()
            }
        }
    }

    private func loadCarHealth() async {
        isLoading = true
        error = nil
        carHealth = nil

        do {
            carHealth = try await athenaService.getCarHealth(dongleId: device.dongleId)
        } catch let err {
            if err.isDeviceOfflineError {
                self.error = "Device is offline. Car health unavailable."
            } else {
                self.error = "Unable to fetch car health"
                Logger.data.error("Failed to load car health", error: err)
            }
        }
        isLoading = false
    }

    private func batteryColor(voltage: Double) -> Color {
        if voltage >= 12.6 {
            return .green
        } else if voltage >= 12.0 {
            return .orange
        } else {
            return .red
        }
    }

    private func batteryHealthPercentage(voltage: Double) -> Double {
        // 12.6V = 100%, 11.8V = 0%
        let normalized = (voltage - 11.8) / (12.6 - 11.8)
        return max(0, min(1, normalized))
    }

    private func batteryHealthText(voltage: Double) -> String {
        if voltage >= 12.6 {
            return "Excellent"
        } else if voltage >= 12.4 {
            return "Good"
        } else if voltage >= 12.0 {
            return "Fair"
        } else if voltage >= 11.8 {
            return "Low"
        } else {
            return "Critical"
        }
    }
}

#Preview {
    DeviceStatsSheet(
        device: Device(
            dongleId: "test123",
            alias: "My comma 3X",
            deviceType: "three",
            lastAthenaPing: Date(),
            prime: true
        ),
        apiClient: ProductionAPIClient()
    )
}
