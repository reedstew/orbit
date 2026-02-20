import Foundation
import SwiftUI
import CoreBluetooth
import Combine

// 1. Define the struct OUTSIDE the class so it is globally accessible
struct NearbyProfile: Identifiable {
    let id: UUID
    let name: String
    let details: String
    let rssi: Int
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    
    // MARK: - Hardware Managers
    var centralManager: CBCentralManager!
    var peripheralManager: CBPeripheralManager!
    
    // MARK: - Published UI State
    @Published var isBluetoothOn = false
    @Published var isBroadcasting = false
    @Published var isScanning = false
    @Published var discoveredProfiles: [NearbyProfile] = []
    @Published var currentMode: AppMode = .personal
    
    // MARK: - Internal Storage
    private var profileBuffer: [UUID: NearbyProfile] = [:]
    private var uiUpdateTimer: Timer?
    
    // Sub-Controllers
    private let discoveryHandler = BasicBroadcastHandler()
    private let connectionHandler = ConnectionCallHandler()
    
    // Cache to prevent duplicate processing (The 30-minute rule)
    private var signalCache: [String: Date] = [:]
    
    // Protocol Constants
    let eventServiceUUID = CBUUID(string: "12345678-1234-1234-1234-1234567890AB")
    let myHexID = "A3B12F" // Your stable 6-char hex ID
    let appUUID = "O9"  // Your custom app identifier
    
    enum AppMode { case personal, events }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    // MARK: - 1. Scanner Logic (Central)
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothOn = central.state == .poweredOn
        if isBluetoothOn {
            startScanning()
        } else {
            stopScanning()
        }
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        print("Orbit Scanner Starting...")
        
        centralManager.scanForPeripherals(
            withServices: [eventServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        
        // Refresh UI from buffer once per second to prevent main-thread hangs
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.flushBufferToUI()
        }
    }

    func stopScanning() {
        print("Orbit Scanner Stopping...")
        centralManager.stopScan()
        isScanning = false
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil
        profileBuffer.removeAll()
        discoveredProfiles.removeAll()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String else { return }
        
        // 1. Filtering Logic: Skip if seen in last 30 mins
        if let lastSeen = signalCache[localName], Date().timeIntervalSince(lastSeen) < 1800 { return }
        signalCache[localName] = Date()
        
        // 2. Route to the internal signal handler
        handleIncomingSignal(localName, rssi: RSSI.intValue)
    }

    // MARK: - 2. Broadcaster Logic (Peripheral)
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // Required delegate method; state handled via centralManager for simplicity
    }

    func toggleBroadcasting(myName: String, myBio: String) {
        if isBroadcasting {
            peripheralManager.stopAdvertising()
            isBroadcasting = false
        } else {
            let header = "O9BB"
            
            // Ensure name is exactly 10 and bio is exactly 11 bytes
            let paddedName = myName.padding(toLength: 10, withPad: " ", startingAt: 0)
            let paddedBio = myBio.padding(toLength: 11, withPad: " ", startingAt: 0)
            
            // Your 6-char Hex ID represented as 3 bytes/chars (e.g., "A3B")
            let shortID = String(myHexID.prefix(3))
            
            // Final Format: O9BB-Name      -Bio        -ID
            let payload = "\(header)-\(paddedName)-\(paddedBio)-\(shortID)"
            
            broadcastSignal(payload)
            isBroadcasting = true
        }
    }

    func broadcastSignal(_ payload: String, forDuration duration: TimeInterval? = nil) {
        guard peripheralManager.state == .poweredOn else { return }
        
        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising() }
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: payload,
            CBAdvertisementDataServiceUUIDsKey: [eventServiceUUID]
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        print("📣 Orbit Broadcasting: \(payload)")
        
        if let duration = duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.peripheralManager.stopAdvertising()
            }
        }
    }

    // MARK: - 3. Signal & Data Processing
    
    func handleIncomingSignal(_ rawString: String, rssi: Int) {
            guard let packet = PacketParser.parse(rawString) else { return }
            guard packet.appUUID == appUUID else { return }
            
            switch packet.type {
            case "BB":
                // Delegate the discovery logic to the specialized handler
                // 'inout' allows the handler to modify the buffer directly
                discoveryHandler.handle(packet: packet, rssi: rssi, buffer: &profileBuffer)
                
            case "CC":
                // connectionHandler.handleRequest(packet, myID: myHexID)
                print("Connection Request Logic Handled Here")
                
            default:
                print("Unhandled signal type: \(packet.type)")
            }
        }
    
    private func updateOrbitMap(userId: String, rssi: Int) {
        // 1. Resolve Hex ID to a full Profile from our JSON "API"
        if let profileData = JSONManager.shared.fetchProfile(for: userId) {
            
            let stableID = userId.toStableUUID()
            
            let profile = NearbyProfile(
                id: stableID,
                name: profileData.name,
                details: profileData.bio, // Now using the real bio from JSON
                rssi: rssi
            )
            
            profileBuffer[stableID] = profile
        } else {
            // Fallback if the user isn't in our hardcoded list
            print("❓ Unknown Hex ID discovered: \(userId)")
        }
    }

    private func performActionAndRepeat(payload: String) {
        // Trigger UI feedback then repeat broadcast for 2 seconds to facilitate epidemic spread
        broadcastSignal(payload, forDuration: 2.0)
    }

    private func flushBufferToUI() {
        DispatchQueue.main.async {
            // Depict 10 closest persons
            let sorted = self.profileBuffer.values.sorted(by: { $0.rssi > $1.rssi })
            self.discoveredProfiles = Array(sorted.prefix(10))
        }
    }
    
    // MARK: - 4. Packet Construction
    
    func constructPacket(type: String, toID: String, fromID: String) -> String {
        let randomPadding = String(format: "%02d", Int.random(in: 0...99))
        // Format: 0r61t-BB-A3B12F-A3B12F00 (29 bytes)
        return "\(appUUID)-\(type)-\(toID)-\(fromID)\(randomPadding)"
    }
}
