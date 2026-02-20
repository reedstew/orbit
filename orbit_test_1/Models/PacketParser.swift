//
//  PacketParser.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/20/26.
//

import Foundation

struct ParsedPacket {
    let appUUID: String
    let type: String
    let part1: String
    let part2: String
    let part3: String
    let padding: String
}

class PacketParser {
    static func parse(_ data: Data) -> ParsedPacket? {
        // Ensure we have the full 31-byte Orbit packet
        guard data.count >= 31 else { return nil }
        
        // 1. Extract the String-based portion (Bytes 0 to 27)
        // This contains: AppUUID(2) + Type(2) + "-" + Part1(10) + "-" + Part3(11) + "-"
        let stringPart = data.subdata(in: 0..<28)
        guard let rawString = String(data: stringPart, encoding: .utf8) else { return nil }
        let components = rawString.components(separatedBy: "-")
        
        guard components.count > 4 else { return nil }
        
        // 2. Extract the Raw Byte portion (Bytes 28 to 30)
        // This is your 3-byte / 6-hex-digit ID
        let rawIDBytes = data.subdata(in: 28..<31)
        
        return ParsedPacket(
            appUUID: String(components[0].prefix(2)),
            type: String(components[0].suffix(2)),
            part1: components[1],
            part2: components[2],
            part3: components[3],
            padding: components.count > 4 ? components[4] : ""
        )
    }
}
