//
//  AppConstants.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  App-wide constants
//

import Foundation

enum AppConstants {
    static let appName = "openpilot connect"
    static let bundleIdentifier = "ai.comma.connect.ios"

    // Demo Mode
    // JWT token for demo account (same as webapp)
    // Identity: 0decdcdcfdf241a60 | Expires: 2062-12-07
    static let demoToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjEwMzg5NTgwNzM1LCJuYmYiOjE3NDk1ODA3MzUsImlhdCI6MTc0OTU4MDczNSwiaWRlbnRpdHkiOiIwZGVjZGRjZmRmMjQxYTYwIn0.KsDzqJxgkYhAs4tCgrMJIdORyxO0CQNb0gHXIf8aUT0"

    // Features
    static let defaultRoutesLimit = 8
    static let defaultTimeFilterDays = 14
    static let maxTimeFilterDays = 365 * 5
    static let maxPreservedRoutes = 10
    static let maxPreservedRoutesPrime = 100

    // Units
    enum DistanceUnit: String {
        case miles
        case kilometers

        var abbreviation: String {
            switch self {
            case .miles: return "mi"
            case .kilometers: return "km"
            }
        }
    }

    enum SpeedUnit: String {
        case mph
        case kph

        var abbreviation: String {
            switch self {
            case .mph: return "mph"
            case .kph: return "kph"
            }
        }
    }
}
