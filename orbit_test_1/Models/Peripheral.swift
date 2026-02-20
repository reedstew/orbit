//
//  Peripheral.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/19/26.
//

import Foundation

struct Peripheral: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int // a constact property of RSSI for signal strength of peripheral
}
