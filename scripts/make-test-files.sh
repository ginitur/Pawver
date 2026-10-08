#!/bin/bash
# Creates a dedicated fixture tree for manual drag tests inside the project:
#   TestFixtures/source/...      files to drag (never modified by FloatShelf)
#   TestFixtures/destination/    empty drop targets
#   TestFixtures/manifest.*      checksums + tree listing for verify-test-files.sh
# Usage: scripts/make-test-files.sh [--force]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FX="$ROOT/TestFixtures"

if [ -e "$FX" ]; then
  if [ "${1:-}" = "--force" ]; then
    case "$FX" in
      "$ROOT/TestFixtures") rm -rf "$FX" ;;
      *) echo "refusing to delete unexpected path: $FX" >&2; exit 1 ;;
    esac
  else
    echo "$FX already exists. Re-run with --force to recreate it." >&2
    exit 1
  fi
fi

SRC="$FX/source"
mkdir -p "$SRC/A/Folder With Spaces/nested" "$SRC/B" "$FX/destination" "$FX/destination-2"

printf 'Report from folder A\n' > "$SRC/A/report.txt"
printf 'Report from folder B — same file name, different content\n' > "$SRC/B/report.txt"
printf '# Notes\n\nFixture for FloatShelf drag tests.\n' > "$SRC/A/notes.md"
printf '中文文件名测试\n' > "$SRC/A/中文 文件.txt"
head -c 262144 /dev/urandom > "$SRC/A/random-256k.bin"
# 1x1 PNG
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 --decode > "$SRC/B/pixel.png"
printf 'inner file 1\n' > "$SRC/A/Folder With Spaces/inner-1.txt"
printf 'inner file 2\n' > "$SRC/A/Folder With Spaces/inner-2.txt"
printf 'deep file\n' > "$SRC/A/Folder With Spaces/nested/deep.txt"

cd "$FX"
find source -name .DS_Store -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 > manifest.sha256
find source -name .DS_Store -prune -o -print | LC_ALL=C sort > manifest.tree

echo "Created fixtures in $FX"
echo "  files:  $(wc -l < manifest.sha256 | tr -d ' ')"
echo "  entries (files+dirs): $(wc -l < manifest.tree | tr -d ' ')"
echo "  empty destinations: destination/, destination-2/"
echo "Run scripts/verify-test-files.sh after testing."
