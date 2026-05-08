//
//  Device.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Data model for comma.ai devices
//

import Foundation

struct Device: Identifiable, Codable, Sendable {
    var dongleId: String
    var alias: String
    var deviceType: String
    var isOwner: Bool
    var shared: Bool
    var serial: String?
    var imei: String?
    var createTime: Date
    var lastAthenaPing: Date?
    var fetchedAt: Date
    var networkMetered: Bool
    var openpilotVersion: String?
    var prime: Bool

    var id: String { dongleId }

    // Memberwise initializer (for testing/preview)
    init(
        dongleId: String,
        alias: String = "",
        deviceType: String = "unknown",
        isOwner: Bool = true,
        shared: Bool = false,
        serial: String? = nil,
        imei: String? = nil,
        createTime: Date = Date(),
        lastAthenaPing: Date? = nil,
        fetchedAt: Date = Date(),
        networkMetered: Bool = false,
        openpilotVersion: String? = nil,
        prime: Bool = false
    ) {
        self.dongleId = dongleId
        self.alias = alias
        self.deviceType = deviceType
        self.isOwner = isOwner
        self.shared = shared
        self.serial = serial
        self.imei = imei
        self.createTime = createTime
        self.lastAthenaPing = lastAthenaPing
        self.fetchedAt = fetchedAt
        self.networkMetered = networkMetered
        self.openpilotVersion = openpilotVersion
        self.prime = prime
    }

    enum CodingKeys: String, CodingKey {
        case dongleId = "dongle_id"
        case alias
        case deviceType = "device_type"
        case isOwner = "is_owner"
        case shared
        case serial
        case imei
        case createTime = "create_time"
        case lastAthenaPing = "last_athena_ping"
        case fetchedAt = "fetched_at"
        case networkMetered = "network_metered"
        case openpilotVersion = "openpilot_version"
        case prime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dongleId = try container.decode(String.self, forKey: .dongleId)
        alias = try container.decodeIfPresent(String.self, forKey: .alias) ?? ""
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType) ?? "unknown"
        isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner) ?? true
        shared = try container.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        serial = try container.decodeIfPresent(String.self, forKey: .serial)
        imei = try container.decodeIfPresent(String.self, forKey: .imei)

        let createTimeStamp = try container.decodeIfPresent(TimeInterval.self, forKey: .createTime) ?? Date().timeIntervalSince1970
        createTime = Date(timeIntervalSince1970: createTimeStamp)

        if let lastPing = try container.decodeIfPresent(TimeInterval.self, forKey: .lastAthenaPing) {
            // Check if timestamp is in milliseconds (> year 3000 when treated as seconds)
            // Year 3000 is ~32503680000 seconds since epoch
            if lastPing > 32503680000 {
                // Likely milliseconds, convert to seconds
                lastAthenaPing = Date(timeIntervalSince1970: lastPing / 1000.0)
            } else {
                // Already in seconds
                lastAthenaPing = Date(timeIntervalSince1970: lastPing)
            }
        } else {
            lastAthenaPing = nil
        }
        fetchedAt = Date()
        networkMetered = try container.decodeIfPresent(Bool.self, forKey: .networkMetered) ?? false
        openpilotVersion = try container.decodeIfPresent(String.self, forKey: .openpilotVersion)
        prime = try container.decodeIfPresent(Bool.self, forKey: .prime) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dongleId, forKey: .dongleId)
        try container.encode(alias, forKey: .alias)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encode(isOwner, forKey: .isOwner)
        try container.encode(shared, forKey: .shared)
        try container.encodeIfPresent(serial, forKey: .serial)
        try container.encodeIfPresent(imei, forKey: .imei)
        try container.encode(createTime.timeIntervalSince1970, forKey: .createTime)
        try container.encodeIfPresent(lastAthenaPing?.timeIntervalSince1970, forKey: .lastAthenaPing)
        try container.encode(networkMetered, forKey: .networkMetered)
        try container.encodeIfPresent(openpilotVersion, forKey: .openpilotVersion)
        try container.encode(prime, forKey: .prime)
    }

    // Computed properties
    var isOnline: Bool {
        guard let lastPing = lastAthenaPing else { return false }
        return Date().timeIntervalSince(lastPing) < 120 // Online if pinged within 2 minutes
    }

    var displayName: String {
        if !alias.isEmpty {
            return alias
        }
        return deviceTypePretty
    }

    var deviceTypePretty: String {
        switch deviceType {
        case "threex": return "comma 3X"
        case "neo": return "comma neo"
        case "freon": return "comma two"
        default: return "comma device"
        }
    }

    var onCellular: Bool {
        return networkMetered
    }

    var hasWriteAccess: Bool {
        return isOwner
    }

    var isReadOnly: Bool {
        return shared || !isOwner
    }
}
