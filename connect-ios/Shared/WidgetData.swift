//
//  WidgetData.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/23/25.
//
//  Shared data model for widget

import Foundation

struct WidgetDeviceData: Codable {
    let dongleId: String
    let displayName: String
    let distance: Double
    let drives: Int
    let hours: Int
    let lastUpdated: Date

    init(dongleId: String, displayName: String, distance: Double, drives: Int, hours: Int, lastUpdated: Date = Date()) {
        self.dongleId = dongleId
        self.displayName = displayName
        self.distance = distance
        self.drives = drives
        self.hours = hours
        self.lastUpdated = lastUpdated
    }
}

struct WidgetDataStore {
    static let appGroupIdentifier = "group.ai.comma.connect"
    static let widgetDataKey = "widgetDeviceData"
    static let distanceUnitKey = "distance_unit"
    static let isLoggedInKey = "widget_is_logged_in"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    // Save device data for widget
    static func saveDeviceData(_ data: WidgetDeviceData) {
        guard let defaults = sharedDefaults else { return }

        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: "\(widgetDataKey)_\(data.dongleId)")
            defaults.synchronize() // Force sync
        }
    }

    // Get device data for widget
    static func getDeviceData(for dongleId: String) -> WidgetDeviceData? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "\(widgetDataKey)_\(dongleId)"),
              let decoded = try? JSONDecoder().decode(WidgetDeviceData.self, from: data) else {
            return nil
        }
        return decoded
    }

    // Get all available devices (for configuration)
    static func getAllDevices() -> [String: String] {
        guard let defaults = sharedDefaults else { return [:] }

        var devices: [String: String] = [:]
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        let matchingKeys = allKeys.filter { $0.hasPrefix(widgetDataKey) }

        for key in matchingKeys {
            let dongleId = key.replacingOccurrences(of: "\(widgetDataKey)_", with: "")
            if let data = getDeviceData(for: dongleId) {
                devices[dongleId] = data.displayName
            }
        }
        return devices
    }

    // Save distance unit preference
    static func saveDistanceUnit(_ unit: String) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(unit, forKey: distanceUnitKey)
        defaults.synchronize()
    }

    // Get distance unit preference (returns "miles" or "kilometers")
    static func getDistanceUnit() -> String {
        guard let defaults = sharedDefaults,
              let unit = defaults.string(forKey: distanceUnitKey) else {
            return "miles" // Default
        }
        return unit
    }

    // Remove device data for widget (used when device is unpaired)
    static func removeDeviceData(for dongleId: String) {
        guard let defaults = sharedDefaults else { return }
        defaults.removeObject(forKey: "\(widgetDataKey)_\(dongleId)")
        defaults.synchronize()
    }

    // Remove all device data (used on logout)
    static func removeAllDeviceData() {
        guard let defaults = sharedDefaults else { return }
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        for key in allKeys where key.hasPrefix(widgetDataKey) {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }

    // Set logged in state for widget
    static func setLoggedIn(_ loggedIn: Bool) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(loggedIn, forKey: isLoggedInKey)
        defaults.synchronize()
    }

    // Check if user is logged in (for widget to show appropriate state)
    static func isLoggedIn() -> Bool {
        guard let defaults = sharedDefaults else { return false }
        return defaults.bool(forKey: isLoggedInKey)
    }
}
