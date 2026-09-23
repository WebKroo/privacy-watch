# Validation — Privacy Watch 1.7.0

This release adds combined activity with durations and an independent compact-row preference. The CSV schema, protected collector and notification content remain the same. The normal-user model tracks observation boundaries for display; timestamp parsing/formatting now reuses a bounded per-thread cache that resets when the local time zone changes.

## Completed checks

- Universal arm64 + x86_64 compilation passed, with strict nested app/helper signature verification.
- Installer verification accepted the expected universal helper and rejected a different code hash.

- Sixteen core test groups passed. Added coverage includes application/sensor pairing, filtering before the five-row limit, search across both raw and displayed timestamps, same-timestamp transitions, duplicate starts/stops, first-seen lower bounds, missing endpoints, backwards/invalid timestamps, time-zone offsets, midnight, saved boundaries and independent display preferences. Existing parsing, CSV safety/storage, AM/PM and menu-filter checks passed, including a time-zone change after the formatter cache was warm.
- Eleven actual-AppModel anonymous-XPC integration checks passed. The new checks observed a live start, paused through sleep, resumed with an unmatched stop, verified persisted boundaries and the original CSV events, and toggled sensor recording between endpoints. Existing wake/cleanup races, stale callbacks, reconnects and final shutdown checks also passed.
- The integration harness uses a fake collector, temporary history and test-process preferences; it never connects to the installed protected reader. A sandboxed attempt could not exchange XPC replies. The run outside that command sandbox passed all eleven checks.
- Nine update-check groups and eight recovery-policy groups passed.
- Native sample-data previews verified separate and combined layouts, compact rows, date/AM-PM display, active/completed/unknown activity, first-seen minimum duration, complete pairs during search, the Ended filter, resetting the event/status filter when changing layouts, and saved display preferences after preview restart. The compact recent-history panel and its footer fit in the 340-point width.
- A local unoptimized probe paired 2,000 distinct-timestamp events into 1,000 activities in about 3 ms and searched those activities with no matches in about 125 ms. These are local spot measurements, not a cross-device performance guarantee.
- Local documentation links and whitespace checks passed.

## Limits

No live sensor, overnight, reboot, Intel runtime or second-Mac installation test was performed for this revision. The installed production app was not replaced or stopped. Pre-1.7 history and copied CSVs without local boundary preferences cannot establish continuity through old unrecorded gaps; incomplete recent history remains Unknown. The app is still locally signed and unnotarized, with one protected-reader approval needed for the new build.

# Historical validation — Privacy Watch 1.6.1

This release adds a native right-click/Control-click menu to the status icon. The collector, event parsing, storage, notifications, update checks and recovery logic are unchanged.

## Completed checks

- Universal arm64 + x86_64 build passed with strict nested signature verification.
- Installer signature checks accepted the staged universal helper and rejected a different approved hash.
- An isolated AppKit preview with sample data exercised the secondary-click branch and displayed See activity, Settings…, Hide icon and Quit Privacy Watch.
- The same native menu's Settings command opened the Settings tab; See activity returned to Activity. Hide icon changed the saved visibility preference to off, and the preview's Settings switch restored it. These actions did not change the recording preferences.
- Source review confirmed that normal clicks retain the existing recent-history panel, Control-click selects the context menu, and Quit uses AppModel's existing termination path with busy-state validation.
- The user's installed app and protected reader were not replaced or stopped for these checks. The earlier regression-suite results are retained below; those unchanged suites were not rerun for this menu-only change.

## Limits

Native menu actions were exercised in an isolated preview using a test anchor. The installed production status icon, live collector shutdown, Intel execution, overnight behavior and second-Mac installation were not retested. The free release remains locally signed and unnotarized; its updated app identity needs reader approval on installation.

# Historical validation — Privacy Watch 1.6.0

Built on Apple Silicon/macOS 27 using Swift 6.4 Command Line Tools. This release adds configurable menu history and clearer update result icons. The protected collector, event parser, CSV schema, notification content and recovery policy are unchanged.

## Completed checks

- Universal arm64 + x86_64 compilation passed with strict nested signature verification.
- Installer checks accepted the staged universal helper and rejected a different approved hash.
- Local documentation links and whitespace checks passed.
- Ten core groups passed, including sensor/event filters applied before the five-row limit, separate First seen classification, empty selections, saved preferences independent of recording settings, and AM/PM timestamp formatting.
- Nine update-check groups passed. Successful, available, absent-release, offline, pending and canceled results are distinct; no failed or canceled request can display the up-to-date state. Existing schedules, persistence and stale-response tests also passed.
- Eight recovery-policy groups and nine actual-AppModel anonymous-XPC integration checks passed. The integration harness uses a fake collector and temporary files, never the installed protected reader.
- The menu views were visually inspected in light and dark appearances with sample history. Five rows displayed app names, sensors, event labels, date and AM/PM time; the compact control, All activity link and Settings gear fit without clipping.
- In the native preview, the gear opened Settings directly. Excluding Camera from menu history backfilled the five rows from older matching events, including First seen; the full activity viewer still showed all seven samples. All activity returned to the Activity tab after Settings.
- Offline UI fixtures displayed the green success checkmark, teal update arrow and orange failure warning without making network requests.

## Limits

No new live sensor, overnight sleep, reboot, Intel execution or second-Mac installation test is claimed for these presentation changes. Existing macOS log-source and local-signing limitations still apply. This build remains unnotarized, and its changed app identity needs administrator approval when installed.

# Historical validation — Privacy Watch 1.5.0

Built on Apple Silicon/macOS 27 using Swift 6.4 Command Line Tools. This release adds optional update checks in the normal user-session app. Collector behavior, event parsing, CSV schema, notifications and logging recovery are unchanged.

## Completed checks

- Universal arm64 + x86_64 build passed, with strict nested signature verification.
- Eight update-check groups passed: numeric version ordering and safe tags; daily/weekly/calendar-month and clock schedules; release decoding/draft/prerelease/rate-limit/size handling; manual checks while off, duplicate suppression and persisted state; wake catch-up, frequency changes and opt-out; offline failure and manual retry; automatic cancellation with stale-response isolation; preview isolation.
- The real HTTPS release client successfully contacted the public GitHub endpoint and read the current v1.4.1 release. This test sent no credentials, sensor events, history or paths.
- Eight existing core groups and eight recovery-policy groups passed.
- Nine actual-AppModel anonymous-XPC integration checks passed. Tests do not use the installed protected reader.
- Installer checks accepted the correct staged universal helper and rejected a different code hash.
- The Updates section was inspected in the native preview: automatic checks off, Weekly selected, installed version 1.5.0, manual-check control and explanation. Preview mode remained offline.

- Release archives passed integrity checks. The APFS DMG mounted read-only; its app and a copy extracted from it passed strict nested signature checks and matched the built app's files and executable permissions. The Applications shortcut resolved correctly.
- The DMG uses APFS (compatible with the macOS 14 deployment target). An unpublished HFS+ packaging attempt added empty Finder metadata to an embedded SVG and failed verification; that image is not distributed.

## Limits

Calendar intervals and wake catch-up were tested with controlled clocks, not by leaving the app open for a day, week or month. No new overnight sleep, reboot, Intel execution or second-Mac installation test is claimed. The existing macOS log-source and local-signing limitations still apply. This build remains unnotarized, and its changed app identity needs administrator approval when installed.

# Historical validation — Privacy Watch 1.4.1

Built on Apple Silicon/macOS 27 with Swift 6.4 Command Line Tools. This release corrects sleep/wake and temporary reader-connection recovery. Sensor parsing, CSV schema, notification content, bundle identity and user preferences are retained.

## Diagnosis and fix

The previous app used Date-based heartbeat deadlines: eight seconds in the app and twelve in the helper. System sleep advanced those deadlines while neither side could renew them. The failure handler then permanently paused logging. The running app was still present after the reported overnight interval; the helper had a much more recent start. This is consistent with the source defect, although the previous version did not record sufficient lifecycle diagnostics to reconstruct the precise failure ordering.

The replacement uses awake-time deadlines, separate user intent, explicit sleep/wake handling, one cancellable retry with capped backoff, and generation-guarded callbacks. The reader is retired for sleep and a fresh observation begins after wake. Shutdown polling accounts for delayed helper exit. An intentional Pause/Quit and a storage or approval failure cancel recovery. No sensor activity is fabricated for gaps.

## Automated checks

- Universal arm64 + x86_64 app and helper build passed; strict nested signature verification passed.
- Eight existing core test groups passed: sensor attribution differences, malformed/redacted inputs, source validation, exact timestamps, CSV safety, persistence, link rejection, and AM/PM formatting.
- Eight recovery-policy/clock groups passed: sleep versus awake expiry, boundary and clock-regression cases, capped retries, Pause/Quit intent, repeated sleep/wake and connection reset.
- Nine integration checks compiled the actual AppModel and connected it to an anonymous native XPC fake collector. Passed actual connection, a helper exit delayed beyond three seconds, wake during asynchronous stop cleanup, rejection of stale event/snapshot/failure callbacks, Pause during sleep, stream-failure reconnection, cancellation of a pending retry, XPC invalidation recovery, and final confirmed shutdown.
- The integration harness substitutes the installer, notifications, application identity and view, uses a temporary log folder and memory-only defaults, and never runs the protected log reader. It required execution outside the command sandbox for anonymous XPC replies. No installed helper, notification permissions, login settings or production preferences were modified by these tests.
- Installer verification accepted the correct staged universal helper and rejected a different code hash.
- A separate source review checked lifecycle races and the existing authentication/console-user checks. It identified the idle-helper shutdown race, fixed by polling for up to eighteen awake seconds before reporting failure.

## Runtime and practical limits

- The previous installed app was quit normally and its service confirmed not running before update.
- The administrator-approved updater installed 1.4.1 build 7 in `/Applications/Privacy Watch.app`. Strict signature verification passed. The app resumed Logging automatically and fresh verified events were saved to the existing CSV after closing the window. The installed helper remained running; preferences and history were preserved.
- Reading lifecycle messages with the unprivileged `log show` command was denied by this Mac. The runtime check used the native status, launchd process status and fresh CSV timestamps instead. An administrator may need `sudo` to inspect unified-log diagnostics on a standard account.
- An actual overnight lid-close interval, reboot, Intel execution, second-Mac installation, sleep/wake under every macOS power mode, and multi-user switching were not tested for this release. The integration tests exercise the real model's asynchronous lifecycle, but do not put the Mac to sleep.
- Another user actively owning the single collector can still prevent reconnection; this release is not a multi-user architecture redesign.
- Logging resumes with the next valid ControlCenter snapshot. A first-observed entry is an observation boundary, not proof of the physical start time. Sleep/disconnection gaps are not reconstructed.
- The ControlCenter source remains undocumented and must be checked after macOS updates. A changed local signature can require folder access to be renewed; no permissions are bypassed.

Source and distribution packages contain no user event history. Earlier interface checks are summarized in the changelog; this record covers 1.4.1.

## GitHub project preparation

The app implementation, test behavior and icon are unchanged from the validated 1.4.1 implementation. SPDX/copyright notices have been added to source and test files. Documentation has been reorganized, and the build script now includes linked help documents in future app bundles. Shell syntax and local documentation links were checked. The supplied 1.4.1 binary remains the previously validated signed build, with its original embedded README; no new runtime claims are made from documentation changes.

## DMG packaging check — 2026-09-22

A free, unnotarized `Privacy-Watch-1.4.1.dmg` was added to the existing release without rebuilding or re-signing the app. It packages the original release binary, an Applications shortcut, a Read Me First guide, offline documentation, AGPLv3 license and corresponding-source links.

- Disk image integrity and its separate SHA-256 checksum passed.
- The image mounted read-only. The packaged app and a copy extracted from the mounted image both passed strict nested signature verification.
- File contents, executable permissions and symlink targets inside the app matched the original validated app. Both GUI and reader contain arm64 and x86_64 slices; bundle version is 1.4.1.
- The Applications shortcut resolves to `/Applications`. Finder displayed all four expected installer items. The RTF instructions parsed successfully, and documentation/license/source files were present.
- The temporary image was ejected after checking. The installed app, protected reader, login preferences and user event history were not changed.

This verifies packaging and copying on the development Mac. It does not establish clean-Mac Gatekeeper approval, Intel execution, or additional OS compatibility. The previously listed runtime limitations still apply. The release tag and corresponding-source ZIP remain unchanged; DMG packaging scripts and newer documentation are on `main`.
