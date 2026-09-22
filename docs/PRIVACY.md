# Privacy and data handling

## What is observed

Privacy Watch reads Control Center privacy-attribution metadata for microphone, camera, screen capture and location. It records the source timestamp, sensor category, START/STOP event, application bundle identifier, resolved app name, an observation marker and an event ID.

It does not record audio, video, screen contents or location coordinates. It does not itself request access to use those sensors. Administrator approval is needed to install the protected-log reader; notification permission controls the optional alerts.

## Where the information goes

The protected reader sends minimal event metadata to the app over authenticated local XPC. The normal user-session app filters selected categories, writes the chosen CSV and optional line-delimited JSON backup, displays recent rows, and submits selected microphone/camera alerts to macOS Notification Center.

The app has no network feature, analytics, advertising, account login or automatic uploader. A folder managed by iCloud, Dropbox or another sync service may still be synced by that service. Notification previews can reveal app names and sensor activity on screen, depending on macOS settings.

## Local storage

Default folder: `~/Documents/Logs/Mac Privacy Activity Local`.

- `Mac Privacy Activity.csv`: full saved event history; no automatic rotation or deletion.
- `Mac Privacy Activity.log`: optional plain-text JSON event backup.
- UserDefaults: preferences and a bookmark for the selected folder.
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
