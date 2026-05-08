//
//  RedirectCaptureDelegate.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  URLSession delegate to capture OAuth redirects without following them
//

import Foundation
import os

class RedirectCaptureDelegate: NSObject, URLSessionTaskDelegate {
    var redirectLocation: String?

    // Intercept redirects and capture the Location header
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Capture the redirect location
        if let location = response.value(forHTTPHeaderField: "Location") {
            redirectLocation = location
            Logger.api.debug("Captured OAuth redirect")
        }

        // Don't follow the redirect - return nil
        completionHandler(nil)
    }
}
