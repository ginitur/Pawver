#!/bin/bash
# Runs the PawverCore unit tests (Swift Testing) under Command Line Tools.
# The explicit macro plugin path works around intermittent
# "plugin for module 'TestingMacros' not found" errors (docs/PLAN.md §1.1).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLUGIN_DIR="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
if [ -d "$PLUGIN_DIR" ]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
else
  swift test "$@"
fi
