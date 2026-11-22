#!/usr/bin/env bash
# Import the project headlessly, then run the test suite.
# Usage: GODOT=/path/to/godot tools/check.sh [--filter=substring]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import --path . >/dev/null 2>&1 || { echo "import failed"; exit 1; }
out=$("$GODOT" --headless --path . -s res://tools/compile_check.gd 2>&1) || { echo "$out" | grep -E "FAIL|ERROR" | head -20; echo "compile check failed"; exit 1; }
if echo "$out" | grep -q "SHADER ERROR"; then echo "$out" | grep -A3 "SHADER ERROR" | head -30; echo "shader compile errors"; exit 1; fi
echo "$out" | grep -E "scripts,"
"$GODOT" --headless --path . -s res://tests/run.gd -- "$@"
