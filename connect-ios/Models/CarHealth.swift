//
//  CarHealth.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Data model for car health data (battery, panda type)
//

import Foundation

struct CarHealth: Codable {
    var peripheralState: PeripheralState

    struct PeripheralState: Codable {
        var voltage: Int // millivolts
        var current: Int

        var voltageInVolts: Double {
            Double(voltage) / 1000.0
        }
    }

    enum CodingKeys: String, CodingKey {
        case peripheralState = "peripheralState"
    }
}
