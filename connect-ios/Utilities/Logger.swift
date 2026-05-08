//
//  Logger.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/16/25.
//
//  Centralized logging using OSLog (Apple's unified logging system)
//  - Use .debug for verbose/development-only logs
//  - Use .info for important production events
//  - Use .error for failures
//  - Automatically redacts sensitive data
//

import Foundation
import OSLog

/// Centralized logger using Apple's unified logging system (OSLog)
/// Provides category-based logging with automatic DEBUG/production filtering
struct Logger {

    // MARK: - Categories

    /// General app lifecycle and state
    static let app = Logger(category: "App")

    /// Authentication and OAuth flows
    static let auth = Logger(category: "Auth")

    /// API requests and responses
    static let api = Logger(category: "API")

    /// UI events and user interactions
    static let ui = Logger(category: "UI")

    /// Data loading and caching
    static let data = Logger(category: "Data")

    // MARK: - Private

    private let osLogger: os.Logger

    private init(category: String) {
        self.osLogger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.comma.connect", category: category)
    }

    // MARK: - Logging Methods

    /// Debug-level logging - only visible in DEBUG builds
    /// Use for verbose operational details, flow tracking, and development debugging
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        osLogger.debug("[\(fileName):\(line)] \(message)")
        #endif
    }

    /// Info-level logging - visible in production
    /// Use for important events: user actions, state changes, major operations
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        osLogger.info("[\(fileName):\(line)] \(message)")
    }

    /// Notice-level logging - visible in production
    /// Use for significant but not critical events
    func notice(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        osLogger.notice("[\(fileName):\(line)] \(message)")
    }

    /// Error-level logging - always visible
    /// Use for errors, failures, and exceptional conditions
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        if let error = error {
            osLogger.error("[\(fileName):\(line)] \(message): \(error.localizedDescription)")
        } else {
            osLogger.error("[\(fileName):\(line)] \(message)")
        }
    }

    /// Fault-level logging - critical system failures
    /// Use for unrecoverable errors or corrupted state
    func fault(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        osLogger.fault("[\(fileName):\(line)] \(message)")
    }
}

// MARK: - Privacy Helpers

extension Logger {
    /// Redacts a token/secret, showing only a safe prefix
    static func redact(token: String, prefixLength: Int = 12) -> String {
        guard token.count > prefixLength else { return "***" }
        return "\(token.prefix(prefixLength))***"
    }

    /// Redacts sensitive query parameters from a URL
    static func redactURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }

        // Redact sensitive query parameters
        let sensitiveParams = ["code", "token", "access_token", "refresh_token", "state"]
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                if sensitiveParams.contains(item.name.lowercased()) {
                    return URLQueryItem(name: item.name, value: "***")
                }
                return item
            }
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}
