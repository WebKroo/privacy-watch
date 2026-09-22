#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-${TMPDIR:-/tmp}/PrivacyWatch-recovery-integration-tests}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD/module-cache" \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/App/AppModel.swift" \
  "$ROOT"/Tests/RecoveryIntegration/*.swift \
  -o "$BUILD/RecoveryIntegrationTests" -framework SwiftUI -framework AppKit -framework Security
codesign --force --sign - --identifier com.norek.privacywatch.recovery-integration-tests "$BUILD/RecoveryIntegrationTests"
"$BUILD/RecoveryIntegrationTests"
