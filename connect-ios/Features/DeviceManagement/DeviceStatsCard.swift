//
//  DeviceStatsCard.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Device statistics display card
//

import SwiftUI

struct DeviceStatsCard: View {
    let stats: DeviceStats
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Text("Lifetime Statistics")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 24) {
                StatItem(
                    icon: "location.fill",
                    value: stats.all.distance.formatDistance(unit: appState.distanceUnit),
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
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.themeGreen)

            Text(value)
                .font(.title3.bold().monospacedDigit())

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DeviceStatsCard(stats: DeviceStats(
        all: DeviceStats.Stats(routes: 342, distance: 5284.7, minutes: 18420)
    ))
    .padding()
    .environment(AppState.shared)
}
