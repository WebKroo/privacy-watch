// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation
// Run the same assertions on a Mac with Command Line Tools but no XCTest installation.
var failures = 0
class XCTestCase {
    var teardown: [() throws -> Void] = []
    func addTeardownBlock(_ block: @escaping () throws -> Void) { teardown.append(block) }
}
func record(_ valid: Bool, _ message: String, file: StaticString, line: UInt) {
    if !valid { failures += 1; print("FAIL \(file):\(line): \(message)") }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { record(try value(), "Expected true", file: file, line: line) } catch { record(false, "Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    do { record(try value() == nil, "Expected nil", file: file, line: line) } catch { record(false, "Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertEqual<T: Equatable>(_ first: @autoclosure () throws -> T, _ second: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { record(try first() == second(), "Values differ", file: file, line: line) } catch { record(false, "Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ block: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try block(); record(false, "Expected error", file: file, line: line) } catch {}
}
func testNotificationClock() {
    let old = NSTimeZone.default
    NSTimeZone.default = TimeZone(identifier: "America/Toronto")!
    defer { NSTimeZone.default = old }
    XCTAssertEqual(NotificationTime.display("2026-09-18 21:46:08"), "2026-09-18 9:46:08 PM")
    XCTAssertEqual(NotificationTime.display("2026-09-18 00:00:00"), "2026-09-18 12:00:00 AM")
    XCTAssertEqual(NotificationTime.display("2026-09-18 12:00:00"), "2026-09-18 12:00:00 PM")
    XCTAssertEqual(NotificationTime.display("2026-09-19 01:46:08.123456+0000"), "2026-09-18 9:46:08 PM")
    XCTAssertEqual(NotificationTime.display("unknown"), "unknown")
    XCTAssertEqual(NotificationTime.menuClock("2026-09-19 01:46:08.123456+0000"), "9:46:08 PM")
    XCTAssertEqual(NotificationTime.menuClock("2026-09-18 00:00:00"), "12:00:00 AM")
    XCTAssertEqual(NotificationTime.menuClock("unknown"), "unknown")
}
let suite = CoreTests()
let tests: [(String, () throws -> Void)] = [
    ("four sensors, duplicate tokens, START/STOP diff", suite.testAllFourSensorsAndSetTransitions),
    ("recent, redacted, malformed and future tokens", suite.testRecentPrivateMalformedAndUnknown),
    ("NDJSON source validation and exact timestamp", suite.testNDJSONKeepsExactTimestampAndRejectsOtherSources),
    ("CSV escaping and formula protection", suite.testCSVQuotingAndFormulaProtection),
    ("CSV/backup persistence, reload, permissions", suite.testCSVAppendBackupAndReload),
    ("legacy history preservation", suite.testLegacyCSVIsPreserved),
    ("symbolic and hard link rejection", suite.testSymlinksAndHardlinksRejected),
    ("12-hour AM/PM, midnight, noon and source timezone", testNotificationClock),
    ("menu history filters before five-item limit; first seen and empty selections", suite.testMenuHistoryFiltersBeforeLimitingAndSeparatesFirstSeen),
    ("menu history preferences persist separately from recording", suite.testMenuHistoryPreferencesPreserveEmptyChoicesAndRecordingSettings)
]
for (name, run) in tests {
    let before = failures
    do { try run() } catch { failures += 1; print("FAIL \(name): \(error)") }
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
for block in suite.teardown { try? block() }
print("\(tests.count) tests, \(failures) failures")
exit(failures == 0 ? 0 : 1)
