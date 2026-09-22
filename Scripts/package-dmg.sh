#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 WebKroo
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_INPUT="${1:?Usage: package-dmg.sh /path/to/Privacy\ Watch.app /path/to/output-directory}"
OUT_INPUT="${2:?Supply an output directory}"
APP="$(cd "$(dirname "$APP_INPUT")" && pwd)/$(basename "$APP_INPUT")"
[[ -d "$APP/Contents" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
case "$VERSION" in ''|*[!A-Za-z0-9._-]*) echo 'Unsafe version string' >&2; exit 1;; esac
SOURCE_REF="${SOURCE_REF:-v$VERSION}"
mkdir -p "$OUT_INPUT"
OUT="$(cd "$OUT_INPUT" && pwd)"
NAME="Privacy-Watch-$VERSION.dmg"
[[ ! -e "$OUT/$NAME" && ! -e "$OUT/$NAME.sha256" ]] || {
  echo "Release output already exists; choose a new directory." >&2; exit 1;
}

/usr/bin/codesign --verify --deep --strict "$APP"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/PrivacyWatch-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
VOLUME="$STAGING/volume"
mkdir -p "$VOLUME/Documentation"
# Copy the already signed app unchanged. Do not rebuild or re-sign it here.
/usr/bin/ditto --norsrc --noextattr "$APP" "$VOLUME/Privacy Watch.app"
ln -s /Applications "$VOLUME/Applications"
cp "$ROOT/Resources/DMG/Read Me First.rtf" "$VOLUME/Read Me First.rtf"
for document in README.md LICENSE COPYRIGHT CHANGELOG.md VALIDATION.md CONTRIBUTING.md SECURITY.md; do
  cp "$ROOT/$document" "$VOLUME/Documentation/$document"
done
/usr/bin/ditto --norsrc --noextattr "$ROOT/docs" "$VOLUME/Documentation/docs"
mkdir -p "$VOLUME/Documentation/.github"
/usr/bin/ditto --norsrc --noextattr "$ROOT/.github/assets" "$VOLUME/Documentation/.github/assets"
cat > "$VOLUME/Documentation/SOURCE.txt" <<EOF
Privacy Watch $VERSION
Copyright (C) 2026 WebKroo
GNU AGPLv3 only (AGPL-3.0-only), without warranty.
See LICENSE and COPYRIGHT in this folder.

Corresponding source, build scripts and tests:
https://github.com/WebKroo/privacy-watch/tree/$SOURCE_REF
Release and corresponding source download:
https://github.com/WebKroo/privacy-watch/releases/tag/$SOURCE_REF

The app bundle is preserved from the supplied signed build. These external
installation documents may be newer than the README inside that app bundle.
The disk image contains no personal activity history or settings.
EOF
/usr/bin/codesign --verify --deep --strict "$VOLUME/Privacy Watch.app"
/usr/bin/hdiutil create -volname "Privacy Watch $VERSION" -srcfolder "$VOLUME" \
  -fs APFS -format UDZO -imagekey zlib-level=9 -nospotlight "$OUT/$NAME"
/usr/bin/hdiutil verify "$OUT/$NAME"
(cd "$OUT" && /usr/bin/shasum -a 256 "$NAME" > "$NAME.sha256")
printf '\nDisk image: %s\nChecksum: %s\n' "$OUT/$NAME" "$OUT/$NAME.sha256"
