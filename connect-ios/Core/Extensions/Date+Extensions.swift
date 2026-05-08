//
//  Date+Extensions.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Date utility extensions
//

import Foundation

extension Date {
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var shortTimeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var dayMonthYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: self)
    }

    var timeOnly: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    static func from(milliseconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }

    var millisecondsSince1970: TimeInterval {
        timeIntervalSince1970 * 1000
    }
}
