// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation

@MainActor private final class PendingFetch {
    var replies: [CheckedContinuation<PublishedRelease?, Error>] = []
    func fetch() async throws -> PublishedRelease? {
        try await withCheckedThrowingContinuation { replies.append($0) }
    }
}

@main struct UpdateTests {
    @MainActor static func main() async throws {
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        func settings() -> UserDefaults {
            let name = "privacy-watch.update-tests.\(UUID())"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            suites.append(name)
            return defaults
        }
        func waitFor(_ condition: () -> Bool) async {
            for _ in 0..<1_000 {
                if condition() { return }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            fatalError("Async check did not finish")
        }
        var suites: [String] = []
        defer { for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) } }
        let version = ReleaseVersion("1.5.0")!
        expect(ReleaseVersion("v1.5.0") == version, "v prefix")
        expect(ReleaseVersion("1.10.0")! > ReleaseVersion("1.9.9")!, "Numeric comparison")
        expect(ReleaseVersion("2.0.0")! > version, "Major comparison")
        for invalid in ["", "1.5", "1.5.0-beta", "01.5.0", "1.-5.0", "1.5.0/../other", "1.5.0?x=y", "١.5.0"] {
            expect(ReleaseVersion(invalid) == nil, "Reject nonstable or unsafe tag: \(invalid)")
        }
        print("PASS version ordering and safe stable tags")

        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 9))!
        expect(UpdateFrequency.monthly.nextDate(after: january, calendar: calendar) == february, "Calendar month boundary")
        expect(UpdateFrequency.weekly.nextDate(after: january, calendar: calendar) == january.addingTimeInterval(7 * 86_400), "Week")
        expect(UpdateFrequency.daily.isDue(lastAttempt: january, now: january.addingTimeInterval(86_400), calendar: calendar), "Due boundary")
        expect(!UpdateFrequency.daily.isDue(lastAttempt: january, now: january.addingTimeInterval(86_399), calendar: calendar), "Not early")
        expect(UpdateFrequency.daily.isDue(lastAttempt: nil, now: january), "First enabled check")
        expect(UpdateFrequency.daily.isDue(lastAttempt: february, now: january), "Clock moved backwards")
        print("PASS daily, weekly, monthly, missed-check and clock schedules")

        func fixture(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
            try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": prerelease])
        }
        let decoded = try GitHubReleaseClient.decode(fixture("v2.0.0"), status: 200)!
        expect(decoded.pageURL.absoluteString == "https://github.com/WebKroo/privacy-watch/releases/tag/v2.0.0", "Pinned repository URL")
        let draft = try GitHubReleaseClient.decode(fixture("v2.0.0", draft: true), status: 200)
        let prerelease = try GitHubReleaseClient.decode(fixture("v2.0.0-beta", prerelease: true), status: 200)
        let missing = try GitHubReleaseClient.decode(Data(), status: 404)
        expect(draft == nil && prerelease == nil && missing == nil, "Ignore drafts/prereleases and handle no release")
        for (data, status) in [(Data(), 200), (fixture("../other"), 200), (Data(), 403), (Data(), 429), (Data(), 500), (Data(repeating: 0, count: GitHubReleaseClient.maximumBytes + 1), 200)] {
            do { _ = try GitHubReleaseClient.decode(data, status: status); fatalError("Bad response accepted") }
            catch is ReleaseCheckError {} // Expected typed, human-readable error.
        }
        print("PASS release decoding, invalid data, rate limits and response bounds")

        var calls = 0
        let defaults = settings()
        let controller = UpdateController(defaults: defaults, installedVersion: "1.5.0", timersEnabled: false,
                                          now: { january }, calendar: calendar, fetch: { calls += 1; return PublishedRelease(tag: "v1.10.0") })
        controller.start(); controller.checkIfDue()
        expect(!controller.automaticChecks && controller.frequency == .weekly && calls == 0, "Offline default")
        controller.check(); controller.check()
        await waitFor { !controller.isChecking }
        expect(calls == 1 && controller.availableRelease?.version == ReleaseVersion("1.10.0"), "Manual check while off; no duplicate request")
        expect(controller.lastChecked == january && controller.nextCheck == nil, "Manual success date; no automatic timer")
        let restored = UpdateController(defaults: defaults, installedVersion: "1.5.0", timersEnabled: false)
        expect(restored.availableRelease == controller.availableRelease, "Known update survives restart")
        let upgraded = UpdateController(defaults: defaults, installedVersion: "1.10.0", timersEnabled: false)
        expect(upgraded.availableRelease == nil, "Installed update clears banner")
        controller.shutDown(); restored.shutDown(); upgraded.shutDown()
        print("PASS manual checks, concurrent-click suppression and persisted update state")

        var time = january
        var automaticCalls = 0
        let autoDefaults = settings(); autoDefaults.set(true, forKey: "updates.enabled")
        autoDefaults.set("daily", forKey: "updates.frequency")
        let automatic = UpdateController(defaults: autoDefaults, installedVersion: "1.5.0", timersEnabled: false,
                                         now: { time }, calendar: calendar, fetch: { automaticCalls += 1; return PublishedRelease(tag: "v1.5.0") })
        automatic.start(); await waitFor { !automatic.isChecking }
        automatic.checkIfDue(); expect(automaticCalls == 1, "No repeated check within interval")
        expect(automatic.availableRelease == nil && automatic.message == "You're up to date.", "Equal version")
        time = january.addingTimeInterval(2 * 86_400)
        automatic.checkIfDue(); await waitFor { !automatic.isChecking }
        expect(automaticCalls == 2, "Check after missed day/wake")
        automatic.frequency = .monthly
        expect(automatic.nextCheck == UpdateFrequency.monthly.nextDate(after: time, calendar: calendar), "Reschedule changed frequency")
        automatic.automaticChecks = false; time = time.addingTimeInterval(90 * 86_400); automatic.checkIfDue()
        expect(automatic.nextCheck == nil && automaticCalls == 2, "Off cancels scheduling")
        expect(autoDefaults.string(forKey: "updates.frequency") == "monthly" && !autoDefaults.bool(forKey: "updates.enabled"), "Settings persist")
        automatic.shutDown()
        print("PASS automatic scheduling, wake catch-up, changed frequency and opt-out")

        let offlineDefaults = settings(); offlineDefaults.set(true, forKey: "updates.enabled")
        var offlineCalls = 0
        let offline = UpdateController(defaults: offlineDefaults, installedVersion: "1.5.0", timersEnabled: false,
                                       now: { january }, fetch: { offlineCalls += 1; throw URLError(.notConnectedToInternet) })
        offline.start(); await waitFor { !offline.isChecking }
        offline.checkIfDue()
        expect(offline.checkFailed && offline.lastChecked == nil && offlineCalls == 1, "Failure is not successful check; no retry loop")
        offline.check(); await waitFor { !offline.isChecking }
        expect(offlineCalls == 2, "Manual retry after network failure")
        offline.shutDown()
        print("PASS offline failures and manual retry without automatic request storms")

        let pending = PendingFetch()
        let cancelDefaults = settings(); cancelDefaults.set(true, forKey: "updates.enabled")
        let cancel = UpdateController(defaults: cancelDefaults, installedVersion: "1.5.0", timersEnabled: false,
                                      fetch: { try await pending.fetch() })
        cancel.start(); await waitFor { pending.replies.count == 1 }
        cancel.automaticChecks = false
        expect(!cancel.isChecking && cancel.nextCheck == nil, "Turning off cancels automatic request")
        cancel.check(); await waitFor { pending.replies.count == 2 }
        pending.replies[0].resume(returning: PublishedRelease(tag: "v9.0.0"))
        await Task.yield()
        expect(cancel.isChecking && cancel.availableRelease == nil, "Retired response cannot replace manual request")
        pending.replies[1].resume(returning: PublishedRelease(tag: "v2.0.0"))
        await waitFor { !cancel.isChecking }
        expect(cancel.availableRelease?.tag == "v2.0.0", "Manual result after cancellation")
        cancel.shutDown()
        print("PASS cancellation and stale-response race")

        var previewCalls = 0
        let previewDefaults = settings(); previewDefaults.set(true, forKey: "updates.enabled")
        let preview = UpdateController(defaults: previewDefaults, installedVersion: "1.5.0", allowsChecks: false,
                                       fetch: { previewCalls += 1; return nil })
        preview.start(); preview.check(); preview.checkIfDue()
        expect(previewCalls == 0 && !preview.isChecking && preview.nextCheck == nil, "Preview stays offline")
        preview.shutDown()
        print("PASS preview isolation")

        if CommandLine.arguments.contains("--live") {
            let release = try await GitHubReleaseClient().latest()
            print("PASS live GitHub request: \(release?.tag ?? "no release")")
        }
        print("All 8 update-check groups passed.")
    }
}
