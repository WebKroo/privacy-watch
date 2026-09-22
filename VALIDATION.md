# Validation — Privacy Watch 1.4.1

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
