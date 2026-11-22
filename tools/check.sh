#!/usr/bin/env bash
# Import the project headlessly, then run the test suite.
# Usage: GODOT=/path/to/godot tools/check.sh [--filter=substring]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import --path . >/dev/null 2>&1 || { echo "import failed"; exit 1; }
"$GODOT" --headless --path . -s res://tools/compile_check.gd | tail -n 20
"$GODOT" --headless --path . -s res://tests/run.gd -- "$@"
