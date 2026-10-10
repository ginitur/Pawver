#!/bin/bash
# Builds dist/Pawver.app using only the Swift toolchain from the
# Command Line Tools (no Xcode). Ad-hoc signed unless SIGN_IDENTITY is set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
BUNDLE_ID="com.weijiaren.Pawver"
DIST="$ROOT/dist"
APP="$DIST/Pawver.app"
IDENTITY="${SIGN_IDENTITY:--}"

echo "==> swift build -c $CONFIG --product Pawver"
swift build -c "$CONFIG" --product Pawver
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Pawver"
[ -x "$BIN" ] || { echo "error: executable not found at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
# Only ever removes the bundle inside this project's dist/ directory.
if [ -d "$APP" ]; then rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pawver"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> plutil -lint"
plutil -lint "$APP/Contents/Info.plist"

echo "==> codesign (identity: $IDENTITY)"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d -r- "$APP" 2>&1 | grep -E "designated" || true

echo "==> Built $APP"
