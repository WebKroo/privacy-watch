// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation

enum ActivityRowStyle: String, CaseIterable, Identifiable {
    case events, combined
    var id: String { rawValue }
    var title: String { self == .events ? "Separate events" : "Combined activity" }
}

struct ActivityDisplay: Equatable {
    var style: ActivityRowStyle = .events
    var compact = false
    init() {}
    init(defaults: UserDefaults) {
        style = ActivityRowStyle(rawValue: defaults.string(forKey: "activity.rowStyle") ?? "") ?? .events
        compact = defaults.bool(forKey: "activity.compactRows")
    }
    func save(to defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: "activity.rowStyle")
        defaults.set(compact, forKey: "activity.compactRows")
    }
}

/// Local presentation metadata: never inserts synthetic events into the CSV.
/// A boundary before the next event for a sensor prevents pairing across a pause,
/// reconnect, process launch, or a change to that sensor's recording preference.
struct ActivityContinuity {
    private(set) var breakBeforeEventIDs = Set<UUID>()
    private var pendingSensors = Set(Sensor.allCases)
    private var activeStarts: [Attribution: UUID] = [:]
    var activeStartIDs: Set<UUID> { Set(activeStarts.values) }

    init() {}
    init(defaults: UserDefaults, folder: URL) {
        breakBeforeEventIDs = Set((defaults.stringArray(forKey: Self.key(folder)) ?? []).compactMap(UUID.init(uuidString:)))
    }
    private static func key(_ folder: URL) -> String { "activity.boundaries:" + folder.standardizedFileURL.path }
    mutating func interrupt(sensors: Set<Sensor> = Set(Sensor.allCases)) {
        pendingSensors.formUnion(sensors)
        activeStarts = activeStarts.filter { !sensors.contains($0.key.sensor) }
    }
    mutating func record(_ event: SensorEvent) {
        if pendingSensors.remove(event.sensor) != nil { breakBeforeEventIDs.insert(event.id) }
        let key = Attribution(sensor: event.sensor, bundleID: event.bundleID)
        if event.action == .start { activeStarts[key] = event.id }
        else { activeStarts.removeValue(forKey: key) }
    }
    mutating func save(to defaults: UserDefaults, folder: URL, retaining events: [SensorEvent]) {
        breakBeforeEventIDs.formIntersection(Set(events.map(\.id)))
        defaults.set(breakBeforeEventIDs.map(\.uuidString).sorted(), forKey: Self.key(folder))
    }
}

struct ActivitySession: Identifiable {
    let start: SensorEvent?
    var stop: SensorEvent?
    var isActive = false
    var id: UUID { start?.id ?? stop!.id }
    var latest: SensorEvent { stop ?? start! }
    var sensor: Sensor { latest.sensor }
    var bundleID: String { latest.bundleID }
    var appName: String { latest.appName.isEmpty ? latest.bundleID : latest.appName }
    var firstSeen: Bool { start?.observation == "first-observed" }
    var isComplete: Bool { start != nil && stop != nil }
    var duration: TimeInterval? {
        guard let start, let stop,
              let began = NotificationTime.date(start.timestamp),
              let ended = NotificationTime.date(stop.timestamp), ended >= began else { return nil }
        return ended.timeIntervalSince(began)
    }
    var durationLabel: String {
        if isActive { return "Active" }
        guard let duration else { return "Unknown" }
        return (firstSeen ? "≥ " : "") + Self.formatDuration(duration)
    }
    var stateLabel: String { isActive ? "Active" : (stop == nil ? "End unknown" : "Ended") }
    var help: String {
        var lines = ["\(appName) · \(bundleID)", sensor.title,
                     "\(firstSeen ? "First seen" : "Started"): \(start?.timestamp ?? "Not recorded")",
                     "Stopped: \(stop?.timestamp ?? (isActive ? "Still observed active" : "Not recorded"))"]
        if let duration {
            lines.append("\(firstSeen ? "Observed for at least" : "Duration"): \(Self.formatDuration(duration))")
        } else if !isActive { lines.append("Duration unavailable: a start or stop is missing, or its timestamp is invalid.") }
        if firstSeen { lines.append("Already active when first observed; the actual start was earlier or at this time.") }
        return lines.joined(separator: "\n")
    }
    func matches(_ filter: MenuHistoryFilter) -> Bool {
        filter.sensors.contains(sensor) && [start, stop].compactMap { $0 }.contains { filter.kinds.contains(MenuEventKind($0)) }
    }
    func matches(search: String, sensor: String, state: String, todayOnly: Bool, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard sensor == "all" || self.sensor.rawValue == sensor else { return false }
        guard state == "all" || (state == "active" && isActive) || (state == "ended" && stop != nil) || (state == "incomplete" && !isComplete && !isActive) else { return false }
        let endpoints = [start, stop].compactMap { $0 }
        if todayOnly && !endpoints.contains(where: {
            NotificationTime.date($0.timestamp).map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }) { return false }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return true }
        let fields = endpoints.flatMap { [$0.appName, $0.bundleID, $0.timestamp, $0.sensor.title, MenuEventKind($0).title] } + [stateLabel]
        if fields.joined(separator: " ").localizedCaseInsensitiveContains(query) { return true }
        return durationLabel.localizedCaseInsensitiveContains(query) || endpoints.contains {
            NotificationTime.display($0.timestamp).localizedCaseInsensitiveContains(query) ||
            NotificationTime.compactTimestamp($0.timestamp).localizedCaseInsensitiveContains(query)
        }
    }
    static func formatDuration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "Unknown" }
        if interval < 1 { return "<1s" }
        // Real source dates cannot approach Int.max; cap defensively for imported data.
        let total = Int(min(interval.rounded(.down), 315_576_000_000))
        let parts = [(total / 86400, "d"), ((total / 3600) % 24, "h"), ((total / 60) % 60, "m"), (total % 60, "s")]
        return parts.filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }
}

enum ActivityHistory {
    /// Pair in recorded order, before filtering or taking the five-row menu limit.
    /// Do not sort timestamps: clock changes and equal timestamps must retain the
    /// CSV's event order. A second START supersedes, never extends, a missing STOP.
    static func sessions(in newestFirst: [SensorEvent], continuity: ActivityContinuity = ActivityContinuity()) -> [ActivitySession] {
        var rows: [ActivitySession] = []
        var open: [Attribution: Int] = [:]
        var recency: [Int] = []
        for (ordinal, event) in newestFirst.reversed().enumerated() {
            if continuity.breakBeforeEventIDs.contains(event.id) {
                open = open.filter { $0.key.sensor != event.sensor }
            }
            let key = Attribution(sensor: event.sensor, bundleID: event.bundleID)
            if event.action == .start {
                open[key] = rows.count
                rows.append(ActivitySession(start: event, isActive: continuity.activeStartIDs.contains(event.id)))
                recency.append(ordinal)
            } else if let index = open.removeValue(forKey: key) {
                rows[index].stop = event
                rows[index].isActive = false
                recency[index] = ordinal
            } else {
                rows.append(ActivitySession(start: nil, stop: event))
                recency.append(ordinal)
            }
        }
        return rows.indices.sorted { recency[$0] > recency[$1] }.map { rows[$0] }
    }
}
