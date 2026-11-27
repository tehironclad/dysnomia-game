#!/bin/sh
# Dysnomia game server on Linux/macOS (docs/SERVER.md). Listens on 127.0.0.1;
# put a tunnel in front of it. Restarts itself if it stops.
#   GODOT=/path/to/godot tools/server.sh [--port=8787] [--name=MyServer]
# Logs: ~/.local/share/godot/app_userdata/Dysnomia/server/server.log (Linux)
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
# Private settings, e.g. the Telegram bridge (docs/SERVER.md 5c): TELEGRAM_BOT_TOKEN=… lines in
# server.local.env at the repo root (git ignores it; keep it chmod 600, never share it).
if [ -f server.local.env ]; then set -a; . ./server.local.env; set +a; fi
"$GODOT" --headless --path . --import >/dev/null 2>&1
while true; do
  "$GODOT" --headless --path . res://scenes/net/game_server.tscn -- "$@"
  echo "server stopped (exit $?); restarting in 5 s (Ctrl+C to quit)"
  sleep 5
done
