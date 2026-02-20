//
//  UserProfile.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/20/26.
//

import Foundation

struct UserProfile: Codable, Identifiable {
    let id: String // The 6-char Hex ID
    let name: String
    let bio: String
    let techStack: [String]
    let linkedIn: String
    
    // Conforming to Identifiable
    var uid: UUID { id.toStableUUID() }
}
