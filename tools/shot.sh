#!/usr/bin/env bash
# Render a still with software Vulkan (lavapipe) under Xvfb. See tools/shot.gd for args.
export VK_ICD_FILENAMES=${SHOT_ICD:-/opt/lavapipe/lvp_icd.json}
unset VK_DRIVER_FILES
export GALLIVM_PERF=${GALLIVM_PERF:-no_aos_sampling} LP_PERF=${LP_PERF:-no_rast_linear}
cd "$(dirname "$0")/.."
exec xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 --rendering-method ${GODOT_RENDERER:-forward_plus} -s tools/shot.gd -- "$@"
