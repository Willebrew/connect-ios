//
//  BatteryIndicator.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Car battery voltage indicator
//

import SwiftUI

struct BatteryIndicator: View {
    let voltage: Double? // in volts

    var body: some View {
        if let voltage = voltage {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(voltageColor)

                Text(String(format: "%.1fV", voltage))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(voltageColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(voltageColor.opacity(0.15), in: Capsule())
        }
    }

    private var voltageColor: Color {
        guard let voltage = voltage else { return .gray }
        return voltage >= 11.0 ? .green : .red
    }
}

#Preview {
    VStack(spacing: 16) {
        BatteryIndicator(voltage: 12.4)
        BatteryIndicator(voltage: 10.8)
        BatteryIndicator(voltage: nil)
    }
    .padding()
}
