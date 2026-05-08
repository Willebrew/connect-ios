//
//  LocationService.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Device location tracking and management
//

import Foundation
import CoreLocation
import os

@Observable
final class LocationService {
    private let apiClient: APIClient

    var deviceLocations: [String: DeviceLocation] = [:]
    var isLoading = false
    var lastError: String?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Fetch location for a single device
    func fetchLocation(for device: Device) async {
        // Skip fetching location for read-only devices (user doesn't have permission)
        if device.isReadOnly {
            Logger.data.debug("Skipping location fetch for read-only device: \(device.dongleId)")
            return
        }

        let dongleId = device.dongleId

        // Always seed from persisted server data (works even when the device is offline)
        do {
            let cached = try await apiClient.fetchDeviceLocation(dongleId: dongleId)
            let persistedLocation = DeviceLocation(
                dongleId: dongleId,
                latitude: cached.latitude,
                longitude: cached.longitude,
                accuracy: cached.accuracy ?? 250.0,
                timestamp: cached.timestamp
            )
            deviceLocations[dongleId] = persistedLocation
        } catch {
            // Don't show errors for permission denied (expected for shared devices)
            if let apiError = error as? APIError,
               case .serverError(403, _) = apiError {
                Logger.data.debug("Permission denied for device location: \(dongleId)")
                return
            }
            Logger.data.error("Failed to fetch cached location", error: error)
            lastError = error.localizedDescription
        }
    }

    /// Fetch locations for all devices
    func fetchAllLocations(devices: [Device]) async {
        isLoading = true
        lastError = nil

        await withTaskGroup(of: Void.self) { group in
            for device in devices {
                group.addTask {
                    await self.fetchLocation(for: device)
                }
            }
        }
        isLoading = false
    }

    /// Get reverse geocoded address for a location
    func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                var addressComponents: [String] = []

                if let street = placemark.thoroughfare {
                    addressComponents.append(street)
                }
                if let city = placemark.locality {
                    addressComponents.append(city)
                }
                if let state = placemark.administrativeArea {
                    addressComponents.append(state)
                }
                return addressComponents.joined(separator: ", ")
            }
        } catch {
            Logger.data.error("Reverse geocoding failed", error: error)
        }
        return nil
    }
}

/// Device location data model
struct DeviceLocation: Identifiable, Sendable {
    let id = UUID()
    let dongleId: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double // meters
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isRecent: Bool {
        Date().timeIntervalSince(timestamp) < 3600 // Within last hour
    }

    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
