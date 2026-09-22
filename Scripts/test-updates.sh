#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 WebKroo
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-${TMPDIR:-/tmp}/PrivacyWatch-update-tests}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD/module-cache" \
  "$ROOT/Sources/Core/Updates.swift" "$ROOT/Tests/Updates/main.swift" -o "$BUILD/UpdateTests"
"$BUILD/UpdateTests" "$@"
