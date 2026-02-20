//
//  ProfileAPIService.swift
//  orbit_test_1
//
//  Resolves a 6-char Hex ID to a full UserProfile.
//
//  Declared as an `actor` so Swift's structured concurrency protects the
//  cache dictionary without any manual locking. Every `await` on this type
//  automatically serialises access — NSLock is neither needed nor allowed
//  in Swift 6 async contexts.
//
//  Current backend: local profiles.json (simulated async call)
//  Future backend:  set useRemote = true and drop in the real baseURL —
//                   no other files need to change.
//

import Foundation

// MARK: - Errors

enum ProfileAPIError: Error, LocalizedError {
    case notFound(hexID: String)
    case networkUnavailable
    case decodingFailed(Error)
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):      return "No profile found for Hex ID: \(id)"
        case .networkUnavailable:    return "No WiFi connection available"
        case .decodingFailed(let e): return "Decoding error: \(e.localizedDescription)"
        case .requestFailed(let c):  return "HTTP \(c)"
        }
    }
}

// MARK: - Service

actor ProfileAPIService {

    // MARK: - Singleton
    static let shared = ProfileAPIService()

    // MARK: - Config
    private let baseURL   = "https://api.orbitapp.io/v1/profiles"
    private let useRemote = false   // ← flip to true when backend is ready

    // MARK: - Cache
    // Actor isolation makes this safe to read/write from any async context —
    // Swift serialises all access automatically. No locks required.
    private var cache: [String: UserProfile] = [:]

    private init() {}

    // MARK: - Public API

    /// Fetch a full UserProfile for the given Hex ID.
    ///
    /// - If WiFi is unavailable: throws `ProfileAPIError.networkUnavailable`
    /// - If not found: throws `ProfileAPIError.notFound`
    /// - On success: caches and returns the `UserProfile`
    func fetchProfile(hexID: String) async throws -> UserProfile {
        // 1. Cache hit — skip the network entirely
        if let cached = cache[hexID] {
            print("💾 [API] Cache hit for \(hexID)")
            return cached
        }

        // 2. WiFi gate
        guard NetworkMonitor.shared.isOnWifi else {
            print("📵 [API] WiFi unavailable — skipping lookup for \(hexID)")
            throw ProfileAPIError.networkUnavailable
        }

        // 3. Fetch
        let profile = try await useRemote
            ? remoteLookup(hexID: hexID)
            : localLookup(hexID: hexID)

        // 4. Write back to cache
        // Still on the actor after the await returns, so this is safe.
        cache[hexID] = profile
        print("✅ [API] Resolved \(hexID) → \(profile.name)")
        return profile
    }

    /// Best-effort fetch — returns nil on any failure.
    /// Use at call sites that don't need error handling (e.g. BB enrichment).
    func tryFetchProfile(hexID: String) async -> UserProfile? {
        try? await fetchProfile(hexID: hexID)
    }

    // MARK: - Local backend (profiles.json)

    private func localLookup(hexID: String) async throws -> UserProfile {
        // Simulate a realistic network round-trip (50–150ms)
        let delay = Double.random(in: 0.05...0.15)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        guard let profile = JSONManager.shared.fetchProfile(for: hexID) else {
            throw ProfileAPIError.notFound(hexID: hexID)
        }
        return profile
    }

    // MARK: - Remote backend (future)
    //
    // Swap localLookup for this once your backend is live.
    // Expected JSON response: { "id": "A3B12F", "name": "...", "bio": "...", ... }

    private func remoteLookup(hexID: String) async throws -> UserProfile {
        guard let url = URL(string: "\(baseURL)/\(hexID)") else {
            throw ProfileAPIError.notFound(hexID: hexID)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 404 { throw ProfileAPIError.notFound(hexID: hexID) }
            throw ProfileAPIError.requestFailed(http.statusCode)
        }

        // Decoding is done in a nonisolated context so it isn't subject to
        // actor isolation rules — this is the correct Swift 6 pattern when
        // JSONDecoder needs to produce a type whose Decodable conformance
        // the compiler can't verify as actor-safe at the call site.
        return try Self.decode(data)
    }

    // MARK: - Nonisolated decode helper
    //
    // `nonisolated` removes this method from the actor's isolation domain,
    // letting JSONDecoder run without the compiler enforcing @MainActor
    // conformance checks. Safe here because Data and UserProfile are both
    // Sendable value types — nothing shared or mutable crosses the boundary.

    nonisolated private static func decode(_ data: Data) throws -> UserProfile {
        do {
            return try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            throw ProfileAPIError.decodingFailed(error)
        }
    }
}
