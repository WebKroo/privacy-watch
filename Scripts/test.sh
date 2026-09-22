#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build/tests}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -swift-version 5 -D STANDALONE -module-cache-path "$BUILD/module-cache" "$ROOT"/Sources/Core/*.swift "$ROOT/Tests/CoreTests/CoreTests.swift" "$ROOT/Tests/Standalone/main.swift" -o "$BUILD/CoreTests"
"$BUILD/CoreTests"
