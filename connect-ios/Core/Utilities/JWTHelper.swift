//
//  JWTHelper.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  JWT token parsing and validation utilities
//

import Foundation

enum JWTHelper {
    // MARK: - Token Parsing

    /// Parses a JWT token and extracts the payload
    static func parseToken(_ token: String) throws -> [String: Any] {
        let segments = token.components(separatedBy: ".")

        guard segments.count == 3 else {
            throw JWTError.invalidFormat
        }

        // JWT format: header.payload.signature
        // We only need the payload (index 1)
        let payloadSegment = segments[1]

        // Add padding if needed (base64 requires length to be multiple of 4)
        var base64 = payloadSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padLength = (4 - (base64.count % 4)) % 4
        base64 += String(repeating: "=", count: padLength)

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JWTError.invalidPayload
        }
        return json
    }

    /// Extracts the expiration date from a JWT token
    static func getExpirationDate(from token: String) throws -> Date? {
        let payload = try parseToken(token)

        guard let exp = payload["exp"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    /// Checks if a JWT token is expired
    static func isTokenExpired(_ token: String) -> Bool {
        guard let expirationDate = try? getExpirationDate(from: token) else {
            return true // If we can't parse it, consider it expired
        }

        // Add 5 minute buffer
        let bufferSeconds: TimeInterval = 300
        return Date().addingTimeInterval(bufferSeconds) >= expirationDate
    }

    /// Extracts user ID from JWT token
    static func getUserID(from token: String) throws -> String? {
        let payload = try parseToken(token)
        return payload["identity"] as? String ?? payload["sub"] as? String
    }

    /// Extracts issued at date from JWT token
    static func getIssuedAtDate(from token: String) throws -> Date? {
        let payload = try parseToken(token)

        guard let iat = payload["iat"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: iat)
    }

    /// Gets time until token expiration
    static func getTimeUntilExpiration(from token: String) -> TimeInterval? {
        guard let expirationDate = try? getExpirationDate(from: token) else {
            return nil
        }

        return expirationDate.timeIntervalSinceNow
    }

    /// Checks if token needs refresh (expires within 1 hour)
    static func needsRefresh(_ token: String) -> Bool {
        guard let timeRemaining = getTimeUntilExpiration(from: token) else {
            return true
        }

        // Refresh if less than 1 hour remaining
        let oneHour: TimeInterval = 3600
        return timeRemaining < oneHour
    }

    // MARK: - Error Types

    enum JWTError: LocalizedError {
        case invalidFormat
        case invalidPayload
        case expired

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid JWT token format"
            case .invalidPayload:
                return "Could not parse JWT payload"
            case .expired:
                return "JWT token has expired"
            }
        }
    }
}

// MARK: - JWT Token Struct (Optional convenience)

struct JWTToken {
    let rawToken: String
    let payload: [String: Any]
    let expirationDate: Date?
    let issuedAtDate: Date?
    let userID: String?

    var isExpired: Bool {
        JWTHelper.isTokenExpired(rawToken)
    }

    var needsRefresh: Bool {
        JWTHelper.needsRefresh(rawToken)
    }

    var timeUntilExpiration: TimeInterval? {
        JWTHelper.getTimeUntilExpiration(from: rawToken)
    }

    init(token: String) throws {
        self.rawToken = token
        self.payload = try JWTHelper.parseToken(token)
        self.expirationDate = try? JWTHelper.getExpirationDate(from: token)
        self.issuedAtDate = try? JWTHelper.getIssuedAtDate(from: token)
        self.userID = try? JWTHelper.getUserID(from: token)
    }
}
