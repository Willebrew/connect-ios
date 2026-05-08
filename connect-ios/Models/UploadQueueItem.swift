//
//  UploadQueueItem.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/14/25.
//
//  Model for file upload queue items
//

import Foundation

struct UploadQueueItem: Identifiable, Codable {
    var id: String
    var path: String
    var url: String
    var progress: Double
    var current: Bool
    var paused: Bool
    var created: Date

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var fileType: String {
        if path.contains("fcamera") || path.contains("qcamera") {
            return "Road Camera"
        } else if path.contains("ecamera") {
            return "Wide Camera"
        } else if path.contains("dcamera") {
            return "Driver Camera"
        } else if path.contains("rlog") || path.contains("qlog") {
            return "Log Data"
        }
        return "File"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case url
        case progress
        case current
        case paused
        case created
    }
}
