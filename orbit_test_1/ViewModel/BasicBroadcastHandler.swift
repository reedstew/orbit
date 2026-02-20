//
//  BasicBroadcastHandler.swift
//  orbit_test_1
//
//  Handles incoming BB (Basic Broadcast) packets.
//
//  Flow:
//    1. Parse BB packet → write raw NearbyProfile to buffer immediately (fast, always works)
//    2. If WiFi available → fire async API lookup → upgrade to EnrichedProfile in buffer
//    3. If WiFi unavailable → leave raw profile in place (BLE name + bio only)
//

import Foundation

// MARK: - Enrichment Delegate

/// BLEManager implements this so the handler can push enriched profiles back
/// without holding a reference to the whole manager.
protocol BBEnrichmentDelegate: AnyObject {
    /// Called on the main thread when an API lookup completes successfully.
    /// The handler for this should replace the existing NearbyProfile in the buffer
    /// with the enriched version.
    func didEnrichProfile(_ enriched: EnrichedProfile)
}

// MARK: - BasicBroadcastHandler

class BasicBroadcastHandler {

    weak var enrichmentDelegate: BBEnrichmentDelegate?

    // MARK: - Incoming: Handle a parsed BB packet

    /// Writes the raw profile immediately, then fires an async enrichment if WiFi is up.
    /// - Parameters:
    ///   - packet: Parsed BBPacket from PacketParser
    ///   - rssi: Signal strength in dBm
    ///   - buffer: Shared NearbyProfile store (inout — written immediately on calling thread)
    func handle(packet: BBPacket, rssi: Int, buffer: inout [UUID: NearbyProfile]) {
        let stableID = packet.hexID.toStableUUID()

        // --- Step 1: Write raw BLE profile immediately ---
        // This ensures the person appears in the UI with zero latency,
        // even before (or if) the API call resolves.
        let rawProfile = NearbyProfile(
            id: stableID,
            hexID: packet.hexID,
            name: packet.name,
            details: packet.bio,
            rssi: rssi
        )
        buffer[stableID] = rawProfile

        print("📡 [BB] Raw profile buffered: [\(packet.hexID)] \"\(packet.name)\" at \(rssi) dBm")

        // --- Step 2: Attempt async enrichment if WiFi is available ---
        guard NetworkMonitor.shared.isOnWifi else {
            print("📵 [BB] No WiFi — showing BLE-only data for \(packet.hexID)")
            return
        }

        // Capture what we need (don't hold inout buffer reference across async boundary)
        let capturedProfile = rawProfile
        let delegate = enrichmentDelegate

        Task {
            await enrich(profile: capturedProfile, delegate: delegate)
        }
    }

    // MARK: - Outgoing: Build a BB payload string

    /// Constructs the outgoing BB advertisement string.
    /// Format: O9BB-<Name[10]>-<Bio[11]>-<HexID[6]>
    func buildPayload(name: String, bio: String, hexID: String) -> String {
        return PacketBuilder.buildBB(name: name, bio: bio, hexID: hexID)
    }

    // MARK: - Private: Async Enrichment

    private func enrich(profile: NearbyProfile, delegate: BBEnrichmentDelegate?) async {
        print("🔍 [API] Fetching full profile for \(profile.hexID)...")

        guard let apiData = await ProfileAPIService.shared.tryFetchProfile(hexID: profile.hexID) else {
            print("❓ [API] No profile found for \(profile.hexID) — keeping BLE data")
            return
        }

        let enriched = EnrichedProfile(from: profile, apiData: apiData)

        await MainActor.run {
            delegate?.didEnrichProfile(enriched)
            print("⬆️  [API] Enriched \(profile.hexID): \(enriched.displayName) | \(enriched.techStack?.joined(separator: ", ") ?? "no stack")")
        }
    }
}
