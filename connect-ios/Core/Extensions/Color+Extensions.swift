//
//  Color+Extensions.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Color utility extensions for hex colors
//

import SwiftUI

extension Color {
    /// Initialize a Color from a hex string (e.g., "#175886")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // Timeline colors matching web app
    static let drivingBlue = Color(hex: "#175886")      // Base driving state
    static let engagedGreen = Color(hex: "#178645")     // Autopilot engaged
    static let engagedGrey = Color(hex: "#919b95")      // User overriding
    static let alertOrange = Color(hex: "#da6f25")      // User prompt alert
    static let alertRed = Color(hex: "#c92231")         // Critical alert

    // App theme color
    static let themeGreen = Color(hex: "#00FF00")       // Bright vibrant green theme color
}
