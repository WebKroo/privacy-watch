// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation
import Dispatch

// Session intent is independent of whether the reader currently has a live
// connection. Sleep and transport recovery must never undo a user's Pause/Quit.
struct LoggingRecovery {
    private(set) var requested = false
    private(set) var sleeping = false
    private(set) var retryAttempt = 0

    var shouldReconnect: Bool { requested && !sleeping }

    mutating func userStarted() {
        requested = true
        retryAttempt = 0
    }

    mutating func userStopped() {
        requested = false
        retryAttempt = 0
    }

    mutating func willSleep() { sleeping = true }

    mutating func didWake() {
        sleeping = false
        retryAttempt = 0
    }

    mutating func connected() { retryAttempt = 0 }

    mutating func nextRetryDelay() -> TimeInterval? {
        guard shouldReconnect else { return nil }
        let delays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
        let delay = delays[min(retryAttempt, delays.count - 1)]
        // Cap the counter as well as the delay, even after a long outage.
        retryAttempt = min(retryAttempt + 1, delays.count)
        return delay
    }
}

// DispatchTime uses mach_absolute_time on macOS: elapsed time excludes system
// sleep and is unaffected by wall-clock changes. Injected readings make expiry
// boundaries testable without sleeping or changing the Mac's clock.
struct AwakeDeadline {
    private(set) var lastSeen: UInt64

    init(now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lastSeen = now
    }

    mutating func renew(now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lastSeen = now
    }

    func expired(after seconds: TimeInterval, now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        // A regressed injected/system reading must not wrap unsigned subtraction
        // into a huge elapsed duration and falsely expire the connection.
        guard now >= lastSeen else { return false }
        return TimeInterval(now - lastSeen) / 1_000_000_000 >= seconds
    }
}
