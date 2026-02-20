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
/// Format: O9BB-<Name 10>-<Bio 8>-<AsciiID 6>
/// Total string length: 4 + 1 + 10 + 1 + 8 + 1 + 6 = 31 chars
struct BBPacket {
    let appUUID: String   // "O9"
    let type: String      // "BB"
    let name: String      // Up to 10 chars (trimmed)
    let bio: String       // Up to 8 chars (trimmed)
    let hexID: String     // 6-char ASCII user ID
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
    case eventHost(EEPacket)
    case eventAttendant(EAPacket)
    case unknown(appUUID: String, type: String)
}

/// An event host broadcast packet (O9EE)
/// Format: O9EE-<EventID 6>-<HostID 6>-<Action 6>
/// Total: 4+1+6+1+6+1+6 = 25 bytes ✓
struct EEPacket {
    let eventID: String   // 6-char event identifier
    let hostID:  String   // 6-char ASCII host user ID
    let action:  String   // 6-char action code (e.g. "RCALL0", "BLUES0")
}

/// An event attendant response packet (O9EA)
/// Format: O9EA-<EventID 6>-<GuestID 6>-<Action 6>
/// Total: 4+1+6+1+6+1+6 = 25 bytes ✓
struct EAPacket {
    let eventID: String   // 6-char event identifier (matches the EE that triggered this)
    let guestID: String   // 6-char ASCII guest user ID
    let action:  String   // 6-char action response (e.g. "RCACK0" for roll call ack)
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
        case "EE":
            return parseEE(raw)
        case "EA":
            return parseEA(raw)
        default:
            return .unknown(appUUID: appUUID, type: packetType)
        }
    }

    // MARK: - BB Parser
    // Format: O9BB-<Name up to 10>-<Bio up to 8>-<AsciiID up to 6>
    // Example: "O9BB-Reed-Policy-ReedSt"
    //
    // We always treat the LAST component as the ID and the SECOND-TO-LAST
    // as the bio, so a name containing a "-" character doesn't break parsing.

    private static func parseBB(_ raw: String) -> OrbitPacket? {
        guard raw.count >= 4 else { return nil }
        let body = String(raw.dropFirst(4)) // "-Reed-Policy-ReedSt"

        var parts = body.components(separatedBy: "-")

        // Drop the leading empty string from the opening "-"
        if parts.first == "" { parts.removeFirst() }

        // Need at least 3 components: name, bio, id
        guard parts.count >= 3 else { return nil }

        // ID is always the last component, bio always second-to-last,
        // everything before that joins back as the name (handles "-" in names)
        let asciiID = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
        let bio     = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
        let name    = parts[0..<(parts.count - 2)]
                        .joined(separator: "-")
                        .trimmingCharacters(in: .whitespaces)

        guard !asciiID.isEmpty, asciiID.count <= 6 else { return nil }

        return .broadcast(BBPacket(
            appUUID: "O9",
            type: "BB",
            name: String(name.prefix(10)),
            bio: String(bio.prefix(8)),
            hexID: asciiID
        ))
    }

    // MARK: - CC Parser
    // Format: O9CC-<Name up to 10>-<FromID 6>-<ToID 6>-<Message 8>
    // Example: "O9CC-Lainey-AditiK-ReedSt-CONNREQ0"
    //
    // We anchor from the END just like parseBB:
    //   last       = message
    //   last - 1   = toID
    //   last - 2   = fromID
    //   everything before = fromName (handles "-" in names)

    private static func parseCC(_ raw: String) -> OrbitPacket? {
        guard raw.count >= 4 else { return nil }
        let body = String(raw.dropFirst(4))

        var parts = body.components(separatedBy: "-")
        if parts.first == "" { parts.removeFirst() }

        // Need at least 4 components: name, fromID, toID, message
        guard parts.count >= 4 else { return nil }

        let message  = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
        let toID     = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
        let fromID   = parts[parts.count - 3].trimmingCharacters(in: .whitespaces)
        let fromName = parts[0..<(parts.count - 3)]
                         .joined(separator: "-")
                         .trimmingCharacters(in: .whitespaces)

        guard fromID.count == 6, toID.count == 6 else {
            print("⚠️ [CC] Parse failed — fromID: '\(fromID)' toID: '\(toID)'")
            return nil
        }

        print("🔬 [CC] Parsed — from: \(fromID) to: \(toID) msg: \(message)")

        return .connection(CCPacket(
            appUUID: "O9",
            type: "CC",
            fromName: fromName,
            fromID: fromID,
            toID: toID,
            message: message.isEmpty ? "RQ" : message
        ))
    }
    // MARK: - EE Parser
    // Format: O9EE-<EventID 6>-<HostID 6>-<Action 6>
    // Example: "O9EE-EVT001-ReedSt-RCALL0"

    private static func parseEE(_ raw: String) -> OrbitPacket? {
        guard raw.count >= 4 else { return nil }
        var parts = String(raw.dropFirst(4)).components(separatedBy: "-")
        if parts.first == "" { parts.removeFirst() }
        guard parts.count >= 3 else { return nil }

        let action  = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
        let hostID  = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
        let eventID = parts[parts.count - 3].trimmingCharacters(in: .whitespaces)

        guard eventID.count <= 6, hostID.count == 6, !action.isEmpty else { return nil }

        print("🔬 [EE] Parsed — event: \(eventID) host: \(hostID) action: \(action)")
        return .eventHost(EEPacket(eventID: eventID, hostID: hostID, action: action))
    }

    // MARK: - EA Parser
    // Format: O9EA-<EventID 6>-<GuestID 6>-<Action 6>
    // Example: "O9EA-EVT001-AditiK-RCACK0"

    private static func parseEA(_ raw: String) -> OrbitPacket? {
        guard raw.count >= 4 else { return nil }
        var parts = String(raw.dropFirst(4)).components(separatedBy: "-")
        if parts.first == "" { parts.removeFirst() }
        guard parts.count >= 3 else { return nil }

        let action  = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
        let guestID = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
        let eventID = parts[parts.count - 3].trimmingCharacters(in: .whitespaces)

        guard eventID.count <= 6, guestID.count == 6, !action.isEmpty else { return nil }

        print("🔬 [EA] Parsed — event: \(eventID) guest: \(guestID) action: \(action)")
        return .eventAttendant(EAPacket(eventID: eventID, guestID: guestID, action: action))
    }
}

// MARK: - Packet Builder (outgoing helpers)

class PacketBuilder {

    // MARK: BB Packet
    /// Builds a delimiter-separated discovery broadcast string
    /// O9BB-<Name up to 10>-<Bio up to 8>-<AsciiID up to 6>
    static func buildBB(name: String, bio: String, asciiID: String) -> String {
        let safeName = String(name.prefix(10))
        let safeBio  = String(bio.prefix(8))
        let safeID   = String(asciiID.prefix(6))
        return "O9BB-\(safeName)-\(safeBio)-\(safeID)"
    }

    // MARK: CC Packet
    /// CC packet — hard budget of 26 bytes (iOS BLE local name limit):
    /// O9CC(4) + -(1) + Name≤4(4) + -(1) + FromID(6) + -(1) + ToID(6) + -(1) + Msg(2) = 26
    static func buildCC(fromName: String, fromID: String, toID: String, message: String = "RQ") -> String {
        let safeName    = String(fromName.trimmingCharacters(in: .whitespaces).prefix(4))
        let safeFromID  = String(fromID.prefix(6))
        let safeToID    = String(toID.prefix(6))
        let safeMessage = String(message.prefix(2))
        return "O9CC-\(safeName)-\(safeFromID)-\(safeToID)-\(safeMessage)"
    }

    // MARK: EE Packet
    /// O9EE(4) + -(1) + EventID≤6(6) + -(1) + HostID(6) + -(1) + Action≤6(6) = 25 ✓
    static func buildEE(eventID: String, hostID: String, action: String) -> String {
        return "O9EE-\(String(eventID.prefix(6)))-\(String(hostID.prefix(6)))-\(String(action.prefix(6)))"
    }

    // MARK: EA Packet
    /// O9EA(4) + -(1) + EventID≤6(6) + -(1) + GuestID(6) + -(1) + Action≤6(6) = 25 ✓
    static func buildEA(eventID: String, guestID: String, action: String) -> String {
        return "O9EA-\(String(eventID.prefix(6)))-\(String(guestID.prefix(6)))-\(String(action.prefix(6)))"
    }
}
