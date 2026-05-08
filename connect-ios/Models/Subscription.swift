//
//  Subscription.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Data model for Prime subscription
//

import Foundation

struct Subscription: Codable, Sendable {
    var dongleId: String
    var plan: String
    var amount: Int
    var trial: Bool
    var subscribedAt: Date
    var nextChargeAt: Date?
    var cancelAt: Date?

    init(dongleId: String, plan: String, amount: Int, trial: Bool, subscribedAt: Date, nextChargeAt: Date? = nil, cancelAt: Date? = nil) {
        self.dongleId = dongleId
        self.plan = plan
        self.amount = amount
        self.trial = trial
        self.subscribedAt = subscribedAt
        self.nextChargeAt = nextChargeAt
        self.cancelAt = cancelAt
    }

    enum CodingKeys: String, CodingKey {
        case dongleId = "dongle_id"
        case plan
        case amount
        case trial
        case subscribedAt = "subscribed_at"
        case nextChargeAt = "next_charge_at"
        case cancelAt = "cancel_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dongleId = try container.decode(String.self, forKey: .dongleId)
        plan = try container.decode(String.self, forKey: .plan)
        amount = try container.decode(Int.self, forKey: .amount)
        trial = try container.decodeIfPresent(Bool.self, forKey: .trial) ?? false

        let subscribedTimestamp = try container.decode(TimeInterval.self, forKey: .subscribedAt)
        subscribedAt = Date(timeIntervalSince1970: subscribedTimestamp)

        if let nextChargeTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .nextChargeAt) {
            nextChargeAt = Date(timeIntervalSince1970: nextChargeTimestamp)
        } else {
            nextChargeAt = nil
        }

        if let cancelTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .cancelAt) {
            cancelAt = Date(timeIntervalSince1970: cancelTimestamp)
        } else {
            cancelAt = nil
        }
    }

    var isActive: Bool {
        if let cancelDate = cancelAt {
            return Date() < cancelDate
        }
        return true
    }

    var planDisplayName: String {
        switch plan {
        case "nodata":
            return "Lite"
        case "data":
            return "Standard"
        default:
            return plan.capitalized
        }
    }

    var planSubtext: String {
        switch plan {
        case "nodata":
            return "without data plan"
        case "data":
            return "with data plan"
        default:
            return ""
        }
    }

    var formattedAmount: String {
        let dollars = Double(amount) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

struct SubscribeInfo: Codable, Sendable {
    var dongleId: String
    var amount: Int
    var currency: String

    enum CodingKeys: String, CodingKey {
        case dongleId = "dongle_id"
        case amount
        case currency
    }
}
