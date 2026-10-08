#!/bin/bash
# Verifies the fixture sources are intact (same tree, same SHA-256) and
# reports what arrived in the destination folders (and whether each file is
# a byte-identical copy of some source file).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FX="$ROOT/TestFixtures"
[ -f "$FX/manifest.sha256" ] || { echo "No fixtures. Run scripts/make-test-files.sh first." >&2; exit 2; }
cd "$FX"

fail=0
echo "==> Source checksums"
if out="$(shasum -a 256 -c manifest.sha256 2>&1)"; then
  echo "OK: all $(wc -l < manifest.sha256 | tr -d ' ') source files match their recorded SHA-256"
else
  printf '%s\n' "$out" | grep -v ': OK$' || true
  echo "FAIL: source checksum mismatch or missing file"
  fail=1
fi

echo "==> Source tree"
if diff <(find source -name .DS_Store -prune -o -print | LC_ALL=C sort) manifest.tree; then
  echo "OK: source tree unchanged ($(wc -l < manifest.tree | tr -d ' ') entries)"
else
  echo "FAIL: source tree differs from manifest (lines with < are new, > are missing)"
  fail=1
fi

for d in destination destination-2; do
  echo "==> $d/"
  if [ -z "$(find "$d" -mindepth 1 -not -name .DS_Store -print -quit)" ]; then
    echo "  (empty)"
    continue
  fi
  find "$d" -name .DS_Store -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
    [ "$p" = "$d" ] && continue
    if [ -d "$p" ]; then
      echo "  [dir]  $p"
    else
      h="$(shasum -a 256 "$p" | awk '{print $1}')"
      match="$(awk -v h="$h" '$1==h { $1=""; sub(/^ +/, ""); print; exit }' manifest.sha256)"
      if [ -n "$match" ]; then
        echo "  [file] $p  == copy of $match"
      else
        echo "  [file] $p  (no matching source checksum)"
      fi
    fi
  done
done

if [ "$fail" -eq 0 ]; then
  echo "RESULT: PASS — sources intact"
else
  echo "RESULT: FAIL — see above"
fi
exit "$fail"
