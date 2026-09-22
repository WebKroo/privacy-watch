#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-${TMPDIR:-/tmp}/PrivacyWatch-recovery-tests}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD/module-cache" \
  "$ROOT/Sources/Core/LoggingRecovery.swift" "$ROOT/Tests/Recovery/main.swift" \
  -o "$BUILD/RecoveryTests"
"$BUILD/RecoveryTests"
