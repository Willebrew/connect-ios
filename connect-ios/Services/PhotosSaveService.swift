//
//  PhotosSaveService.swift
//  connect-ios
//
//  Created by Will Killebrew on 1/21/26.
//
//  Service for saving videos to the iOS Photos library

import Foundation
import Photos
import os

/// Service responsible for saving videos to the Photos library
@Observable
final class PhotosSaveService {
    static let shared = PhotosSaveService()
    
    private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    private init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }
    
    // MARK: - Authorization
    
    /// Requests authorization to add photos to the library
    @MainActor
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        authorizationStatus = status
        return status
    }
    
    /// Checks if we have permission to save to Photos
    var canSaveToPhotos: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }
    
    /// Returns a human-readable status message
    var authorizationMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Permission required to save to Photos"
        case .restricted:
            return "Photos access is restricted on this device"
        case .denied:
            return "Photos access denied. Enable in Settings."
        case .authorized:
            return "Ready to save to Photos"
        case .limited:
            return "Limited Photos access granted"
        @unknown default:
            return "Unknown authorization status"
        }
    }
    
    // MARK: - Save Methods
    
    /// Saves a video file to the Photos library
    /// - Parameter videoURL: URL to the video file (must be MP4 or MOV)
    /// - Returns: The local identifier of the saved asset
    @MainActor
    func saveVideoToPhotos(_ videoURL: URL) async throws -> String {
        // Check authorization
        if !canSaveToPhotos {
            let status = await requestAuthorization()
            guard status == .authorized || status == .limited else {
                throw PhotosSaveError.notAuthorized(status)
            }
        }
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw PhotosSaveError.fileNotFound
        }
        
        // Verify it's a video
        let fileExtension = videoURL.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(fileExtension) else {
            throw PhotosSaveError.unsupportedFormat(fileExtension)
        }
        
        Logger.data.debug("Saving video to Photos: \(videoURL.lastPathComponent)")
        
        var localIdentifier: String?
        var saveError: Error?
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: videoURL, options: nil)
                localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            saveError = error
        }

        if let error = saveError {
            Logger.data.error("Failed to save video to Photos", error: error)
            throw PhotosSaveError.saveFailed(Self.friendlyPhotosErrorMessage(for: error))
        }
        
        guard let identifier = localIdentifier else {
            throw PhotosSaveError.saveFailed("No identifier returned")
        }
        
        Logger.data.debug("Video saved to Photos with ID: \(identifier)")
        return identifier
    }
    
    /// Saves a video from a temporary URL, then cleans up the source file
    /// - Parameters:
    ///   - videoURL: URL to the temporary video file
    ///   - deleteAfterSave: Whether to delete the source file after saving
    /// - Returns: The local identifier of the saved asset
    @MainActor
    func saveAndCleanup(_ videoURL: URL, deleteAfterSave: Bool = true) async throws -> String {
        let identifier = try await saveVideoToPhotos(videoURL)
        
        if deleteAfterSave {
            do {
                try FileManager.default.removeItem(at: videoURL)
                Logger.data.debug("Cleaned up temporary file: \(videoURL.lastPathComponent)")
            } catch {
                // Non-fatal, just log
                Logger.data.warning("Failed to clean up temporary file: \(error.localizedDescription)")
            }
        }
        
        return identifier
    }
    
    // MARK: - Error Mapping

    /// Maps PHPhotosError codes to user-friendly messages
    static func friendlyPhotosErrorMessage(for error: Error) -> String {
        let nsError = error as NSError

        // PHPhotosErrorDomain errors
        if nsError.domain == "PHPhotosErrorDomain" || nsError.domain == "com.apple.photos.error" {
            switch nsError.code {
            case 3302: // PHPhotosError.invalidResource
                return "Photos rejected the video (invalid resource). The video file may be corrupted or in an unsupported format."
            case 3300: // PHPhotosError.notEnoughSpace
                return "Not enough storage space to save the video. Free up space and try again."
            case 3301: // PHPhotosError.userCancelled
                return "Save was cancelled."
            case 3303: // PHPhotosError.libraryVolumeOffline
                return "The Photos library is unavailable. Make sure your device has enough storage."
            default:
                return "Photos error (code \(nsError.code)): \(error.localizedDescription)"
            }
        }

        return error.localizedDescription
    }

    // MARK: - Errors

    enum PhotosSaveError: LocalizedError {
        case notAuthorized(PHAuthorizationStatus)
        case fileNotFound
        case unsupportedFormat(String)
        case saveFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized(let status):
                switch status {
                case .denied:
                    return "Photos access denied. Please enable in Settings."
                case .restricted:
                    return "Photos access is restricted on this device."
                default:
                    return "Photos permission not granted."
                }
            case .fileNotFound:
                return "Video file not found"
            case .unsupportedFormat(let ext):
                return "Unsupported format: .\(ext)"
            case .saveFailed(let reason):
                return "Failed to save: \(reason)"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .notAuthorized:
                return "Go to Settings > Privacy > Photos and enable access for Connect."
            case .unsupportedFormat:
                return "Only MP4, MOV, and M4V formats are supported."
            default:
                return nil
            }
        }
    }
}

// MARK: - Logger Extension

extension Logger {
    /// Warning-level logging - visible in production
    /// Use for non-critical issues that should be monitored
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        self.info("WARNING: \(message)", file: file, function: function, line: line)
    }
}
