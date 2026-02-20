//
//  NetworkMonitor.swift
//  orbit_test_1
//
//  A lightweight singleton that tracks whether the device has an active
//  WiFi connection using Apple's Network framework.
//
//  Usage:
//      if NetworkMonitor.shared.isOnWifi { ... }
//      NetworkMonitor.shared.onStatusChange = { isWifi in ... }
//

import Foundation
import Network

class NetworkMonitor {

    // MARK: - Singleton
    static let shared = NetworkMonitor()

    // MARK: - State

    /// True when the device has an active WiFi interface
    private(set) var isOnWifi: Bool = false

    /// True when the device has ANY network path (WiFi or cellular)
    private(set) var isConnected: Bool = false

    /// Optional callback — fires on the main thread whenever status changes
    var onStatusChange: ((Bool) -> Void)?

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.orbit.networkmonitor", qos: .utility)

    // MARK: - Init

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let connected = path.status == .satisfied
            // WiFi = satisfied path that uses the wifi interface
            let onWifi = connected && path.usesInterfaceType(.wifi)

            let changed = self.isOnWifi != onWifi || self.isConnected != connected

            self.isConnected = connected
            self.isOnWifi    = onWifi

            if changed {
                DispatchQueue.main.async {
                    self.onStatusChange?(onWifi)
                    print("📶 Network status: \(connected ? (onWifi ? "WiFi ✅" : "Cellular only") : "Offline ❌")")
                }
            }
        }

        monitor.start(queue: monitorQueue)
    }
}
