//
//  AppIntent.swift
//  CommaDeviceStatusWidget
//
//  Created by Will Killebrew on 11/23/25.
//

import WidgetKit
import AppIntents

struct DeviceSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Device" }
    static var description: IntentDescription { "Choose which device to display statistics for" }

    @Parameter(title: "Device")
    var selectedDevice: DeviceEntity?

    init(selectedDevice: DeviceEntity? = nil) {
        self.selectedDevice = selectedDevice
    }

    init() {
        self.selectedDevice = nil
    }
}

struct DeviceEntity: AppEntity {
    let id: String
    let displayName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Device"
    static var defaultQuery = DeviceEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct DeviceEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DeviceEntity] {
        let allDevices = WidgetDataStore.getAllDevices()
        guard !allDevices.isEmpty else {
            // No devices available yet - return placeholder
            return [DeviceEntity(id: "placeholder", displayName: "No devices yet")]
        }
        return identifiers.compactMap { id in
            guard let name = allDevices[id] else { return nil }
            return DeviceEntity(id: id, displayName: name)
        }
    }

    func suggestedEntities() async throws -> [DeviceEntity] {
        let allDevices = WidgetDataStore.getAllDevices()
        guard !allDevices.isEmpty else {
            // No devices available yet - return placeholder
            return [DeviceEntity(id: "placeholder", displayName: "No devices yet")]
        }
        return allDevices.map { DeviceEntity(id: $0.key, displayName: $0.value) }
    }

    func defaultResult() async -> DeviceEntity? {
        let allDevices = WidgetDataStore.getAllDevices()
        guard let first = allDevices.first else {
            // No devices available yet - return placeholder
            return DeviceEntity(id: "placeholder", displayName: "No devices yet")
        }
        return DeviceEntity(id: first.key, displayName: first.value)
    }
}
