//
//  TimeInterval+Extensions.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  TimeInterval utility extensions for duration formatting
//

import Foundation

extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = Int(self / 1000) // Convert milliseconds to seconds
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d hr %d min", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%d min %d sec", minutes, seconds)
        } else {
            return String(format: "%d sec", seconds)
        }
    }

    var compactDuration: String {
        let totalSeconds = Int(self / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }

    var hourMinuteDuration: String {
        let totalSeconds = Int(self / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        var components: [String] = []
        if hours > 0 {
            components.append("\(hours) hr")
        }
        if minutes > 0 {
            components.append("\(minutes) min")
        }
        return components.isEmpty ? "0 min" : components.joined(separator: " ")
    }
}
