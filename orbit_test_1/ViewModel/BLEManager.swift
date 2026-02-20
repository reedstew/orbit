//
//  BLEManager.swift
//  orbit_test_1
//
//  Central orchestrator for all Bluetooth scanning and broadcasting.
//  Routes parsed packets to the appropriate sub-handler.
//

import Foundation
import SwiftUI
import CoreBluetooth
import Combine

// MARK: - BLEManager

class BLEManager: NSObject, ObservableObject,
                  CBCentralManagerDelegate,
                  CBPeripheralManagerDelegate,
                  ConnectionCallDelegate {

    // MARK: - Hardware
    var centralManager: CBCentralManager!
    var peripheralManager: CBPeripheralManager!

    // MARK: - Published UI State
    @Published var isBluetoothOn        = false
    @Published var isBroadcasting       = false
    @Published var isScanning           = false
    @Published var discoveredProfiles:    [NearbyProfile] = []

    /// Set when an inbound connection request arrives — drives a sheet/alert in the UI
    @Published var pendingConnectionRequest: CCPacket? = nil

    // MARK: - Internal Storage
    private var profileBuffer: [UUID: NearbyProfile] = [:]
    private var uiUpdateTimer: Timer?
    private var cacheCleanupTimer: Timer?

    // MARK: - Sub-Handlers
    private let bbHandler = BasicBroadcastHandler()
    private lazy var ccHandler: ConnectionCallHandler = {
        let handler = ConnectionCallHandler(myHexID: myHexID)
        handler.delegate = self
        return handler
    }()

    // MARK: - Signal Dedup Cache (BB — 30-minute rule)
    // Key: raw advertisement string, Value: time last seen
    private var signalCache: [String: Date] = [:]

    // MARK: - Protocol Constants
    let eventServiceUUID = CBUUID(string: "12345678-1234-1234-1234-1234567890AB")
    let myHexID  = "A3B12F"   // This device's stable 6-char Hex ID
    let appUUID  = "O9"       // Orbit app identifier prefix

    // MARK: - Init

    override init() {
        super.init()
        centralManager   = CBCentralManager(delegate: self, queue: nil)
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

        // Flush the buffer to UI once per second
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.flushBufferToUI()
        }

        // Clean up the CC connection cache every 10 minutes
        cacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.ccHandler.purgeExpiredCache()
        }
    }

    func stopScanning() {
        print("🛑 Orbit Scanner Stopping...")
        centralManager.stopScan()
        isScanning = false
        uiUpdateTimer?.invalidate();    uiUpdateTimer = nil
        cacheCleanupTimer?.invalidate(); cacheCleanupTimer = nil
        profileBuffer.removeAll()
        discoveredProfiles.removeAll()
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String else { return }

        // BB dedup: ignore same string seen within 30 minutes
        // (CC packets use their own cache inside ConnectionCallHandler)
        if localName.hasPrefix("O9BB") {
            if let lastSeen = signalCache[localName],
               Date().timeIntervalSince(lastSeen) < 1800 { return }
            signalCache[localName] = Date()
        }

        handleIncomingSignal(localName, rssi: RSSI.intValue)
    }

    // MARK: - 2. Broadcaster (Peripheral)

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // State mirrored via centralManager; nothing extra needed here
    }

    /// Toggle broadcasting on/off using the user's current name, bio, and this device's Hex ID.
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

    /// Parse and route any incoming BLE advertisement string.
    func handleIncomingSignal(_ rawString: String, rssi: Int) {
        guard let packet = PacketParser.parse(rawString) else {
            print("⚠️ Could not parse: \(rawString)")
            return
        }

        switch packet {

        case .broadcast(let bbPacket):
            // Hand off to BasicBroadcastHandler — updates the profile buffer
            bbHandler.handle(packet: bbPacket, rssi: rssi, buffer: &profileBuffer)

        case .connection(let ccPacket):
            // Hand off to ConnectionCallHandler — checks if addressed to us, updates cache
            ccHandler.handle(packet: ccPacket)

        case .unknown(let appUUID, let type):
            print("❓ Unknown packet type: \(appUUID)\(type)")
        }
    }

    // MARK: - 4. Connection Actions (called from UI)

    /// Initiate a connection request to a nearby user
    func sendConnectionRequest(to profile: NearbyProfile, myName: String) {
        // Reverse-map UUID → HexID by scanning the buffer
        guard let hexID = hexIDFor(profile: profile) else {
            print("⚠️ Could not find Hex ID for \(profile.name)")
            return
        }
        ccHandler.sendConnectionRequest(myName: myName, toHexID: hexID)
    }

    /// Accept an inbound connection request
    func acceptConnectionRequest(from packet: CCPacket, myName: String) {
        ccHandler.acceptConnectionRequest(myName: myName, toHexID: packet.fromID)
        pendingConnectionRequest = nil
    }

    /// Reject an inbound connection request
    func rejectConnectionRequest(from packet: CCPacket, myName: String) {
        ccHandler.rejectConnectionRequest(myName: myName, toHexID: packet.fromID)
        pendingConnectionRequest = nil
    }

    // MARK: - 5. ConnectionCallDelegate

    func didReceiveConnectionRequest(from packet: CCPacket) {
        DispatchQueue.main.async { [weak self] in
            print("🤝 Connection request from \(packet.fromName) (\(packet.fromID))")
            self?.pendingConnectionRequest = packet
        }
    }

    func didReceiveConnectionConfirmation(from packet: CCPacket) {
        DispatchQueue.main.async {
            print("🎉 Connection confirmed with \(packet.fromName) (\(packet.fromID))")
            // TODO: Load full profile from JSONManager and present it
            if let fullProfile = JSONManager.shared.fetchProfile(for: packet.fromID) {
                print("✅ Full profile loaded: \(fullProfile.name) — \(fullProfile.bio)")
            }
        }
    }

    func broadcastConnectionPacket(_ payload: String) {
        // Broadcast 3 times with a short gap to improve receipt reliability
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

    /// Retrieve the original HexID for a NearbyProfile by matching its stableID
    private func hexIDFor(profile: NearbyProfile) -> String? {
        // The profile's UUID was generated from a HexID via toStableUUID().
        // We find it by checking all known profiles in the JSONManager.
        // For profiles not in JSON (discovered via BLE only), we can't recover the raw HexID
        // unless we store it explicitly — see note below.
        //
        // TODO: Store hexID directly on NearbyProfile for cleaner reverse lookup.
        return nil
    }
}

// MARK: - NearbyProfile HexID Extension
// To properly support sendConnectionRequest, store hexID on the profile.
// Update NearbyProfile to:
//
//   struct NearbyProfile: Identifiable {
//       let id: UUID
//       let hexID: String   // ← ADD THIS
//       let name: String
//       let details: String
//       let rssi: Int
//   }
//
// Then update BasicBroadcastHandler.handle() to pass packet.hexID when constructing the profile.
