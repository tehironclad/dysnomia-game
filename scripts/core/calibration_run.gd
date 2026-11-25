class_name CalibrationRun
extends Node
## Renders the current scene at a few quality levels and measures each (the
## decisions are GraphicsCalibration's). V-Sync is off while measuring, so a
## frame's time is its real cost; the window's render scale is held at each
## level's nominal value (Config.calibration_level). A few seconds in all; the
## warp's loading card (or a small "Measuring…" line, from F2) covers it.
## Emits `step(text, fraction)` as it goes and `finished(level, target_fps, results)`.

signal step(text: String, fraction: float)
signal finished(level: int, target_fps: int, results: Dictionary)

const SETTLE_S := 0.7      ## after a level change: pipelines compile, buffers reallocate
const SETTLE_FRAMES := 6
const MEASURE_S := 1.2
const MEASURE_FRAMES := 8
const STEP_CAP_S := 8.0    ## a very slow machine: measure what fits, then decide

var start_level := 2
var top := 4

var _level := 2
var _results := {}
var _phase := 0            ## 0 settle · 1 measure · 2 done
var _t := 0.0
var _frames := 0
var _samples: Array = []
var _gpu: Array = []
var _last_us := 0
var _target_ms := 1000.0 / 60.0
var _vsync_was := DisplayServer.VSYNC_ENABLED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vsync_was = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_begin(start_level)


func _begin(level: int) -> void:
	_level = level
	_phase = 0
	_t = 0.0
	_frames = 0
	_samples.clear()
	_gpu.clear()
	Config.calibration_level(level)
	step.emit("Measuring %s…" % String(Config.QUALITY_NAMES[level]).split(" ")[0], float(_results.size()) / float(GraphicsCalibration.MAX_STEPS))


func _process(delta: float) -> void:
	if _phase == 2:
		return
	var now := Time.get_ticks_usec()
	var dt_ms := (now - _last_us) / 1000.0 if _last_us > 0 else delta * 1000.0
	_last_us = now
	_t += delta
	_frames += 1
	if _phase == 0:
		if (_t >= SETTLE_S and _frames >= SETTLE_FRAMES) or _t >= STEP_CAP_S * 0.5:
			_phase = 1
			_t = 0.0
			_frames = 0
		return
	_samples.append(dt_ms)
	var g := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if g > 0.0:
		_gpu.append(g)
	if (_t < MEASURE_S or _frames < MEASURE_FRAMES) and _t < STEP_CAP_S:
		return
	var cost := median(_samples)
	_results[_level] = cost
	var n := GraphicsCalibration.next(_level, cost, _results, _target_ms, top)
	print("[Calibration] %s: %.1f ms a frame (GPU %.1f ms, %d frames)" % [Config.QUALITY_NAMES[_level], cost, median(_gpu), _samples.size()])
	if bool(n["done"]):
		_finish(int(n["level"]))
	else:
		_begin(int(n["level"]))


func _finish(level: int) -> void:
	_phase = 2
	DisplayServer.window_set_vsync_mode(_vsync_was)
	var fps := GraphicsCalibration.target_fps_for(level, _results, _target_ms)
	step.emit("Done", 1.0)
	finished.emit(level, fps, _results.duplicate())
	queue_free()


static func median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := xs.duplicate()
	s.sort()
	return float(s[s.size() / 2])
