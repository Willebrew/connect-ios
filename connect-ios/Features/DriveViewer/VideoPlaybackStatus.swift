//
//  VideoPlaybackStatus.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Represents the availability state of the playback surface so the UI
//  can show spinners, retry affordances, or "unavailable" messaging.
//

import Foundation

enum VideoPlaybackStatus: Equatable {
    case idle
    case loading
    case ready
    /// Video is permanently unavailable (404, not uploaded, etc.) - no retry
    case unavailable(reason: UnavailableReason)
    /// Temporary error that can be retried
    case error(message: String)
    /// Loading timed out
    case timeout
    
    enum UnavailableReason: Equatable {
        case notUploaded
        case deleted
        case processingFailed
        case unknown
        
        var message: String {
            switch self {
            case .notUploaded:
                return "Video not uploaded"
            case .deleted:
                return "Video no longer available"
            case .processingFailed:
                return "Video failed to process"
            case .unknown:
                return "Video unavailable"
            }
        }
        
        var description: String {
            switch self {
            case .notUploaded:
                return "This drive's video hasn't been uploaded to the cloud yet."
            case .deleted:
                return "This video has been deleted or is no longer available."
            case .processingFailed:
                return "The video couldn't be processed. Try re-uploading from your device."
            case .unknown:
                return "This video isn't available for playback."
            }
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}
