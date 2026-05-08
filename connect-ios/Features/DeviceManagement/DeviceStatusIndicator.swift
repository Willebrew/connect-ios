//
//  DeviceStatusIndicator.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Online/offline status indicator for devices
//

import SwiftUI

struct DeviceStatusIndicator: View {
    let device: Device

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(device.isOnline ? .green : .gray)
                .frame(width: 8, height: 8)

            if let lastPing = device.lastAthenaPing {
                Text(device.isOnline ? "Online" : lastPing.shortTimeAgo)
                    .font(.caption2)
                    .foregroundStyle(device.isOnline ? .green : .secondary)
            } else {
                Text("Unknown")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
