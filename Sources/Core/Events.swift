// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation

enum Sensor: String, Codable, CaseIterable, Identifiable {
    case mic, cam, scr, loc
    var id: String { rawValue }
    var title: String {
        switch self { case .mic: return "Microphone"; case .cam: return "Camera"; case .scr: return "Screen Capture"; case .loc: return "Location" }
    }
    var symbol: String {
        switch self { case .mic: return "mic.fill"; case .cam: return "video.fill"; case .scr: return "rectangle.inset.filled"; case .loc: return "location.fill" }
    }
}
enum EventAction: String, Codable, CaseIterable { case start = "START", stop = "STOP" }
struct SensorEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    let timestamp: String // Source timestamp, including fractional seconds and UTC offset.
    let sensor: Sensor
    let action: EventAction
    let bundleID: String
    var appName: String = ""
    var observation: String = "change"
}
struct Attribution: Hashable {
    let sensor: Sensor
    let bundleID: String
}
struct Snapshot {
    let timestamp: String
    let attributions: Set<Attribution>
}
enum LogParser {
    static let marker = "Active activity attributions changed to "
    static let predicate = "process == \"ControlCenter\" AND subsystem == \"com.apple.controlcenter\" AND category == \"sensor-indicators\""
    // Reject partial/redacted arrays rather than treating them as the empty set.
    static func snapshot(message: String, timestamp: String) -> Snapshot? {
        guard message.hasPrefix(marker), !timestamp.isEmpty,
              let data = String(message.dropFirst(marker.count)).data(using: .utf8),
              let tokens = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        var result = Set<Attribution>()
        for token in tokens {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[1].isEmpty, parts[1].utf8.count <= 1024,
                  !parts[1].contains("<private>"),
                  !parts[1].unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            // Unknown future tokens are ignored; a redacted/malformed known token invalidates the whole snapshot.
            if let sensor = Sensor(rawValue: parts[0]) { result.insert(Attribution(sensor: sensor, bundleID: parts[1])) }
        }
        return Snapshot(timestamp: timestamp, attributions: result)
    }
    static func jsonLine(_ data: Data) -> Snapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["subsystem"] as? String == "com.apple.controlcenter",
              object["category"] as? String == "sensor-indicators",
              let message = object["eventMessage"] as? String,
              let stamp = object["timestamp"] as? String else { return nil }
        return snapshot(message: message, timestamp: stamp)
    }
}
struct EventDiffer {
    private(set) var active = Set<Attribution>()
    private var initialized = false
    mutating func consume(_ snapshot: Snapshot) -> [SensorEvent] {
        let baseline = !initialized
        var events: [SensorEvent] = []
        for (set, action) in [(active.subtracting(snapshot.attributions), EventAction.stop), (snapshot.attributions.subtracting(active), .start)] {
            for item in set.sorted(by: { ($0.sensor.rawValue, $0.bundleID) < ($1.sensor.rawValue, $1.bundleID) }) {
                events.append(SensorEvent(timestamp: snapshot.timestamp, sensor: item.sensor, action: action, bundleID: item.bundleID, observation: baseline ? "first-observed" : "change"))
            }
        }
        active = snapshot.attributions
        initialized = true
        return events
    }
}
enum CSV {
    static let columns = ["Event ID", "Timestamp", "Sensor", "Action", "App", "Bundle ID", "Observation"]
    static let header = columns.joined(separator: ",") + "\r\n"
    static func cell(_ value: String) -> String {
        // Prevent spreadsheet formula evaluation of app-supplied names/identifiers.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = ["=", "+", "-", "@"].contains(String(trimmed.prefix(1))) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static func row(_ event: SensorEvent) -> String {
        [event.id.uuidString, event.timestamp, event.sensor.title, event.action.rawValue, event.appName, event.bundleID, event.observation].map(cell).joined(separator: ",") + "\r\n"
    }
    static func rows(_ text: String) -> [[String]] {
        let chars = Array(text); var i = 0; var quoted = false; var field = ""; var row: [String] = []; var rows: [[String]] = []
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 } else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r\n" || c == "\r") && !quoted {
                row.append(field); rows.append(row); row = []; field = ""
                if c == "\r" && i + 1 < chars.count && chars[i+1] == "\n" { i += 1 }
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
    static func event(_ row: [String]) -> SensorEvent? {
        guard row.count == 7, let id = UUID(uuidString: row[0]), let sensor = Sensor.allCases.first(where: { $0.title == row[2] }), let action = EventAction(rawValue: row[3]) else { return nil }
        return SensorEvent(id: id, timestamp: row[1], sensor: sensor, action: action, bundleID: row[5], appName: row[4], observation: row[6])
    }
}
