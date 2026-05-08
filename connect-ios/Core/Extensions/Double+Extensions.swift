//
//  Double+Extensions.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Double utility extensions for distance formatting
//

import Foundation

extension Double {
    func formatDistance(unit: AppConstants.DistanceUnit) -> String {
        let value = unit == .kilometers ? self * 1.60934 : self
        return String(format: "%.1f %@", value, unit.abbreviation)
    }

    func formatDistanceCompact(unit: AppConstants.DistanceUnit) -> String {
        let value = unit == .kilometers ? self * 1.60934 : self

        if value >= 1000 {
            let thousands = (value / 100).rounded(.down) / 10
            return String(format: "%.1fK %@", thousands, unit.abbreviation)
        } else {
            return String(format: "%.1f %@", value, unit.abbreviation)
        }
    }

    var formattedMiles: String {
        String(format: "%.1f mi", self)
    }

    var formattedKilometers: String {
        String(format: "%.1f km", self * 1.60934)
    }
}
