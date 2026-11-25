#!/usr/bin/env bash
# icon.svg → a Windows .ico (16, 32, 48, 256) for Dysnomia.exe and the installer.
#   installer/windows/make_icon.sh icon.svg build/icon/dysnomia.ico
# Needs rsvg-convert (apt librsvg2-bin) and ImageMagick's convert (apt imagemagick).
set -euo pipefail
svg="${1:?usage: make_icon.sh <icon.svg> <out.ico>}"
out="${2:?usage: make_icon.sh <icon.svg> <out.ico>}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for s in 16 32 48 256; do
  rsvg-convert -w "$s" -h "$s" -o "$tmp/$s.png" "$svg"
done
mkdir -p "$(dirname "$out")"
convert "$tmp/16.png" "$tmp/32.png" "$tmp/48.png" "$tmp/256.png" "$out"
