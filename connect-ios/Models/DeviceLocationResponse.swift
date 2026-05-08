//
//  DeviceLocationResponse.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  DTO for persisted device location returned by the API
//

import Foundation

struct DeviceLocationResponse: Decodable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case lat
        case latitude
        case lng
        case longitude
        case accuracy
        case time
        case timestamp
    }

    init(latitude: Double, longitude: Double, accuracy: Double?, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let latValue = try container.decodeIfPresent(Double.self, forKey: .lat)
            ?? container.decodeIfPresent(Double.self, forKey: .latitude)
        let lngValue = try container.decodeIfPresent(Double.self, forKey: .lng)
            ?? container.decodeIfPresent(Double.self, forKey: .longitude)

        guard let lat = latValue, let lng = lngValue else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing lat/lng in device location response")
            )
        }

        latitude = lat
        longitude = lng
        accuracy = try container.decodeIfPresent(Double.self, forKey: .accuracy)

        let timeValue = try container.decodeIfPresent(TimeInterval.self, forKey: .time)
            ?? container.decodeIfPresent(TimeInterval.self, forKey: .timestamp)
            ?? Date().timeIntervalSince1970

        // Check if timestamp is in milliseconds (> year 3000 when treated as seconds)
        if timeValue > 32503680000 {
            // Likely milliseconds, convert to seconds
            timestamp = Date(timeIntervalSince1970: timeValue / 1000.0)
        } else {
            // Already in seconds
            timestamp = Date(timeIntervalSince1970: timeValue)
        }
    }
}
