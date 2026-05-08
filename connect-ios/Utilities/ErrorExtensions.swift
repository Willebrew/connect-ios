//
//  ErrorExtensions.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Common helpers for working with networking errors
//

import Foundation

extension Error {
    nonisolated var isCancellationError: Bool {
        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }

        if let apiError = self as? APIError {
            return apiError.isCancelledRequest
        }
        return false
    }

    nonisolated var isDeviceOfflineError: Bool {
        if let apiError = self as? APIError {
            switch apiError {
            case .serverError(let code, let message):
                return code == 404 && message.lowercased().contains("device not registered")
            default:
                return false
            }
        }
        return false
    }

    nonisolated var isNetworkConnectionError: Bool {
        if let urlError = self as? URLError {
            return urlError.code == .notConnectedToInternet ||
                   urlError.code == .networkConnectionLost ||
                   urlError.code == .timedOut
        }
        return false
    }

    nonisolated var isPermissionDenied: Bool {
        if let apiError = self as? APIError {
            return apiError.isPermissionDenied
        }
        return false
    }
}
