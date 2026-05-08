//
//  DriveEvent.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Data model for drive events (engagement, alerts, bookmarks)
//

import Foundation

struct DriveEvent: Codable, Identifiable {
    var id = UUID()
    var type: EventType
    var routeOffsetMillis: TimeInterval
    var data: EventData

    enum EventType: String, Codable {
        case engage
        case alert
        case overriding
        case bookmark
        case event
    }

    struct EventData: Codable {
        var state: String?
        var eventType: String?
        var alertStatus: AlertStatus?
        var endRouteOffsetMillis: TimeInterval?

        enum AlertStatus: String, Codable {
            case normal
            case userPrompt
            case critical
        }

        enum CodingKeys: String, CodingKey {
            case state
            case eventType = "event_type"
            case alertStatus = "alertStatus"
            case endRouteOffsetMillis = "end_route_offset_millis"
        }

        init(
            state: String? = nil,
            eventType: String? = nil,
            alertStatus: AlertStatus? = nil,
            endRouteOffsetMillis: TimeInterval? = nil
        ) {
            self.state = state
            self.eventType = eventType
            self.alertStatus = alertStatus
            self.endRouteOffsetMillis = endRouteOffsetMillis
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case routeOffsetMillis = "route_offset_millis"
        case data
    }

    init(type: EventType, routeOffsetMillis: TimeInterval, data: EventData) {
        self.type = type
        self.routeOffsetMillis = routeOffsetMillis
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(EventType.self, forKey: .type)
        routeOffsetMillis = try container.decode(TimeInterval.self, forKey: .routeOffsetMillis)
        data = try container.decode(EventData.self, forKey: .data)
    }
}
