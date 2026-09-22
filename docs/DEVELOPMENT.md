# Build, test and release

## Requirements

Use macOS with Apple Command Line Tools and a compatible SDK. Version 1.4.1 was built using Swift 6.4 in Swift 5 language mode on Apple Silicon/macOS 27. Full Xcode, a signing team and third-party packages are not required. The deployment target is macOS 14; that target alone does not establish compatibility with Apple's undocumented log source on every OS release.

```sh
xcode-select --install
```

From the repository root:

```sh
bash Scripts/test.sh
bash Scripts/test-recovery.sh
bash Scripts/test-recovery-integration.sh
bash Scripts/build-local.sh
bash Scripts/test-installer.sh "${TMPDIR:-/tmp}/PrivacyWatch-local/Privacy Watch.app/Contents/MacOS/MacPrivacyCollector"
```

The build creates a universal arm64 + x86_64 app under `${TMPDIR:-/tmp}/PrivacyWatch-local`. Use `ARCHS=arm64` or `ARCHS=x86_64` for one architecture, and `BUILD_DIR` to select another destination. Keep signed output outside iCloud/OneDrive: resource-fork or Finder metadata can invalidate signing.

## Tests and their scope

| Suite | What it exercises |
|---|---|
| `test.sh` | Parser and set differences, source/timestamp fidelity, CSV safety/storage, link rejection and notification time formatting. |
| `test-recovery.sh` | Awake-time deadlines, sleep, retry limits and user intent. |
| `test-recovery-integration.sh` | Actual AppModel with an anonymous native XPC fake collector, including wake/cleanup races, stale callbacks, reconnect and stop cancellation. |
| `test-installer.sh` | Acceptance of the expected locally signed helper and rejection of a different code hash. |

The integration executable substitutes installation, notifications and app identity, uses a temporary folder, and never runs the protected log reader. Restrictive command sandboxes can block its anonymous XPC replies; run it in a normal local Terminal. Do not grant a test harness access to the production root helper.

A passing build or test suite does not replace the [manual sensor and lifecycle checks](TROUBLESHOOTING.md#verify-after-setup-and-macos-updates). Record the OS, hardware and actual tests performed in [VALIDATION.md](../VALIDATION.md). Keep untested behavior explicit.

## Preview

A locally built app supports `--demo` for sample activity. The preview does not start the privileged collector. Keep previews separate from the installed production copy and clearly label any screenshots as sample data.

## Local signing and updates

The app and helper are signed ad hoc with hardened runtime. The administrator-approved policy pins an exact app code identity, and the app pins its bundled helper identity. Rebuilding, changing signed resources or changing architecture can require approval again. Do not weaken those checks to simplify installation.

To try a new build: Quit the installed version, preserve a copy, replace the app, open it and use Install / Repair Local Collector when required. Prefer a test Mac for changes to the privileged component. No development script should automatically delete the user's old logger or history.

## Preparing a release

1. Update the version/build in `Resources/Info.plist` and document changes.
2. Run the suites and build both architectures. Verify `codesign --verify --deep --strict` on the app.
3. Perform the relevant runtime checks and record remaining limitations.
4. Package the app without extra resource metadata:

```sh
ditto -c -k --norsrc --noextattr --keepParent \
  "${TMPDIR:-/tmp}/PrivacyWatch-local/Privacy Watch.app" \
  /tmp/Privacy-Watch-release.zip
shasum -a 256 /tmp/Privacy-Watch-release.zip
```

5. Extract the ZIP outside a cloud folder and verify its signature again.
6. Create a drag-to-Applications disk image from the verified app (no rebuild or re-signing):

```sh
bash Scripts/package-dmg.sh \
  "${TMPDIR:-/tmp}/PrivacyWatch-local/Privacy Watch.app" \
  /tmp/Privacy-Watch-release
```

This creates a compressed, read-only HFS+ DMG and an adjacent `.dmg.sha256` file. It includes an Applications shortcut, first-launch instructions, offline documentation, license and corresponding-source links. The default source ref is `v` plus the app's version; set `SOURCE_REF` to the actual corresponding published ref if different. The output must not already exist. The packaging script uses only tools included with macOS and does not install or launch the app.

7. Mount the resulting DMG read-only, verify the packaged app signature, copy it to a temporary folder and verify the copied app again. Check that the Applications shortcut resolves to `/Applications`, both architecture slices are present, and the app contents match the validated input. Eject the test image afterward. This packaging check does not replace a clean-Mac installation test.
8. Attach the DMG and its checksum to the GitHub release alongside the ZIP, corresponding source archive and existing ZIP checksums. Keep published asset names immutable. Include installation notes, source commit, OS/hardware validation and the local-signing/notarization limitation. Include no personal logs, preferences, policy files or machine-specific updater scripts.

The GitHub documentation may evolve independently of the README embedded in a previously signed release. Rebuilding from current source produces a new local identity and requires approval; byte-for-byte identity with an older packaged app is not promised.
