//
//  orbit_test_1App.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/19/26.
//

import SwiftUI

@main
struct orbit_test_1App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Generates a stable UUID from any string
extension String {
    func toStableUUID() -> UUID {
        // Use a hash of the string to create a perfectly reproducible 16-byte UUID
        var hash = self.hashValue
        let data = Data(bytes: &hash, count: MemoryLayout.size(ofValue: hash))
        
        // Pad the data to 16 bytes (the required length for a UUID)
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        let copyCount = min(data.count, 16)
        data.copyBytes(to: &uuidBytes, count: copyCount)
        
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
}

func hexToData(_ hex: String) -> Data {
    var data = Data()
    var hexString = hex
    while(hexString.count > 0) {
        let subIndex = hexString.index(hexString.startIndex, offsetBy: 2)
        let c = String(hexString[..<subIndex])
        hexString = String(hexString[subIndex...])
        if let ch = UInt8(c, radix: 16) {
            data.append(ch)
        }
    }
    return data
}
