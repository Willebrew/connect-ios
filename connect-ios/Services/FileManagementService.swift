//
//  FileManagementService.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/14/25.
//
//  Service for managing file uploads and downloads
//

import Foundation
import os

@Observable
final class FileManagementService {
    private let apiClient: APIClient
    private let athenaService: AthenaService

    var uploadQueue: [UploadQueueItem] = []
    var isLoadingQueue = false
    var wifiOnlyMode = true
    var lastError: String?

    init(apiClient: APIClient, athenaService: AthenaService) {
        self.apiClient = apiClient
        self.athenaService = athenaService
    }

    // MARK: - Upload Queue

    @MainActor
    func fetchUploadQueue(dongleId: String, isDeviceOnline: Bool? = nil) async {
        lastError = nil
        isLoadingQueue = true

        if let isOnline = isDeviceOnline, !isOnline {
            uploadQueue = []
            isLoadingQueue = false
            lastError = "Device is offline. Upload queue unavailable."
            return
        }

        do {
            let queue = try await athenaService.listUploadQueue(dongleId: dongleId)

            uploadQueue = queue.compactMap { item -> UploadQueueItem? in
                guard let id = item["id"] as? String,
                      let path = item["path"] as? String,
                      let url = item["url"] as? String else {
                    return nil
                }

                let progress = item["progress"] as? Double ?? 0
                let current = item["current"] as? Bool ?? false
                let paused = item["paused"] as? Bool ?? false
                let created = Date(timeIntervalSince1970: (item["created"] as? TimeInterval ?? 0) / 1000)

                return UploadQueueItem(
                    id: id,
                    path: path,
                    url: url,
                    progress: progress,
                    current: current,
                    paused: paused,
                    created: created
                )
            }
        } catch {
            if error.isDeviceOfflineError {
                uploadQueue = []
                lastError = "Device is offline. Upload queue unavailable."
            } else {
                Logger.data.error("Failed to fetch upload queue", error: error)
                lastError = "Failed to fetch upload queue."
            }
        }
        isLoadingQueue = false
    }

    @MainActor
    func requestUpload(dongleId: String, route: Route, fileType: FileType) async throws {
        // Get upload URL from API
        let segmentNumbers = route.segmentNumbers.isEmpty ? [0] : route.segmentNumbers
        let paths = segmentNumbers.flatMap { segment in
            fileType.fileNames.map { fileName in
                "\(route.logId)--\(segment)/\(fileName)"
            }
        }

        let uploadURLs = try await apiClient.getUploadURLs(dongleId: dongleId, paths: paths, expiryDays: 7)

        // Send upload request to device via Athena
        let filesData: [[String: Any]] = zip(paths.indices, uploadURLs).map { index, urlData in
            var headers = urlData.headers ?? [:]
            if headers.isEmpty {
                headers = ["x-ms-blob-type": "BlockBlob"]
            }

            let normalizedPath = urlData.path.isEmpty ? paths[index] : urlData.path

            return [
                "path": normalizedPath,
                "fn": normalizedPath,
                "url": urlData.url,
                "headers": headers
            ]
        }

        try await athenaService.uploadFiles(dongleId: dongleId, filesData: filesData)

        // Refresh queue
        await fetchUploadQueue(dongleId: dongleId)
    }

    @MainActor
    func cancelUpload(dongleId: String, uploadId: String) async {
        do {
            try await athenaService.cancelUpload(dongleId: dongleId, uploadIds: [uploadId])
            await fetchUploadQueue(dongleId: dongleId)
        } catch {
            Logger.data.error("Failed to cancel upload", error: error)
        }
    }

    @MainActor
    func cancelAllUploads(dongleId: String) async {
        let ids = uploadQueue.map { $0.id }
        guard !ids.isEmpty else { return }

        do {
            try await athenaService.cancelUpload(dongleId: dongleId, uploadIds: ids)
            await fetchUploadQueue(dongleId: dongleId)
        } catch {
            Logger.data.error("Failed to cancel all uploads", error: error)
        }
    }

    // MARK: - File Downloads

    func getAvailableFiles(route: Route) async throws -> [FileType: [RouteFileEntry]] {
        let files = try await apiClient.getRouteFiles(routeName: route.fullname)

        var availableFiles: [FileType: [RouteFileEntry]] = [:]

        for (key, urls) in files {
            guard let fileType = FileType(rawValue: key) else { continue }
            let entries = urls.compactMap { RouteFileEntry(urlString: $0) }
                .sorted { ($0.segmentNumber ?? -1) < ($1.segmentNumber ?? -1) }

            if !entries.isEmpty {
                availableFiles[fileType] = entries
            }
        }
        return availableFiles
    }

    func downloadFile(url: String, preferredName: String) async throws -> URL {
        guard let downloadURL = URL(string: url) else {
            throw APIError.invalidURL
        }

        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        let destinationURL = try destinationURL(for: preferredName, originalURL: downloadURL)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }

    private func destinationURL(for preferredName: String, originalURL: URL) throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)

        let sanitizedBase = sanitizeFileName(preferredName.isEmpty ? originalURL.lastPathComponent : preferredName)
        let (basename, ext) = splitNameAndExtension(sanitizedBase)

        var candidate = downloadsURL.appendingPathComponent(sanitizedBase)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = "(\(counter))"
            let newName = ext.isEmpty ? "\(basename) \(suffix)" : "\(basename) \(suffix).\(ext)"
            candidate = downloadsURL.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitNameAndExtension(_ name: String) -> (String, String) {
        let nsName = name as NSString
        let ext = nsName.pathExtension
        let base = ext.isEmpty ? name : nsName.deletingPathExtension
        return (base, ext)
    }
}
