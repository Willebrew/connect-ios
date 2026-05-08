//
//  AthenaService.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Real-time device communication via Athena JSON-RPC
//

import Foundation

@Observable
final class AthenaService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Snapshot

    func takeSnapshot(dongleId: String) async throws -> SnapshotResult {
        return try await apiClient.takeSnapshot(dongleId: dongleId)
    }

    // MARK: - Car Health

    func getCarHealth(dongleId: String) async throws -> CarHealth {
        let response = try await apiClient.sendAthenaCommand(
            dongleId: dongleId,
            method: "getMessage",
            params: ["service": "peripheralState", "timeout": 5000]
        )

        guard let resultData = response["result"] as? [String: Any] else {
            throw APIError.noData
        }

        // Convert the result dictionary to JSON data
        let jsonData = try JSONSerialization.data(withJSONObject: resultData)
        return try JSONDecoder().decode(CarHealth.self, from: jsonData)
    }

    // MARK: - Network Status

    func isNetworkMetered(dongleId: String) async throws -> Bool {
        let response = try await apiClient.sendAthenaCommand(
            dongleId: dongleId,
            method: "getNetworkMetered",
            params: nil
        )

        return response["result"] as? Bool ?? false
    }

    func getNetworkType(dongleId: String) async throws -> String {
        let response = try await apiClient.sendAthenaCommand(
            dongleId: dongleId,
            method: "getNetworkType",
            params: nil
        )
        return response["result"] as? String ?? "unknown"
    }

    // MARK: - Upload Management

    func listUploadQueue(dongleId: String) async throws -> [[String: Any]] {
        return try await apiClient.getUploadQueue(dongleId: dongleId)
    }

    func uploadFile(dongleId: String, path: String, url: String, headers: [String: String]) async throws {
        let params: [String: Any] = [
            "path": path,
            "fn": path,
            "url": url,
            "headers": headers
        ]

        _ = try await apiClient.sendAthenaCommand(
            dongleId: dongleId,
            method: "uploadFileToUrl",
            params: params
        )
    }

    func uploadFiles(dongleId: String, filesData: [[String: Any]]) async throws {
        let params: [String: Any] = [
            "files_data": filesData
        ]

        _ = try await apiClient.sendAthenaCommand(
            dongleId: dongleId,
            method: "uploadFilesToUrls",
            params: params
        )
    }

    func cancelUpload(dongleId: String, uploadIds: [String]) async throws {
        let params: [String: Any] = [
            "upload_id": uploadIds
        ]

        _ = try await apiClient.sendAthenaCommand(
            dongleId: dongleId,
            method: "cancelUpload",
            params: params
        )
    }

    // MARK: - Route Management

    func setRouteViewed(dongleId: String, routeFullname: String) async throws {
        let params: [String: Any] = [
            "route": routeFullname
        ]

        _ = try await apiClient.sendAthenaCommand(
            dongleId: dongleId,
            method: "setRouteViewed",
            params: params
        )
    }

    // MARK: - Location

    func getDeviceLocation(dongleId: String) async throws -> (lat: Double, lng: Double, accuracy: Double?) {
        let response = try await apiClient.sendAthenaCommand(
            dongleId: dongleId,
            method: "getLocation",
            params: nil
        )

        guard let result = response["result"] as? [String: Any],
              let lat = result["latitude"] as? Double,
              let lng = result["longitude"] as? Double else {
            throw APIError.noData
        }
        let accuracy = result["accuracy"] as? Double
        return (lat, lng, accuracy)
    }
}
