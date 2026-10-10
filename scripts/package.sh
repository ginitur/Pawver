#!/bin/bash
# Builds a clean universal release and packages dist/Pawver-<version>-macOS.{zip,dmg}
# plus SHA256SUMS.txt. Verifies the signature inside both packages.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
NAME="Pawver-$VERSION-macOS"
DIST="$ROOT/dist"
TMP="$ROOT/.scratch/package"

rm -rf "$ROOT/.build/out" "$ROOT/.build/apple" "$ROOT/.build/release" "$TMP"
UNIVERSAL=1 "$ROOT/scripts/build.sh"

rm -f "$DIST/$NAME.zip" "$DIST/$NAME.dmg" "$DIST/SHA256SUMS.txt"
echo "==> zip"
ditto -c -k --keepParent "$DIST/Pawver.app" "$DIST/$NAME.zip"

echo "==> dmg"
mkdir -p "$TMP/stage"
ditto "$DIST/Pawver.app" "$TMP/stage/Pawver.app"
ln -s /Applications "$TMP/stage/Applications"
hdiutil create -volname Pawver -srcfolder "$TMP/stage" -ov -format UDZO "$DIST/$NAME.dmg" >/dev/null

echo "==> checksums"
(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt && cat SHA256SUMS.txt)

echo "==> verify zip"
mkdir -p "$TMP/unzip"
ditto -x -k "$DIST/$NAME.zip" "$TMP/unzip"
codesign --verify --strict --verbose=2 "$TMP/unzip/Pawver.app"
lipo -archs "$TMP/unzip/Pawver.app/Contents/MacOS/Pawver"

echo "==> verify dmg"
mkdir -p "$TMP/mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$TMP/mnt" "$DIST/$NAME.dmg" >/dev/null
trap 'hdiutil detach "$TMP/mnt" >/dev/null 2>&1 || true' EXIT
ls -l "$TMP/mnt"
codesign --verify --strict --verbose=2 "$TMP/mnt/Pawver.app"
hdiutil detach "$TMP/mnt" >/dev/null
trap - EXIT

rm -rf "$TMP"
ls -l "$DIST/$NAME.zip" "$DIST/$NAME.dmg" "$DIST/SHA256SUMS.txt"
echo "==> Packaged $NAME"
