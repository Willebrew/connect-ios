//
//  FileDownloadService.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/14/25.
//
//  Service for downloading route files (logs, videos, etc.)
//

import Foundation
import Combine
import os

@Observable
final class FileDownloadService: NSObject {
    static let shared = FileDownloadService()

    // Active downloads
    private(set) var activeDownloads: [String: DownloadTask] = [:]

    // Progress publishers
    var downloadProgress = PassthroughSubject<(String, Double), Never>()
    var downloadComplete = PassthroughSubject<(String, URL), Never>()
    var downloadFailed = PassthroughSubject<(String, Error), Never>()

    private var downloadSession: URLSession!

    override private init() {
        super.init()

        let config = URLSessionConfiguration.background(withIdentifier: "ai.comma.connect.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Download Management

    /// Starts downloading a file from a URL
    func downloadFile(from url: URL, filename: String) throws {
        // Check if already downloading
        if activeDownloads[filename] != nil {
            throw DownloadError.alreadyDownloading
        }

        // Create download task
        let task = downloadSession.downloadTask(with: url)

        let downloadTask = DownloadTask(
            task: task,
            filename: filename,
            url: url,
            progress: 0,
            totalBytes: 0,
            downloadedBytes: 0
        )

        activeDownloads[filename] = downloadTask

        task.resume()

        Logger.data.debug("Started download: \(filename)")
    }

    /// Cancels a download
    func cancelDownload(filename: String) {
        guard let downloadTask = activeDownloads[filename] else { return }

        downloadTask.task.cancel()
        activeDownloads.removeValue(forKey: filename)

        Logger.data.debug("Cancelled download: \(filename)")
    }

    /// Cancels all downloads
    func cancelAllDownloads() {
        for (_, downloadTask) in activeDownloads {
            downloadTask.task.cancel()
        }
        activeDownloads.removeAll()

        Logger.data.debug("Cancelled all downloads")
    }

    /// Gets the progress of a download
    func getProgress(for filename: String) -> Double? {
        return activeDownloads[filename]?.progress
    }

    // MARK: - File Management

    /// Gets the downloads directory URL
    private func getDownloadsDirectory() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)

        // Create downloads directory if it doesn't exist
        try FileManager.default.createDirectory(
            at: downloadsURL,
            withIntermediateDirectories: true
        )
        return downloadsURL
    }

    /// Moves downloaded file to permanent location
    private func moveDownloadedFile(from tempURL: URL, filename: String) throws -> URL {
        let downloadsURL = try getDownloadsDirectory()
        let destinationURL = downloadsURL.appendingPathComponent(filename)

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        // Move file
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        return destinationURL
    }

    /// Lists all downloaded files
    func listDownloadedFiles() throws -> [URL] {
        let downloadsURL = try getDownloadsDirectory()
        return try FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
    }

    /// Deletes a downloaded file
    func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        Logger.data.debug("Deleted file: \(url.lastPathComponent)")
    }

    /// Gets total size of downloaded files
    func getTotalDownloadedSize() throws -> Int64 {
        let files = try listDownloadedFiles()
        var totalSize: Int64 = 0

        for file in files {
            let resources = try file.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resources.fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    // MARK: - Types

    struct DownloadTask {
        let task: URLSessionDownloadTask
        let filename: String
        let url: URL
        var progress: Double
        var totalBytes: Int64
        var downloadedBytes: Int64
    }

    enum DownloadError: LocalizedError {
        case alreadyDownloading
        case downloadFailed(String)
        case fileMoveFailed

        var errorDescription: String? {
            switch self {
            case .alreadyDownloading:
                return "This file is already being downloaded"
            case .downloadFailed(let message):
                return "Download failed: \(message)"
            case .fileMoveFailed:
                return "Failed to move downloaded file"
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension FileDownloadService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Find the download task
        guard let (filename, task) = activeDownloads.first(where: { $0.value.task == downloadTask }) else {
            return
        }

        do {
            // Move file to permanent location
            let permanentURL = try moveDownloadedFile(from: location, filename: filename)

            // Remove from active downloads
            activeDownloads.removeValue(forKey: filename)

            // Notify completion
            DispatchQueue.main.async {
                self.downloadComplete.send((filename, permanentURL))
            }

            Logger.data.debug("Download complete: \(filename)")

        } catch {
            Logger.data.error("Failed to move downloaded file", error: error)

            activeDownloads.removeValue(forKey: filename)

            DispatchQueue.main.async {
                self.downloadFailed.send((filename, error))
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Find and update the download task
        guard let entry = activeDownloads.first(where: { $0.value.task == downloadTask }) else {
            return
        }

        let filename = entry.key
        var task = entry.value

        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        task.progress = progress
        task.totalBytes = totalBytesExpectedToWrite
        task.downloadedBytes = totalBytesWritten

        activeDownloads[filename] = task

        // Notify progress
        DispatchQueue.main.async {
            self.downloadProgress.send((filename, progress))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let (filename, _) = activeDownloads.first(where: { $0.value.task == downloadTask }) else {
            return
        }

        if let error = error {
            Logger.data.error("Download failed: \(filename)", error: error)

            activeDownloads.removeValue(forKey: filename)

            DispatchQueue.main.async {
                self.downloadFailed.send((filename, error))
            }
        }
    }
}
