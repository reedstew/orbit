//
//  BasicBroadcastHandler.swift
//  orbit_test_1
//
//  Handles incoming BB (Basic Broadcast) packets.
//
//  RSSI update policy:
//    - The profile buffer is written on EVERY signal → RSSI stays live
//    - The enrichment API call fires only ONCE per userID per session
//      (ProfileAPIService has its own session cache, so duplicate calls
//       are free, but we skip the Task entirely after first success)
//

import Foundation

// MARK: - Enrichment Delegate

protocol BBEnrichmentDelegate: AnyObject {
    func didEnrichProfile(_ enriched: EnrichedProfile)
}

// MARK: - BasicBroadcastHandler

class BasicBroadcastHandler {

    weak var enrichmentDelegate: BBEnrichmentDelegate?

    /// Tracks which userIDs have already had an enrichment Task fired this session.
    /// Prevents spawning a new Task on every RSSI update (which can be many per second).
    private var enrichmentAttempted: Set<String> = []

    // MARK: - Incoming

    func handle(packet: BBPacket, rssi: Int, buffer: inout [UUID: NearbyProfile]) {
        let stableID = packet.hexID.toStableUUID()

        // Always write the latest RSSI — this is what keeps the radar live.
        // If the profile already exists we preserve the name/bio from the
        // first packet and just update signal strength.
        let existing = buffer[stableID]
        let profile = NearbyProfile(
            id: stableID,
            hexID: packet.hexID,
            name: existing?.name ?? packet.name,
            details: existing?.details ?? packet.bio,
            rssi: rssi
        )
        buffer[stableID] = profile

        print("📡 [BB] [\(packet.hexID)] \"\(profile.name)\" \(rssi) dBm")

        // Only attempt enrichment for confirmed connections
        guard ConnectionsStore.shared.isConnected(to: packet.hexID) else { return }

        // Only fire the API Task once per session per userID
        guard !enrichmentAttempted.contains(packet.hexID) else { return }
        guard NetworkMonitor.shared.isOnWifi else {
            print("📵 [BB] No WiFi — BLE-only for \(packet.hexID)")
            return
        }

        enrichmentAttempted.insert(packet.hexID)

        let capturedProfile = profile
        let delegate = enrichmentDelegate
        Task {
            await enrich(profile: capturedProfile, delegate: delegate)
        }
    }

    // MARK: - Outgoing

    func buildPayload(name: String, bio: String, asciiID: String) -> String {
        return PacketBuilder.buildBB(name: name, bio: bio, asciiID: asciiID)
    }

    /// Called immediately after a connection is confirmed so the UI updates
    /// without waiting for the next BB signal cycle.
    func enrichIfConnected(profile: NearbyProfile, delegate: BBEnrichmentDelegate?) async {
        guard ConnectionsStore.shared.isConnected(to: profile.hexID) else { return }
        guard NetworkMonitor.shared.isOnWifi else { return }
        enrichmentAttempted.insert(profile.hexID)
        await enrich(profile: profile, delegate: delegate)
    }

    // MARK: - Private

    private func enrich(profile: NearbyProfile, delegate: BBEnrichmentDelegate?) async {
        print("🔍 [API] Fetching full profile for \(profile.hexID)...")

        guard let apiData = await ProfileAPIService.shared.tryFetchProfile(hexID: profile.hexID) else {
            print("❓ [API] No profile found for \(profile.hexID) — keeping BLE data")
            // Remove from attempted so WiFi coming online later can retry
            enrichmentAttempted.remove(profile.hexID)
            return
        }

        let enriched = EnrichedProfile(from: profile, apiData: apiData)
        await MainActor.run {
            delegate?.didEnrichProfile(enriched)
            print("⬆️  [API] Enriched \(profile.hexID): \(enriched.displayName) | \(enriched.techStack?.joined(separator: ", ") ?? "no stack")")
        }
    }
}
