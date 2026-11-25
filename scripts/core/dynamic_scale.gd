class_name DynamicScale
extends RefCounted
## Dynamic resolution: the 3D render scale that holds a target frame time. Pure
## (fed numbers, returns decisions; Config applies them), so tests drive it.
##
## Each frame `feed(dt, frame_ms, gpu_ms)`:
## - With GPU timing (Forward+ / Mobile: the viewport's measured GPU time), the cost is
##   the GPU's own time per frame, which is what resolution changes. A CPU-bound frame
##   (slow frame, idle GPU) never lowers the scale: fewer pixels wouldn't help.
##   Steps are proportional: pixels ∝ scale², so scale × √(target / cost), at most
##   MAX_STEP per change.
## - Without GPU timing (Compatibility), the cost is the frame time. With V-Sync the
##   frame time can't show headroom, so raising is a probe: one STEP after UP_HOLD_S × 3
##   at the target; if a drop follows within PROBE_S, that scale becomes a ceiling for
##   CEILING_S.
## The scale moves at most once per COOL_S, in multiples of QUANTUM (each change
## reallocates the render buffers).

const QUANTUM := 0.05
const MAX_STEP := 0.10
const DOWN_AT := 1.08     ## cost over target × this → lower
const UP_AT := 0.72       ## GPU cost under target × this for UP_HOLD_S → raise
const UP_HOLD_S := 2.0
const COOL_S := 1.0
const EMA := 0.12          ## smoothing per frame
const PROBE_S := 6.0
const CEILING_S := 30.0
const WARMUP_FRAMES := 20  ## frames ignored after a (re)configure: pipelines compile then

var scale := 1.0
var min_scale := 0.5
var max_scale := 1.0
var target_ms := 1000.0 / 60.0
var cost_ms := 0.0         ## the smoothed cost the last decision used
var gpu_timed := false

var _ema := -1.0
var _cool := 0.0
var _ok_t := 0.0
var _since_raise := 999.0
var _ceiling := 1.0
var _ceiling_t := 0.0
var _skip := WARMUP_FRAMES


## Range and start; resets the history (a level change, a new scene).
func configure(p_min: float, p_max: float, start: float, target_fps: float) -> void:
	min_scale = clampf(p_min, 0.25, 1.0)
	max_scale = clampf(maxf(p_max, min_scale), min_scale, 2.0)
	scale = clampf(snap(start), min_scale, max_scale)
	target_ms = 1000.0 / maxf(target_fps, 10.0)
	_ema = -1.0
	_cool = COOL_S
	_ok_t = 0.0
	_since_raise = 999.0
	_ceiling = max_scale
	_ceiling_t = 0.0
	_skip = WARMUP_FRAMES


static func snap(s: float) -> float:
	return snappedf(s, QUANTUM)


## One frame. Returns true when `scale` changed.
func feed(dt: float, frame_ms: float, gpu_ms: float) -> bool:
	if _skip > 0:
		_skip -= 1
		return false
	gpu_timed = gpu_ms > 0.0
	var cost := gpu_ms if gpu_timed else frame_ms
	if cost <= 0.0 or frame_ms > 1000.0:
		return false  # a stall (loading, alt-tab) says nothing about the steady cost
	_ema = cost if _ema < 0.0 else lerpf(_ema, cost, EMA)
	cost_ms = _ema
	_cool -= dt
	_since_raise += dt
	if _ceiling_t > 0.0:
		_ceiling_t -= dt
		if _ceiling_t <= 0.0:
			_ceiling = max_scale
	var over := _ema > target_ms * DOWN_AT
	if gpu_timed and over and frame_ms > 0.0 and gpu_ms < frame_ms * 0.6 and frame_ms > target_ms * DOWN_AT:
		over = gpu_ms > target_ms * DOWN_AT  # CPU-bound: resolution isn't the problem
	if over:
		_ok_t = 0.0
		if _cool > 0.0 or scale <= min_scale + 0.001:
			return false
		var want := scale * sqrt(target_ms / _ema) if gpu_timed else scale - QUANTUM
		var ns := clampf(snap(maxf(want, scale - MAX_STEP)), min_scale, max_scale)
		if ns >= scale:
			ns = maxf(min_scale, scale - QUANTUM)
		if _since_raise < PROBE_S:
			_ceiling = ns  # the last raise was too much: stay under it a while
			_ceiling_t = CEILING_S
		return _change(ns)
	var roomy := (_ema < target_ms * UP_AT) if gpu_timed else (_ema <= target_ms * 1.03)
	if roomy:
		_ok_t += dt
	else:
		_ok_t = 0.0
	var hold := UP_HOLD_S if gpu_timed else UP_HOLD_S * 3.0
	if _ok_t >= hold and _cool <= 0.0 and scale < minf(max_scale, _ceiling) - 0.001:
		var up := scale * sqrt(target_ms * 0.85 / _ema) if gpu_timed else scale + QUANTUM
		var ns2 := clampf(snap(minf(up, scale + MAX_STEP)), min_scale, minf(max_scale, _ceiling))
		if ns2 <= scale:
			ns2 = minf(scale + QUANTUM, minf(max_scale, _ceiling))
		_ok_t = 0.0
		_since_raise = 0.0
		return _change(ns2)
	return false


func _change(s: float) -> bool:
	if is_equal_approx(s, scale):
		return false
	scale = s
	_cool = COOL_S
	_ema = -1.0  # the new scale's cost is a new measurement
	_skip = 3
	return true


## Nothing left to give: at the floor and still over the target.
func pinned_low() -> bool:
	return scale <= min_scale + 0.001 and cost_ms > target_ms * DOWN_AT


## At the top of its range (a level step up is the next thing).
func at_max() -> bool:
	return scale >= max_scale - 0.001


## The render scale for a window, relative to its pixel count: each level has a
## budget of rendered pixels (megapixels), so a 4K or Retina screen renders the same
## work as 1080p at that level and FSR/bilinear brings it up to the window. The UI
## (canvas) is never scaled by this. Pure.
static func for_window(nominal: float, budget_mp: float, window_px: Vector2i) -> float:
	var px := float(maxi(window_px.x, 1)) * float(maxi(window_px.y, 1)) / 1.0e6
	if budget_mp <= 0.0 or px <= 0.0:
		return nominal
	var s := sqrt(budget_mp / px)
	return nominal if s >= nominal else clampf(snap(s), 0.25, nominal)
