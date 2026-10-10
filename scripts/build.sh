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

# UNIVERSAL=1 builds arm64 + x86_64 (used by scripts/package.sh); default is the host arch.
ARCH_ARGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_ARGS=(--arch arm64 --arch x86_64); fi
echo "==> swift build -c $CONFIG --product Pawver ${ARCH_ARGS[*]-}"
swift build -c "$CONFIG" --product Pawver ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"
BIN="$BIN_DIR/Pawver"
[ -x "$BIN" ] || { echo "error: executable not found at $BIN" >&2; exit 1; }

echo "==> App icon (scripts/make-icon.sh)"
ICNS="$ROOT/build/icon/AppIcon.icns"
if [ ! -f "$ICNS" ] || [ "$ROOT/Resources/Brand/pawver-source.png" -nt "$ICNS" ] || [ "$ROOT/scripts/make-icon.swift" -nt "$ICNS" ]; then
  "$ROOT/scripts/make-icon.sh"
else
  echo "    up to date: $ICNS"
fi

echo "==> Assembling $APP"
# Only ever removes the bundle inside this project's dist/ directory.
if [ -d "$APP" ]; then rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pawver"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> plutil -lint"
plutil -lint "$APP/Contents/Info.plist"

echo "==> codesign (identity: $IDENTITY)"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d -r- "$APP" 2>&1 | grep -E "designated" || true

# Nudge Finder/LaunchServices to drop a cached (old or generic) icon.
touch "$APP"
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/Pawver")"
echo "==> Built $APP"
