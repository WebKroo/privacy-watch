# Troubleshooting

- **“Privacy Watch” Not Opened / Apple could not verify:** this free build is unnotarized. Review the [app-specific opening steps](INSTALLATION.md#if-macos-or-blockblock-stops-the-app-from-opening), including the separate BlockBlock alert if you use it. BlockBlock's notarization-mode approval may be requested again after reboot; this is distinct from protected-reader setup.
- **Can't find Privacy Watch in Privacy & Security:** scroll the main pane on the right down to **Security**, near the bottom, just above **FileVault**. Look for the temporary **“Privacy Watch” was blocked to protect your Mac** message and its **Open Anyway** button. It is not an entry in Camera, Microphone or other permission lists. If the message is missing, open the installed app again, click **Done** on the warning, and return to Settings. If the warning returns after **Open Anyway**, tell us whether the second Open/authentication prompt appeared.
- **Setup requires an administrator:** free software still needs permission to read this protected source. Ask the Mac's administrator to complete the macOS dialog; no Apple membership is required.
- **Logging but no verified updates during deliberate sensor tests:** pause and inspect the source. A macOS format/redaction change needs a parser update. Preserve the original until the new reader passes live checks.
- **Setup/signature/connectivity error:** use one installed copy; quit other copies, then Install / Repair Local Collector. A rebuild or architecture change needs a new approved policy. If setup partially completed, repair or restore the original.
- **No alerts:** Allow Notifications, then check System Settings, Focus, preview settings and both relevant switches. Existing notifications keep their old format.
- **Cannot save after renaming or moving the app:** reselect the same existing log folder with Settings → Choose Folder, then Resume Logging. This refreshes macOS folder access without moving history.
- **Cannot save / legacy schema:** choose a fresh writable folder. Never replace the old CSV through its symlink. Check disk space and permission to your selected folder.
- **Stop needs attention:** allow roughly 20 awake seconds for cleanup, then retry Quit. If still running, an administrator can stop this exact service with `sudo launchctl bootout system/com.norek.macprivacyactivity.local.collector`; then retry Quit. Do not remove the app while the reader is running.
- **Restore Original Logger…** in Settings → Advanced stops/disables the new service, re-enables the original root job and notification watcher, and marks local setup inactive. This requires administrator approval. The original resumes its independent background logging, including after this GUI quits.


## Verify after setup and macOS updates

ControlCenter's sensor message format is undocumented and can change with an OS update. Logging status means the reader started; **Last verified update** confirms a recognized snapshot arrived. An idle source can legitimately be quiet.

1. Start/stop Voice Memos (microphone), then a FaceTime camera preview. Confirm respective START/STOP entries, a saved CSV row, an attributed application and an AM/PM START alert.
2. Test screen sharing/recording and a location request in Maps or Weather. Confirm `scr:` and `loc:` attribution changes; not every app action necessarily produces one.
3. Test Dismiss and notification-body CSV opening. Turn a sensor off and verify it is not saved or notified; test mic/cam alert switches separately.
4. Pause and verify sensor use produces no new rows. Resume and check fresh updates. Quit and verify the helper is not running. Test quitting during startup and closing the window while logging.
5. Quit and reopen the app: with Settings → Startup enabled, status should change to Logging without clicking Resume. Turn it off and relaunch to confirm Paused, then restore your preference. Pause and reopen just the window to verify it stays paused. Keep the app in Open at Login for automatic logging after sign-in.
6. Close the lid while Logging, then reopen/unlock. Confirm Logging returns and a deliberate sensor test creates fresh rows. Repeat while Paused and confirm it stays paused. First seen after reconnect means active at the new observation boundary; it is not a reconstructed start time.
7. Repeat on another Mac and after every OS update before relying on the history.

For a read-only status check in Terminal:

```sh
launchctl print system/com.norek.macprivacyactivity.local.collector
pgrep -fl 'com.norek.macprivacyactivity.local.collector'
```

After Pause/Quit the service may still be listed, but must have no `pid` and must not say `state = running`. The collector process should be absent. Other `log stream` processes may belong to the original logger or unrelated tools; never kill every log reader indiscriminately.

To inspect the current Apple source, an administrator can run the fixed `sudo /usr/bin/log stream ...` command shown above and press Control-C afterward. Expect the system ControlCenter executable path, its process ID and full active-attribution arrays. Do not enable global private-data logging. This utility is an observation aid, not a complete security audit.

## Logging after sleep

Version 1.4.1 stops its reader for sleep and restores requested logging on wake. It also recovers from temporary reader disconnections. Pause and Quit cancel recovery. If a connection remains unavailable, retry delays increase to 30 seconds. A storage or setup error needs attention rather than indefinite retries.

If an overnight problem persists, note the app version, macOS version, displayed status and approximate sleep/wake times. Check whether logging had been deliberately paused. Reproduce with a short sleep while logging and a deliberate sensor test afterward. Repeat while paused to confirm it stays paused. Do not attach your full personal CSV to a public issue.

## Lifecycle diagnostics

The app records connection lifecycle messages without sensor event contents. On a standard account, inspecting the unified log may require an administrator:

```sh
sudo /usr/bin/log show --last 1h --style compact --info --predicate 'subsystem == "com.norek.macprivacyactivity.local.app" AND category == "lifecycle"'
```

Review and redact any diagnostics before sharing. The [validation record](../VALIDATION.md) distinguishes automated checks from physical sleep and second-Mac tests that remain to be performed.

## Update checks

If a check fails, confirm internet access and try Check for Updates again. GitHub can temporarily rate-limit requests. Automatic checks wait for the selected interval after each attempt; a manual retry remains available. The last successful check time does not advance on failure.

Checks run only while Privacy Watch is open, including when its window and icons are hidden. Launching or waking the app catches up on an overdue automatic check. Automatic checks are off initially. Turning them off cancels an automatic request but still allows explicit manual checks. Preview mode never contacts GitHub.

The checker considers the repository's latest published stable release, not source commits, draft releases or prereleases. It never installs anything. If a new release is reported, review its notes and compatibility before downloading. A local development build newer than the published version is already up to date.
