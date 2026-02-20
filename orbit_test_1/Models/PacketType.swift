//
//  PacketType.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/20/26.
//

enum PacketType {
    case discovery(name: String, bio: String, userId: String)
    case connectionRequest(targetId: String, fromId: String)
    case connectionGrant(targetId: String, fromId: String)
    case eventHost(eventId: String, hostName: String, userId: String)
    case eventAction(eventId: String, actionId: String, hostId: String)
    case unknown
}
