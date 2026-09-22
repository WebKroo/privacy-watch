#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-${TMPDIR:-/tmp}/PrivacyWatch-local}"
APP="$BUILD/Privacy Watch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD/module-cache"
ARCHITECTURES="${ARCHS:-arm64 x86_64}"
HELPERS=(); APPS=()
for arch in $ARCHITECTURES; do
  mkdir -p "$BUILD/$arch"
  COMMON=(-swift-version 5 -target "$arch-apple-macosx14.0")
  xcrun swiftc "${COMMON[@]}" "$ROOT/Sources/Core/Events.swift" "$ROOT/Sources/Core/LoggingRecovery.swift" "$ROOT/Sources/Shared/IPC.swift" "$ROOT/Sources/Collector/main.swift" -o "$BUILD/$arch/MacPrivacyCollector" -framework Foundation -framework Security -framework SystemConfiguration
  xcrun swiftc "${COMMON[@]}" -parse-as-library "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/Shared/*.swift "$ROOT"/Sources/App/*.swift -o "$BUILD/$arch/MacPrivacyActivity" -framework SwiftUI -framework AppKit -framework UserNotifications -framework Security
  HELPERS+=("$BUILD/$arch/MacPrivacyCollector"); APPS+=("$BUILD/$arch/MacPrivacyActivity")
done
xcrun lipo -create "${HELPERS[@]}" -output "$APP/Contents/MacOS/MacPrivacyCollector"
xcrun lipo -create "${APPS[@]}" -output "$APP/Contents/MacOS/MacPrivacyActivity"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/README.md" "$APP/Contents/Resources/README.md"
# Keep linked help available alongside the README in future local builds.
for directory in docs .github/assets; do
  if [ -d "$ROOT/$directory" ]; then
    mkdir -p "$APP/Contents/Resources/$directory"
    ditto --norsrc --noextattr "$ROOT/$directory" "$APP/Contents/Resources/$directory"
  fi
done
for document in VALIDATION.md CHANGELOG.md CONTRIBUTING.md SECURITY.md LICENSE COPYRIGHT; do
  if [ -f "$ROOT/$document" ]; then cp "$ROOT/$document" "$APP/Contents/Resources/$document"; fi
done
xattr -cr "$APP"
codesign --force --options runtime --sign - --identifier com.norek.macprivacyactivity.local.collector "$APP/Contents/MacOS/MacPrivacyCollector"
codesign --force --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '\nLocal app: %s\n' "$APP"
