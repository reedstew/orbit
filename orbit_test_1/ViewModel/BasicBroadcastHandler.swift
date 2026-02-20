//
//  BasicBroadcastHandler.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/20/26.
//

import Foundation

class BasicBroadcastHandler {
    
    // MARK: - Outgoing: Payload Preparation
    
    /// Constructs the 31-byte delimited packet for discovery
    func preparePayload(name: String, bio: String, hexID: String) -> Data {
        let header = "O9BB"
        let paddedName = name.padding(toLength: 10, withPad: " ", startingAt: 0)
        let paddedBio = bio.padding(toLength: 11, withPad: " ", startingAt: 0)
        
        // Combine the string parts: O9BB-Name-Bio-
        let stringPart = "\(header)-\(paddedName)-\(paddedBio)-"
        var packetData = stringPart.data(using: .utf8)!
        
        // Append the 3 raw hex bytes (The full ID)
        let rawIDBytes = hexToData(hexID)
        packetData.append(rawIDBytes)
        
        return packetData // Now 31 bytes of Data
    }
    
    // MARK: - Incoming: Signal Handling
    
    func handle(packet: ParsedPacket, rssi: Int, buffer: inout [UUID: NearbyProfile]) {
        let stableID = packet.part2.toStableUUID()
        
        let profile = NearbyProfile(
            id: stableID,
            name: packet.part1,
            details: packet.part3,
            rssi: rssi
        )
        
        buffer[stableID] = profile
    }
}
