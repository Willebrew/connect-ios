//
//  CommaDeviceStatusWidget.swift
//  CommaDeviceStatusWidget
//
//  Created by Will Killebrew on 11/23/25.
//

import WidgetKit
import SwiftUI

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeviceStatsEntry {
        DeviceStatsEntry(
            date: Date(),
            deviceName: "comma 3X",
            distance: "5,284 mi",
            drives: "342",
            hours: "307h",
            configuration: DeviceSelectionIntent()
        )
    }

    func snapshot(for configuration: DeviceSelectionIntent, in context: Context) async -> DeviceStatsEntry {
        // Return placeholder data for preview
        return DeviceStatsEntry(
            date: Date(),
            deviceName: configuration.selectedDevice?.displayName ?? "comma 3X",
            distance: "69,000 mi",
            drives: "420",
            hours: "670h",
            configuration: configuration
        )
    }

    func timeline(for configuration: DeviceSelectionIntent, in context: Context) async -> Timeline<DeviceStatsEntry> {
        var entries: [DeviceStatsEntry] = []
        let currentDate = Date()

        // Check if user is logged in first
        guard WidgetDataStore.isLoggedIn() else {
            // User is logged out - show empty state
            let entry = DeviceStatsEntry(
                date: currentDate,
                deviceName: "No device",
                distance: "—",
                drives: "—",
                hours: "—",
                configuration: configuration,
                hasData: false
            )
            entries.append(entry)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
            return Timeline(entries: entries, policy: .after(nextUpdate))
        }

        // Get device data from shared storage
        let dongleId = configuration.selectedDevice?.id
        let deviceData: WidgetDeviceData?

        if let id = dongleId {
            deviceData = WidgetDataStore.getDeviceData(for: id)
        } else {
            // Use first available device
            let allDevices = WidgetDataStore.getAllDevices()
            if let firstId = allDevices.keys.first {
                deviceData = WidgetDataStore.getDeviceData(for: firstId)
            } else {
                deviceData = nil
            }
        }

        let entry: DeviceStatsEntry
        if let data = deviceData {
            // Get user's distance unit preference
            let distanceUnitStr = WidgetDataStore.getDistanceUnit()
            let distanceUnit: DistanceUnit = distanceUnitStr == "kilometers" ? .kilometers : .miles

            // Format the data
            let distanceStr = data.distance.formatDistance(unit: distanceUnit)
            let drivesStr = "\(data.drives)"
            let hoursStr = "\(data.hours)h"

            entry = DeviceStatsEntry(
                date: currentDate,
                deviceName: data.displayName,
                distance: distanceStr,
                drives: drivesStr,
                hours: hoursStr,
                configuration: configuration
            )
        } else {
            // No data available - user may be logged out or no devices paired
            entry = DeviceStatsEntry(
                date: currentDate,
                deviceName: "No device",
                distance: "—",
                drives: "—",
                hours: "—",
                configuration: configuration,
                hasData: false
            )
        }

        entries.append(entry)

        // Update every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
        return Timeline(entries: entries, policy: .after(nextUpdate))
    }
}

struct DeviceStatsEntry: TimelineEntry {
    let date: Date
    let deviceName: String
    let distance: String
    let drives: String
    let hours: String
    let configuration: DeviceSelectionIntent
    let hasData: Bool

    init(date: Date, deviceName: String, distance: String, drives: String, hours: String, configuration: DeviceSelectionIntent, hasData: Bool = true) {
        self.date = date
        self.deviceName = deviceName
        self.distance = distance
        self.drives = drives
        self.hours = hours
        self.configuration = configuration
        self.hasData = hasData
    }
}

struct CommaDeviceStatusWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            if entry.hasData {
                VStack(alignment: .leading, spacing: widgetFamily == .systemSmall ? 12 : 16) {
                    // Header with device name and logo
                    HStack {
                        Text(entry.deviceName)
                            .font(widgetFamily == .systemSmall ? .subheadline : .headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        // Show logo only in medium widget
                        if widgetFamily == .systemMedium {
                            Image("comma-ai-logo")
                                .resizable()
                                .renderingMode(.original)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                        }
                    }

                    Spacer()

                    // Stats
                    if widgetFamily == .systemSmall {
                        smallLayout
                    } else {
                        mediumLayout
                    }
                }
                .padding(widgetFamily == .systemSmall ? 14 : 18)
            } else {
                // No data state - prompt user to open app
                VStack(spacing: 12) {
                    Image("comma-ai-logo")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)

                    Text("Open app to view stats")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var smallLayout: some View {
        VStack(spacing: 10) {
            StatRow(icon: "location.fill", value: entry.distance)
            StatRow(icon: "car.fill", value: entry.drives)
            StatRow(icon: "clock.fill", value: entry.hours)
        }
    }

    @ViewBuilder
    private var mediumLayout: some View {
        HStack(spacing: 20) {
            StatColumn(icon: "location.fill", value: entry.distance, label: "Distance")
            StatColumn(icon: "car.fill", value: entry.drives, label: "Drives")
            StatColumn(icon: "clock.fill", value: entry.hours, label: "Time")
        }
    }
}

struct StatRow: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.0, green: 1.0, blue: 0.0)) // #00FF00 bright green
                .frame(width: 16)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

struct StatColumn: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color(red: 0.0, green: 1.0, blue: 0.0)) // #00FF00 bright green

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CommaDeviceStatusWidget: Widget {
    let kind: String = "CommaDeviceStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DeviceSelectionIntent.self, provider: Provider()) { entry in
            CommaDeviceStatusWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.15),
                            Color(red: 0.05, green: 0.05, blue: 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Device Stats")
        .description("View lifetime statistics for your comma device")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Helper extension for distance formatting
extension Double {
    func formatDistance(unit: DistanceUnit) -> String {
        let value: Double
        let unitStr: String

        switch unit {
        case .miles:
            value = self
            unitStr = "mi"
        case .kilometers:
            value = self * 1.60934
            unitStr = "km"
        }

        // Match the compact formatting from the app
        if value >= 1000 {
            let thousands = (value / 100.0).rounded(.down) / 10.0
            return String(format: "%.1fK %@", thousands, unitStr)
        } else {
            return String(format: "%.1f %@", value, unitStr)
        }
    }
}

enum DistanceUnit {
    case miles
    case kilometers
}

#Preview(as: .systemSmall) {
    CommaDeviceStatusWidget()
} timeline: {
    DeviceStatsEntry(date: .now, deviceName: "comma 3X", distance: "5,284 mi", drives: "342", hours: "307h", configuration: DeviceSelectionIntent())
    DeviceStatsEntry(date: .now, deviceName: "comma neo", distance: "12.5k mi", drives: "1,247", hours: "892h", configuration: DeviceSelectionIntent())
}

#Preview(as: .systemMedium) {
    CommaDeviceStatusWidget()
} timeline: {
    DeviceStatsEntry(date: .now, deviceName: "comma 3X", distance: "5,284 mi", drives: "342", hours: "307h", configuration: DeviceSelectionIntent())
}
