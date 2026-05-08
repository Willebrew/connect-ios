//
//  NetworkMonitor.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Real-time network connectivity monitoring
//

import Network
import Foundation

@Observable
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    var isConnected = true

    static let shared = NetworkMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
