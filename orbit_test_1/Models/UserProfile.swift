//
//  UserProfile.swift
//  orbit_test_1
//
//  A plain value type representing a fully resolved user from the "API".
//
//  `Sendable` conformance is explicit so Swift 6 allows this struct to
//  cross actor boundaries freely (e.g. decoded inside ProfileAPIService's
//  actor context, then passed back to MainActor-isolated UI code).
//
//  Note: `Identifiable` is intentionally NOT conformed here — that caused
//  the struct to pick up implicit @MainActor isolation via SwiftUI. Use
//  `id` directly where needed, or conform at the call site.
//

import Foundation

struct UserProfile: Codable, Sendable {
    let id: String          // The 6-char Hex ID (e.g. "A3B12F")
    let name: String
    let bio: String
    let techStack: [String]
    let linkedIn: String

    // Stable UUID derived from the Hex ID — computed, never stored
    var stableID: UUID { id.toStableUUID() }
}
