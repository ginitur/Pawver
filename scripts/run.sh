#!/bin/bash
# Launches dist/FloatShelf.app via LaunchServices and mirrors diagnostics to
# <project>/logs/floatshelf-<timestamp>.log (in addition to os_log).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/FloatShelf.app"
LOG_DIR="$ROOT/logs"

[ -d "$APP" ] || "$ROOT/scripts/build.sh"

if pgrep -x FloatShelf >/dev/null 2>&1; then
  echo "FloatShelf is already running (pid $(pgrep -x FloatShelf | tr '\n' ' ')). Quit it from the menu bar first." >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
open --env "FLOATSHELF_LOG_DIR=$LOG_DIR" "$APP"
echo "Launched $APP"
echo "Log file directory: $LOG_DIR"
echo "Live system log:   /usr/bin/log stream --level debug --style compact --predicate 'subsystem == \"com.weijiaren.FloatShelf\"'"
