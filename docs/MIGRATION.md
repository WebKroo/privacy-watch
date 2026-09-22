# Migration from the original logger

This app was previously called Mac Privacy Activity Local. Privacy Watch keeps its existing internal bundle identifiers, preferences, helper paths and CSV filenames so renaming the interface does not discard history.

## Existing prototype installations

The local setup disables the known original logger and notification watcher when replacing them. It preserves their programs, configuration and history. It does not automatically delete prototype components or convert their old CSV schema.

The default GUI folder is `~/Documents/Logs/Mac Privacy Activity Local`, separate from the original `~/Documents/Logs/Mac Privacy Activity.csv` symlink. Keep the old history intact. Choose a fresh folder if a file has a different schema; do not point the GUI at the legacy symlink.

## Original components

These are recognized legacy paths, not components installed by a new Privacy Watch setup:

- `/Library/LaunchDaemons/local.privacy-sensors.logger.plist`
- `~/Library/LaunchAgents/local.privacy-sensors.notify.plist`
- `/usr/local/libexec/privacy-sensors-logger`
- `/usr/local/bin/privacylog`
- `/Applications/Mac Privacy Activity.app`
- `~/Library/Scripts/privacy-sensor-notify.sh`
- `/Library/Logs/Privacy-Sensors.csv` and `/Library/Logs/Privacy-Sensors.log`
- The original Documents CSV symlink and any old diagnostics.

## Restoring the original

**Settings → Advanced → Restore Original Logger…** stops and disables the new service, marks its setup inactive, and attempts to re-enable the known original jobs. It requires administrator approval and the actual original components to still exist. Do not assume the old app path still contains the original notifier: it may have been replaced or renamed during local development.

The original logger runs independently and can keep logging after Privacy Watch quits. Archive history and verify the exact legacy files before any manual cleanup. See [clean uninstall](UNINSTALL.md) for removing only the new app's helper.
