//
//  EnrichedProfile.swift
//  orbit_test_1
//
//  Represents a fully resolved user profile — the BLE-discovered baseline
//  upgraded with data from the API (currently backed by profiles.json).
//
//  The UI should prefer an EnrichedProfile when available, falling back
//  to the raw NearbyProfile fields (name, details) when it isn't.
//

import Foundation

struct EnrichedProfile: Identifiable {

    // MARK: - Identity (always present — from BLE)
    let id: UUID           // Stable UUID derived from hexID
    let hexID: String      // 6-char hex ID (e.g. "A3B12F")
    let rssi: Int          // Latest signal strength

    // MARK: - BLE baseline (always present)
    let bleName: String    // Up to 10-char name from BB packet
    let bleBio: String     // Up to 11-char bio from BB packet

    // MARK: - API-enriched fields (nil until the lookup succeeds)
    let fullName: String?      // Full name from API
    let fullBio: String?       // Full bio from API
    let techStack: [String]?   // e.g. ["SwiftUI", "Python", "C#"]
    let linkedIn: String?      // e.g. "linkedin.com/in/reedstewart"
    let isEnriched: Bool       // True once API data has been applied

    // MARK: - Convenience display accessors

    /// Returns the best available name: API full name → BLE name
    var displayName: String { fullName ?? bleName }

    /// Returns the best available bio: API full bio → BLE bio
    var displayBio: String { fullBio ?? bleBio }

    // MARK: - Init from BLE only (pre-enrichment)

    init(from profile: NearbyProfile) {
        self.id        = profile.id
        self.hexID     = profile.hexID
        self.rssi      = profile.rssi
        self.bleName   = profile.name
        self.bleBio    = profile.details
        self.fullName  = nil
        self.fullBio   = nil
        self.techStack = nil
        self.linkedIn  = nil
        self.isEnriched = false
    }

    // MARK: - Init enriched (post-API call)

    init(from profile: NearbyProfile, apiData: UserProfile) {
        self.id        = profile.id
        self.hexID     = profile.hexID
        self.rssi      = profile.rssi
        self.bleName   = profile.name
        self.bleBio    = profile.details
        self.fullName  = apiData.name
        self.fullBio   = apiData.bio
        self.techStack = apiData.techStack
        self.linkedIn  = apiData.linkedIn
        self.isEnriched = true
    }

    // MARK: - Convenience: update RSSI without losing enrichment

    func withUpdatedRSSI(_ newRSSI: Int) -> EnrichedProfile {
        EnrichedProfile(
            id: id, hexID: hexID, rssi: newRSSI,
            bleName: bleName, bleBio: bleBio,
            fullName: fullName, fullBio: fullBio,
            techStack: techStack, linkedIn: linkedIn,
            isEnriched: isEnriched
        )
    }

    // MARK: - Private full init (used by withUpdatedRSSI)

    private init(id: UUID, hexID: String, rssi: Int,
                 bleName: String, bleBio: String,
                 fullName: String?, fullBio: String?,
                 techStack: [String]?, linkedIn: String?,
                 isEnriched: Bool) {
        self.id = id; self.hexID = hexID; self.rssi = rssi
        self.bleName = bleName; self.bleBio = bleBio
        self.fullName = fullName; self.fullBio = fullBio
        self.techStack = techStack; self.linkedIn = linkedIn
        self.isEnriched = isEnriched
    }
}
