# Install Privacy Watch

## Requirements

- A Mac: macOS 14 is the deployment target. Actual source behavior was validated on Apple Silicon/macOS 27. Intel and other OS versions need their own checks.
- A macOS administrator available for the initial protected-reader setup and subsequent changed builds.
- A writable folder for your history.
- Notification permission if you want microphone or camera alerts.

No paid Apple account or developer membership is needed. To run a packaged app, neither Xcode nor Command Line Tools is required. Building from source requires Apple Command Line Tools with a compatible SDK.

## Download and install the DMG

1. Download **[Privacy-Watch-1.4.1.dmg](https://github.com/WebKroo/privacy-watch/releases/download/v1.4.1/Privacy-Watch-1.4.1.dmg)** from the official GitHub release. The neighboring `.dmg.sha256` file lets you verify its checksum.
2. Open the disk image. Drag **Privacy Watch.app** onto the **Applications** shortcut. Quit any running older copy before replacing it.
3. Eject the Privacy Watch disk image and open **Privacy Watch** from Applications. Do not set up the protected reader while the app is still on the mounted disk image.
4. Follow the first-launch steps below. Copying the app alone does not authorize the protected reader.

The DMG includes the same app as the 1.4.1 ZIP, an Applications shortcut, a **Read Me First** guide and a **Documentation** folder with the AGPLv3 license and source links. It remains a free, locally signed, unnotarized release; a DMG does not remove Gatekeeper warnings.

If you prefer the ZIP, extract it and copy the app into Applications manually. Neither format includes personal activity logs or settings.

## First launch

1. Put **Privacy Watch.app** in your personal Applications folder (`~/Applications`) or `/Applications`. Keep it outside iCloud/OneDrive. Open that installed copy.
2. Click **Set Up & Start Logging**. A macOS administrator must approve installing the protected-log reader. Enter credentials only in the macOS dialog. A standard account cannot approve this alone.
3. In **Settings**, click **Allow Notifications…**, then allow notifications in the system dialog. Set the banner/alert style you prefer in System Settings → Notifications.
4. Start and stop a microphone recording or camera preview. Check Activity for real START/STOP rows and the Last verified update time.

Setup pauses the known original logger and notification watcher if present. It preserves their programs, configuration and history. If setup is canceled, it does not switch away from the original logger.

The new default folder is `~/Documents/Logs/Mac Privacy Activity Local`. This separate folder preserves the original `~/Documents/Logs/Mac Privacy Activity.csv` symlink and its different CSV schema. Choose any fresh writable folder in Settings while paused.

## Move or share for free

The supplied ZIP contains a universal Apple Silicon + Intel app, targeting macOS 14 or later. Source behavior was developed on macOS 27; other releases and Intel hardware require the checks below. Quit before moving/copying. Install from the DMG, or unzip outside cloud-synced folders, place the app in Applications, and run its setup on each Mac. Each Mac requires its own administrator approval and notification permission. Copy your CSV history separately if desired; the distributed app contains no personal history.

This is a local, unnotarized build. A downloaded copy may be blocked by Gatekeeper. Only if you trust the source, use Apple's **System Settings → Privacy & Security → Open Anyway** option when offered. Managed Macs may prohibit this. Do not disable Gatekeeper globally. Receiving Macs do not need development tools. Updating/rebuilding changes the approved identity and requires repair/setup again.

## Automatic startup

Enable **Settings → Startup → Start logging automatically when the app opens**, then add Privacy Watch in **System Settings → General → Login Items & Extensions → Open at Login**. This starts after sign-in, not before login. Login launches stay in the background.

## Updating

Quit the running app before replacing it. Reopen the installed copy and use **Settings → Advanced → Install / Repair Local Collector…** if requested. Local signatures pin the exact approved build, so an update needs administrator approval once; it does not need approval every reboot. Keep one installed copy and the same Applications path. Existing app identity, preferences and CSV names are retained.

Pause before changing folders. If macOS denies access after an update, choose the same folder again; this renews access without deleting history.

Next: [everyday use](USER_GUIDE.md) and [verify your installation](TROUBLESHOOTING.md#verify-after-setup-and-macos-updates).
