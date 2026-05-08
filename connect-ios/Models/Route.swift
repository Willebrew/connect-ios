//
//  Route.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Data model for drive routes
//

import Foundation
import SwiftData

@Model
final class Route: Identifiable, Codable, @unchecked Sendable {
    @Attribute(.unique) var fullname: String
    var logId: String
    var dongleId: String
    var url: String
    var createTime: Date
    var startTimeUtc: Date
    var endTimeUtc: Date
    var duration: TimeInterval // milliseconds
    var distance: Double // miles
    var segmentNumbers: [Int]
    var segmentStartTimes: [Date]
    var segmentEndTimes: [Date]
    var maxqlog: Int
    var isPublic: Bool
    var isPreserved: Bool

    // Cached/computed data (not persisted by SwiftData)
    @Transient var events: [DriveEvent]?
    @Transient var driveCoords: [Int: Coordinate]? // [second: coordinate]
    @Transient var startLocation: Location?
    @Transient var endLocation: Location?
    @Transient var videoStartOffset: TimeInterval? // milliseconds
    var startLat: Double?
    var startLng: Double?
    var endLat: Double?
    var endLng: Double?
    var shareSig: String?
    var shareExp: String?

    var id: String { fullname }

    init(
        fullname: String,
        logId: String,
        dongleId: String,
        url: String = "",
        createTime: Date = Date(),
        startTimeUtc: Date = Date(),
        endTimeUtc: Date = Date(),
        duration: TimeInterval = 0,
        distance: Double = 0,
        segmentNumbers: [Int] = [],
        segmentStartTimes: [Date] = [],
        segmentEndTimes: [Date] = [],
        maxqlog: Int = 0,
        isPublic: Bool = false,
        isPreserved: Bool = false,
        startLat: Double? = nil,
        startLng: Double? = nil,
        endLat: Double? = nil,
        endLng: Double? = nil,
        shareSig: String? = nil,
        shareExp: String? = nil
    ) {
        self.fullname = fullname
        self.logId = logId
        self.dongleId = dongleId
        self.url = url
        self.createTime = createTime
        self.startTimeUtc = startTimeUtc
        self.endTimeUtc = endTimeUtc
        self.duration = duration
        self.distance = distance
        self.segmentNumbers = segmentNumbers
        self.segmentStartTimes = segmentStartTimes
        self.segmentEndTimes = segmentEndTimes
        self.maxqlog = maxqlog
        self.isPublic = isPublic
        self.isPreserved = isPreserved
        self.startLat = startLat
        self.startLng = startLng
        self.endLat = endLat
        self.endLng = endLng
        self.shareSig = shareSig
        self.shareExp = shareExp
    }

    enum CodingKeys: String, CodingKey {
        case fullname
        case logId = "log_id"
        case dongleId = "dongle_id"
        case url
        case createTime = "create_time"
        case startTimeUtc = "start_time_utc_millis"
        case endTimeUtc = "end_time_utc_millis"
        case duration
        case distance
        case length
        case segmentNumbers = "segment_numbers"
        case segmentStartTimes = "segment_start_times"
        case segmentEndTimes = "segment_end_times"
        case maxqlog
        case isPublic = "is_public"
        case isPreserved = "is_preserved"
        case startLat = "start_lat"
        case startLng = "start_lng"
        case endLat = "end_lat"
        case endLng = "end_lng"
        case shareSig = "share_sig"
        case shareExp = "share_exp"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedFullname = try container.decode(String.self, forKey: .fullname)
        fullname = decodedFullname

        if let explicitLogId = try container.decodeIfPresent(String.self, forKey: .logId),
           !explicitLogId.isEmpty {
            logId = explicitLogId
        } else if let derived = decodedFullname.split(separator: "|").last {
            logId = String(derived)
        } else {
            logId = decodedFullname
        }
        if let idString = try? container.decode(String.self, forKey: .dongleId) {
            dongleId = idString
        } else if let idInt = try? container.decode(Int.self, forKey: .dongleId) {
            dongleId = String(idInt)
        } else {
            dongleId = ""
        }
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""

        let createTimeMs = try container.decodeIfPresent(TimeInterval.self, forKey: .createTime) ?? Date().timeIntervalSince1970 * 1000
        createTime = Date(timeIntervalSince1970: createTimeMs / 1000)

        let startTimeMs = try container.decode(TimeInterval.self, forKey: .startTimeUtc)
        startTimeUtc = Date(timeIntervalSince1970: startTimeMs / 1000)

        let endTimeMs = try container.decode(TimeInterval.self, forKey: .endTimeUtc)
        endTimeUtc = Date(timeIntervalSince1970: endTimeMs / 1000)

        let decodedDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        duration = decodedDuration ?? max(endTimeMs - startTimeMs, 0)

        if let distanceValue = try container.decodeIfPresent(Double.self, forKey: .distance) {
            distance = distanceValue
        } else if let lengthValue = try container.decodeIfPresent(Double.self, forKey: .length) {
            distance = lengthValue
        } else {
            distance = 0
        }

        segmentNumbers = try container.decodeIfPresent([Int].self, forKey: .segmentNumbers) ?? []

        let startTimes = try container.decodeIfPresent([TimeInterval].self, forKey: .segmentStartTimes) ?? []
        segmentStartTimes = startTimes.map { Date(timeIntervalSince1970: $0 / 1000) }

        let endTimes = try container.decodeIfPresent([TimeInterval].self, forKey: .segmentEndTimes) ?? []
        segmentEndTimes = endTimes.map { Date(timeIntervalSince1970: $0 / 1000) }

        maxqlog = try container.decodeIfPresent(Int.self, forKey: .maxqlog) ?? 0
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        isPreserved = try container.decodeIfPresent(Bool.self, forKey: .isPreserved) ?? false
        startLat = try container.decodeIfPresent(Double.self, forKey: .startLat)
        startLng = try container.decodeIfPresent(Double.self, forKey: .startLng)
        endLat = try container.decodeIfPresent(Double.self, forKey: .endLat)
        endLng = try container.decodeIfPresent(Double.self, forKey: .endLng)
        shareSig = try container.decodeIfPresent(String.self, forKey: .shareSig)
        if let expString = try? container.decode(String.self, forKey: .shareExp) {
            shareExp = expString
        } else if let expInt = try? container.decode(Int.self, forKey: .shareExp) {
            shareExp = String(expInt)
        } else {
            shareExp = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fullname, forKey: .fullname)
        try container.encode(logId, forKey: .logId)
        try container.encode(dongleId, forKey: .dongleId)
        try container.encode(url, forKey: .url)
        try container.encode(createTime.timeIntervalSince1970 * 1000, forKey: .createTime)
        try container.encode(startTimeUtc.timeIntervalSince1970 * 1000, forKey: .startTimeUtc)
        try container.encode(endTimeUtc.timeIntervalSince1970 * 1000, forKey: .endTimeUtc)
        try container.encode(duration, forKey: .duration)
        try container.encode(distance, forKey: .distance)
        try container.encode(segmentNumbers, forKey: .segmentNumbers)
        try container.encode(segmentStartTimes.map { $0.timeIntervalSince1970 * 1000 }, forKey: .segmentStartTimes)
        try container.encode(segmentEndTimes.map { $0.timeIntervalSince1970 * 1000 }, forKey: .segmentEndTimes)
        try container.encode(maxqlog, forKey: .maxqlog)
        try container.encode(isPublic, forKey: .isPublic)
        try container.encode(isPreserved, forKey: .isPreserved)
        try container.encodeIfPresent(startLat, forKey: .startLat)
        try container.encodeIfPresent(startLng, forKey: .startLng)
        try container.encodeIfPresent(endLat, forKey: .endLat)
        try container.encodeIfPresent(endLng, forKey: .endLng)
        try container.encodeIfPresent(shareSig, forKey: .shareSig)
        try container.encodeIfPresent(shareExp, forKey: .shareExp)
    }

    // Computed properties
    var segmentDurations: [TimeInterval] {
        zip(segmentStartTimes, segmentEndTimes).map { startTime, endTime in
            endTime.timeIntervalSince(startTime) * 1000 // milliseconds
        }
    }

    func segmentNumber(for offset: TimeInterval) -> Int? {
        var currentOffset: TimeInterval = 0
        for (index, duration) in segmentDurations.enumerated() {
            if offset >= currentOffset && offset < currentOffset + duration {
                return segmentNumbers[index]
            }
            currentOffset += duration
        }
        return nil
    }
}

// Location data model
struct Location: Codable {
    var place: String
    var details: String

    var displayText: String {
        if place.isEmpty { return "Unknown Location" }
        return "\(place)\(details.isEmpty ? "" : ", \(details)")"
    }
}
