//
//  BLEManager.swift
//  orbit_test_1
//
//  Central orchestrator for all Bluetooth scanning and broadcasting.
//  Routes parsed packets to the appropriate sub-handler.
//
//  Changes in this version:
//  - Adopts BBEnrichmentDelegate to receive async-enriched profiles from BasicBroadcastHandler
//  - Publishes `enrichedProfiles` ([String: EnrichedProfile]) alongside `discoveredProfiles`
//  - NearbyProfile definition moved to NearbyProfile.swift (includes hexID field)
//

import Foundation
import SwiftUI
import CoreBluetooth
import Combine

// MARK: - BLEManager

class BLEManager: NSObject, ObservableObject,
                  CBCentralManagerDelegate,
                  CBPeripheralManagerDelegate,
                  ConnectionCallDelegate,
                  BBEnrichmentDelegate,
                  EventActionDelegate {

    // MARK: - Hardware
    var centralManager: CBCentralManager!
    var peripheralManager: CBPeripheralManager!

    // MARK: - Published UI State

    @Published var isBluetoothOn  = false
    @Published var isBroadcasting = false
    @Published var isScanning     = false

    /// Raw BLE-only profiles — always populated, even without WiFi.
    /// Used by OrbitMapView and the People Nearby list.
    @Published var discoveredProfiles: [NearbyProfile] = []

    /// Enriched profiles keyed by hexID — populated when WiFi API lookup succeeds.
    /// The UI should overlay these on top of the raw profiles wherever available.
    /// Access pattern: bleManager.enrichedProfiles["A3B12F"]
    @Published var enrichedProfiles: [String: EnrichedProfile] = [:]

    /// Mirrors ConnectionsStore.connectedIDs — drives UI reactivity for connection state.
    @Published var connectedIDs: Set<String> = ConnectionsStore.shared.connectedIDs

    /// Active host action to display — set when an EE packet triggers a screen action.
    /// Cleared after the UI has handled it.
    @Published var activeEventAction: EventAction? = nil

    /// Attendees logged by the host during roll call — keyed by guestID.
    @Published var eventAttendees: [String: Date] = [:]

    /// True when this device is in event host mode.
    @Published var isHostingEvent: Bool = false

    /// Set when an inbound CC connection request arrives — drives a confirmation sheet in the UI
    @Published var pendingConnectionRequest: CCPacket? = nil

    // MARK: - Internal Storage
    private var profileBuffer: [UUID: NearbyProfile] = [:]
    private var uiUpdateTimer: Timer?
    private var cacheCleanupTimer: Timer?
    /// Fires every 3s while hosting to keep EE packets flowing for epidemic spread
    private var eeBroadcastTimer: Timer?

    // MARK: - Sub-Handlers

    // bbHandler is lazy so we can assign self as delegate after super.init()
    private lazy var bbHandler: BasicBroadcastHandler = {
        let handler = BasicBroadcastHandler()
        handler.enrichmentDelegate = self
        return handler
    }()

    private lazy var ccHandler: ConnectionCallHandler = {
        let handler = ConnectionCallHandler(myIDProvider: { [weak self] in
            self?.myUserID ?? "NONE00"
        })
        handler.delegate = self
        return handler
    }()

    lazy var eventHandler: EventActionHandler = {
        let handler = EventActionHandler(myIDProvider: { [weak self] in
            self?.myUserID ?? "NONE00"
        })
        handler.delegate = self
        return handler
    }()

    // MARK: - Signal Dedup Cache (BB — 30-minute rule)
    private var signalCache: [String: Date] = [:]

    // MARK: - Protocol Constants
    let eventServiceUUID = CBUUID(string: "12345678-1234-1234-1234-1234567890AB")
    let appUUID  = "O9"

    /// Reads the active user ID from UserDefaults at the moment of use so it
    /// always reflects whichever dev profile was selected in EditProfileView.
    /// Falls back to "NONE00" (valid 6-char length) if not yet configured.
    var myUserID: String {
        let stored = UserDefaults.standard.string(forKey: "userID") ?? ""
        return stored.isEmpty ? "NONE00" : String(stored.prefix(6))
    }

    // MARK: - Init

    override init() {
        super.init()
        centralManager    = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)

        // Mirror ConnectionsStore changes into @Published so SwiftUI reacts
        ConnectionsStore.shared.onChange = { [weak self] updated in
            DispatchQueue.main.async {
                self?.connectedIDs = updated
            }
        }
    }

    // MARK: - 1. Scanner (Central)

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothOn = central.state == .poweredOn
        if isBluetoothOn { startScanning() } else { stopScanning() }
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        print("🔍 Orbit Scanner Starting...")

        centralManager.scanForPeripherals(
            withServices: [eventServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true

        // Flush buffer to UI once per second
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.flushBufferToUI()
        }

        // Purge CC connection cache every 10 minutes
        cacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.ccHandler.purgeExpiredCache()
        }
    }

    func stopScanning() {
        print("🛑 Orbit Scanner Stopping...")
        centralManager.stopScan()
        isScanning = false
        uiUpdateTimer?.invalidate();     uiUpdateTimer = nil
        cacheCleanupTimer?.invalidate(); cacheCleanupTimer = nil
        profileBuffer.removeAll()
        discoveredProfiles.removeAll()
        // Note: enrichedProfiles intentionally retained — no need to re-fetch on re-scan
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String else { return }
        handleIncomingSignal(localName, rssi: RSSI.intValue)
    }

    // MARK: - 2. Broadcaster (Peripheral)

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) { }

    func toggleBroadcasting(myName: String, myBio: String) {
        if isBroadcasting {
            peripheralManager.stopAdvertising()
            isBroadcasting = false
            print("📴 Broadcasting stopped")
        } else {
            // Trim whitespace so stale padded AppStorage values never reach the packet
            let name    = myName.trimmingCharacters(in: .whitespaces)
            let bio     = myBio.trimmingCharacters(in: .whitespaces)
            let payload = bbHandler.buildPayload(name: name, bio: bio, asciiID: myUserID)
            broadcastSignal(payload)
            isBroadcasting = true
        }
    }

    func broadcastSignal(_ payload: String, forDuration duration: TimeInterval? = nil) {
        guard peripheralManager.state == .poweredOn else {
            print("⚠️ Cannot broadcast — peripheral manager not powered on")
            return
        }

        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising() }

        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: payload,
            CBAdvertisementDataServiceUUIDsKey: [eventServiceUUID]
        ]

        peripheralManager.startAdvertising(advertisementData)
        print("📣 Broadcasting: \(payload)")

        if let duration = duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.peripheralManager.stopAdvertising()
            }
        }
    }

    // MARK: - 3. Signal Routing

    func handleIncomingSignal(_ rawString: String, rssi: Int) {
        guard let packet = PacketParser.parse(rawString) else {
            print("⚠️ Could not parse: \(rawString)")
            return
        }

        switch packet {
        case .broadcast(let bbPacket):
            bbHandler.handle(packet: bbPacket, rssi: rssi, buffer: &profileBuffer)

        case .connection(let ccPacket):
            print("📨 [CC] Received → toID: \(ccPacket.toID) | myID: \(myUserID)")
            ccHandler.handle(packet: ccPacket)

        case .eventHost(let eePacket):
            let rebroadcast = PacketBuilder.buildEE(
                eventID: eePacket.eventID,
                hostID: eePacket.hostID,
                action: eePacket.action
            )
            eventHandler.handleEE(packet: eePacket, rebroadcastPayload: rebroadcast)

        case .eventAttendant(let eaPacket):
            eventHandler.handleEA(packet: eaPacket)

        case .unknown(let uuid, let type):
            print("❓ Unknown packet type: \(uuid)\(type)")
        }
    }

    // MARK: - 4. BBEnrichmentDelegate

    /// Called on the main thread by BasicBroadcastHandler after a successful API lookup.
    func didEnrichProfile(_ enriched: EnrichedProfile) {
        // Store by hexID for O(1) lookup from the UI
        enrichedProfiles[enriched.hexID] = enriched
        print("✨ Profile enriched and stored: \(enriched.hexID) → \(enriched.displayName)")
    }

    // MARK: - 5. Connection Actions (called from UI)

    func sendConnectionRequest(to profile: NearbyProfile, myName: String) {
        ccHandler.sendConnectionRequest(myName: myName, toHexID: profile.hexID)
    }

    func acceptConnectionRequest(from packet: CCPacket, myName: String) {
        ccHandler.acceptConnectionRequest(myName: myName, toHexID: packet.fromID)
        pendingConnectionRequest = nil
    }

    func rejectConnectionRequest(from packet: CCPacket, myName: String) {
        ccHandler.rejectConnectionRequest(myName: myName, toHexID: packet.fromID)
        pendingConnectionRequest = nil
    }

    // MARK: - 6. ConnectionCallDelegate

    func didReceiveConnectionRequest(from packet: CCPacket) {
        DispatchQueue.main.async { [weak self] in
            print("🤝 Connection request from \(packet.fromName) (\(packet.fromID))")
            self?.pendingConnectionRequest = packet
        }
    }

    func didReceiveConnectionConfirmation(from packet: CCPacket) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("🎉 Connection confirmed with \(packet.fromName) (\(packet.fromID))")

            // If their BB profile is already in our buffer, enrich it now
            // rather than waiting for the next BB signal
            let stableID = packet.fromID.toStableUUID()
            if let existingProfile = self.profileBuffer[stableID] {
                Task {
                    await self.bbHandler.enrichIfConnected(
                        profile: existingProfile,
                        delegate: self
                    )
                }
            }
        }
    }

    func broadcastConnectionPacket(_ payload: String) {
        // Send 3× with short gaps for epidemic-reliable receipt
        broadcastSignal(payload, forDuration: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.broadcastSignal(payload, forDuration: 0.5)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.broadcastSignal(payload, forDuration: 0.5)
        }
    }

    // MARK: - 7. EventActionDelegate

    func didReceiveHostAction(_ action: EventAction, eventID: String, hostID: String) {
        DispatchQueue.main.async { [weak self] in
            print("🎬 [Event] Action received: \(action.displayName) for event \(eventID)")
            self?.activeEventAction = action
            // Auto-clear after 3 seconds so overlay doesn't stay up forever
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self?.activeEventAction == action { self?.activeEventAction = nil }
            }
        }
    }

    func didReceiveEndEvent(eventID: String) {
        DispatchQueue.main.async { [weak self] in
            print("🏁 [Event] Event ended: \(eventID)")
            self?.activeEventAction = nil
            self?.eventAttendees.removeAll()
            self?.isHostingEvent = false
        }
    }

    func didReceiveAttendantResponse(guestID: String, action: String, eventID: String) {
        DispatchQueue.main.async { [weak self] in
            print("📋 [Event] Attendee \(guestID) → \(action)")
            self?.eventAttendees[guestID] = Date()
        }
    }

    func broadcastEventResponse(_ payload: String) {
        // EA response — send once (crowd will re-broadcast via epidemic)
        broadcastSignal(payload, forDuration: 0.5)
    }

    func rebroadcastAction(_ payload: String) {
        // Epidemic re-broadcast — 2 second burst to propagate to farther devices
        broadcastSignal(payload, forDuration: 2.0)
    }

    // MARK: - 8. Public Event API (called from UI)

    /// Start hosting an event — broadcasts EE every 3s so trust anchors stay
    /// alive on attendant devices and epidemic spread remains reliable.
    func startHostingEvent(eventID: String) {
        eventHandler.startHosting(eventID: eventID)
        isHostingEvent = true

        // Broadcast immediately, then repeat every 3 seconds
        broadcastCurrentHostAction()
        eeBroadcastTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.broadcastCurrentHostAction()
        }
    }

    func stopHostingEvent() {
        eeBroadcastTimer?.invalidate()
        eeBroadcastTimer = nil

        guard let session = eventHandler.hostSession else { return }
        // Broadcast end event 3× so all attendants catch it
        let payload = PacketBuilder.buildEE(
            eventID: session.eventID,
            hostID: myUserID,
            action: EventAction.endEvent.rawValue
        )
        for delay in [0.0, 0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.broadcastSignal(payload, forDuration: 0.5)
            }
        }
        eventHandler.stopHosting()
        isHostingEvent = false
        eventAttendees.removeAll()
    }

    /// Send an action to all attendees as the host.
    /// Also updates what the timer will repeat.
    func broadcastHostAction(_ action: EventAction) {
        guard let payload = eventHandler.buildHostBroadcast(action: action) else {
            print("⚠️ Not currently hosting an event")
            return
        }
        currentHostAction = action
        broadcastSignal(payload)
        print("📣 [Event] Broadcasting action: \(action.displayName)")
    }

    /// The action the host timer will keep broadcasting (defaults to rollCall)
    private var currentHostAction: EventAction = .rollCall

    private func broadcastCurrentHostAction() {
        guard let payload = eventHandler.buildHostBroadcast(action: currentHostAction) else { return }
        broadcastSignal(payload)
        print("📡 [EE] Timer broadcast: \(currentHostAction.displayName)")
    }

    // MARK: - Private Helpers

    private func flushBufferToUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let sorted = self.profileBuffer.values.sorted { $0.rssi > $1.rssi }
            self.discoveredProfiles = Array(sorted.prefix(10))
        }
    }
}
