# User guide

- The shield opens a compact panel with status, a small **Pause/Resume** button and the five newest matching events. **All activity** opens the activity viewer; the **gear icon** opens Settings directly. File paths and CSV/folder buttons remain in the main window. While its window is open, Privacy Watch has a normal macOS application menu and Dock icon. **Quit**, **Privacy Watch → Quit Privacy Watch** or Command-Q stops logging and quits. Closing only the window leaves logging running.
- **Right-click or Control-click the shield** for **See activity**, **Settings…**, **Hide icon** and **Quit Privacy Watch**. A normal click still opens the five-event panel. Hiding the icon keeps logging and is remembered; reopen Privacy Watch from Applications, then enable **Settings → Appearance → Show menu-bar icon** to restore it. Quit uses the same confirmed reader shutdown as the other Quit controls.
- **Settings → Menu bar history** controls which sensors and event types appear in the shield panel. Choose Microphone, Camera, Screen Capture and/or Location, then Started, Stopped and/or First seen. All are shown by default; preferences are remembered. The five-item limit is applied after filtering the loaded recent history. These choices do not change recording, notifications, the activity table or your CSV. Unchecking every sensor or event type hides the menu history.
- Each menu row shows the application, sensor, event and local time in **12-hour AM/PM** format, with a date to distinguish older activity. Hover for the bundle ID and exact source timestamp. **First seen** means the application was already using that sensor when observed; its actual start time may be earlier.
- **Settings → Appearance → Show menu-bar icon** hides or shows the shield without stopping collection. Open Privacy Watch from Applications to recover its window and controls even with both icons hidden. This setting is remembered; the icon is shown by default.
- **Keep Dock icon visible when the window is closed** is off by default in Settings → Appearance. Close the window to hide the Dock icon and keep logging. Opening the app from Applications restores the window, Dock icon and normal menus. Turning this setting on keeps the Dock icon available in the background. Login launches stay in the background; ordinary launches open Activity & Settings.
- Each sensor switch controls future saved records and alerts. The Microphone and Camera notification switches work independently while those sensors are enabled.
- START notices show the utility's shield icon/name, the attributed application, sensor, and local timestamp in **12-hour AM/PM** format, such as `2026-09-18 9:46:08 PM`. The CSV retains the exact source timestamp, including any fractional seconds and UTC offset. There is one custom action, **Dismiss**. Clicking the notification body opens the CSV. macOS controls its own close button, grouping and banner layout.
- **Open CSV** opens `Mac Privacy Activity.csv` in your configured CSV application. **Show Folder** reveals the directory.
- Activity filters by sensor, START/STOP and Today, with text search. It loads up to 2,000 events from the last 4 MiB; the CSV keeps full history.
- Optional `Mac Privacy Activity.log` is plain text, one readable JSON event per line.
- **Pause Logging** stops the reader and helper. **Resume Logging** starts a new observation period without another password. **Quit & Stop Logging** also waits for shutdown before exiting. The registered launchd service remains dormant with no collector process until the app starts a session.
- **Start logging automatically when the app opens** is enabled by default under Settings → Startup. Once this version has been approved, opening the app starts logging. Adding the app to macOS **System Settings → General → Login Items & Extensions → Open at Login** starts it after you sign in, including after a reboot. This is login-time collection, not pre-login collection. Turn off the setting to open paused.
- Pause stays in effect for the current app session; reopening its window does not resume it. Quit stops the reader. A later fresh app launch resumes if automatic logging is on. Automatic startup never installs/repairs a helper or requests an administrator password by itself. A new build needs one setup approval before automatic logging works.
- When the Mac sleeps, the reader stops. Logging resumes automatically after wake if it was requested before sleep. Unexpected reader interruptions reconnect automatically; an intentional Pause or Quit cancels recovery. Storage/approval failures still need attention.
- The app does not reconstruct activity during sleep, disconnection or a pause. Sensor switches changed mid-session may produce unmatched START/STOP rows.

## CSV columns

| Column | Meaning |
|---|---|
| Event ID | Unique ID for the observed event. |
| Timestamp | Exact Apple source timestamp, including available fractional seconds and UTC offset. |
| Sensor | Microphone, Camera, Screen Capture or Location. |
| Action | `START` or `STOP`; displayed as Started/Stopped in the table. |
| App | Resolved display name when available, otherwise the bundle identifier. |
| Bundle ID | Application attribution reported by Control Center. |
| Observation | `first-observed` for the initial snapshot, or `change` for a subsequent set difference. |

The default file is `~/Documents/Logs/Mac Privacy Activity Local/Mac Privacy Activity.csv`. The old filename is retained for compatibility. Optional `Mac Privacy Activity.log` contains one JSON event per line; it is not a byte-for-byte copy of the CSV.

The CSV has no built-in size limit, deletion schedule or rotation. Archive it while paused. Turning a category off changes future saved records and alerts, not existing history. The privileged reader still receives the fixed combined source; the normal-user app applies the selected recording categories.

## Status meanings

- **Logging:** the reader session connected; confirm fresh recognized source data using Last verified update and a deliberate sensor test.
- **Reconnecting:** logging is still requested and the app is trying to restore the reader.
- **Paused:** logging was stopped or a failure needs attention; read any displayed message.
- **Setup required:** approve the current local build once through the macOS administrator dialog.
- **Stop needs attention:** shutdown could not be confirmed. Keep the app open and follow [troubleshooting](TROUBLESHOOTING.md).

A quiet source can be normal. Privacy Watch cannot infer sensor activity that macOS did not report, or activity that occurred during an observation gap.

## Updates

Open **Settings → Updates** to see the installed version and check status.

- **Check for updates automatically:** off initially. Enable it to schedule checks while Privacy Watch is running.
- **Check frequency:** Daily, Weekly or Monthly; Weekly is initially selected. Monthly uses calendar months.
- **Check for Updates:** checks immediately, including when automatic checks are off. The same command appears under the **Privacy Watch** application menu while its window is open.
- **Last checked:** the last successful response. **Next check:** the planned automatic check; sleep or quitting can delay it until the next wake or launch. Manual checks also reset the interval.
- **View Release & Download…:** appears when a newer stable version is found. It opens the official GitHub release page so you can review changes and download the DMG. A notice also appears in the activity window and menu panel.
- A **green checkmark** accompanies **You're up to date** after a successful check. A **teal download arrow** identifies an available update. A failed check has an orange warning symbol; it never displays the success checkmark.

Checks never pause logging or open your browser automatically. A failed check shows a message and leaves logging alone. Automatic attempts wait until the next selected interval after a failure; you can retry manually at any time. Updates are never downloaded or installed automatically. Quit before replacing the app and approve its updated protected reader when prompted.

GitHub receives normal connection metadata, but no activity records or log paths. See [what update checks send](PRIVACY.md#optional-github-update-checks).
