//
//  APIClient.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Protocol defining API client interface
//

import Foundation

protocol APIClient {
    // Auth
    func authenticate(code: String, provider: String, state: String?) async throws -> String
    func exchangeToken(code: String, provider: String) async throws -> String
    func getProfile() async throws -> UserProfile

    // Devices
    func listDevices() async throws -> [Device]
    func fetchDevice(dongleId: String) async throws -> Device
    func fetchDeviceStats(dongleId: String) async throws -> DeviceStats
    func pairDevice(token: String) async throws -> Device
    func unpairDevice(dongleId: String) async throws
    func setDeviceAlias(dongleId: String, alias: String) async throws -> Device
    func shareDevice(dongleId: String, userIdentifier: String) async throws

    // Routes
    func fetchRoutes(dongleId: String, start: Date, end: Date, limit: Int) async throws -> [Route]
    func getPreservedRoutes(dongleId: String) async throws -> [Route]
    func setRoutePublic(fullname: String, isPublic: Bool) async throws
    func setRoutePreserved(fullname: String, preserved: Bool) async throws

    // Athena (real-time device communication)
    func sendAthenaCommand(dongleId: String, method: String, params: [String: Any]?) async throws -> [String: Any]
    func getUploadQueue(dongleId: String) async throws -> [[String: Any]]
    func takeSnapshot(dongleId: String) async throws -> SnapshotResult

    // Video
    func getVideoStreamURL(for route: Route) async throws -> URL
    func getVideoStreamURL(for route: Route, camera: CameraStreamType) async throws -> URL

    // Files
    func getRouteFiles(routeName: String) async throws -> [String: [String]] // [fileType: [urls]]
    func getUploadURLs(dongleId: String, paths: [String], expiryDays: Int) async throws -> [UploadURLResponse]
    func fetchRouteEvents(route: Route) async throws -> [DriveEvent]
    func fetchDriveCoordinates(route: Route) async throws -> [Int: Coordinate]
    func checkFileAvailability(routeName: String, fileType: FileType) async throws -> FileAvailabilityStatus

    // Billing
    func getSubscription(dongleId: String) async throws -> Subscription?
    func getSubscribeInfo(dongleId: String) async throws -> SubscribeInfo

    // Geocoding
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> Location

    // Device telemetry
    func fetchDeviceLocation(dongleId: String) async throws -> DeviceLocationResponse
}

struct SnapshotResult {
    let jpegBack: String?  // Road-facing camera (base64)
    let jpegFront: String? // Driver-facing camera (base64)
}

/// Status of file availability for high-quality download
enum FileAvailabilityStatus {
    case available(urls: [String])     // Files are in cloud, ready to download
    case partiallyAvailable(available: Int, total: Int, urls: [String])  // Some segments available
    case notAvailable                  // Files not uploaded yet
    case uploadInProgress(progress: Double)  // Device is currently uploading
    
    var isReady: Bool {
        switch self {
        case .available, .partiallyAvailable: return true
        case .notAvailable, .uploadInProgress: return false
        }
    }
    
    var displayMessage: String {
        switch self {
        case .available:
            return "Ready to download"
        case .partiallyAvailable(let available, let total, _):
            return "\(available)/\(total) segments available"
        case .notAvailable:
            return "Not in cloud - request upload from device"
        case .uploadInProgress(let progress):
            return "Uploading... \(Int(progress * 100))%"
        }
    }
}

/// Camera stream types for HLS video URLs
enum CameraStreamType: String, Codable {
    case road       // qcamera - standard quality road camera
    case driver     // dcamera - driver-facing camera
    case wide       // ecamera - wide angle camera
    
    /// The HLS playlist filename for this camera type
    var hlsFilename: String {
        switch self {
        case .road: return "qcamera.m3u8"
        case .driver: return "dcamera.m3u8"
        case .wide: return "ecamera.m3u8"
        }
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case serverError(Int, String)
    case unauthorized
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .unauthorized:
            return "Unauthorized - please sign in again"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

extension APIError {
    nonisolated var underlyingURLError: URLError? {
        if case .networkError(let error) = self {
            return error as? URLError
        }
        return nil
    }
    nonisolated var isCancelledRequest: Bool {
        underlyingURLError?.code == .cancelled
    }
    nonisolated var isPermissionDenied: Bool {
        if case .serverError(403, _) = self {
            return true
        }
        return false
    }
}
