//
//  ConnectionCallHandler.swift
//  orbit_test_1
//
//  Handles incoming and outgoing CC (Connection Call) packets.
//  CC packets are used for peer-to-peer connection requests between users.
//

import Foundation

// MARK: - Connection State

/// Represents the state of a connection attempt with another user
enum ConnectionState: String {
    case pending    // We sent a request, waiting for response
    case accepted   // Both sides have confirmed
    case rejected   // The other side declined (or we declined theirs)
    case ignored    // Seen but not acted on (e.g. not addressed to us)
}

// MARK: - Delegate Protocol

/// BLEManager conforms to this so the handler can trigger UI updates
protocol ConnectionCallDelegate: AnyObject {
    /// Called when a CC packet addressed to THIS user arrives (inbound request)
    func didReceiveConnectionRequest(from packet: CCPacket)

    /// Called when a CC packet confirms a connection we initiated
    func didReceiveConnectionConfirmation(from packet: CCPacket)

    /// Sends a CC packet over BLE (the handler asks BLEManager to broadcast)
    func broadcastConnectionPacket(_ payload: String)
}

// MARK: - ConnectionCallHandler

class ConnectionCallHandler {

    // MARK: - State

    weak var delegate: ConnectionCallDelegate?

    /// Maps HexID → ConnectionState for quick dedup and status lookup.
    /// Cleared after 30 minutes per the Orbit protocol spec.
    private var connectionCache: [String: (state: ConnectionState, timestamp: Date)] = [:]

    /// Our own stable Hex ID (injected from BLEManager)
    private let myHexID: String

    init(myHexID: String) {
        self.myHexID = myHexID
    }

    // MARK: - Incoming: Handle a parsed CC packet

    /// Routes an incoming CC packet.
    /// - Parameters:
    ///   - packet: The fully parsed CCPacket
    ///   - myHexID: This device's Hex ID, used to check if packet is addressed to us
    func handle(packet: CCPacket) {
        let cacheKey = cacheKeyFor(fromID: packet.fromID, toID: packet.toID)

        // --- 1. Dedup check: ignore if seen in the last 30 minutes ---
        if let cached = connectionCache[cacheKey] {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < 1800 {
                print("🔁 [CC] Duplicate from \(packet.fromID) — ignoring (cached state: \(cached.state.rawValue))")
                return
            }
        }

        // --- 2. Is this packet addressed to ME? ---
        guard packet.toID == myHexID else {
            print("📭 [CC] Packet for \(packet.toID) — not us, ignoring")
            return
        }

        // --- 3. Decode the message field to determine intent ---
        let intent = decodeIntent(from: packet.message)
        print("📬 [CC] Received from \(packet.fromID) (\(packet.fromName)) | Intent: \(intent) | Msg: \(packet.message)")

        switch intent {

        case .connectionRequest:
            // Someone wants to connect with us — notify the UI
            connectionCache[cacheKey] = (.pending, Date())
            delegate?.didReceiveConnectionRequest(from: packet)

        case .connectionAccept:
            // The person we requested has accepted — notify the UI
            connectionCache[cacheKey] = (.accepted, Date())
            delegate?.didReceiveConnectionConfirmation(from: packet)

        case .connectionReject:
            connectionCache[cacheKey] = (.rejected, Date())
            print("❌ [CC] \(packet.fromName) rejected the connection")

        case .unknown:
            print("❓ [CC] Unknown message payload: \(packet.message)")
        }
    }

    // MARK: - Outgoing: Send a Connection Request

    /// Constructs and broadcasts a CC connection request to a target user.
    /// - Parameters:
    ///   - myName: This user's display name
    ///   - toHexID: The target user's 6-char Hex ID
    func sendConnectionRequest(myName: String, toHexID: String) {
        let cacheKey = cacheKeyFor(fromID: myHexID, toID: toHexID)

        // Don't spam — check cache first
        if let cached = connectionCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < 1800 {
            print("⚠️ [CC] Already sent a request to \(toHexID) recently — skipping")
            return
        }

        let payload = PacketBuilder.buildCC(
            fromName: myName,
            fromID: myHexID,
            toID: toHexID,
            message: CCMessage.request.rawValue
        )

        connectionCache[cacheKey] = (.pending, Date())
        print("📤 [CC] Sending connection request to \(toHexID): \(payload)")
        delegate?.broadcastConnectionPacket(payload)
    }

    // MARK: - Outgoing: Accept a Connection Request

    /// Broadcasts a CC acceptance packet back to the requester.
    /// - Parameters:
    ///   - myName: This user's display name
    ///   - toHexID: The hex ID of the person whose request we're accepting
    func acceptConnectionRequest(myName: String, toHexID: String) {
        let payload = PacketBuilder.buildCC(
            fromName: myName,
            fromID: myHexID,
            toID: toHexID,
            message: CCMessage.accept.rawValue
        )

        let cacheKey = cacheKeyFor(fromID: myHexID, toID: toHexID)
        connectionCache[cacheKey] = (.accepted, Date())

        print("✅ [CC] Accepting connection from \(toHexID): \(payload)")
        delegate?.broadcastConnectionPacket(payload)
    }

    // MARK: - Outgoing: Reject a Connection Request

    func rejectConnectionRequest(myName: String, toHexID: String) {
        let payload = PacketBuilder.buildCC(
            fromName: myName,
            fromID: myHexID,
            toID: toHexID,
            message: CCMessage.reject.rawValue
        )

        let cacheKey = cacheKeyFor(fromID: myHexID, toID: toHexID)
        connectionCache[cacheKey] = (.rejected, Date())

        print("🚫 [CC] Rejecting connection from \(toHexID): \(payload)")
        delegate?.broadcastConnectionPacket(payload)
    }

    // MARK: - Cache Management

    /// Purges stale entries older than 30 minutes.
    /// Call this periodically (e.g. from a BLEManager timer).
    func purgeExpiredCache() {
        let now = Date()
        let before = connectionCache.count
        connectionCache = connectionCache.filter { now.timeIntervalSince($0.value.timestamp) < 1800 }
        let purged = before - connectionCache.count
        if purged > 0 { print("🗑️ [CC] Purged \(purged) expired cache entries") }
    }

    /// Look up the current connection state for a given user
    func connectionState(for hexID: String) -> ConnectionState? {
        let key1 = cacheKeyFor(fromID: myHexID, toID: hexID)
        let key2 = cacheKeyFor(fromID: hexID, toID: myHexID)
        return connectionCache[key1]?.state ?? connectionCache[key2]?.state
    }

    // MARK: - Helpers

    /// Generates a canonical cache key for a from/to pair.
    /// Sorted so the key is the same regardless of direction.
    private func cacheKeyFor(fromID: String, toID: String) -> String {
        let sorted = [fromID, toID].sorted()
        return "\(sorted[0]):\(sorted[1])"
    }

    private func decodeIntent(from message: String) -> CCIntent {
        guard let intent = CCMessage(rawValue: message) else { return .unknown }
        switch intent {
        case .request: return .connectionRequest
        case .accept:  return .connectionAccept
        case .reject:  return .connectionReject
        }
    }
}

// MARK: - CC Message Constants

/// The 8-char message field values used in CC packets
enum CCMessage: String {
    case request = "CONNREQ0"   // Connection request
    case accept  = "CONNACC0"   // Connection accepted
    case reject  = "CONNREJ0"   // Connection rejected
}

private enum CCIntent {
    case connectionRequest
    case connectionAccept
    case connectionReject
    case unknown
}
