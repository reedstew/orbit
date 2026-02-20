//
//  JSONManager.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/20/26.
//


import Foundation

class JSONManager {
    static let shared = JSONManager()
    private var profileDatabase: [String: UserProfile] = [:]

    init() {
        loadLocalData()
    }

    private func loadLocalData() {
        guard let url = Bundle.main.url(forResource: "profiles", withExtension: "json") else {
            print("❌ profiles.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: UserProfile].self, from: data)
            self.profileDatabase = decoded
            print("✅ Loaded \(profileDatabase.count) profiles from JSON")
        } catch {
            print("❌ Error decoding JSON: \(error)")
        }
    }

    func fetchProfile(for hexID: String) -> UserProfile? {
        return profileDatabase[hexID]
    }
}