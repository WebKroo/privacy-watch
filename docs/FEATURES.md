# Features and benefits

Privacy Watch turns transient privacy indicators into a local history you can revisit. It is intended for personal awareness and troubleshooting: understanding the sensor activity macOS attributed to applications while logging was active.

## Review four kinds of activity

Microphone, Camera, Screen Capture and Location can each be enabled or disabled. The app records changes in Control Center's active attribution set as Started and Stopped events. You can focus on one category without collecting every category in your saved history. These controls do not grant or revoke macOS sensor permissions.

## Find useful records quickly

The native SwiftUI table shows timestamps, sensor, event, application, bundle ID and observation type. Search works across these fields; filter by sensor, event and Today. Clear Filters restores the complete recent view. The table loads up to 2,000 rows from the last 4 MiB for responsiveness, while the CSV retains the full saved history.

## Read an activity once, with its duration

Combine a start and stop into one row to follow each app's sensor use without scanning separate events. A current use is marked Active; its duration appears when it ends. The menu shows five activities, and All activity shows both times with search and status filters. Choose Compact rows to fit more on screen, or return to separate events at any time. These display choices leave your full CSV history intact.

Missing endpoints stay Unknown, and activity already underway when first seen has a minimum observed duration marked with ≥. Known observation gaps break pairing; historical gaps from older versions cannot be recovered. See [duration meanings](USER_GUIDE.md#choose-how-activity-is-displayed).

## Notice microphone and camera use

Separate start-alert switches let you choose microphone, camera or both. Notifications identify Privacy Watch, the attributed app and the sensor, with a local 12-hour AM/PM timestamp. They include one custom Dismiss action; clicking the body opens the CSV. macOS controls delivery, Focus, grouping and banner appearance. First-observed alerts identify their observation boundary.

## Own a portable history

Choose a log folder and open its CSV in your preferred spreadsheet app. Exact source timestamps retain fractional seconds and time-zone offsets. An optional plain-text file stores one JSON event per line. Open CSV and Show Folder are available in Activity & Settings. There is no built-in account or cloud upload; macOS may sync a folder you place in iCloud or another sync service.

## Keep the interface as quiet as you prefer

The shield panel shows the five newest matching events with application names, sensor labels and AM/PM times. Choose which sensors and Started, Stopped or First seen events appear under Settings → Menu bar history, independently of what you record. A compact Pause/Resume button, All activity, a Settings gear and Quit keep the controls within reach. Right-click or Control-click the shield for direct access to activity, settings, hiding the icon and quitting. Closing the main window keeps logging and hides the Dock icon by default. The shield can also be hidden. Opening Privacy Watch from Applications restores the activity window and standard menus. Window size and position are remembered.

## Start and stop predictably

Automatic logging on a fresh app launch is enabled by default. Combined with macOS Open at Login, it starts after sign-in. Sleep and temporary connection interruptions have automatic recovery. A deliberate Pause stays in effect for the current process, including across sleep and reopening its window. Quit confirms the reader has stopped; a later fresh launch follows the startup preference.

## Keep privileged work narrow

The protected reader only reads a fixed Apple log source and emits minimal metadata. File writing, notifications and the UI run in your normal user session. The app and reader authenticate each other's locally approved code identities. This separation supports the product's local operation; it is not a claim of an independent security audit.

## Use it without a subscription

No paid developer membership is needed to build or run this edition. A macOS administrator must approve the protected reader for each new build and each receiving Mac. Local signing is not Developer ID signing or notarization, so installation has more friction than a notarized commercial app.

See [coverage limits](PRIVACY.md#coverage-and-limits) and [verification steps](TROUBLESHOOTING.md#verify-after-setup-and-macos-updates) before relying on the record.

## Choose when to check for updates

Keep track of new versions without visiting GitHub repeatedly. Enable daily, weekly or monthly release checks, or leave them off and use Check for Updates when convenient. Privacy Watch shows available releases with a download link, while you decide when to install. Offline checks do not interrupt sensor logging, and activity history is never included in update requests.

A green checkmark confirms a successful up-to-date result. A teal download arrow marks a new release; an orange warning identifies a failed check.
