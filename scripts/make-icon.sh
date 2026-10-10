#!/bin/bash
# Generates build/icon/AppIcon.icns from Resources/Brand/pawver-source.png.
# Uses only CoreGraphics (via a Swift script), sips and iconutil. Output is git-ignored.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/Brand/pawver-source.png"
OUT="$ROOT/build/icon"
SET="$OUT/AppIcon.iconset"
rm -rf "$SET"; mkdir -p "$SET"
swift "$ROOT/scripts/make-icon.swift" "$SRC" "$OUT/master-1024.png"
for s in 16 32 128 256 512; do
  sips -s format png -z $s $s "$OUT/master-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -s format png -z $d $d "$OUT/master-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$OUT/AppIcon.icns"
mkdir -p "$ROOT/dist"
cp "$SET/icon_512x512.png" "$ROOT/dist/icon-preview.png"
echo "==> $OUT/AppIcon.icns ($(stat -f %z "$OUT/AppIcon.icns") bytes); preview: dist/icon-preview.png"
