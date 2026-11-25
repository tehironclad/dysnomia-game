#!/usr/bin/env bash
# Wallet end to end: the real game bridge + the real wallet.html in Chromium with a
# mock EIP-1193 wallet; drives a fair ticket, an arcade credit, a ticket strip (two of its plays
# replayed and verified), personal_sign, a
# rejection, a dropped link, a simulation revert, the wallet test and a closed window.
# Needs: Godot (GODOT=…), node with playwright (+ its Chromium), network to rpc.pulsechain.com.
# Usage: GODOT=/path/to/godot tools/e2e_wallet.sh [--port=48420] [--keep]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import --path . >/dev/null 2>&1 || { echo "import failed"; exit 1; }
exec node tools/e2e_wallet.js --godot="$GODOT" "$@"
