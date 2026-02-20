//
//  ConnectionsStore.swift
//  orbit_test_1
//
//  Plain persistent store — no ObservableObject.
//  BLEManager mirrors `connectedIDs` into its own @Published property
//  so SwiftUI reactivity flows through the object SwiftUI already owns.
//

import Foundation

class ConnectionsStore {

    static let shared = ConnectionsStore()

    private let key = "confirmedConnections"

    /// Raw set — read directly for logic checks (e.g. enrichment gate).
    /// For UI reactivity, observe BLEManager.connectedIDs instead.
    private(set) var connectedIDs: Set<String> = []

    /// Called whenever the set changes — BLEManager hooks this to republish.
    var onChange: ((Set<String>) -> Void)?

    private init() {
        load()
    }

    // MARK: - Public API

    func isConnected(to userID: String) -> Bool {
        connectedIDs.contains(userID)
    }

    func addConnection(userID: String) {
        guard !connectedIDs.contains(userID) else { return }
        connectedIDs.insert(userID)
        save()
        onChange?(connectedIDs)
        print("🤝 [Connections] Added: \(userID) — total: \(connectedIDs.count)")
    }

    func removeConnection(userID: String) {
        connectedIDs.remove(userID)
        save()
        onChange?(connectedIDs)
        print("🗑️ [Connections] Removed: \(userID)")
    }

    // MARK: - Persistence

    private func save() {
        UserDefaults.standard.set(Array(connectedIDs), forKey: key)
    }

    private func load() {
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        connectedIDs = Set(stored)
        print("📂 [Connections] Loaded \(connectedIDs.count) connection(s): \(connectedIDs)")
    }
}
