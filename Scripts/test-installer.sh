#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-${TMPDIR:-/tmp}/MacPrivacyActivity-installer-tests}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD/module-cache" "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Shared/IPC.swift" "$ROOT/Sources/App/LocalInstallation.swift" "$ROOT/Tests/Installer/InstallerTests.swift" -o "$BUILD/InstallerTests" -framework AppKit -framework Security
"$BUILD/InstallerTests" "${1:?Pass the built MacPrivacyCollector path}"
