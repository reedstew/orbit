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
                  BBEnrichmentDelegate {

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

    /// Set when an inbound CC connection request arrives — drives a confirmation sheet in the UI
    @Published var pendingConnectionRequest: CCPacket? = nil

    // MARK: - Internal Storage
    private var profileBuffer: [UUID: NearbyProfile] = [:]
    private var uiUpdateTimer: Timer?
    private var cacheCleanupTimer: Timer?

    // MARK: - Sub-Handlers

    // bbHandler is lazy so we can assign self as delegate after super.init()
    private lazy var bbHandler: BasicBroadcastHandler = {
        let handler = BasicBroadcastHandler()
        handler.enrichmentDelegate = self
        return handler
    }()

    private lazy var ccHandler: ConnectionCallHandler = {
        let handler = ConnectionCallHandler(myHexID: myHexID)
        handler.delegate = self
        return handler
    }()

    // MARK: - Signal Dedup Cache (BB — 30-minute rule)
    private var signalCache: [String: Date] = [:]

    // MARK: - Protocol Constants
    let eventServiceUUID = CBUUID(string: "12345678-1234-1234-1234-1234567890AB")
    let myHexID = "A3B12F"
    let appUUID = "O9"

    // MARK: - Init

    override init() {
        super.init()
        centralManager    = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
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

        // BB dedup: skip if we saw this exact string within 30 minutes
        if localName.hasPrefix("O9BB") {
            if let lastSeen = signalCache[localName],
               Date().timeIntervalSince(lastSeen) < 1800 { return }
            signalCache[localName] = Date()
        }

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
            let payload = bbHandler.buildPayload(name: myName, bio: myBio, hexID: myHexID)
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
            // Step 1: write raw profile immediately (sync)
            // Step 2: fire async enrichment if WiFi available (inside handler)
            bbHandler.handle(packet: bbPacket, rssi: rssi, buffer: &profileBuffer)

        case .connection(let ccPacket):
            ccHandler.handle(packet: ccPacket)

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
        DispatchQueue.main.async {
            print("🎉 Connection confirmed with \(packet.fromName) (\(packet.fromID))")
            if let fullProfile = JSONManager.shared.fetchProfile(for: packet.fromID) {
                print("✅ Full profile loaded: \(fullProfile.name)")
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

    // MARK: - Private Helpers

    private func flushBufferToUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let sorted = self.profileBuffer.values.sorted { $0.rssi > $1.rssi }
            self.discoveredProfiles = Array(sorted.prefix(10))
        }
    }
}
