//
//  DeviceStats.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Data model for device statistics
//

import Foundation

struct DeviceStats: Codable, Sendable {
    var all: Stats

    struct Stats: Codable, Sendable {
        var routes: Int
        var distance: Double // Stored in miles
        var minutes: Int

        var hours: Int {
            minutes / 60
        }

        enum CodingKeys: String, CodingKey {
            case routes
            case distance
            case minutes
            case drives
            case distanceMiles = "distance_miles"
            case distanceKilometers = "distance_km"
            case seconds
            case hours
        }

        init(routes: Int, distance: Double, minutes: Int) {
            self.routes = routes
            self.distance = distance
            self.minutes = minutes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Routes/Drives
            if let value = try container.decodeIfPresent(Int.self, forKey: .routes) {
                routes = value
            } else if let drives = try container.decodeIfPresent(Int.self, forKey: .drives) {
                routes = drives
            } else {
                routes = 0
            }

            // Distance (supports multiple field names + string fallback)
            if let miles = try container.decodeIfPresent(Double.self, forKey: .distance) {
                distance = miles
            } else if let miles = try container.decodeIfPresent(Double.self, forKey: .distanceMiles) {
                distance = miles
            } else if let km = try container.decodeIfPresent(Double.self, forKey: .distanceKilometers) {
                distance = km * 0.621371
            } else if let distanceString = try container.decodeIfPresent(String.self, forKey: .distance),
                      let miles = Double(distanceString) {
                distance = miles
            } else {
                distance = 0
            }

            // Minutes (support seconds/hours fallbacks)
            if let mins = try container.decodeIfPresent(Int.self, forKey: .minutes) {
                minutes = mins
            } else if let seconds = try container.decodeIfPresent(Int.self, forKey: .seconds) {
                minutes = seconds / 60
            } else if let hours = try container.decodeIfPresent(Int.self, forKey: .hours) {
                minutes = hours * 60
            } else {
                minutes = 0
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(routes, forKey: .routes)
            try container.encode(distance, forKey: .distance)
            try container.encode(minutes, forKey: .minutes)
        }
    }
}
