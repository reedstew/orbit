//
//  PacketParser.swift
//  orbit_test_1
//
//  Parses incoming BLE advertisement local name strings into typed packets.
//  Supports BB (broadcast) and CC (connection) packet formats.
//

import Foundation

// MARK: - Parsed Packet Types

/// A discovery broadcast packet (O9BB)
/// Format: O9BB-<Name 10>-<Bio 11>-<HexID 6>
/// Total string length: 4 + 1 + 10 + 1 + 11 + 1 + 6 = 34 chars
struct BBPacket {
    let appUUID: String   // "O9"
    let type: String      // "BB"
    let name: String      // Up to 10 chars (trimmed)
    let bio: String       // Up to 11 chars (trimmed)
    let hexID: String     // 6-char hex ID
}

/// A connection request/grant packet (O9CC)
/// Format: O9CC-<Name 10>-<FromID 6>-<ToID 6>-<Message 8>
/// Total string length: 4 + 1 + 10 + 1 + 6 + 1 + 6 + 1 + 8 = 38 chars
struct CCPacket {
    let appUUID: String   // "O9"
    let type: String      // "CC"
    let fromName: String  // Up to 10 chars (trimmed)
    let fromID: String    // 6-char hex ID of sender
    let toID: String      // 6-char hex ID of intended recipient
    let message: String   // 8-char optional message payload ("00000000" if empty)
}

/// Union type returned by the parser
enum OrbitPacket {
    case broadcast(BBPacket)
    case connection(CCPacket)
    case unknown(appUUID: String, type: String)
}

// MARK: - PacketParser

class PacketParser {

    static let expectedAppUUID = "O9"

    /// Entry point: parse a raw BLE local name string into a typed OrbitPacket.
    /// Returns nil if the string is not a valid Orbit packet.
    static func parse(_ raw: String) -> OrbitPacket? {
        // All Orbit packets start with "O9" + 2-char type
        guard raw.count >= 4 else { return nil }

        let appUUID = String(raw.prefix(2))
        guard appUUID == expectedAppUUID else { return nil }

        let packetType = String(raw.dropFirst(2).prefix(2))

        switch packetType {
        case "BB":
            return parseBB(raw)
        case "CC":
            return parseCC(raw)
        default:
            return .unknown(appUUID: appUUID, type: packetType)
        }
    }

    // MARK: - BB Parser
    // Format: O9BB-<Name[10]>-<Bio[11]>-<HexID[6]>
    // Example: "O9BB-Reed      -SwiftUI    -A3B12F"

    private static func parseBB(_ raw: String) -> OrbitPacket? {
        // Strip the 4-char header "O9BB" then split on "-"
        guard raw.count >= 4 else { return nil }
        let body = String(raw.dropFirst(4)) // "-Reed      -SwiftUI    -A3B12F"

        // Expected: ["", "Reed      ", "SwiftUI    ", "A3B12F"]
        let parts = body.components(separatedBy: "-")

        // We need at least 4 parts (leading empty + name + bio + id)
        guard parts.count >= 4 else { return nil }

        let name  = parts[1].trimmingCharacters(in: .whitespaces)
        let bio   = parts[2].trimmingCharacters(in: .whitespaces)
        let hexID = parts[3].trimmingCharacters(in: .whitespaces)

        guard hexID.count == 6 else { return nil }

        let packet = BBPacket(
            appUUID: "O9",
            type: "BB",
            name: name,
            bio: bio,
            hexID: hexID
        )

        return .broadcast(packet)
    }

    // MARK: - CC Parser
    // Format: O9CC-<Name[10]>-<FromID[6]>-<ToID[6]>-<Message[8]>
    // Example: "O9CC-Reed      -A3B12F-B22C91-00000000"

    private static func parseCC(_ raw: String) -> OrbitPacket? {
        guard raw.count >= 4 else { return nil }
        let body = String(raw.dropFirst(4))

        // Expected: ["", "Reed      ", "A3B12F", "B22C91", "00000000"]
        let parts = body.components(separatedBy: "-")

        guard parts.count >= 5 else { return nil }

        let fromName = parts[1].trimmingCharacters(in: .whitespaces)
        let fromID   = parts[2].trimmingCharacters(in: .whitespaces)
        let toID     = parts[3].trimmingCharacters(in: .whitespaces)
        let message  = parts[4].trimmingCharacters(in: .whitespaces)

        guard fromID.count == 6, toID.count == 6 else { return nil }

        let packet = CCPacket(
            appUUID: "O9",
            type: "CC",
            fromName: fromName,
            fromID: fromID,
            toID: toID,
            message: message.isEmpty ? "00000000" : message
        )

        return .connection(packet)
    }
}

// MARK: - Packet Builder (outgoing helpers)

class PacketBuilder {

    // MARK: BB Packet
    /// Builds a 34-char discovery broadcast string
    /// O9BB-<Name[10]>-<Bio[11]>-<HexID[6]>
    static func buildBB(name: String, bio: String, hexID: String) -> String {
        let paddedName  = name.padding(toLength: 10, withPad: " ", startingAt: 0).prefix(10)
        let paddedBio   = bio.padding(toLength: 11, withPad: " ", startingAt: 0).prefix(11)
        let safeHexID   = hexID.prefix(6)
        return "O9BB-\(paddedName)-\(paddedBio)-\(safeHexID)"
    }

    // MARK: CC Packet
    /// Builds a 38-char connection request string
    /// O9CC-<Name[10]>-<FromID[6]>-<ToID[6]>-<Message[8]>
    static func buildCC(fromName: String, fromID: String, toID: String, message: String = "00000000") -> String {
        let paddedName    = fromName.padding(toLength: 10, withPad: " ", startingAt: 0).prefix(10)
        let safeFromID    = fromID.prefix(6)
        let safeToID      = toID.prefix(6)
        let paddedMessage = message.padding(toLength: 8, withPad: "0", startingAt: 0).prefix(8)
        return "O9CC-\(paddedName)-\(safeFromID)-\(safeToID)-\(paddedMessage)"
    }
}
