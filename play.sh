#!/bin/sh
# Dysnomia on macOS or Linux. Imports new or changed files, then starts the game
# (the game picks its graphics level and renderer for this computer by itself).
# Set GODOT=/path/to/Godot if it lives somewhere else.
cd "$(dirname "$0")" || exit 1
if [ -z "$GODOT" ]; then
  for g in "/Applications/Godot.app/Contents/MacOS/Godot" "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
           "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" "$(command -v godot 2>/dev/null)"; do
    if [ -n "$g" ] && [ -x "$g" ]; then GODOT="$g"; break; fi
  done
fi
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "Godot not found. Put Godot.app in Applications, or run: GODOT=/path/to/Godot ./play.sh"
  exit 1
fi
echo "Importing new or changed files..."
"$GODOT" --headless --path . --import
"$GODOT" --path . "$@"
