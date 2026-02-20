//
//  EventActionHandler.swift
//  orbit_test_1
//
//  DEV: all cache windows = 10s (flip constants for production)
//
//  Security model:
//    - First EE packet seen for an eventID locks in the hostID as trusted.
//      Any later EE with same eventID but different hostID is dropped.
//    - Host device ignores its own EE broadcasts (no self-action, no self-ack).
//    - Host device broadcasts EE repeatedly on a timer so trust anchors
//      stay fresh and epidemic spread remains reliable.
//

import Foundation
import SwiftUI

// MARK: - Dev/Prod cache windows (change these before shipping)
private let kActionDedupWindow:   TimeInterval = 10   // prod: 60
private let kResponseDedupWindow: TimeInterval = 10   // prod: 1800

// MARK: - Action Definitions

enum EventAction: String, CaseIterable {
    case rollCall    = "RCALL0"
    case blueScreen  = "BLUES0"
    case greenScreen = "GRNS00"
    case endEvent    = "ENDVT0"

    var displayName: String {
        switch self {
        case .rollCall:    return "Roll Call"
        case .blueScreen:  return "Blue Screen"
        case .greenScreen: return "Green Screen"
        case .endEvent:    return "End Event"
        }
    }
}

enum AttendantAction: String {
    case rollCallAck = "RCACK0"
    case actionAck   = "ACTACK"
}

// MARK: - Event State

struct EventSession {
    let eventID: String
    let hostID:  String
}

// MARK: - Delegate

protocol EventActionDelegate: AnyObject {
    func didReceiveHostAction(_ action: EventAction, eventID: String, hostID: String)
    func didReceiveEndEvent(eventID: String)
    func didReceiveAttendantResponse(guestID: String, action: String, eventID: String)
    func broadcastEventResponse(_ payload: String)
    func rebroadcastAction(_ payload: String)
}

// MARK: - EventActionHandler

class EventActionHandler {

    weak var delegate: EventActionDelegate?

    // MARK: - State

    var hostSession:   EventSession?
    var joinedEventID: String?
    var joinedHostID:  String?

    /// Trust anchor: eventID → locked hostID.
    /// Populated on first valid EE for that eventID.
    /// Persisted to UserDefaults so it survives app restarts mid-event.
    private var trustedHosts: [String: String] = [:] {
        didSet { saveTrustedHosts() }
    }

    private let myIDProvider: () -> String
    private var myUserID: String { myIDProvider() }

    // MARK: - Dedup Caches
    private var attendantActionCache: [String: Date] = [:]
    private var hostResponseCache:    [String: Date] = [:]

    // MARK: - Init

    init(myIDProvider: @escaping () -> String) {
        self.myIDProvider = myIDProvider
        loadTrustedHosts()
    }

    // MARK: - Incoming: EE (host broadcast → attendants handle)

    func handleEE(packet: EEPacket, rebroadcastPayload: String) {

        // 1. HOST ISOLATION — never act on our own broadcast
        guard packet.hostID != myUserID else {
            print("🙈 [EE] Own EE received — ignoring (we are the host)")
            return
        }

        // 2. TRUST ANCHOR — lock hostID on first sight; reject impostors
        if let locked = trustedHosts[packet.eventID] {
            guard locked == packet.hostID else {
                print("🚨 [EE] Fake host! Event \(packet.eventID) is locked to \(locked), got \(packet.hostID) — dropping")
                return
            }
        } else {
            trustedHosts[packet.eventID] = packet.hostID
            joinedEventID = packet.eventID
            joinedHostID  = packet.hostID
            print("🔐 [EE] Trust anchor: event \(packet.eventID) → \(packet.hostID)")
        }

        // 3. ACTION DEDUP
        let cacheKey = "\(packet.eventID):\(packet.action)"
        if let last = attendantActionCache[cacheKey],
           Date().timeIntervalSince(last) < kActionDedupWindow {
            print("🔁 [EE] '\(packet.action)' suppressed (< \(Int(kActionDedupWindow))s)")
            // Still re-broadcast for epidemic spread even if we skip acting
            delegate?.rebroadcastAction(rebroadcastPayload)
            return
        }
        attendantActionCache[cacheKey] = Date()

        // 4. PARSE
        guard let action = EventAction(rawValue: packet.action) else {
            print("❓ [EE] Unknown action: \(packet.action)")
            return
        }
        print("📋 [EE] Event: \(packet.eventID) | Host: \(packet.hostID) | \(action.displayName)")

        // 5. EPIDEMIC RE-BROADCAST
        delegate?.rebroadcastAction(rebroadcastPayload)

        // 6. END EVENT
        if action == .endEvent {
            joinedEventID = nil
            joinedHostID  = nil
            trustedHosts.removeValue(forKey: packet.eventID)
            delegate?.didReceiveEndEvent(eventID: packet.eventID)
            return
        }

        // 7. NOTIFY UI
        delegate?.didReceiveHostAction(action, eventID: packet.eventID, hostID: packet.hostID)

        // 8. SEND ACK
        let ackAction = action == .rollCall
            ? AttendantAction.rollCallAck.rawValue
            : AttendantAction.actionAck.rawValue
        delegate?.broadcastEventResponse(
            PacketBuilder.buildEA(eventID: packet.eventID, guestID: myUserID, action: ackAction)
        )
    }

    // MARK: - Incoming: EA (attendant response → host handles)

    func handleEA(packet: EAPacket) {
        guard let session = hostSession, session.eventID == packet.eventID else {
            print("📭 [EA] Not hosting \(packet.eventID) — ignoring")
            return
        }

        let cacheKey = "\(packet.guestID):\(packet.action)"
        if let last = hostResponseCache[cacheKey],
           Date().timeIntervalSince(last) < kResponseDedupWindow {
            print("🔁 [EA] \(packet.guestID)/'\(packet.action)' suppressed (< \(Int(kResponseDedupWindow))s)")
            return
        }
        hostResponseCache[cacheKey] = Date()

        print("✅ [EA] \(packet.guestID) → \(packet.action) (event \(packet.eventID))")
        delegate?.didReceiveAttendantResponse(
            guestID: packet.guestID,
            action: packet.action,
            eventID: packet.eventID
        )
    }

    // MARK: - Host Controls

    func startHosting(eventID: String) {
        hostSession   = EventSession(eventID: eventID, hostID: myUserID)
        joinedEventID = eventID
        joinedHostID  = myUserID
        trustedHosts[eventID] = myUserID  // register ourselves as the anchor
        print("🎤 [Event] Hosting: \(eventID)")
    }

    func stopHosting() {
        guard let s = hostSession else { return }
        trustedHosts.removeValue(forKey: s.eventID)
        hostSession = nil
        print("🛑 [Event] Stopped hosting: \(s.eventID)")
    }

    func buildHostBroadcast(action: EventAction) -> String? {
        guard let s = hostSession else { return nil }
        return PacketBuilder.buildEE(eventID: s.eventID, hostID: myUserID, action: action.rawValue)
    }

    // MARK: - Attendant Controls

    func joinEvent(eventID: String, hostID: String) {
        joinedEventID = eventID
        joinedHostID  = hostID
        trustedHosts[eventID] = hostID
        print("🎟️ [Event] Joined \(eventID) hosted by \(hostID)")
    }

    func leaveEvent() {
        if let id = joinedEventID { trustedHosts.removeValue(forKey: id) }
        joinedEventID = nil
        joinedHostID  = nil
        attendantActionCache.removeAll()
        print("👋 [Event] Left event")
    }

    var isHosting:   Bool { hostSession   != nil }
    var isAttending: Bool { joinedEventID != nil }

    // MARK: - Cache Maintenance

    func purgeExpiredCaches() {
        let now = Date()
        attendantActionCache = attendantActionCache.filter { now.timeIntervalSince($0.value) < kActionDedupWindow }
        hostResponseCache    = hostResponseCache.filter    { now.timeIntervalSince($0.value) < kResponseDedupWindow }
    }

    // MARK: - Trust Anchor Persistence

    private let kTrustedHostsKey = "orbit_trustedHosts"

    private func saveTrustedHosts() {
        UserDefaults.standard.set(trustedHosts, forKey: kTrustedHostsKey)
    }

    private func loadTrustedHosts() {
        trustedHosts = (UserDefaults.standard.dictionary(forKey: kTrustedHostsKey) as? [String: String]) ?? [:]
        if !trustedHosts.isEmpty {
            print("🔐 [Event] Loaded \(trustedHosts.count) trust anchor(s): \(trustedHosts)")
        }
    }
}
