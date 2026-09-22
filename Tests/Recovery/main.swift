// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func check(_ condition: @autoclosure () -> Bool, _ message: String,
           file: StaticString = #filePath, line: UInt = #line) throws {
    if !condition() { throw CheckFailure(description: "\(file):\(line): \(message)") }
}

let tests: [(String, () throws -> Void)] = [
    ("sleep advances wall time without expiring an awake deadline", {
        let bedtime = Date(timeIntervalSince1970: 1_800_000_000)
        let wakeTime = bedtime.addingTimeInterval(8 * 60 * 60)
        let bedtimeUptime: UInt64 = 100_000_000_000
        let deadline = AwakeDeadline(now: bedtimeUptime)
        try check(wakeTime.timeIntervalSince(bedtime) > 12, "The fixture must exceed both lease limits")
        try check(!deadline.expired(after: 8, now: bedtimeUptime), "Sleeping must not expire the app heartbeat")
        try check(!deadline.expired(after: 12, now: bedtimeUptime), "Sleeping must not expire the helper lease")
        try check(!deadline.expired(after: 8, now: bedtimeUptime + 1_000_000_000), "One awake second after wake must retain the grace period")
    }),
    ("real awake loss expires at the boundary and renewal resets it", {
        let start: UInt64 = 42_000_000_000
        var deadline = AwakeDeadline(now: start)
        try check(!deadline.expired(after: 8, now: start + 7_999_999_999), "Must stay live before the deadline")
        try check(deadline.expired(after: 8, now: start + 8_000_000_000), "Must expire at the deadline")
        try check(deadline.expired(after: 8, now: start + 9_000_000_000), "Must expire after actual awake loss")
        deadline.renew(now: start + 9_000_000_000)
        try check(deadline.lastSeen == start + 9_000_000_000, "Renewal must replace the heartbeat reading")
        try check(!deadline.expired(after: 8, now: start + 10_000_000_000), "A fresh heartbeat must restore the full grace period")
        try check(deadline.expired(after: 12, now: start + 21_000_000_000), "Helper lease must also expire at its boundary")
    }),
    ("clock regressions and large uptime values cannot underflow", {
        let deadline = AwakeDeadline(now: 10_000)
        try check(!deadline.expired(after: 8, now: 9_999), "A regressed reading must not underflow")
        try check(!deadline.expired(after: 8, now: 10_000), "An unchanged reading has no elapsed time")
        let nearMaximum = AwakeDeadline(now: UInt64.max - 1)
        try check(!nearMaximum.expired(after: 8, now: UInt64.max), "Large absolute uptime must not become a large age")
        try check(nearMaximum.expired(after: 0.000000001, now: UInt64.max), "One nanosecond remains measurable near UInt64.max")
        try check(!nearMaximum.expired(after: 8, now: 0), "A wrapped/regressed reading must not falsely expire")
    }),
    ("retry delays back off and remain capped through a long outage", {
        var recovery = LoggingRecovery()
        try check(recovery.nextRetryDelay() == nil, "A fresh app has no reconnect intent")
        recovery.userStarted()
        let expected: [TimeInterval] = [1, 2, 4, 8, 15, 30, 30, 30]
        for delay in expected { try check(recovery.nextRetryDelay() == delay, "Unexpected retry delay; expected \(delay)") }
        for _ in 0..<10_000 { try check(recovery.nextRetryDelay() == 30, "Long outages must retain the capped delay") }
        try check(recovery.retryAttempt == 6, "The attempt counter must also stay bounded")
    }),
    ("Pause while asleep survives wake without restarting", {
        var recovery = LoggingRecovery()
        recovery.userStarted()
        _ = recovery.nextRetryDelay()
        recovery.willSleep()
        try check(recovery.requested && recovery.sleeping, "Sleep must preserve prior logging intent")
        try check(recovery.nextRetryDelay() == nil, "No reconnect may be scheduled while asleep")
        recovery.userStopped()
        try check(recovery.sleeping, "Pause must not pretend the Mac has woken")
        try check(!recovery.requested && recovery.retryAttempt == 0, "Pause must clear intent and retries")
        recovery.didWake()
        try check(!recovery.shouldReconnect && recovery.nextRetryDelay() == nil, "Wake must respect Pause")
    }),
    ("Quit vetoes a previously scheduled reconnect", {
        var recovery = LoggingRecovery()
        recovery.userStarted()
        let scheduledDelay = recovery.nextRetryDelay()
        try check(scheduledDelay == 1, "The fixture needs a pending reconnect")
        recovery.userStopped()
        // A delayed task must recheck this predicate after its delay; its earlier
        // scheduling permission is not permission to undo a later Quit.
        try check(!recovery.shouldReconnect, "A queued retry must be vetoed after Quit")
        try check(recovery.nextRetryDelay() == nil, "Quit must prevent subsequent retries too")
        recovery.connected()
        try check(!recovery.requested, "A late success callback must not recreate logging intent")
    }),
    ("repeated sleep and wake preserve intent but never create it", {
        var recovery = LoggingRecovery()
        recovery.willSleep(); recovery.willSleep(); recovery.didWake(); recovery.didWake()
        try check(!recovery.shouldReconnect, "Wake without a preceding Start must remain paused")
        recovery.userStarted()
        for _ in 0..<20 {
            _ = recovery.nextRetryDelay(); _ = recovery.nextRetryDelay()
            recovery.willSleep(); recovery.willSleep()
            try check(!recovery.shouldReconnect && recovery.requested, "Sleep must suspend, not erase, intent")
            recovery.didWake(); recovery.didWake()
            try check(recovery.shouldReconnect && recovery.retryAttempt == 0, "Wake must restore requested logging with fresh backoff")
            try check(recovery.nextRetryDelay() == 1, "Each wake should begin with the shortest retry")
        }
    }),
    ("connection success resets backoff without changing sleep or intent", {
        var recovery = LoggingRecovery()
        recovery.userStarted()
        _ = recovery.nextRetryDelay(); _ = recovery.nextRetryDelay(); _ = recovery.nextRetryDelay()
        recovery.connected()
        try check(recovery.requested && recovery.retryAttempt == 0, "Success must retain intent and reset retry history")
        try check(recovery.nextRetryDelay() == 1, "A later failure should start fresh")
        recovery.willSleep(); recovery.connected()
        try check(recovery.sleeping && !recovery.shouldReconnect, "A late success must not wake the recovery state")
        recovery.userStopped(); recovery.didWake(); recovery.connected()
        try check(!recovery.requested && !recovery.shouldReconnect, "A late success after Stop must leave logging stopped")
    })
]

var failures = 0
for (name, run) in tests {
    do { try run(); print("PASS \(name)") }
    catch { failures += 1; print("FAIL \(name): \(error)") }
}
print("\(tests.count) recovery tests, \(failures) failures")
exit(failures == 0 ? 0 : 1)
