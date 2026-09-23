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

extension CoreTests {
    private func activityEvent(_ timestamp: String, _ action: EventAction, sensor: Sensor = .mic, app: String = "com.example.call", firstSeen: Bool = false) -> SensorEvent {
        SensorEvent(timestamp: timestamp, sensor: sensor, action: action, bundleID: app, appName: "Example", observation: firstSeen ? "first-observed" : "change")
    }
    func testActivitySessionsPairByAppAndSensorBeforeFilters() {
        let start = activityEvent("2026-09-22 21:32:24.000000-0400", .start)
        let camera = activityEvent("2026-09-22 21:32:25.000000-0400", .start, sensor: .cam)
        let other = activityEvent("2026-09-22 21:32:26.000000-0400", .start, app: "com.example.other")
        let stop = activityEvent("2026-09-22 21:33:46.000000-0400", .stop)
        let events = [stop, other, camera, start]
        var continuity = ActivityContinuity()
        events.reversed().forEach { continuity.record($0) }
        let rows = ActivityHistory.sessions(in: events, continuity: continuity)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].id, start.id)
        XCTAssertEqual(rows[0].stop?.id, stop.id)
        XCTAssertEqual(rows[0].durationLabel, "1m 22s")
        XCTAssertTrue(rows[1].isActive && rows[2].isActive)
        var filter = MenuHistoryFilter(); filter.sensors = [.mic]; filter.kinds = [.stopped]
        let matching = rows.filter { $0.matches(filter) }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching[0].start?.id, start.id)
        XCTAssertEqual(matching[0].durationLabel, "1m 22s")
        XCTAssertEqual(events, [stop, other, camera, start])
    }
    func testActivitySessionsPreserveRapidTransitionsAndMissingEndpoints() {
        let start = activityEvent(stamp, .start)
        let stop = activityEvent(stamp, .stop)
        let next = activityEvent(stamp, .start)
        let superseded = activityEvent(stamp, .start)
        let duplicateStop = activityEvent(stamp, .stop)
        let rows = ActivityHistory.sessions(in: [next, duplicateStop, stop, start, superseded])
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].id, next.id)
        XCTAssertEqual(rows[0].stateLabel, "End unknown")
        XCTAssertNil(rows[1].start)
        XCTAssertEqual(rows[1].durationLabel, "Unknown")
        XCTAssertEqual(rows[2].id, start.id)
        XCTAssertEqual(rows[2].durationLabel, "<1s")
        XCTAssertEqual(rows[3].id, superseded.id)
        XCTAssertNil(rows[3].stop)
        let truncated = ActivityHistory.sessions(in: [stop])
        XCTAssertEqual(truncated[0].durationLabel, "Unknown")
    }
    func testActivityDurationFirstSeenOffsetsAndInvalidTimes() {
        let start = activityEvent("2026-09-22 23:59:30.000000-0400", .start, firstSeen: true)
        let stop = activityEvent("2026-09-23 04:00:45.000000+0000", .stop)
        let row = ActivityHistory.sessions(in: [stop, start])[0]
        XCTAssertEqual(row.durationLabel, "≥ 1m 15s")
        let invalid = activityEvent("not-a-time", .start)
        XCTAssertEqual(ActivityHistory.sessions(in: [stop, invalid])[0].durationLabel, "Unknown")
        let backwards = activityEvent("2026-09-22 23:59:29.000000-0400", .stop)
        XCTAssertEqual(ActivityHistory.sessions(in: [backwards, start])[0].durationLabel, "Unknown")
        XCTAssertEqual(ActivitySession.formatDuration(90_061), "1d 1h 1m 1s")
        XCTAssertEqual(ActivitySession.formatDuration(0.009), "<1s")
        XCTAssertEqual(ActivitySession.formatDuration(.infinity), "Unknown")
    }
    func testActivityContinuityPreventsPairingAcrossGapsAndPersists() {
        let suite = "privacy-watch.activity-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let folder = URL(fileURLWithPath: "/tmp/activity-tests")
        let start = activityEvent("2026-09-22 21:30:00-0400", .start)
        let camStart = activityEvent("2026-09-22 21:30:00-0400", .start, sensor: .cam)
        let stop = activityEvent("2026-09-22 21:31:00-0400", .stop)
        let camStop = activityEvent("2026-09-22 21:31:00-0400", .stop, sensor: .cam)
        let events = [camStop, stop, camStart, start]
        var continuity = ActivityContinuity()
        continuity.record(start); continuity.record(camStart)
        continuity.interrupt(sensors: [.mic])
        XCTAssertEqual(continuity.activeStartIDs, [camStart.id])
        continuity.record(stop); continuity.record(camStop)
        var rows = ActivityHistory.sessions(in: events, continuity: continuity)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].durationLabel, "1m")
        XCTAssertNil(rows[1].start)
        XCTAssertNil(rows[2].stop)
        continuity.save(to: defaults, folder: folder, retaining: events)
        let restored = ActivityContinuity(defaults: defaults, folder: folder)
        XCTAssertEqual(restored.breakBeforeEventIDs, continuity.breakBeforeEventIDs)
        XCTAssertTrue(restored.activeStartIDs.isEmpty)
        rows = ActivityHistory.sessions(in: events, continuity: restored)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1].durationLabel, "Unknown")
        XCTAssertTrue(ActivityContinuity(defaults: defaults, folder: URL(fileURLWithPath: "/tmp/another-folder")).breakBeforeEventIDs.isEmpty)
        var restart = restored
        let nextStop = activityEvent("2026-09-22 21:32:00-0400", .stop)
        restart.record(nextStop)
        XCTAssertTrue(restart.breakBeforeEventIDs.contains(nextStop.id))
        restart.save(to: defaults, folder: folder, retaining: [nextStop])
        XCTAssertEqual(restart.breakBeforeEventIDs, [nextStop.id])
    }
    func testActivitySessionsKeepFiveCompleteMatchesAndSearchEndpoints() {
        var chronological: [SensorEvent] = []
        for minute in 10...17 {
            chronological.append(activityEvent("2026-09-22 21:\(minute):00-0400", .start))
            chronological.append(activityEvent("2026-09-22 21:\(minute):30-0400", .stop))
        }
        let sessions = ActivityHistory.sessions(in: Array(chronological.reversed()))
        var filter = MenuHistoryFilter(); filter.kinds = [.stopped]
        let recent = Array(sessions.filter { $0.matches(filter) }.prefix(MenuHistoryFilter.limit))
        XCTAssertEqual(recent.count, 5)
        XCTAssertTrue(recent.allSatisfy { $0.durationLabel == "30s" })
        XCTAssertEqual(recent[0].start?.id, chronological[14].id)
        XCTAssertTrue(recent[0].matches(search: "21:17:00", sensor: "mic", state: "ended", todayOnly: false))
        XCTAssertTrue(recent[0].matches(search: NotificationTime.menuClock(recent[0].start!.timestamp), sensor: "mic", state: "ended", todayOnly: false))
        XCTAssertTrue(recent[0].matches(search: "30s", sensor: "mic", state: "ended", todayOnly: false))
        XCTAssertTrue(!recent[0].matches(search: "", sensor: "cam", state: "all", todayOnly: false))
        XCTAssertTrue(!recent[0].matches(search: "", sensor: "all", state: "active", todayOnly: false))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertTrue(recent[0].matches(search: "", sensor: "all", state: "all", todayOnly: true,
                                      now: NotificationTime.date("2026-09-23 01:18:00+0000")!, calendar: calendar))
        filter.kinds = []
        XCTAssertTrue(sessions.filter { $0.matches(filter) }.isEmpty)
    }
    func testActivityDisplayPreferencesAreIndependent() {
        let suite = "privacy-watch.activity-display-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ActivityDisplay(defaults: defaults), ActivityDisplay())
        defaults.set(["mic"], forKey: "sensors")
        var display = ActivityDisplay(); display.style = .combined; display.compact = true; display.save(to: defaults)
        XCTAssertEqual(ActivityDisplay(defaults: defaults), display)
        XCTAssertEqual(defaults.stringArray(forKey: "sensors"), ["mic"])
        defaults.set("future-mode", forKey: "activity.rowStyle")
        XCTAssertEqual(ActivityDisplay(defaults: defaults).style, .events)
    }
}
