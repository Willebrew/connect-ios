//
//  FileMetadata.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Data model for file upload/download metadata
//

import Foundation

struct FileMetadata: Codable {
    var url: String?
    var notFound: Bool
    var progress: Double
    var current: Bool
    var paused: Bool
    var requested: Bool

    init(
        url: String? = nil,
        notFound: Bool = false,
        progress: Double = 0,
        current: Bool = false,
        paused: Bool = false,
        requested: Bool = false
    ) {
        self.url = url
        self.notFound = notFound
        self.progress = progress
        self.current = current
        self.paused = paused
        self.requested = requested
    }
}

enum FileType: String, CaseIterable {
    case qcameras
    case cameras
    case dcameras
    case ecameras
    case qlogs
    case logs

    var displayName: String {
        switch self {
        case .qcameras: return "Road Camera (Quick)"
        case .cameras: return "Road Camera (Full)"
        case .dcameras: return "Driver Camera"
        case .ecameras: return "Wide Road Camera"
        case .qlogs: return "Log (Compressed)"
        case .logs: return "Log (Full)"
        }
    }

    /// File names that can appear for this type (matches web FILE_NAMES constant)
    var fileNames: [String] {
        switch self {
        case .qcameras: return ["qcamera.ts"]
        case .cameras: return ["fcamera.hevc"]
        case .dcameras: return ["dcamera.hevc"]
        case .ecameras: return ["ecamera.hevc"]
        case .qlogs: return ["qlog.bz2", "qlog.zst"]
        case .logs: return ["rlog.bz2", "rlog.zst"]
        }
    }

    var primaryFileName: String {
        fileNames.first ?? rawValue
    }
}

struct RouteFileEntry: Identifiable, Hashable {
    let id: String
    let fileName: String
    let segmentNumber: Int?
    let url: String

    init?(urlString: String) {
        guard let url = URL(string: urlString) else {
            return nil
        }
        self.url = urlString
        self.fileName = url.lastPathComponent
        self.segmentNumber = RouteFileEntry.extractSegmentNumber(from: url)
        self.id = urlString
    }

    private static func extractSegmentNumber(from url: URL) -> Int? {
        let components = url.pathComponents
        if components.count >= 2 {
            let candidate = components.dropLast().last ?? ""
            if let segment = Int(candidate) {
                return segment
            }
        }

        // Fallback to parsing "--<segment>" suffix in the file name path
        let pattern = #"--(\d+)"#
        if let range = url.absoluteString.range(of: pattern, options: .regularExpression) {
            let value = url.absoluteString[range].replacingOccurrences(of: "--", with: "")
            return Int(value)
        }
        return nil
    }
}
