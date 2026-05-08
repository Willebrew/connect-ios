//
//  TSRemuxService.swift
//  connect-ios
//
//  Created by Will Killebrew on 1/21/26.
//
//  Service for remuxing MPEG-TS (.ts) files to MP4 using FFmpegKit
//  Uses Beeper's ffmpeg-kit fork: https://github.com/beeper/ffmpeg-kit

import Foundation
import ffmpegkit

/// Service for remuxing MPEG-TS segments to MP4 using FFmpegKit
@Observable
final class TSRemuxService {
    static let shared = TSRemuxService()

    private(set) var isProcessing = false
    private(set) var progress: Double = 0

    /// comma.ai cameras record at 20fps, segments are ~60 seconds
    private static let fps = 20
    private static let estimatedFramesPerSegment = fps * 60 // 1200

    private init() {}

    // MARK: - Public Types

    enum RemuxError: LocalizedError {
        case noInputFiles
        case ffmpegFailed(String)
        case outputNotCreated
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noInputFiles:
                return "No input files provided"
            case .ffmpegFailed(let reason):
                return "FFmpeg failed: \(reason)"
            case .outputNotCreated:
                return "Output file was not created"
            case .cancelled:
                return "Remux was cancelled"
            }
        }
    }

    // MARK: - Public Methods

    /// Remuxes multiple .ts segment files into a single MP4 file
    func remuxSegmentsToMP4(segmentURLs: [URL], outputURL: URL) async throws -> URL {
        guard !segmentURLs.isEmpty else {
            throw RemuxError.noInputFiles
        }

        await MainActor.run {
            isProcessing = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        Logger.data.debug("[TSRemuxService] Starting FFmpeg remux of \(segmentURLs.count) segments")

        // Remove existing output file
        try? FileManager.default.removeItem(at: outputURL)

        if segmentURLs.count == 1 {
            return try await remuxSingleSegment(segmentURLs[0], to: outputURL)
        } else {
            return try await concatAndRemux(segmentURLs, to: outputURL)
        }
    }

    /// Cancels any in-progress FFmpeg operation
    func cancel() {
        FFmpegKit.cancel()
        Logger.data.debug("[TSRemuxService] Cancelled")
    }

    // MARK: - Private Methods

    /// Remuxes a single video file to MP4
    private func remuxSingleSegment(_ inputURL: URL, to outputURL: URL) async throws -> URL {
        Logger.data.debug("[TSRemuxService] Remuxing single segment: \(inputURL.lastPathComponent)")

        let fileExtension = inputURL.pathExtension.lowercased()

        var arguments: [String] = []
        var expectedFrames = 0

        if fileExtension == "hevc" {
            arguments = [
                "-f", "hevc",
                "-framerate", "20",
                "-i", inputURL.path,
                "-c:v", "hevc_videotoolbox",
                "-b:v", "10M",
                "-tag:v", "hvc1",
                "-movflags", "+faststart",
                "-y",
                outputURL.path
            ]
            expectedFrames = Self.estimatedFramesPerSegment
        } else {
            arguments = [
                "-i", inputURL.path,
                "-c", "copy",
                "-movflags", "+faststart",
                "-y",
                outputURL.path
            ]
        }

        return try await executeFFmpeg(
            arguments: arguments,
            outputURL: outputURL,
            expectedFrames: expectedFrames,
            baseProgress: 0,
            progressRange: 1.0
        )
    }

    /// Concatenates multiple video files and remuxes to MP4
    private func concatAndRemux(_ inputURLs: [URL], to outputURL: URL) async throws -> URL {
        Logger.data.debug("[TSRemuxService] Concatenating \(inputURLs.count) segments")

        let fileExtension = inputURLs.first?.pathExtension.lowercased() ?? "ts"

        let tempDir = FileManager.default.temporaryDirectory

        if fileExtension == "hevc" {
            var intermediateURLs: [URL] = []

            defer {
                for url in intermediateURLs {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            let segmentCount = inputURLs.count
            // Reserve 80% of progress for encoding, 20% for final concat (which is fast)
            let encodingRange = 0.8
            let perSegmentRange = encodingRange / Double(segmentCount)

            for (index, inputURL) in inputURLs.enumerated() {
                let intermediateURL = tempDir.appendingPathComponent("intermediate_\(UUID().uuidString)_\(index).mp4")

                Logger.data.debug("[TSRemuxService] Remuxing HEVC segment \(index + 1)/\(segmentCount)")

                let arguments = [
                    "-f", "hevc",
                    "-framerate", "20",
                    "-i", inputURL.path,
                    "-c:v", "hevc_videotoolbox",
                    "-b:v", "10M",
                    "-tag:v", "hvc1",
                    "-movflags", "+faststart",
                    "-y",
                    intermediateURL.path
                ]

                _ = try await executeFFmpeg(
                    arguments: arguments,
                    outputURL: intermediateURL,
                    expectedFrames: Self.estimatedFramesPerSegment,
                    baseProgress: Double(index) * perSegmentRange,
                    progressRange: perSegmentRange
                )
                intermediateURLs.append(intermediateURL)
            }

            // Now concat all intermediate MP4s using concat demuxer (stream copy, no re-encode)
            let concatListURL = tempDir.appendingPathComponent("concat_\(UUID().uuidString).txt")
            let fileList = intermediateURLs.map { "file '\($0.path)'" }.joined(separator: "\n")
            try fileList.write(to: concatListURL, atomically: true, encoding: .utf8)

            defer {
                try? FileManager.default.removeItem(at: concatListURL)
            }

            Logger.data.debug("[TSRemuxService] Concatenating \(intermediateURLs.count) intermediate MP4s")

            let concatArguments = [
                "-f", "concat",
                "-safe", "0",
                "-i", concatListURL.path,
                "-c", "copy",
                "-movflags", "+faststart",
                "-y",
                outputURL.path
            ]

            // Concat is stream copy — near-instant, no frame progress needed
            return try await executeFFmpeg(
                arguments: concatArguments,
                outputURL: outputURL,
                expectedFrames: 0,
                baseProgress: encodingRange,
                progressRange: 1.0 - encodingRange
            )
        } else {
            // For .ts files, use concat demuxer directly (stream copy)
            let concatListURL = tempDir.appendingPathComponent("concat_\(UUID().uuidString).txt")
            let fileList = inputURLs.map { "file '\($0.path)'" }.joined(separator: "\n")
            try fileList.write(to: concatListURL, atomically: true, encoding: .utf8)

            Logger.data.debug("[TSRemuxService] Created concat list at: \(concatListURL.path)")

            defer {
                try? FileManager.default.removeItem(at: concatListURL)
            }

            let arguments = [
                "-f", "concat",
                "-safe", "0",
                "-i", concatListURL.path,
                "-c", "copy",
                "-movflags", "+faststart",
                "-y",
                outputURL.path
            ]

            return try await executeFFmpeg(
                arguments: arguments,
                outputURL: outputURL,
                expectedFrames: 0,
                baseProgress: 0,
                progressRange: 1.0
            )
        }
    }

    // MARK: - FFmpeg Execution

    /// Executes FFmpeg with arguments and returns the output URL on success.
    /// When `expectedFrames` > 0, uses the async API with a statistics callback
    /// to report real frame-based progress.
    private func executeFFmpeg(
        arguments: [String],
        outputURL: URL,
        expectedFrames: Int = 0,
        baseProgress: Double = 0,
        progressRange: Double = 0
    ) async throws -> URL {
        let command = arguments.joined(separator: " ")
        Logger.data.debug("[TSRemuxService] Executing: ffmpeg \(command)")

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            func resumeOnce(_ result: Result<URL, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let session = FFmpegKit.execute(
                withArgumentsAsync: arguments,
                withCompleteCallback: { [weak self] session in
                    guard let session = session else {
                        resumeOnce(.failure(RemuxError.ffmpegFailed("No session returned")))
                        return
                    }

                    let returnCode = session.getReturnCode()

                    if ReturnCode.isSuccess(returnCode) {
                        if FileManager.default.fileExists(atPath: outputURL.path) {
                            if let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
                               let fileSize = attributes[.size] as? NSNumber {
                                Logger.data.debug("[TSRemuxService] Remux successful: \(outputURL.path) (\(fileSize.intValue) bytes)")
                            }
                            // Set progress to full range — statistics callback may not fire for the final frame
                            if expectedFrames > 0, let self {
                                Task { @MainActor in
                                    self.progress = baseProgress + progressRange
                                }
                            }
                            resumeOnce(.success(outputURL))
                        } else {
                            resumeOnce(.failure(RemuxError.outputNotCreated))
                        }
                    } else if ReturnCode.isCancel(returnCode) {
                        resumeOnce(.failure(RemuxError.cancelled))
                    } else {
                        let logs = session.getAllLogsAsString() ?? "Unknown error"
                        let returnCodeValue = returnCode?.getValue() ?? -1
                        Logger.data.error("[TSRemuxService] FFmpeg failed with code \(returnCodeValue): \(logs)")
                        resumeOnce(.failure(RemuxError.ffmpegFailed("Exit code: \(returnCodeValue)")))
                    }
                },
                withLogCallback: nil,
                withStatisticsCallback: { [weak self] statistics in
                    guard let self, let statistics, expectedFrames > 0 else { return }
                    let currentFrame = Int(statistics.getVideoFrameNumber())
                    let frameProgress = min(Double(currentFrame) / Double(expectedFrames), 1.0)
                    Task { @MainActor in
                        self.progress = baseProgress + (frameProgress * progressRange)
                    }
                }
            )

            if session == nil {
                resumeOnce(.failure(RemuxError.ffmpegFailed("Failed to create FFmpeg session")))
            }
        }
    }
}
