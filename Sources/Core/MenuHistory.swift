// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation

enum MenuEventKind: String, CaseIterable, Identifiable {
    case started, stopped, firstSeen
    var id: String { rawValue }
    var title: String {
        switch self { case .started: return "Started"; case .stopped: return "Stopped"; case .firstSeen: return "First seen" }
    }
    init(_ event: SensorEvent) {
        self = event.observation == "first-observed" ? .firstSeen : (event.action == .start ? .started : .stopped)
    }
}

/// Presentation preferences only. These never change collection, CSV output or notifications.
struct MenuHistoryFilter: Equatable {
    static let limit = 5
    var sensors: Set<Sensor> = Set(Sensor.allCases)
    var kinds: Set<MenuEventKind> = Set(MenuEventKind.allCases)
    var hasSelection: Bool { !sensors.isEmpty && !kinds.isEmpty }

    init() {}
    init(defaults: UserDefaults) {
        // A saved empty selection is intentional; only missing keys get the defaults.
        if let values = defaults.stringArray(forKey: "menuHistory.sensors") {
            sensors = Set(values.compactMap(Sensor.init(rawValue:)))
        }
        if let values = defaults.stringArray(forKey: "menuHistory.eventKinds") {
            kinds = Set(values.compactMap(MenuEventKind.init(rawValue:)))
        }
    }
    func save(to defaults: UserDefaults) {
        defaults.set(sensors.map(\.rawValue).sorted(), forKey: "menuHistory.sensors")
        defaults.set(kinds.map(\.rawValue).sorted(), forKey: "menuHistory.eventKinds")
    }
    /// The app and CSV reader supply newest-first history. Filter before limiting
    /// so an older matching event isn't hidden by five more recent excluded ones.
    func recentEvents(in events: [SensorEvent]) -> [SensorEvent] {
        Array(events.lazy.filter { sensors.contains($0.sensor) && kinds.contains(MenuEventKind($0)) }.prefix(Self.limit))
    }
}
