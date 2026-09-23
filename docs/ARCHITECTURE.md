# Architecture

```
ControlCenter protected unified log
  → administrator-installed root reader: fixed source → parse → diff
  → authenticated XPC: minimal event metadata
  → normal-user GUI: app names → CSV / optional text / notifications / table
```

This local edition uses a root-owned launchd registration rather than `SMAppService`. Apple's recommended SMAppService development workflow relies on consistent Apple-issued signing; this edition instead uses local ad-hoc signatures and an administrator-approved policy pinning this exact app's code hash. Rebuilding the app requires **Install / Repair Local Collector…** again. No Developer ID or notarization is claimed.

The GUI authenticates the helper's code hash too. Hardened runtime is enabled. The root policy, helper and launch plist are administrator-owned. The installation script copies the reader into root-only staging and verifies its expected signature before installing. Only an authenticated app running as the active console user can start a session. The reader also verifies the emitting ControlCenter process path and UID, preventing attribution forwarding from another user's session.

The helper exposes only start, heartbeat and stop. It accepts no file path, shell command or sensor configuration from the client. Root only launches this fixed reader, parses the source and emits timestamp, sensor, action, bundle ID and observation type:

```
/usr/bin/log stream --style ndjson --info --predicate 'process == "ControlCenter" AND subsystem == "com.apple.controlcenter" AND category == "sensor-indicators"'
```

Only complete `Active activity attributions changed to [...]` arrays are accepted. Verified tokens are `mic:`, `cam:`, `scr:`, `loc:`. Duplicate tokens collapse into sets; additions/removals produce START/STOP. Recent-attribution messages, malformed/redacted arrays and unknown sensor kinds cannot manufacture STOP events. The first snapshot emits START tagged `first-observed`, meaning active when first seen, not proof of the physical start time. No STOP is invented on pause/quit. If already-active use produces no fresh snapshot, it remains unseen until ControlCenter emits an update.

The app renews a 12-second lease every three seconds. Liveness deadlines measure awake time, excluding system sleep and wall-clock adjustments. Disconnect, console-user change or lease expiry stops the reader. Stop terminates and reaps it before acknowledgement; launchd also owns its process group. An unused helper checks for idle exit every 15 awake seconds. Quit checks the local service has no running process and stays open with an error when shutdown cannot be confirmed. The original logger, if explicitly restored, runs independently and is not stopped when this GUI quits.

CSV writing and notifications run as the normal user. Log files are mode 0600; unsafe symbolic/hard links, other owners and incompatible schemas are rejected. CSV quoting and formula-prefix protection are applied. A write error pauses collection. There is no automatic rotation/deletion; archive logs while paused. Optional release checks make a public GitHub request from the user-session app; no event data is attached. A chosen iCloud-synced folder is still synced by macOS.

## File locations

| Location | Purpose |
|---|---|
| `~/Applications/Privacy Watch.app` | Installed GUI and bundled source reader; README under Contents/Resources |
| `/Library/PrivilegedHelperTools/com.norek.macprivacyactivity.local.collector` | Installed root reader |
| `/Library/LaunchDaemons/com.norek.macprivacyactivity.local.collector.plist` | Dormant on-demand service registration |
| `/Library/Application Support/Mac Privacy Activity Local/Client.plist` | Administrator-approved app code hash and active state |
| Selected folder | `Mac Privacy Activity.csv` and optional `Mac Privacy Activity.log` |
| `~/Library/Preferences/com.norek.macprivacyactivity.local.app.plist` | User preferences managed by UserDefaults |

## Sleep and reconnect lifecycle

User intent is separate from connection state. `LoggingRecovery` preserves requested logging through sleep and temporary transport loss. `AwakeDeadline` measures monotonic awake time, so sleep and wall-clock changes do not falsely expire a live connection.

Workspace sleep retires the current session. Wake reconciles the saved intent, including when cleanup is still awaiting a reply. A fresh observation begins after reconnect. Retry delays are 1, 2, 4, 8, 15 and then 30 seconds, with one cancellable retry pending. Generation checks reject delayed replies and receiver callbacks from retired connections. Stop confirmation polls for up to 18 awake seconds, allowing the helper's idle exit to complete.

Explicit Pause/Quit clears intent before asynchronous cleanup. Approval, signature-preflight and storage failures require attention instead of automatic installation or repeated writes. A process activity keeps heartbeat/retry work responsive while permitting normal system sleep.

## Source map

- `Sources/Collector`: fixed source reader, authenticated session ownership, process validation and lease.
- `Sources/Shared`: XPC interfaces and local code identity checks.
- `Sources/Core`: source parser, set differences, storage, notification time formatting and recovery policy.
- `Sources/App`: native interface, lifecycle, local setup, file access and notifications.
- `Tests`: parser/storage tests, installer identity tests, recovery policy tests and isolated XPC integration tests.

Apple references: [NSXPC signing requirements](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [workspace sleep](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification), [workspace wake](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification), [uptime excludes sleep](https://developer.apple.com/documentation/dispatch/dispatchtime/uptimenanoseconds).

## Menu history

`Sources/Core/MenuHistory.swift` filters the app's newest-first in-memory history and returns the first five matches. Sensor and event-kind preferences persist under separate `menuHistory.*` keys; recording and notifications never read them. `first-observed` is its own display/filter category rather than a confirmed start. The menu uses the same bounded history as the activity viewer; it does not read extra CSV data, request new collector permissions or fetch application icons from the network.

## Combined activity presentation

`Sources/Core/ActivityHistory.swift` projects the bounded newest-first event array into activities keyed by application bundle ID and sensor. It processes the original recorded order, preserving equal timestamps and rapid transitions. A new START supersedes an unmatched prior START. Pairing happens before UI filters and the menu limit; it does not rewrite the CSV, alter notifications or change the reader protocol.

`ActivityContinuity` remembers boundaries before the next saved event for each affected sensor. A fresh process, collector session, stop, sleep/reconnect or recording toggle invalidates live-active IDs. Boundary IDs are saved in UserDefaults under a per-folder key and pruned to the loaded event window. Only starts observed in the current continuous session can display Active. A missing endpoint has no duration; a first-observed start supplies a lower bound. Invalid or backwards timestamps never produce a negative duration.

Pre-1.7 histories and copied CSVs without their local preference metadata have no complete boundary record. Pairing can only use their available sequence; it cannot prove continuity through an unrecorded gap. The app documents this limitation instead of synthesizing missing events. Display preferences use `activity.rowStyle` and `activity.compactRows`, independent of recording and menu filters.

## Update checks

`Sources/Core/Updates.swift` contains numeric stable-version comparison, calendar scheduling, a bounded GitHub release client and an observable update controller. `AppModel` owns the controller; checks start independently of logging and re-evaluate on wake. A one-shot timer re-evaluates at least hourly while automatic checks are enabled, so clock changes do not leave a long-lived timer stranded. Preferences and timestamps persist across launches. Failed attempts count toward the schedule to avoid retry storms, while manual retries remain available.

One request may be in flight. Turning automatic checks off cancels an automatic request, and generation checks prevent its delayed result from overwriting a later manual check. Preview mode performs no checks. Network errors do not enter the logging failure or collector recovery paths. The collector binary has no update code.

The fixed endpoint supplies only the stable release tag and draft/prerelease flags. The app constructs a GitHub release-page URL from a strictly validated numeric tag instead of following API-provided links. Opening that page is a user action; downloads and installation remain manual. See the [privacy notes](PRIVACY.md#optional-github-update-checks).

The result state distinguishes up-to-date, update available and no published release. The UI renders a green checkmark only for a successful up-to-date result. Starting a request, canceling or receiving an error clears that result so stale success cannot be shown as the latest outcome.
