//
//  ConnectionHandler.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/20/26.
//

import Foundation

class ConnectionCallHandler {
    
    /// Handles the "BB" (Broadcast) signal logic
    /// - Parameters:
    ///   - packet: The parsed packet from the PacketParser
    ///   - rssi: Signal strength for distance calculation
    ///   - buffer: The in-memory storage for nearby profiles
    func handle(packet: ParsedPacket, rssi: Int, buffer: inout [UUID: NearbyProfile]) {
        // 1. Generate the stable UUID from the Hex ID
        // We use the 6-char Hex ID (part2) as the anchor for stability
        let stableID = packet.part2.toStableUUID()
        
        // 2. Extract discovery info (Name and Bio) from the plaintext parts
        let name = packet.part1 // First 10 chars of Name
        let bio = packet.part3  // First 11 chars of Bio
        
        // 3. Create or Update the profile in the buffer
        let discoveredProfile = NearbyProfile(
            id: stableID,
            name: name,
            details: bio,
            rssi: rssi
        )
        
        // Since we use the stableID, this naturally overwrites old signals from the same user
        buffer[stableID] = discoveredProfile
        
        print("📍 Discovery: [\(packet.part2)] \(name) detected at \(rssi) dBm")
    }
}
