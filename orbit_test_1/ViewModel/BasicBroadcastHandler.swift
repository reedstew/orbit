//
//  BasicBroadcastHandler.swift
//  orbit_test_1
//
//  Handles incoming BB (Basic Broadcast) packets and outgoing BB payload construction.
//

import Foundation

class BasicBroadcastHandler {

    // MARK: - Incoming: Handle a parsed BB packet

    /// Called by BLEManager when a BB packet arrives.
    /// Creates or updates a NearbyProfile in the shared buffer.
    /// - Parameters:
    ///   - packet: The parsed BBPacket from PacketParser
    ///   - rssi: Signal strength in dBm (used for distance positioning)
    ///   - buffer: Shared in-memory profile store (passed inout from BLEManager)
    func handle(packet: BBPacket, rssi: Int, buffer: inout [UUID: NearbyProfile]) {
        // Generate a stable UUID from the sender's 6-char Hex ID.
        // Using the Hex ID (not the name) ensures the same person
        // always maps to the same UUID even if their name changes.
        let stableID = packet.hexID.toStableUUID()

        let profile = NearbyProfile(
            id: stableID,
            name: packet.name,
            details: packet.bio,
            rssi: rssi
        )

        // Writing to the dict by stableID naturally deduplicates:
        // a new signal from the same person just overwrites the old one.
        buffer[stableID] = profile

        print("📡 [BB] Discovered: [\(packet.hexID)] \"\(packet.name)\" at \(rssi) dBm | Bio: \"\(packet.bio)\"")
    }

    // MARK: - Outgoing: Build a BB payload string

    /// Constructs the outgoing BB advertisement string.
    /// Format: O9BB-<Name[10]>-<Bio[11]>-<HexID[6]>
    /// - Parameters:
    ///   - name: The broadcaster's display name (truncated to 10 chars)
    ///   - bio: The broadcaster's bio/tech stack (truncated to 11 chars)
    ///   - hexID: The broadcaster's stable 6-char Hex ID
    /// - Returns: A properly formatted 34-char string ready to broadcast
    func buildPayload(name: String, bio: String, hexID: String) -> String {
        return PacketBuilder.buildBB(name: name, bio: bio, hexID: hexID)
    }
}
