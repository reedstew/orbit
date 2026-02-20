//
//  NearbyProfile.swift
//  orbit_test_1
//
//  The in-memory model for a user discovered via BLE.
//  Lives in the BLEManager's profileBuffer and drives the UI.
//

import Foundation

struct NearbyProfile: Identifiable {
    /// Stable UUID derived from hexID via String.toStableUUID()
    /// Used as the SwiftUI Identifiable key and map position anchor
    let id: UUID

    /// The raw 6-char Hex ID from the BLE packet (e.g. "A3B12F")
    /// Needed to build CC (connection) packets addressed to this person
    let hexID: String

    /// Display name (up to 10 chars, trimmed from BB packet)
    let name: String

    /// Bio / tech stack (up to 11 chars, trimmed from BB packet)
    let details: String

    /// Signal strength in dBm — used for distance estimation on the map
    let rssi: Int
}
