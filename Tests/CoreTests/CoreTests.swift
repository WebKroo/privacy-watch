// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation
#if !STANDALONE
import XCTest
@testable import PrivacyCore
#endif

final class CoreTests: XCTestCase {
    let stamp = "2026-09-18 19:24:55.484123-0400"
    func snapshot(_ tokens: [String]) -> Snapshot {
        LogParser.snapshot(message: LogParser.marker + String(decoding: try! JSONEncoder().encode(tokens), as: UTF8.self), timestamp: stamp)!
    }
    func testAllFourSensorsAndSetTransitions() {
        var differ = EventDiffer()
        let baseline = differ.consume(snapshot(["mic:com.apple.VoiceMemos", "cam:com.apple.FaceTime", "scr:pl.maketheweb.cleanshotx", "loc:com.apple.weather"]))
        XCTAssertEqual(baseline.count, 4)
        XCTAssertTrue(baseline.allSatisfy { $0.action == .start && $0.timestamp == stamp && $0.observation == "first-observed" })
        XCTAssertEqual(differ.consume(snapshot(["mic:com.apple.VoiceMemos", "mic:com.apple.VoiceMemos", "cam:com.apple.FaceTime", "scr:pl.maketheweb.cleanshotx", "loc:com.apple.weather"])), [])
        let delta = differ.consume(snapshot(["mic:com.example.Other", "loc:com.apple.weather"]))
        XCTAssertEqual(delta.filter { $0.action == .stop }.count, 3)
        XCTAssertEqual(delta.filter { $0.action == .start }.count, 1)
        XCTAssertTrue(delta.allSatisfy { $0.observation == "change" })
        XCTAssertEqual(differ.consume(snapshot([])).count, 2)
        XCTAssertEqual(differ.consume(snapshot([])), [])
    }
    func testRecentPrivateMalformedAndUnknown() {
        XCTAssertNil(LogParser.snapshot(message: "Recent activity attributions changed to []", timestamp: stamp))
        for value in ["<private>", "[\"mic:<private>\"]", "[\"mic:\"]", "[\"mic:app\"", "[\"mic:app\", \"broken\"]"] {
            XCTAssertNil(LogParser.snapshot(message: LogParser.marker + value, timestamp: stamp))
        }
        XCTAssertTrue(snapshot(["future:com.example.app"]).attributions.isEmpty)
    }
    func testNDJSONKeepsExactTimestampAndRejectsOtherSources() throws {
        var object = ["timestamp": stamp, "subsystem": "com.apple.controlcenter", "category": "sensor-indicators", "eventMessage": LogParser.marker + "[\"mic:com.apple.VoiceMemos\"]"]
        XCTAssertEqual(LogParser.jsonLine(try JSONSerialization.data(withJSONObject: object))?.timestamp, stamp)
        object["subsystem"] = "other"
        XCTAssertNil(LogParser.jsonLine(try JSONSerialization.data(withJSONObject: object)))
    }
    func testCSVQuotingAndFormulaProtection() {
        var event = SensorEvent(timestamp: stamp, sensor: .mic, action: .start, bundleID: "com.example.app", appName: "App, \"Name\"")
        XCTAssertEqual(CSV.event(CSV.rows(CSV.row(event))[0]), event)
        event.appName = " =HYPERLINK(\"bad\")"
        XCTAssertTrue(CSV.rows(CSV.row(event))[0][4].hasPrefix("'"))
    }
    func temporaryStore() throws -> LogStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return LogStore(folder: folder)
    }
    func testCSVAppendBackupAndReload() throws {
        let store = try temporaryStore(); try store.prepare(backup: true)
        let event = SensorEvent(timestamp: stamp, sensor: .cam, action: .start, bundleID: "com.apple.FaceTime", appName: "FaceTime")
        try store.append(event, backup: true)
        XCTAssertEqual(try store.recentEvents(), [event])
        let backup = try Data(contentsOf: store.textURL)
        XCTAssertEqual(try JSONDecoder().decode(SensorEvent.self, from: backup), event)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.csvURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testLegacyCSVIsPreserved() throws {
        let store = try temporaryStore(); let original = Data("Timestamp,Sensor,Action\nold history\n".utf8)
        try original.write(to: store.csvURL)
        XCTAssertThrowsError(try store.prepare(backup: false))
        XCTAssertEqual(try Data(contentsOf: store.csvURL), original)
    }
    func testSymlinksAndHardlinksRejected() throws {
        let store = try temporaryStore(); let target = store.folder.appendingPathComponent("old.csv")
        try Data("history".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: store.csvURL, withDestinationURL: target)
        XCTAssertThrowsError(try store.prepare(backup: false))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "history")
        try FileManager.default.removeItem(at: store.csvURL)
        try FileManager.default.linkItem(at: target, to: store.csvURL)
        XCTAssertThrowsError(try store.prepare(backup: false))
    }
    func testMenuHistoryFiltersBeforeLimitingAndSeparatesFirstSeen() {
        let events = (0..<14).map { index in
            SensorEvent(timestamp: stamp, sensor: index < 6 ? .cam : .mic,
                        action: index.isMultiple(of: 2) ? .start : .stop,
                        bundleID: "com.example.app\(index)", observation: index == 6 ? "first-observed" : "change")
        }
        var filter = MenuHistoryFilter()
        XCTAssertEqual(filter.recentEvents(in: events), Array(events.prefix(5)))
        filter.sensors = [.mic]
        XCTAssertEqual(filter.recentEvents(in: events), Array(events[6...10]))
        filter.kinds = [.started, .stopped]
        XCTAssertEqual(filter.recentEvents(in: events), Array(events[7...11]))
        filter.kinds = [.firstSeen]
        XCTAssertEqual(filter.recentEvents(in: events), [events[6]])
        filter.kinds = [.started]
        XCTAssertEqual(filter.recentEvents(in: events), [events[8], events[10], events[12]])
        filter.kinds = [.stopped]
        XCTAssertEqual(filter.recentEvents(in: events), [events[7], events[9], events[11], events[13]])
        filter.sensors = []
        XCTAssertEqual(filter.recentEvents(in: events), [])
        XCTAssertTrue(!filter.hasSelection)
        filter.sensors = [.mic]; filter.kinds = []
        XCTAssertEqual(filter.recentEvents(in: events), [])
    }
    func testMenuHistoryPreferencesPreserveEmptyChoicesAndRecordingSettings() {
        let suite = "privacy-watch.menu-history-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(MenuHistoryFilter(defaults: defaults), MenuHistoryFilter())
        defaults.set(["cam"], forKey: "sensors")
        defaults.set(true, forKey: "notifyMic")
        var filter = MenuHistoryFilter(); filter.sensors = [.mic, .scr]; filter.kinds = [.stopped]
        filter.save(to: defaults)
        XCTAssertEqual(MenuHistoryFilter(defaults: defaults), filter)
        filter.sensors = []; filter.kinds = []; filter.save(to: defaults)
        XCTAssertEqual(MenuHistoryFilter(defaults: defaults), filter)
        XCTAssertEqual(defaults.stringArray(forKey: "sensors"), ["cam"])
        XCTAssertTrue(defaults.bool(forKey: "notifyMic"))
    }
}
