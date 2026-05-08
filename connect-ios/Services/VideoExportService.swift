//
//  VideoExportService.swift
//  connect-ios
//
//  Created by Will Killebrew on 1/21/26.
//
//  Service for exporting video streams to iOS-compatible formats

import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
import os

/// Notification posted when video export starts (video player should pause)
extension Notification.Name {
    static let videoExportDidStart = Notification.Name("videoExportDidStart")
    static let videoExportDidEnd = Notification.Name("videoExportDidEnd")
}

/// Download statistics for live progress display
struct DownloadStats {
    var totalBytes: Int64 = 0
    var downloadedBytes: Int64 = 0
    var bytesPerSecond: Double = 0
    var currentSegment: Int = 0
    var totalSegments: Int = 0
    var phase: DownloadPhase = .downloading

    enum DownloadPhase: String {
        case downloading = "Downloading"
        case converting = "Converting"
        case saving = "Saving"
        case complete = "Complete"
    }
    
    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }
    
    var estimatedTimeRemaining: TimeInterval? {
        guard bytesPerSecond > 0, totalBytes > downloadedBytes else { return nil }
        return Double(totalBytes - downloadedBytes) / bytesPerSecond
    }
    
    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
    
    var formattedDownloaded: String {
        ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }
    
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    var formattedETA: String? {
        guard let eta = estimatedTimeRemaining else { return nil }
        if eta < 60 {
            return "\(Int(eta))s remaining"
        } else if eta < 3600 {
            return "\(Int(eta / 60))m \(Int(eta.truncatingRemainder(dividingBy: 60)))s remaining"
        } else {
            return "\(Int(eta / 3600))h \(Int((eta / 60).truncatingRemainder(dividingBy: 60)))m remaining"
        }
    }
}

/// Service responsible for converting video formats to iOS-compatible MP4
@Observable
final class VideoExportService {
    static let shared = VideoExportService()
    
    // Export state
    private(set) var isExporting = false
    private(set) var exportProgress: Double = 0
    private(set) var downloadStats = DownloadStats()
    private var currentExportSession: AVAssetExportSession?
    
    // For speed calculation
    private var downloadStartTime: Date?
    private var lastBytesUpdate: Int64 = 0
    private var lastUpdateTime: Date?

    private let downloadQueue = DispatchQueue(label: "videoExport.hlsDownload")

    private final class HLSDownloadDelegate: NSObject, AVAssetDownloadDelegate {
        private var continuation: CheckedContinuation<URL, Error>?

        func download(_ task: AVAssetDownloadTask) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                task.resume()
            }
        }

        func urlSession(
            _ session: URLSession,
            assetDownloadTask: AVAssetDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            continuation?.resume(returning: location)
            continuation = nil
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            if let error {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }
    }
    
    /// Download delegate for real-time progress tracking
    private final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate {
        var onProgress: ((Int64, Int64) -> Void)?
        var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        
        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
        }
        
        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            // Move to temp location before continuation returns (file gets deleted after delegate returns)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".tmp")
            do {
                try FileManager.default.moveItem(at: location, to: tempURL)
                if let response = downloadTask.response {
                    continuation?.resume(returning: (tempURL, response))
                } else {
                    continuation?.resume(throwing: ExportError.downloadFailed)
                }
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
        
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            if let error {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }
    }
    
    private init() {}
    
    // MARK: - Public Types
    
    enum ExportQuality {
        case standard   // Uses qcamera HLS stream (~480p)
        case high       // Uses fcamera HEVC (1080p)
        
        var displayName: String {
            switch self {
            case .standard: return "Standard"
            case .high: return "High Quality"
            }
        }
        
        var description: String {
            switch self {
            case .standard: return "Faster download, smaller file (~480p)"
            case .high: return "Full resolution (1080p), may require upload"
            }
        }
    }
    
    enum CameraAngle: String, CaseIterable, Identifiable {
        case road = "qcameras"
        case roadFull = "cameras"
        case driver = "dcameras"
        case wide = "ecameras"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .road, .roadFull: return "Road Camera"
            case .driver: return "Driver Camera"
            case .wide: return "Wide Camera"
            }
        }
        
        var iconName: String {
            switch self {
            case .road, .roadFull: return "car"
            case .driver: return "person.fill"
            case .wide: return "camera.aperture"
            }
        }
        
        /// The corresponding FileType for this camera
        var fileType: FileType {
            switch self {
            case .road: return .qcameras
            case .roadFull: return .cameras
            case .driver: return .dcameras
            case .wide: return .ecameras
            }
        }
        
        /// HLS stream path component (for standard quality)
        var hlsPath: String {
            switch self {
            case .road, .roadFull: return "qcamera.m3u8"
            case .driver: return "dcamera.m3u8"
            case .wide: return "ecamera.m3u8"
            }
        }
    }
    
    enum ExportRange: Equatable {
        case currentSegment(Int)
        case fullDrive
        
        var displayName: String {
            switch self {
            case .currentSegment(let num): return "Segment \(num)"
            case .fullDrive: return "Full Drive"
            }
        }
    }
    
    struct ExportOptions {
        let quality: ExportQuality
        let camera: CameraAngle
        let range: ExportRange
        let routeFullname: String
        let routeDuration: TimeInterval
        let segmentDuration: TimeInterval
        
        init(
            quality: ExportQuality = .standard,
            camera: CameraAngle = .road,
            range: ExportRange = .fullDrive,
            routeFullname: String,
            routeDuration: TimeInterval,
            segmentDuration: TimeInterval = 60
        ) {
            self.quality = quality
            self.camera = camera
            self.range = range
            self.routeFullname = routeFullname
            self.routeDuration = routeDuration
            self.segmentDuration = segmentDuration
        }
        
        /// Estimated file size in bytes
        var estimatedSize: Int64 {
            let duration: TimeInterval
            switch range {
            case .currentSegment: duration = segmentDuration
            case .fullDrive: duration = routeDuration
            }
            
            // Rough estimates: standard ~1MB/min, high ~5MB/min
            let bytesPerSecond: Double = quality == .standard ? 17000 : 85000
            return Int64(duration * bytesPerSecond)
        }
        
        /// Formatted estimated size string
        var estimatedSizeString: String {
            ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
        }
        
        /// Estimated duration string
        var durationString: String {
            let duration: TimeInterval
            switch range {
            case .currentSegment: duration = segmentDuration
            case .fullDrive: duration = routeDuration
            }
            return formatDuration(duration)
        }
    }
    
    enum ExportError: LocalizedError {
        case invalidURL
        case exportFailed(String)
        case cancelled
        case assetLoadFailed
        case streamNotAvailable
        case noVideoTrack
        case unsupportedFormat
        case missingSegments
        case downloadFailed
        case invalidOutput(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid video URL"
            case .exportFailed(let reason): return "Export failed: \(reason)"
            case .cancelled: return "Export was cancelled"
            case .assetLoadFailed: return "Failed to load video asset"
            case .streamNotAvailable: return "This camera angle is not available for this drive. The video may not have been uploaded from the device."
            case .noVideoTrack: return "No video track found"
            case .unsupportedFormat: return "Unsupported video format"
            case .missingSegments: return "No video segments found to export"
            case .downloadFailed: return "Failed to download video segments"
            case .invalidOutput(let reason): return "The exported video is invalid and cannot be saved to Photos. \(reason)"
            }
        }

        /// User-friendly message with recovery suggestions
        var userFriendlyMessage: String {
            switch self {
            case .streamNotAvailable:
                return "This camera angle isn't available. The video may not have been uploaded from the device yet."
            case .downloadFailed:
                return "Download failed. Please check your internet connection and try again."
            case .invalidOutput:
                return "The video couldn't be processed correctly. Try downloading a different quality or camera angle."
            case .cancelled:
                return "Download was cancelled."
            case .missingSegments:
                return "No video segments found for this drive."
            case .exportFailed(let reason):
                if reason.lowercased().contains("exit code") {
                    return "Video conversion failed. Try a different quality setting."
                }
                return "Export failed: \(reason)"
            default:
                return errorDescription ?? "An unknown error occurred."
            }
        }
    }
    
    // MARK: - Export Methods
    
    /// Exports an HLS stream to MP4 format
    /// - Parameters:
    ///   - streamURL: The HLS stream URL (m3u8)
    ///   - outputName: Desired output filename (without extension)
    /// - Returns: URL to the exported MP4 file
    @MainActor
    func exportHLSToMP4(streamURL: URL, outputName: String) async throws -> URL {
        isExporting = true
        exportProgress = 0
        
        // Notify that export is starting (video player should pause/release)
        NotificationCenter.default.post(name: .videoExportDidStart, object: nil)
        
        // Wait for player to fully release the stream
        // AVPlayer needs time to tear down its connection
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        defer {
            isExporting = false
            currentExportSession = nil
            // Notify that export has ended
            NotificationCenter.default.post(name: .videoExportDidEnd, object: nil)
        }
        
        Logger.data.debug("Starting HLS export from: \(streamURL.absoluteString)")

        // Download HLS stream to a local asset first
        let localAssetURL = try await downloadHLSAsset(from: streamURL, outputName: outputName)
        Logger.data.debug("Downloaded HLS asset to: \(localAssetURL.path)")

        // Create AVAsset from local HLS package
        let asset = AVURLAsset(url: localAssetURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        
        // Load asset properties
        do {
            let (isPlayable, duration, isExportable, hasProtectedContent) = try await asset.load(
                .isPlayable,
                .duration,
                .isExportable,
                .hasProtectedContent
            )

            guard isPlayable else {
                throw ExportError.assetLoadFailed
            }

            Logger.data.debug("Asset loaded, duration: \(CMTimeGetSeconds(duration))s")
            Logger.data.debug("Asset exportable: \(isExportable), protected: \(hasProtectedContent)")

            if !isExportable {
                throw ExportError.exportFailed("Asset is not exportable")
            }
        } catch let error as ExportError {
            throw error
        } catch {
            // Check if this is a "not found" error (404)
            let errorDescription = error.localizedDescription.lowercased()
            if errorDescription.contains("not found") || errorDescription.contains("404") {
                Logger.data.error("Stream not available (404)", error: error)
                throw ExportError.streamNotAvailable
            }
            Logger.data.error("Failed to load asset properties", error: error)
            throw ExportError.assetLoadFailed
        }
        
        // Check which export presets are compatible with this asset
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        Logger.data.debug("Compatible presets: \(compatiblePresets.joined(separator: ", "))")
        
        // Create export session
        // Try presets in order of preference from compatible ones
        let preferredPresets = [
            AVAssetExportPresetPassthrough,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetLowQuality,
            AVAssetExportPresetHighestQuality,
            AVAssetExportPreset1280x720,
            AVAssetExportPreset960x540,
            AVAssetExportPreset640x480
        ]
        
        var exportSession: AVAssetExportSession?
        for preset in preferredPresets {
            if compatiblePresets.contains(preset) {
                if let session = AVAssetExportSession(asset: asset, presetName: preset) {
                    Logger.data.debug("Using export preset: \(preset)")
                    exportSession = session
                    break
                }
            }
        }
        
        guard let exportSession = exportSession else {
            throw ExportError.exportFailed("No compatible export preset found. Compatible: \(compatiblePresets.joined(separator: ", "))")
        }

        // Force full duration time range to avoid interruptions
        exportSession.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        currentExportSession = exportSession
        
        // Configure output file type based on what the export session supports
        let supportedTypes = exportSession.supportedFileTypes
        Logger.data.debug("Supported output types: \(supportedTypes.map { $0.rawValue }.joined(separator: ", "))")

        let outputFileType: AVFileType
        if supportedTypes.contains(.mp4) {
            outputFileType = .mp4
        } else if supportedTypes.contains(.mov) {
            outputFileType = .mov
        } else if let firstType = supportedTypes.first {
            outputFileType = firstType
        } else {
            throw ExportError.exportFailed("No supported output file types")
        }

        let fileExtension = outputFileType == .mov ? "mov" : "mp4"
        let outputURL = try createOutputURL(filename: "\(outputName).\(fileExtension)")
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Start progress monitoring
        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                await MainActor.run {
                    self.exportProgress = Double(exportSession.progress)
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        // Check if task was cancelled before starting export
        if Task.isCancelled {
            Logger.data.debug("Task was cancelled before export started")
            progressTask.cancel()
            throw ExportError.cancelled
        }
        
        Logger.data.debug("Starting AVAssetExportSession.export()...")
        
        // Begin background task to prevent iOS from interrupting the export
        #if canImport(UIKit)
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "VideoExport") {
            // Cleanup if background time expires
            Logger.data.warning("Background time expired during export")
            exportSession.cancelExport()
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        
        Logger.data.debug("Background task started: \(backgroundTaskID.rawValue)")
        #endif
        
        // Export
        await exportSession.export()
        
        // End background task
        #if canImport(UIKit)
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            Logger.data.debug("Background task ended")
        }
        #endif
        
        Logger.data.debug("AVAssetExportSession.export() returned, status: \(exportSession.status.rawValue)")
        progressTask.cancel()
        
        // Check result
        switch exportSession.status {
        case .completed:
            exportProgress = 1.0
            Logger.data.debug("Export completed: \(outputURL.path)")
            return outputURL
            
        case .failed:
            let error = exportSession.error
            let errorMessage = error?.localizedDescription ?? "Unknown error"
            let nsError = error as NSError?
            Logger.data.error("Export failed: \(errorMessage) (code: \(nsError?.code ?? -1), domain: \(nsError?.domain ?? "unknown"))")
            
            // Check if this looks like a cancellation
            if nsError?.code == -16976 || errorMessage.contains("Operation Stopped") {
                Logger.data.debug("Export was stopped/cancelled")
                throw ExportError.cancelled
            }
            
            throw ExportError.exportFailed(errorMessage)
            
        case .cancelled:
            Logger.data.debug("Export status: cancelled")
            throw ExportError.cancelled
            
        default:
            throw ExportError.exportFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }

    // MARK: - Segment Export (FFmpeg-based)

    /// Downloads .ts segments and remuxes them to MP4 using FFmpeg
    /// This approach works because AVFoundation cannot directly read MPEG-TS containers,
    /// but FFmpeg handles them natively.
    ///
    /// Downloads up to 3 segments concurrently for faster multi-segment exports.
    /// Each segment is retried up to 2 times on failure.
    func exportSegmentsToMP4(segmentURLs: [URL], outputName: String) async throws -> URL {
        guard !segmentURLs.isEmpty else {
            throw ExportError.missingSegments
        }

        await MainActor.run {
            isExporting = true
            exportProgress = 0
            downloadStats = DownloadStats()
            downloadStats.totalSegments = segmentURLs.count
        }

        Logger.data.debug("[VideoExportService] Starting FFmpeg-based segment export with \(segmentURLs.count) segments")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("connect-export-\(UUID().uuidString)", isDirectory: true)

        defer {
            Task { @MainActor in
                isExporting = false
                currentExportSession = nil
            }
        }

        // Phase 0: Get total file sizes via HEAD requests
        let totalSize = await fetchTotalSize(for: segmentURLs)
        await MainActor.run {
            downloadStats.totalBytes = totalSize
        }

        Logger.data.debug("[VideoExportService] Total download size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // For foreground, use default config (background config doesn't support async/await well)
        let foregroundConfig = URLSessionConfiguration.default
        foregroundConfig.timeoutIntervalForRequest = 60
        foregroundConfig.timeoutIntervalForResource = 600
        let session = URLSession(configuration: foregroundConfig)

        // Reset speed tracking
        await MainActor.run {
            downloadStartTime = Date()
            lastUpdateTime = Date()
            lastBytesUpdate = 0
        }

        // Phase 1: Download segments with parallel downloads (up to 3 concurrent)
        let localURLs: [URL]
        do {
            localURLs = try await downloadSegmentsParallel(
                segmentURLs: segmentURLs,
                session: session,
                tempDir: tempDir,
                maxConcurrent: 3
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: tempDir)
            throw ExportError.cancelled
        } catch let error as ExportError {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        } catch {
            Logger.data.error("[VideoExportService] Failed to download segments", error: error)
            try? FileManager.default.removeItem(at: tempDir)
            throw ExportError.downloadFailed
        }

        // Phase 2: Remux with FFmpeg (85% - 95% progress)
        await MainActor.run {
            exportProgress = 0.85
            downloadStats.phase = .converting
        }

        let outputURL = try createOutputURL(filename: "\(outputName).mp4")

        // Poll TSRemuxService.progress for real frame-based converting progress.
        // TSRemuxService reports progress via FFmpegKit statistics callback (frame count).
        let remuxProgressTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    let remuxProgress = TSRemuxService.shared.progress
                    self.exportProgress = 0.85 + (remuxProgress * 0.10)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        do {
            try Task.checkCancellation()

            Logger.data.debug("[VideoExportService] Starting FFmpeg remux of \(localURLs.count) segments")

            _ = try await TSRemuxService.shared.remuxSegmentsToMP4(
                segmentURLs: localURLs,
                outputURL: outputURL
            )

            remuxProgressTask.cancel()

            await MainActor.run {
                exportProgress = 0.95
            }
        } catch is CancellationError {
            remuxProgressTask.cancel()
            TSRemuxService.shared.cancel()
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.cancelled
        } catch let error as TSRemuxService.RemuxError {
            remuxProgressTask.cancel()
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: outputURL)
            if case .cancelled = error {
                throw ExportError.cancelled
            }
            Logger.data.error("[VideoExportService] FFmpeg remux failed: \(error.localizedDescription)")
            throw ExportError.exportFailed(error.localizedDescription)
        }

        // Cleanup temp download files
        try? FileManager.default.removeItem(at: tempDir)

        // Verify output exists
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExportError.exportFailed("Output file not created")
        }

        // Phase 3: Validate output MP4 before saving to Photos
        try await validateOutputMP4(at: outputURL)

        if let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let fileSize = attributes[.size] as? NSNumber {
            Logger.data.debug("[VideoExportService] Export complete: \(outputURL.path) (\(fileSize.intValue) bytes)")
        }

        await MainActor.run {
            exportProgress = 0.95
            downloadStats.phase = .saving
        }

        return outputURL
    }

    // MARK: - Parallel Segment Download

    /// Downloads segments with up to `maxConcurrent` parallel downloads.
    /// Results are returned in the original segment order.
    /// Each segment is retried up to 2 times on failure.
    private func downloadSegmentsParallel(
        segmentURLs: [URL],
        session: URLSession,
        tempDir: URL,
        maxConcurrent: Int
    ) async throws -> [URL] {
        // Pre-allocate result array to maintain ordering
        var results = [URL?](repeating: nil, count: segmentURLs.count)
        // Track bytes per-segment to avoid bouncing when parallel delegates update
        let segmentBytes = OSAllocatedUnfairLock(initialState: [Int: Int64]())
        let completedCount = OSAllocatedUnfairLock(initialState: 0)

        try await withThrowingTaskGroup(of: (Int, URL, Int64).self) { group in
            var nextIndex = 0

            // Seed the group with initial concurrent tasks
            while nextIndex < min(maxConcurrent, segmentURLs.count) {
                let index = nextIndex
                let url = segmentURLs[index]
                group.addTask {
                    try Task.checkCancellation()
                    let (localURL, size) = try await self.downloadSegmentWithRetry(
                        url: url,
                        index: index,
                        session: session,
                        tempDir: tempDir,
                        segmentBytes: segmentBytes
                    )
                    return (index, localURL, size)
                }
                nextIndex += 1
            }

            // As each task completes, add the next one
            for try await (index, localURL, segmentSize) in group {
                try Task.checkCancellation()

                results[index] = localURL

                let completed = completedCount.withLock { state -> Int in
                    state += 1
                    return state
                }

                await MainActor.run {
                    self.downloadStats.currentSegment = completed
                }

                Logger.data.debug("[VideoExportService] Segment \(index + 1) saved (\(segmentSize) bytes)")

                // Add next task if available
                if nextIndex < segmentURLs.count {
                    let nextIdx = nextIndex
                    let nextURL = segmentURLs[nextIdx]
                    group.addTask {
                        try Task.checkCancellation()
                        let (localURL, size) = try await self.downloadSegmentWithRetry(
                            url: nextURL,
                            index: nextIdx,
                            session: session,
                            tempDir: tempDir,
                            segmentBytes: segmentBytes
                        )
                        return (nextIdx, localURL, size)
                    }
                    nextIndex += 1
                }
            }
        }

        return results.compactMap { $0 }
    }

    /// Downloads a single segment, retrying up to 2 times on failure.
    private func downloadSegmentWithRetry(
        url: URL,
        index: Int,
        session: URLSession,
        tempDir: URL,
        segmentBytes: OSAllocatedUnfairLock<[Int: Int64]>,
        maxRetries: Int = 2
    ) async throws -> (URL, Int64) {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                try Task.checkCancellation()

                if attempt > 0 {
                    Logger.data.debug("[VideoExportService] Retry \(attempt)/\(maxRetries) for segment \(index + 1)")
                    // Exponential backoff: 1s, 2s
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }

                let (downloadURL, response, segmentSize) = try await downloadWithProgress(
                    url: url,
                    session: session,
                    segmentIndex: index,
                    segmentBytes: segmentBytes
                )

                if let httpResponse = response as? HTTPURLResponse {
                    guard httpResponse.statusCode == 200 else {
                        Logger.data.error("[VideoExportService] Segment \(index + 1) HTTP \(httpResponse.statusCode)")
                        throw ExportError.downloadFailed
                    }
                }

                let fileExtension = url.pathExtension.isEmpty ? "ts" : url.pathExtension
                let destination = tempDir.appendingPathComponent("segment_\(String(format: "%04d", index)).\(fileExtension)")
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: downloadURL, to: destination)

                return (destination, segmentSize)

            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                Logger.data.error("[VideoExportService] Segment \(index + 1) attempt \(attempt + 1) failed: \(error.localizedDescription)")
            }
        }

        throw lastError ?? ExportError.downloadFailed
    }

    // MARK: - Output Validation

    /// Validates an output MP4 file with AVAsset before handing it to Photos.
    /// Catches corrupt files that would cause PHPhotosError.invalidResource (3302).
    private func validateOutputMP4(at url: URL) async throws {
        Logger.data.debug("[VideoExportService] Validating output MP4: \(url.lastPathComponent)")

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        do {
            let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            guard isPlayable else {
                Logger.data.error("[VideoExportService] Output MP4 is not playable")
                try? FileManager.default.removeItem(at: url)
                throw ExportError.invalidOutput("Video is not playable. The conversion may have failed.")
            }

            guard durationSeconds > 0 else {
                Logger.data.error("[VideoExportService] Output MP4 has zero duration")
                try? FileManager.default.removeItem(at: url)
                throw ExportError.invalidOutput("Video has zero duration. The source file may be corrupted.")
            }

            Logger.data.debug("[VideoExportService] Output validated: playable=true, duration=\(durationSeconds)s")
        } catch let error as ExportError {
            throw error
        } catch {
            Logger.data.error("[VideoExportService] Failed to validate output: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            throw ExportError.invalidOutput("Could not verify video integrity: \(error.localizedDescription)")
        }
    }
    
    // MARK: - File Size Fetching
    
    /// Fetches total size of all segment files using HEAD requests
    private func fetchTotalSize(for urls: [URL]) async -> Int64 {
        var totalSize: Int64 = 0
        
        await withTaskGroup(of: Int64.self) { group in
            for url in urls {
                group.addTask {
                    await self.fetchFileSize(for: url)
                }
            }
            
            for await size in group {
                totalSize += size
            }
        }
        
        return totalSize
    }
    
    /// Fetches file size for a single URL using HEAD request
    private func fetchFileSize(for url: URL) async -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let size = Int64(contentLength) {
                return size
            }
        } catch {
            Logger.data.debug("[VideoExportService] Failed to get size for \(url.lastPathComponent): \(error.localizedDescription)")
        }
        
        return 0
    }
    
    /// Downloads a file with real-time progress updates
    /// Uses per-segment byte tracking to avoid bouncing progress with parallel downloads.
    private func downloadWithProgress(
        url: URL,
        session: URLSession,
        segmentIndex: Int,
        segmentBytes: OSAllocatedUnfairLock<[Int: Int64]>
    ) async throws -> (URL, URLResponse, Int64) {
        let delegate = ProgressDownloadDelegate()
        let delegateSession = URLSession(
            configuration: session.configuration,
            delegate: delegate,
            delegateQueue: nil
        )

        // Track bytes for speed calculation
        var lastProgressUpdate = Date()
        var lastProgressBytes: Int64 = 0

        // Set up progress callback for real-time updates
        delegate.onProgress = { [weak self] bytesWritten, totalExpected in
            guard let self = self else { return }

            let now = Date()

            // Update this segment's bytes and compute total across all segments
            let totalDownloaded = segmentBytes.withLock { state -> Int64 in
                state[segmentIndex] = bytesWritten
                return state.values.reduce(0, +)
            }

            // Calculate instantaneous speed
            let elapsed = now.timeIntervalSince(lastProgressUpdate)
            var speed: Double = 0
            if elapsed > 0.1 {
                let bytesInInterval = bytesWritten - lastProgressBytes
                speed = Double(bytesInInterval) / elapsed
                lastProgressUpdate = now
                lastProgressBytes = bytesWritten
            }

            Task { @MainActor in
                self.downloadStats.downloadedBytes = totalDownloaded

                // Update exportProgress based on actual bytes downloaded
                if self.downloadStats.totalBytes > 0 {
                    let byteProgress = Double(totalDownloaded) / Double(self.downloadStats.totalBytes)
                    self.exportProgress = min(byteProgress * 0.85, 0.85)
                }

                if speed > 0 {
                    // Smooth the speed with exponential moving average
                    if self.downloadStats.bytesPerSecond > 0 {
                        self.downloadStats.bytesPerSecond = self.downloadStats.bytesPerSecond * 0.7 + speed * 0.3
                    } else {
                        self.downloadStats.bytesPerSecond = speed
                    }
                }
            }
        }

        // Perform download with delegate
        let (downloadURL, response) = try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let task = delegateSession.downloadTask(with: url)
            task.resume()
        }

        // Get final file size
        var fileSize: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: downloadURL.path),
           let size = attributes[.size] as? NSNumber {
            fileSize = size.int64Value
        }

        // Final update with accurate per-segment total
        let totalDownloaded = segmentBytes.withLock { state -> Int64 in
            state[segmentIndex] = fileSize
            return state.values.reduce(0, +)
        }
        await MainActor.run {
            downloadStats.downloadedBytes = totalDownloaded
            if downloadStats.totalBytes > 0 {
                let byteProgress = Double(totalDownloaded) / Double(downloadStats.totalBytes)
                exportProgress = min(byteProgress * 0.8, 0.8)
            }
            lastUpdateTime = Date()
            lastBytesUpdate = totalDownloaded
        }

        delegateSession.invalidateAndCancel()

        return (downloadURL, response, fileSize)
    }

    // MARK: - HLS Download

    private func downloadHLSAsset(from streamURL: URL, outputName: String) async throws -> URL {
        let asset = AVURLAsset(url: streamURL)

        let configuration = URLSessionConfiguration.background(withIdentifier: "hls.download.\(UUID().uuidString)")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = false

        let delegate = HLSDownloadDelegate()
        let session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: delegate,
            delegateQueue: OperationQueue.main
        )

        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: outputName,
            assetArtworkData: nil,
            options: nil
        ) else {
            throw ExportError.exportFailed("Failed to create HLS download task")
        }

        Logger.data.debug("Starting HLS download task: \(task.taskIdentifier)")
        let location = try await delegate.download(task)
        Logger.data.debug("HLS download task completed at: \(location.path)")
        return location
    }
    
    /// Remuxes an HEVC file into an MP4 container (for high quality exports)
    /// - Parameters:
    ///   - hevcURL: URL to the HEVC file
    ///   - outputName: Desired output filename (without extension)
    /// - Returns: URL to the exported MP4 file
    @MainActor
    func remuxHEVCToMP4(hevcURL: URL, outputName: String) async throws -> URL {
        isExporting = true
        exportProgress = 0
        
        defer {
            isExporting = false
        }
        
        Logger.data.debug("Starting HEVC remux from: \(hevcURL.path)")
        
        // Create asset
        let asset = AVURLAsset(url: hevcURL)
        
        // Load tracks
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.load(.tracks)
        } catch {
            Logger.data.error("Failed to load HEVC tracks", error: error)
            throw ExportError.assetLoadFailed
        }
        
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw ExportError.noVideoTrack
        }
        
        // Create composition
        let composition = AVMutableComposition()
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Could not create composition track")
        }
        
        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        
        do {
            try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        } catch {
            throw ExportError.exportFailed("Could not insert video track: \(error.localizedDescription)")
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ExportError.exportFailed("Could not create export session")
        }
        
        currentExportSession = exportSession
        
        // Configure output
        let outputURL = try createOutputURL(filename: "\(outputName).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        // Progress monitoring
        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                await MainActor.run {
                    self.exportProgress = Double(exportSession.progress)
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        
        // Export
        await exportSession.export()
        progressTask.cancel()
        
        switch exportSession.status {
        case .completed:
            exportProgress = 1.0
            Logger.data.debug("HEVC remux completed: \(outputURL.path)")
            return outputURL
            
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            throw ExportError.exportFailed(errorMessage)
            
        case .cancelled:
            throw ExportError.cancelled
            
        default:
            throw ExportError.exportFailed("Unexpected status")
        }
    }
    
    /// Cancels the current export operation
    func cancelExport() {
        currentExportSession?.cancelExport()
        currentExportSession = nil
        isExporting = false
        exportProgress = 0
        Logger.data.debug("Export cancelled")
    }
    
    // MARK: - Helper Methods
    
    private func createOutputURL(filename: String) throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        let exportsURL = documentsURL.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsURL, withIntermediateDirectories: true)
        
        return exportsURL.appendingPathComponent(filename)
    }
    
    /// Cleans up old exported files
    func cleanupExports(olderThan days: Int = 7) throws {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        
        let exportsURL = documentsURL.appendingPathComponent("Exports", isDirectory: true)
        
        guard FileManager.default.fileExists(atPath: exportsURL.path) else { return }
        
        let files = try FileManager.default.contentsOfDirectory(
            at: exportsURL,
            includingPropertiesForKeys: [.creationDateKey]
        )
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        
        for file in files {
            let resources = try file.resourceValues(forKeys: [.creationDateKey])
            if let creationDate = resources.creationDate, creationDate < cutoffDate {
                try FileManager.default.removeItem(at: file)
                Logger.data.debug("Cleaned up old export: \(file.lastPathComponent)")
            }
        }
    }
}

// MARK: - Duration Formatting Helper

private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    
    if minutes > 0 {
        return "\(minutes):\(String(format: "%02d", seconds))"
    } else {
        return "0:\(String(format: "%02d", seconds))"
    }
}
