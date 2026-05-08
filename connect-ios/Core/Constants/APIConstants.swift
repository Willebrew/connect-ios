//
//  APIConstants.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  API configuration and constants
//

import Foundation

enum APIConstants {
    static let commaURLRoot = "https://api.comma.ai/"
    static let athenaURLRoot = "https://athena.comma.ai/"
    static let billingURLRoot = "https://billing.comma.ai/"
    static let useradminURLRoot = "https://useradmin.comma.ai/"

    // Mapbox
    static let mapboxToken = "pk.eyJ1IjoiY29tbWFhaSIsImEiOiJjangyYXV0c20wMGU2NDluMWR4amUydGl5In0.6Vb11S6tdX6Arpj6trRE_g"
    static let mapboxStyleURL = "mapbox://styles/commaai/cjj4yzqk201c52ss60ebmow0w"

    // Cache settings
    static let cacheExpiryDays = 14
    static let maxCacheSize = 500_000_000 // 500MB

    // Playback settings
    static let maxPlaybackSpeed = 16.0
    static let maxBufferLength = 40 // seconds

    // Device settings
    static let deviceOnlineThreshold: TimeInterval = 120 // seconds
    static let autoFollowTimeout: TimeInterval = 5 // seconds
}
