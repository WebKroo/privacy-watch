# Privacy and data handling

## What is observed

Privacy Watch reads Control Center privacy-attribution metadata for microphone, camera, screen capture and location. It records the source timestamp, sensor category, START/STOP event, application bundle identifier, resolved app name, an observation marker and an event ID.

It does not record audio, video, screen contents or location coordinates. It does not itself request access to use those sensors. Administrator approval is needed to install the protected-log reader; notification permission controls the optional alerts.

## Where the information goes

The protected reader sends minimal event metadata to the app over authenticated local XPC. The normal user-session app filters selected categories, writes the chosen CSV and optional line-delimited JSON backup, displays recent rows, and submits selected microphone/camera alerts to macOS Notification Center.

The app has no analytics, advertising, account login or activity uploader. Update checks are an optional network feature described below. A folder managed by iCloud, Dropbox or another sync service may still be synced by that service. Notification previews can reveal app names and sensor activity on screen, depending on macOS settings.

## Optional GitHub update checks

Automatic checks are off by default. Turning them on permits a public HTTPS request to `api.github.com/repos/WebKroo/privacy-watch/releases/latest` at the selected daily, weekly or monthly interval while the app is running. Check for Updates makes that same request on demand, including when automatic checks are off.

GitHub receives the connection's IP address and normal request metadata, including a generic Privacy-Watch-Updater user agent. The request contains no activity logs, sensor events, application history, folder paths, account identifier or installed-version identifier. The checker has no GitHub token, uses an ephemeral session without cookies, credentials or a disk cache, rejects redirects, and reads at most 1 MiB of response data. The privileged reader does not participate in networking.

Only stable, published releases are considered. Following View Release & Download opens the official repository in your browser; your browser then uses its own GitHub sign-in and privacy settings. The app never downloads, executes or installs update files automatically.

The chosen frequency, switch, last attempt, last successful check and known newer release tag are saved locally. Turning automatic checks off cancels a pending automatic check; an explicitly requested manual check can still finish. No checks run while Privacy Watch is quit. A missed check happens when it next runs or wakes. A failed check waits for the chosen interval unless you retry manually.

## Local storage

Default folder: `~/Documents/Logs/Mac Privacy Activity Local`.

- `Mac Privacy Activity.csv`: full saved event history; no automatic rotation or deletion.
- `Mac Privacy Activity.log`: optional plain-text JSON event backup.
- UserDefaults: preferences, a bookmark for the selected folder, and event IDs marking observation boundaries for each log folder's loaded history. These local markers prevent combined rows from pairing across known logging gaps; they contain no new sensor data and are not uploaded.
- Administrator-owned helper policy: the approved local app identity and activation state.
- Unified log: connection lifecycle messages; this diagnostic channel does not intentionally include sensor event records.

Files are created with mode 0600 and checked for ownership, regular-file type and unsafe links. These are local file protections, not application-level encryption. People or software with sufficient access to your account, backups, synced folder or Mac may still read the history. Pause before archiving files. Review and redact logs before sharing them.

## Coverage and limits

- The source is an undocumented Apple log stream. An OS update can change its format, availability or redaction.
- The reader accepts recognized Control Center messages for the connected console user. It is not a system-wide multi-user surveillance service.
- First seen marks activity present at the first valid snapshot of a new session. It does not prove the physical sensor start time.
- Sleep, Pause, disconnection and disabled recording categories can leave gaps or unmatched START/STOP entries. Gaps are not reconstructed.
- Logging status confirms a connection; deliberate sensor checks and Last verified update confirm source activity.
- The app does not block sensor access, detect all misuse, establish that a Mac is uncompromised, or replace macOS privacy permissions.
- This edition uses local ad-hoc signing and explicit administrator approval. It is not notarized and has not received an independent security audit.

See [architecture](ARCHITECTURE.md), [security reporting](../SECURITY.md) and [uninstall](UNINSTALL.md).
