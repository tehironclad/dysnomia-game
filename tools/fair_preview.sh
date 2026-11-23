#!/usr/bin/env bash
# Render Affection Fair preview shots with software Vulkan (lavapipe) under Xvfb.
#   tools/fair_preview.sh [preset] [outdir]    presets: all night noon rides rocket wheel drop carousel
export VK_ICD_FILENAMES=${SHOT_ICD:-/opt/lavapipe/lvp_icd.json}
unset VK_DRIVER_FILES
export GALLIVM_PERF=${GALLIVM_PERF:-no_aos_sampling} LP_PERF=${LP_PERF:-no_rast_linear}
cd "$(dirname "$0")/.."
exec xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 --fixed-fps 30 -s tools/fair_preview.gd -- "$@"
