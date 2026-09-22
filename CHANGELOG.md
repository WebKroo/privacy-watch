# Changelog

## 1.5.0 — Optional GitHub update checks

Adds an Updates section with an automatic-check switch, daily/weekly/monthly frequency, installed version, last successful check, next check and a Check for Updates button. A matching command is available in the Privacy Watch application menu. New releases appear in the activity window and menu panel with a link to their GitHub release and download.

Automatic checks are off by default; weekly is the initial frequency. Checks run in the user app while it is open, catch up after launch/wake, and never download or install an update automatically. Failures stay separate from logging. The checker uses the fixed public GitHub release endpoint with no credentials, cookies, activity records or telemetry. The privacy guide now explains this optional network connection.

The free build remains locally signed and unnotarized. Updating from 1.4.1 requires one administrator approval for the new app identity; existing settings and history are preserved.

## 1.4.1 — Sleep and connection recovery

Corrects a sleep/wake bug: the old heartbeat checks used wall time, so sleep could exhaust the app's eight-second timeout and helper's twelve-second lease. The resulting failure permanently paused logging. Both deadlines now use awake monotonic time. The app observes workspace sleep/wake notifications, retires its reader at sleep, and opens a fresh authenticated session on wake. A late stop acknowledgement or callback from an old session cannot cancel the new session. Shutdown confirmation polls over awake time, covering sleep between acknowledgement and helper exit.

Logging intent is kept separately from connection state. Temporary connection failures retry after 1, 2, 4, 8, 15 and then at most every 30 seconds, with only one retry pending. Pause and Quit cancel intent and pending retries before cleanup. Automatic recovery never requests administrator approval, bypasses a signature check, or retries a CSV write failure. The normal sleep behavior and both icon preferences are unchanged. Sleep and reconnect gaps are not reconstructed or filled with invented STOP events.


## 1.4.0 — Interface refinements

The shield panel is narrower and shorter, with status beside the icon, one main Pause/Resume button, and compact Activity & Settings and Quit controls. Paused status is neutral; errors are orange; progress appears during transitions. The main window has tighter spacing, a clearable search field, a Clear Filters action, helpful no-results feedback and plain-language event labels. Exact source timestamps and CSV values are unchanged. Sensor labels retain readable primary text with colored symbols.

Settings uses shorter explanations and keeps collector maintenance in an Advanced disclosure. Notification permission status is read from macOS when opening Settings. Disabled recording sensors also disable their alert controls without discarding preferences. The main window remembers size and position; icon visibility and background behavior are unchanged.

## 1.3.0 — Background operation

Removes log paths and file buttons from the shield panel; those controls remain in the main window. Adds an optional persistent Dock preference, off by default. The app uses accessory activation while its window is closed and normal activation while viewing Activity & Settings, keeping native menus available when needed. A login launch suppresses the window; reopening the app from Applications always shows it without resuming an explicit pause. `--background` is available for an explicit windowless launch or lifecycle testing.

While logging, a process activity prevents App Nap from suspending the reader heartbeat but permits normal system sleep. Heartbeats run in common run-loop modes so navigating menus does not interrupt them. Pause and Quit release this activity. Sleep/wake remains a separate acceptance check.

Folder selection now creates and resolves its stored bookmark before switching access, retains the resolved URL and renews stale bookmarks. Bookmark errors are surfaced instead of silently discarded. Permission errors direct you to reselect the existing folder rather than implying that history is a legacy shortcut. A changed local signature may require choosing the folder again after an update.

## 1.2.0 — Privacy Watch

Renames the visible app to Privacy Watch, removes sensor toggles from the status panel, adds standard application menus and Dock access, and adds an optional persistent Show menu-bar icon setting. The icon is controlled independently of application lifetime. Existing bundle identity, preferences, log folder and CSV filenames are retained so history and startup settings continue to work. This update needs one administrator approval for its new local code signature.


## 1.1.0 — Automatic logging on launch

Adds automatic logging on fresh app launch, enabled by default with an optional Settings → Startup switch. Uses your macOS login item to start after reboot/sign-in. Updating from 1.0.1 changes the approved code identity, so setup is needed once for this version; it is not needed on each reboot.

## 1.0.1 — Installer signature verification

Corrects the installer signature-check argument and checks the architecture-specific approved hash after verifying all universal-binary signatures. The same check runs before administrator approval and is tested against a staged helper, including rejection of a different hash. If version 1.0 setup stopped with “invalid requirement specification,” reopen 1.0.1 and retry setup; that early failure did not unload the original logger.
