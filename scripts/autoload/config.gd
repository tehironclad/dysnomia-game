extends Node
## Autoload "Config": player settings, saved to user://settings.cfg. Every
## setting here is applied somewhere (WP 7.4); apply() pushes them to the
## display, the audio buses and any registered scene (environment, sun,
## camera) and emits `applied`.
##
## Automatic graphics (2026-11-25, docs/BUILDING.md "Graphics levels"):
## 1. recommend(): the hardware's name, type, cores and RAM give a first guess (level + renderer);
## 2. calibration (CalibrationRun + GraphicsCalibration): on the first territory arrival, behind
##    the warp's card, the scene is rendered at a few levels with V-Sync off and the level that
##    holds the frame-rate target is kept (Ultra only with lots of headroom);
## 3. in play, dynamic resolution (DynamicScale) moves the 3D render scale within the level's
##    range to hold the target; only when it has nothing left does a 10 s window step the level
##    down (decide()), and with headroom at full scale, up (never past auto_top).
## The render scale is relative to the window's pixels (a 4K or Retina screen renders the same
## work as 1080p at that level; the UI is never scaled).

signal applied
## The automatic graphics picked or changed a level (a line for the HUD).
signal auto_changed(text: String)

# Graphics
var graphics_quality: int = 2  # 0 potato · 1 low · 2 medium · 3 high · 4 ultra (Medium until the player picks)
const RENDER_DEFAULT := 1300.0  # a 724 m territory's diagonal is 1024 m, plus the neighbours' ground
const OLD_RENDER_DEFAULT := 900.0  # the default before territories grew from 512 m to 724 m
var render_distance: float = RENDER_DEFAULT  # camera far plane, metres (a level may shorten it: preset "far")
## Pick the level from the hardware on first launch, measure it, then follow the frame rate.
var auto_quality := true
## The renderer the hardware (or calibration) asks for ("forward_plus" | "gl_compatibility" | "mobile"; "" until detected).
var renderer_pref := ""
var detected := ""  # what was found, for the settings menu
var last_note := ""  # the latest auto change, for a HUD that arrives after it
## Dynamic resolution: the 3D render scale moves within the level's range to hold the target frame rate.
var dynamic_resolution := true
## Frame-rate target: 0 = automatic (60, or 30 where calibration found even Potato can't hold 60).
var target_fps_setting := 0
var target_fps_auto := 60
## Performance mode: frame rate first (Low at most; resolution drops before frames do).
var performance_mode := false
## Calibration: the version it last ran at (0 = never), and per renderer what it measured.
const CALIB_VERSION := 1
var calibrated := 0
var calib_records := {}  # renderer → {"level": int, "cost_ms": float, "fps": int}
var calib_note := ""     # the last calibration's one-line result, for F2
## The highest level the automatic follow may reach: High, or Ultra if calibration measured lots of headroom.
var auto_top := 3
## Other display adapters in this PC (Windows), and a hint when the game runs on the weaker one.
var hybrid_hint := ""

# Controls
var mouse_sensitivity: float = 0.003
var invert_y: bool = false
var fov: float = 70.0

# Audio (linear 0..1; buses "Music" and "SFX" are created under Master)
var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8

# Display
var fullscreen: bool = false
var vsync: bool = true

# Chain
var rpc_url: String = "https://rpc.pulsechain.com"
## Optional accelerator (chain-backed site endpoints). The game works without it.
var site_api_base: String = Contracts.DEFAULT_SITE_API
var site_api_enabled: bool = true

# Wallet relay (local HTTP + WebSocket)
var wallet_bridge_port: int = 38420
## The browser the wallet window opens in (full path to its .exe); blank = automatic:
## the default browser when it is Chrome/Brave/Edge, else the default browser itself.
var wallet_browser: String = ""

# Updates: the release the player said "Later" to on the front door (UpdateCheck)
var update_dismissed: String = ""

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Potato (no GPU)", "Low", "Medium", "High", "Ultra"]
## What each quality level does. Detail only: every level shows the same world (content follows
## territory state, never the level).
##   scale / scale_min / scale_max: 3D render scale (nominal, and the dynamic range; FSR1 upscales on
##     Forward+/Mobile, bilinear on Compatibility) · budget_mp: rendered megapixels the scale is capped
##     to on big windows (4K, Retina) · iter: fractal iterations on the ground · simple_sky: stars/Eris/sun
##     only · detail: regolith + city lights on the ground · warp_iter: the dive · shadow_distance /
##     shadow_splits: the sun's shadow reach and cascades · far: the camera's far plane cap (m; depth fog
##     hides the cut where `fog_far`) · crowd / particles: share of ambient visitors and particle counts ·
##     mesh_step: ground mesh spacing (m; the collider stays 1 m) · nb_step: the neighbours' ground mesh
##     step (DetailCull's screen-size factors per level: K_BY_QUALITY in detail_cull.gd)
## perf 2026-11-24: at the old 260 m × 4 splits the whole fair, off screen behind you at the Core, cast
## into the shadow maps; High is 120 m, Medium 90 m in 2 splits. 2026-11-25: the low levels lighter
## (MSAA was never on below High; now also shorter view, coarser ground, fewer visitors and particles).
const QUALITY_PRESETS: Array[Dictionary] = [
	{"ssao": false, "ssil": false, "glow": false, "volumetric_fog": false, "shadow_distance": 60.0, "shadow_splits": 2, "msaa": Viewport.MSAA_DISABLED,
		"scale": 0.5, "scale_min": 0.4, "scale_max": 0.67, "budget_mp": 0.55, "iter": 24, "shadows": false, "simple_sky": true, "detail": 0.0, "warp_iter": 40,
		"far": 800.0, "fog_far": true, "crowd": 0.35, "particles": 0.35, "mesh_step": 4, "nb_step": 2, "shadow_atlas": 1024},
	{"ssao": false, "ssil": false, "glow": true, "volumetric_fog": false, "shadow_distance": 90.0, "shadow_splits": 2, "msaa": Viewport.MSAA_DISABLED,
		"scale": 0.67, "scale_min": 0.5, "scale_max": 0.85, "budget_mp": 1.0, "iter": 40, "shadows": false, "simple_sky": false, "detail": 0.6, "warp_iter": 70,
		"far": 1000.0, "fog_far": true, "crowd": 0.5, "particles": 0.5, "mesh_step": 4, "nb_step": 2, "shadow_atlas": 1024},
	{"ssao": false, "ssil": false, "glow": true, "volumetric_fog": false, "shadow_distance": 90.0, "shadow_splits": 2, "msaa": Viewport.MSAA_DISABLED,
		"scale": 0.8, "scale_min": 0.6, "scale_max": 1.0, "budget_mp": 2.1, "iter": 64, "shadows": true, "simple_sky": false, "detail": 1.0, "warp_iter": 110,
		"far": 0.0, "fog_far": false, "crowd": 0.75, "particles": 0.75, "mesh_step": 2, "nb_step": 1},
	{"ssao": true, "ssil": true, "glow": true, "volumetric_fog": false, "shadow_distance": 120.0, "shadow_splits": 4, "msaa": Viewport.MSAA_2X,
		"scale": 1.0, "scale_min": 0.7, "scale_max": 1.0, "budget_mp": 3.7, "iter": 96, "shadows": true, "simple_sky": false, "detail": 1.0, "warp_iter": 160,
		"far": 0.0, "fog_far": false, "crowd": 1.0, "particles": 1.0, "mesh_step": 2, "nb_step": 1},
	{"ssao": true, "ssil": true, "glow": true, "volumetric_fog": true, "shadow_distance": 320.0, "shadow_splits": 4, "msaa": Viewport.MSAA_4X,
		"scale": 1.0, "scale_min": 0.85, "scale_max": 1.0, "budget_mp": 8.3, "iter": 128, "shadows": true, "simple_sky": false, "detail": 1.0, "warp_iter": 200,
		"far": 0.0, "fog_far": false, "crowd": 1.0, "particles": 1.0, "mesh_step": 2, "nb_step": 1, "far_min": 1800.0, "shadow_atlas": 8192, "ultra_fx": true},
]

## Frame-rate follow: a 10 s window, after a 12 s settle on every new scene.
const WINDOW_S := 10.0
const SETTLE_S := 12.0
const MAX_CHANGES := 4
const AUTO_TOP := 3  # auto never goes past High unless calibration measured lots of headroom (auto_top)
const PERFORMANCE_TOP := 1  # performance mode: Low at most
## A relaunch by the automatic graphics marks itself, so its --rendering-method isn't taken for the player's choice.
const AUTO_RENDERER_ARG := "--auto-renderer"

var _mon_time := 0.0
var _mon_frames := 0
var _settle := SETTLE_S
var _changes := 0
var _went_down := false
var _explicit_quality := false
var _explicit_renderer := false
var _first_run := false

var dyn := DynamicScale.new()
var fps_now := 0.0       ## smoothed frames per second (interactive runs)
var frame_ms_now := 0.0  ## smoothed frame time
var gpu_ms_now := 0.0    ## smoothed GPU time (0 where the renderer doesn't time it)
var _last_us := 0
var _cal_level := -1     ## the level a calibration is measuring (-1: none)
var _calibration: CalibrationRun
var _dyn_ok := false     ## the dynamic range is configured for the current level/window
var _scale_now := 1.0

var _terrain_material: ShaderMaterial
var _sky_material: ShaderMaterial
var _environment: Environment
var _sun: DirectionalLight3D
var _outdoor := false
var _fog_mode := 0
var _fog_density := 0.0
var _hybrid_thread: Thread


func _ready() -> void:
	_first_run = not FileAccess.file_exists(SETTINGS_PATH)
	load_settings()
	# `-- --quality=0` (Potato) … 4 (Ultra) on the command line: applied and saved, and fixed for this session.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			graphics_quality = clampi(int(a.substr(10)), 0, QUALITY_NAMES.size() - 1)
			_explicit_quality = true
			save_settings()
	var args := OS.get_cmdline_args()
	_explicit_renderer = (args.has("--rendering-method") or args.has("--rendering-driver")) \
		and not OS.get_cmdline_user_args().has(AUTO_RENDERER_ARG)
	_ensure_buses()
	if _interactive():
		var rec := recommend(RenderingServer.get_video_adapter_type(), RenderingServer.get_video_adapter_name(),
			OS.get_processor_count(), float(OS.get_memory_info().get("physical", 0)) / 1073741824.0,
			RenderingServer.get_current_rendering_method())
		detected = rec["why"]
		if auto_quality and not _explicit_quality and (_first_run or renderer_pref == ""):
			graphics_quality = rec["quality"]
			renderer_pref = rec["renderer"]
			calibrated = 0  # measure it on the first arrival
			save_settings()
			_note("Graphics set to %s for this PC (%s); measuring on arrival. F2 to change." % [QUALITY_NAMES[graphics_quality], detected])
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		# (Not again from a relaunch of ours: if the renderer still differs, it couldn't start; carry on.)
		if auto_quality and not _explicit_renderer and renderer_pref != "" and renderer_pref != RenderingServer.get_current_rendering_method() \
				and not OS.get_cmdline_user_args().has(AUTO_RENDERER_ARG):
			_relaunch.call_deferred(renderer_pref)
			return
		get_viewport().size_changed.connect(func(): _dyn_ok = false; apply())
		if OS.get_name() == "Windows":
			_hybrid_thread = Thread.new()
			_hybrid_thread.start(_list_adapters)
	apply()


## A real window with a player at it (not the headless tests or a -s tool script).
func is_interactive() -> bool:
	return _interactive()


func _interactive() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var args := OS.get_cmdline_args()
	return not (args.has("-s") or args.has("--script"))


## Starts the game again with another renderer (the renderer can't change
## while running), then quits this one.
func _relaunch(method: String) -> void:
	# An exported game (a release template) refuses --path and aborts, so only a run
	# from the project folder (the editor binary) passes it.
	var args: Array = relaunch_args(method, OS.has_feature("template"), ProjectSettings.globalize_path("res://"))
	var user := OS.get_cmdline_user_args()
	if not user.has(AUTO_RENDERER_ARG):
		user.append(AUTO_RENDERER_ARG)  # the new process knows its --rendering-method was ours, not the player's
	args.append("--")
	args.append_array(user)
	if OS.create_process(OS.get_executable_path(), PackedStringArray(args)) > 0:
		get_tree().quit()
	else:
		apply()  # couldn't start it: carry on as we are


## Pure: the command line for a relaunch with another renderer. `exported` = an
## exported build (feature "template"), which aborts on --path; the editor binary needs it.
static func relaunch_args(method: String, exported: bool, project_dir: String) -> Array:
	if exported:
		return ["--rendering-method", method]
	return ["--path", project_dir, "--rendering-method", method]


## The level and renderer the hardware asks for: only a first guess, which the
## calibration then measures. Pure (tests call it).
##   adapter_type: RenderingDevice.DeviceType (0 other, 1 integrated, 2 discrete, 3 virtual, 4 CPU)
static func recommend(adapter_type: int, adapter: String, cores: int, ram_gb: float, method: String) -> Dictionary:
	var name := adapter.to_lower()
	var kinds := ["other", "integrated GPU", "dedicated GPU", "virtual GPU", "software rendering"]
	var kind: String = kinds[adapter_type] if adapter_type >= 0 and adapter_type < kinds.size() else "unknown GPU"
	var q := 2
	var renderer := "forward_plus"
	var software := adapter_type == 4
	for s in ["llvmpipe", "softpipe", "lavapipe", "swiftshader", "microsoft basic render", "gdi generic"]:
		if name.contains(s):
			software = true
	var apu_strong := RegEx.create_from_string("\\b(6[68]0m|7[68]0m|8[89]0m)\\b")
	if software:
		kind = "software rendering"
		q = 0
		renderer = "gl_compatibility"
	elif name.contains("apple m"):
		# Apple silicon reports as integrated, but its GPUs are strong: Medium, High for the Pro/Max/Ultra parts.
		kind = "Apple silicon"
		q = 3 if (name.contains("pro") or name.contains("max") or name.contains("ultra")) else 2
	elif apu_strong.search(name):
		# AMD's RDNA2/3 APUs (680M, 780M, 890M): a real mid-range GPU inside the CPU.
		kind = "integrated GPU"
		q = 2
	elif adapter_type == 1 or (method == "gl_compatibility" and adapter_type == 0 and name.contains("intel")):
		# Older Intel HD/UHD chips (Gen9, HD 520/620/630, UHD 620/630): the lightweight renderer at Potato.
		# Newer iGPUs (Iris Xe, Arc, AMD Vega/Radeon Graphics) cope with Low.
		if name.contains("intel") and (name.contains("hd graphics") or name.contains("uhd graphics")):
			q = 0
			renderer = "gl_compatibility"
		else:
			q = 1
		kind = "integrated GPU"
	elif adapter_type == 2 or name.contains("nvidia") or name.contains("geforce") or name.contains("quadro") or name.contains("radeon rx") or name.contains("arc a"):
		kind = "dedicated GPU"
		var strong := RegEx.create_from_string("rtx\\s*(20[6-8]0|30[6-9]0|40[6-9]0|50[6-9]0)|rx\\s*(6[7-9]00|7[6-9]00|9[0-9]{3})|arc\\s*a7[0-9]0")
		var weak := RegEx.create_from_string("gt\\s*[0-9]{3,4}\\b|gtx\\s*[67][0-9]{2}\\b|\\br[57]\\s|mx\\s*[0-9]{3}|quadro\\s*[kp]?[0-9]{3,4}m?\\b|quadro\\s*m[0-9]{3,4}\\b")
		if strong.search(name):
			q = 3
		elif weak.search(name):
			q = 1
		else:
			q = 2
	elif adapter_type == 3:
		q = 1
	if ram_gb > 0.0 and ram_gb < 6.0:
		q = mini(q, 1)
	if cores > 0 and cores <= 2:
		q = mini(q, 0)
	var why := "%s%s · %d threads · %.0f GB" % [adapter if adapter != "" else "unknown GPU", "" if kind == "" else " (%s)" % kind, cores, ram_gb]
	return {"quality": q, "renderer": renderer, "why": why}


## The frame-rate follow, one window at a time. Pure (tests call it).
## Returns the new level (or the same one). Dynamic resolution acts first: a level
## goes down only when the render scale is at its floor (`scale_low`) and the frame
## rate is under ¾ of the target, or at once under half of it; up only with the scale
## at its top (`scale_full`), the target held and the GPU and CPU each under half the frame.
static func decide(q: int, fps: float, gpu_ms: float, cpu_ms: float, went_down: bool,
		target_fps: float = 60.0, scale_low: bool = false, scale_full: bool = true, top: int = AUTO_TOP) -> int:
	var budget := 1000.0 / maxf(target_fps, 10.0)
	if q > 0 and (fps < target_fps * 0.5 or (scale_low and fps < target_fps * 0.75)):
		return q - 1
	if not went_down and q < top and scale_full and fps >= target_fps * 0.92 and gpu_ms > 0.0 \
			and gpu_ms < budget * 0.33 and cpu_ms < budget * 0.42:
		return q + 1
	return q


## The level in effect: the setting, capped by performance mode, or the one a calibration measures.
func level() -> int:
	if _cal_level >= 0:
		return _cal_level
	var q := clampi(graphics_quality, 0, QUALITY_PRESETS.size() - 1)
	return mini(q, PERFORMANCE_TOP) if performance_mode else q


func target_fps() -> int:
	if target_fps_setting > 0:
		return target_fps_setting
	return target_fps_auto


func preset() -> Dictionary:
	return QUALITY_PRESETS[level()]


## How many of `n` ambient things (visitors, dancers, regulars) this level shows. Never below `floor_n`.
func crowd(n: int, floor_n: int = 0) -> int:
	return maxi(floor_n, int(round(n * float(preset().get("crowd", 1.0)))))


## A particle emitter's amount at this level (≥ 1).
func particles(n: int) -> int:
	return maxi(1, int(round(n * float(preset().get("particles", 1.0)))))


## The camera's far plane: the player's render distance, capped by the level.
func far_m() -> float:
	var p := preset()
	var cap := float(p.get("far", 0.0))
	var f := render_distance if cap <= 0.0 else minf(render_distance, cap)
	return maxf(f, float(p.get("far_min", 0.0)))


## The 3D render scale this level asks for in this window (nominal, before dynamic resolution).
func nominal_scale(lv: int = -1) -> float:
	var p: Dictionary = QUALITY_PRESETS[clampi(level() if lv < 0 else lv, 0, QUALITY_PRESETS.size() - 1)]
	return DynamicScale.for_window(float(p["scale"]), float(p["budget_mp"]), _window_px())


func _window_px() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(1920, 1080)
	return DisplayServer.window_get_size()


func render_scale() -> float:
	return _scale_now


## Tools (tools/calibrate.gd) turn the in-play follow on in a -s run, under xvfb.
var follow_in_tools := false


func _process(delta: float) -> void:
	if not _interactive() and not follow_in_tools:
		return
	var now := Time.get_ticks_usec()
	var dt_ms := (now - _last_us) / 1000.0 if _last_us > 0 else delta * 1000.0
	_last_us = now
	var rid := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	if dt_ms < 1000.0:
		frame_ms_now = dt_ms if frame_ms_now <= 0.0 else lerpf(frame_ms_now, dt_ms, 0.05)
		gpu_ms_now = gpu if gpu_ms_now <= 0.0 else lerpf(gpu_ms_now, gpu, 0.05)
		fps_now = 1000.0 / maxf(frame_ms_now, 0.1)
	if _calibration != null or not is_instance_valid(_environment):
		return
	if (not DisplayServer.window_is_focused() and not follow_in_tools) or get_tree().paused:
		_mon_time = 0.0
		_mon_frames = 0
		return
	# Dynamic resolution: every frame, within the level's range.
	if dynamic_resolution and (auto_quality or performance_mode):
		if not _dyn_ok:
			_configure_dynamic()
		if dyn.feed(delta, dt_ms, gpu):
			_set_scale(dyn.scale)
	# The level follow: 10 s windows after a settle.
	if not auto_quality or _explicit_quality or _changes >= MAX_CHANGES:
		return
	if _settle > 0.0:
		_settle -= delta
		return
	_mon_time += delta
	_mon_frames += 1
	if _mon_time < WINDOW_S:
		return
	var fps := _mon_frames / _mon_time
	_mon_time = 0.0
	_mon_frames = 0
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var dyn_on := dynamic_resolution
	var top := mini(auto_top, PERFORMANCE_TOP) if performance_mode else auto_top
	var q := decide(graphics_quality, fps, gpu, cpu, _went_down, float(target_fps()),
		dyn.pinned_low() if dyn_on else true, dyn.at_max() if dyn_on else true, top)
	if performance_mode and q > PERFORMANCE_TOP:
		q = graphics_quality
	if q != graphics_quality:
		var down := q < graphics_quality
		_went_down = _went_down or down
		graphics_quality = q
		_changes += 1
		_settle = SETTLE_S
		save_settings()
		apply()
		_note("Graphics %s to %s (%.0f fps). F2 to change." % ["lowered" if down else "raised", QUALITY_NAMES[q], fps])
	elif graphics_quality == 0 and target_fps_setting == 0 and target_fps_auto > 30 and fps < 45.0 and (not dyn_on or dyn.pinned_low()):
		# Even Potato at its lowest resolution can't hold 60 here: hold a steady 30 instead.
		target_fps_auto = 30
		_dyn_ok = false
		save_settings()
		_note("This PC holds 30 fps best: the frame-rate target is now 30. F2 to change.")
	elif graphics_quality == 0 and fps < 14.0 and RenderingServer.get_current_rendering_method() != "gl_compatibility" and renderer_pref != "gl_compatibility":
		renderer_pref = "gl_compatibility"
		_changes = MAX_CHANGES
		save_settings()
		_note("Still slow at Potato (%.0f fps): the next launch uses the lightweight renderer." % fps)


func _configure_dynamic() -> void:
	var p := preset()
	var nom := nominal_scale()
	var px := _window_px()
	var lo := minf(float(p["scale_min"]), nom)
	var hi := maxf(nom, DynamicScale.for_window(float(p["scale_max"]), float(p["budget_mp"]) * 1.5, px))
	dyn.configure(lo, hi, nom, float(target_fps()))
	_dyn_ok = true


func _set_scale(sc: float) -> void:
	_scale_now = sc
	var vp := get_viewport()
	if vp == null or DisplayServer.get_name() == "headless":
		return
	# FSR 1 upscales on Forward+ and Mobile (≈ 1–2 ms on an iGPU at 1080p, much sharper than
	# bilinear); the Compatibility renderer has bilinear only, and so does software rendering
	# (its two FSR passes over the whole window cost more than they save there).
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (sc < 1.0 and _fsr_ok()) else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = sc


func _fsr_ok() -> bool:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return false
	return RenderingServer.get_video_adapter_type() != RenderingDevice.DEVICE_TYPE_CPU \
		and not RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe")


func _note(text: String) -> void:
	last_note = text
	auto_changed.emit(text)


## A scene registers what the graphics settings act on (territories do). `outdoor`:
## the level's view distance may be shortened there, with depth fog over the cut.
func register_scene(env: Environment, sun: DirectionalLight3D, outdoor: bool = false) -> void:
	_environment = env
	_sun = sun
	_outdoor = outdoor
	if env:
		_fog_mode = env.fog_mode
		_fog_density = env.fog_density
	_settle = SETTLE_S  # loading hitches aren't the game's speed
	_mon_time = 0.0
	_mon_frames = 0
	_dyn_ok = false
	apply()


## The territory's ground shader: its fractal iteration count follows quality.
func register_terrain(m: ShaderMaterial) -> void:
	_terrain_material = m
	apply()


func register_sky(m: ShaderMaterial) -> void:
	_sky_material = m
	apply()


## Cameras read fov / render distance from here.
func apply_camera(cam: Camera3D) -> void:
	if cam:
		cam.fov = fov
		cam.far = far_m()


# --- Calibration -----------------------------------------------------------------------

## True when the next territory arrival should measure this computer (first launch,
## a new calibration version, a renderer trial, or Recalibrate). Interactive runs only.
func calibration_due() -> bool:
	return _interactive() and auto_quality and not _explicit_quality and calibrated < CALIB_VERSION


## Starts measuring in the current scene (the warp's card covers it; from F2 the world shows).
## Returns the run (signals `step` and `finished`), or null if one is running already.
func calibrate() -> CalibrationRun:
	if _calibration != null:
		return null
	_calibration = CalibrationRun.new()
	_calibration.name = "CalibrationRun"
	_calibration.start_level = mini(graphics_quality, PERFORMANCE_TOP) if performance_mode else graphics_quality
	_calibration.top = PERFORMANCE_TOP if performance_mode else 4
	_calibration.finished.connect(_on_calibrated)
	add_child(_calibration)
	return _calibration


func is_calibrating() -> bool:
	return _calibration != null


## CalibrationRun: render at `lv` for a measurement (not saved).
func calibration_level(lv: int) -> void:
	_cal_level = lv
	apply()
	_set_scale(nominal_scale(lv))


func _on_calibrated(lv: int, fps: int, results: Dictionary) -> void:
	_cal_level = -1
	_calibration = null
	graphics_quality = lv
	target_fps_auto = fps
	auto_top = 4 if lv >= 4 else AUTO_TOP
	calibrated = CALIB_VERSION
	_went_down = false
	_changes = 0
	_settle = SETTLE_S
	var method := RenderingServer.get_current_rendering_method()
	calib_records[method] = {"level": lv, "cost_ms": snappedf(float(results.get(lv, 0.0)), 0.1), "fps": fps}
	calib_note = GraphicsCalibration.describe(results, lv, fps, QUALITY_NAMES) + " · " + renderer_label(method)
	var msg := "Graphics measured: %s. F2 to change." % calib_note
	var better := GraphicsCalibration.better_renderer(calib_records)
	if better != "" and better != method and not _explicit_renderer:
		renderer_pref = better  # the other renderer measured better here: the next launch uses it
		msg += " The next launch uses %s (it measured better here)." % renderer_label(better)
	elif better == "" and lv == 0 and fps <= 30 and not _explicit_renderer:
		# A very weak GPU: the other renderer gets one measured try (the next launch), the faster one stays.
		var other := "forward_plus" if method == "gl_compatibility" else "gl_compatibility"
		renderer_pref = other
		calibrated = 0
		msg += " The next launch tries %s and keeps the faster." % renderer_label(other)
	print("[Calibration] ", msg)
	_dyn_ok = false
	save_settings()
	apply()
	_note(msg)


## F2 "Recalibrate": measure again now (or on the next arrival if no scene is up).
func recalibrate() -> CalibrationRun:
	calibrated = 0
	auto_quality = true
	save_settings()
	if is_instance_valid(_environment) and _interactive():
		return calibrate()
	return null


## F2 "Try the other renderer": relaunch with it; the arrival measures it, the faster one stays.
func try_other_renderer() -> void:
	var method := RenderingServer.get_current_rendering_method()
	renderer_pref = "forward_plus" if method == "gl_compatibility" else "gl_compatibility"
	calibrated = 0
	auto_quality = true
	save_settings()
	_relaunch(renderer_pref)


static func renderer_label(method: String) -> String:
	match method:
		"forward_plus": return "Forward+ (Vulkan/Metal/D3D12)"
		"mobile": return "Mobile (Vulkan/Metal)"
		"gl_compatibility": return "Compatibility (OpenGL)"
	return method


## The GPU in use and the renderer, for F2.
func gpu_line() -> String:
	if DisplayServer.get_name() == "headless":
		return "headless"
	var kinds := ["", "integrated", "dedicated", "virtual", "software"]
	var t := RenderingServer.get_video_adapter_type()
	var kind: String = kinds[t] if t >= 0 and t < kinds.size() else ""
	return "%s%s · %s · %s %s" % [RenderingServer.get_video_adapter_name(), (" (%s)" % kind) if kind != "" else "",
		RenderingServer.get_video_adapter_vendor(), renderer_label(RenderingServer.get_current_rendering_method()),
		RenderingServer.get_video_adapter_api_version()]


## Level, render scale and frame rate right now (F2, the F3 overlay).
func status_line() -> String:
	var gpu := (" · GPU %.1f ms" % gpu_ms_now) if gpu_ms_now > 0.05 else ""
	var lv := String(QUALITY_NAMES[level()]).split(" ")[0]
	var mode := "FSR" if _scale_now < 1.0 and _fsr_ok() else "bilinear"
	return "%s%s · render %d%% (%s%s) · %.0f fps · %.1f ms%s · target %d" % [lv, " (performance mode)" if performance_mode else "",
		int(round(_scale_now * 100.0)), mode, ", dynamic" if dynamic_resolution and (auto_quality or performance_mode) else "",
		fps_now, frame_ms_now, gpu, target_fps()]


## Pure: a hint when the game runs on a weak integrated GPU while the PC has a dedicated one
## (Windows' per-app setting picks the GPU; the game asks for the dedicated one already).
static func hybrid_hint_for(in_use: String, adapters: Array) -> String:
	var u := in_use.to_lower()
	var weak := u.contains("intel") or u.contains("radeon(tm) graphics") or u.contains("vega") or u == ""
	if not weak:
		return ""
	for a in adapters:
		var n := String(a).strip_edges()
		var l := n.to_lower()
		if n == "" or l == u:
			continue
		for k in ["nvidia", "geforce", "quadro", "rtx", "radeon rx", "radeon pro", "arc a", "firepro"]:
			if l.contains(k):
				return "This PC also has %s. To use it: Windows Settings › System › Display › Graphics › Dysnomia › High performance, then restart the game." % n
	return ""


## Worker thread (Windows): the display adapters this PC has.
func _list_adapters() -> void:
	var out: Array = []
	var code := OS.execute("powershell", ["-NoProfile", "-Command", "(Get-CimInstance Win32_VideoController).Name"], out, true)
	if code != 0 or out.is_empty():
		return
	var names := Array(String(out[0]).split("\n", false))
	call_deferred("_set_hybrid", hybrid_hint_for(RenderingServer.get_video_adapter_name(), names))


func _set_hybrid(h: String) -> void:
	hybrid_hint = h
	if _hybrid_thread and _hybrid_thread.is_started():
		_hybrid_thread.wait_to_finish()
	_hybrid_thread = null


func _exit_tree() -> void:
	if _hybrid_thread and _hybrid_thread.is_started():
		_hybrid_thread.wait_to_finish()


func apply() -> void:
	var p := preset()
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if is_instance_valid(_environment):
		# The Compatibility (OpenGL) renderer, for PCs without a real GPU, lights
		# the scene darker than Forward+: lift it so the ground stays readable.
		# Its ambient light doesn't come from a custom sky shader, so give it a fill.
		if compat:
			_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			_environment.ambient_light_color = Color(0.55, 0.6, 0.75)
			_environment.ambient_light_energy = 1.1
			_environment.adjustment_enabled = true
			_environment.adjustment_brightness = 1.25
		_environment.ssao_enabled = p["ssao"]
		_environment.ssil_enabled = p["ssil"]
		_environment.glow_enabled = p["glow"]
		_environment.volumetric_fog_enabled = p["volumetric_fog"]
		if _outdoor and _environment.fog_enabled:
			# A shortened view: depth fog over its last stretch hides the cut (the sky is unaffected).
			var far := far_m()
			if bool(p.get("fog_far", false)) and far < render_distance + 1.0 and far < 1200.0:
				_environment.fog_mode = Environment.FOG_MODE_DEPTH
				_environment.fog_density = 1.0
				_environment.fog_depth_begin = far * 0.5
				_environment.fog_depth_end = far * 0.97
				_environment.fog_depth_curve = 1.6
			else:
				_environment.fog_mode = _fog_mode as Environment.FogMode
				_environment.fog_density = _fog_density
	if is_instance_valid(_sun):
		_sun.directional_shadow_max_distance = minf(p["shadow_distance"], far_m())
		_sun.shadow_enabled = p["shadows"]
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(p.get("shadow_splits", 4)) >= 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if DisplayServer.get_name() != "headless":
		# The sun's shadow atlas: 4096 (Godot's default) at Medium/High; 1024 where nothing casts (Potato, Low:
		# 16 MB of VRAM instead of 64 on a 1 GB shared iGPU); 8192 with soft high filtering and full-size
		# SSAO/SSIL at the High preset of each (project: medium, half size) on Ultra.
		RenderingServer.directional_shadow_atlas_set_size(int(p.get("shadow_atlas", 4096)), true)
		var ultra := bool(p.get("ultra_fx", false))
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if ultra else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if ultra else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, not ultra, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH if ultra else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, not ultra, 0.5, 4, 50.0, 300.0)
	if is_instance_valid(_terrain_material):
		_terrain_material.set_shader_parameter("max_iter", int(p["iter"]))
		_terrain_material.set_shader_parameter("detail_strength", float(p["detail"]))
		_terrain_material.set_shader_parameter("ground_lift", 4.0 if compat else 1.0)
	if is_instance_valid(_sky_material):
		_sky_material.set_shader_parameter("simple", bool(p["simple_sky"]))
	var vp := get_viewport()
	if vp and DisplayServer.get_name() != "headless":
		vp.msaa_3d = p["msaa"]
		if _cal_level < 0:
			if not _dyn_ok or not (dynamic_resolution and (auto_quality or performance_mode) and (_interactive() or follow_in_tools)):
				_configure_dynamic()
				_set_scale(nominal_scale())
			else:
				_set_scale(dyn.scale)
		var cam := vp.get_camera_3d()
		apply_camera(cam)
		if _calibration == null:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and (fullscreen or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
			DisplayServer.window_set_mode(want)
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	applied.emit()


func _ensure_buses() -> void:
	for nm in ["Music", "SFX"]:
		if AudioServer.get_bus_index(nm) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, "Master")


func _set_bus(nm: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(nm)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(i, linear <= 0.001)


func save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("graphics", "quality", graphics_quality)
	c.set_value("graphics", "render_distance", render_distance)
	c.set_value("graphics", "auto", auto_quality)
	c.set_value("graphics", "renderer", renderer_pref)
	c.set_value("graphics", "dynamic_resolution", dynamic_resolution)
	c.set_value("graphics", "target_fps", target_fps_setting)
	c.set_value("graphics", "target_fps_auto", target_fps_auto)
	c.set_value("graphics", "performance_mode", performance_mode)
	c.set_value("graphics", "calibrated", calibrated)
	c.set_value("graphics", "calib_records", calib_records)
	c.set_value("graphics", "calib_note", calib_note)
	c.set_value("graphics", "auto_top", auto_top)
	c.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	c.set_value("controls", "invert_y", invert_y)
	c.set_value("controls", "fov", fov)
	c.set_value("audio", "master_volume", master_volume)
	c.set_value("audio", "music_volume", music_volume)
	c.set_value("audio", "sfx_volume", sfx_volume)
	c.set_value("display", "fullscreen", fullscreen)
	c.set_value("display", "vsync", vsync)
	c.set_value("chain", "rpc_url", rpc_url)
	c.set_value("chain", "site_api_base", site_api_base)
	c.set_value("chain", "site_api_enabled", site_api_enabled)
	c.set_value("wallet", "bridge_port", wallet_bridge_port)
	c.set_value("wallet", "browser", wallet_browser)
	c.set_value("update", "dismissed", update_dismissed)
	c.save(SETTINGS_PATH)


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) != OK:
		return
	graphics_quality = int(c.get_value("graphics", "quality", graphics_quality))
	render_distance = float(c.get_value("graphics", "render_distance", render_distance))
	if is_equal_approx(render_distance, OLD_RENDER_DEFAULT):
		render_distance = RENDER_DEFAULT  # saved before the territories grew: the far border would be cut off
	auto_quality = bool(c.get_value("graphics", "auto", auto_quality))
	renderer_pref = String(c.get_value("graphics", "renderer", renderer_pref))
	dynamic_resolution = bool(c.get_value("graphics", "dynamic_resolution", dynamic_resolution))
	target_fps_setting = int(c.get_value("graphics", "target_fps", target_fps_setting))
	target_fps_auto = int(c.get_value("graphics", "target_fps_auto", target_fps_auto))
	performance_mode = bool(c.get_value("graphics", "performance_mode", performance_mode))
	calibrated = int(c.get_value("graphics", "calibrated", calibrated))
	var rec = c.get_value("graphics", "calib_records", calib_records)
	calib_records = rec if rec is Dictionary else {}
	calib_note = String(c.get_value("graphics", "calib_note", calib_note))
	auto_top = clampi(int(c.get_value("graphics", "auto_top", auto_top)), AUTO_TOP, 4)
	mouse_sensitivity = float(c.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	invert_y = bool(c.get_value("controls", "invert_y", invert_y))
	fov = float(c.get_value("controls", "fov", fov))
	master_volume = float(c.get_value("audio", "master_volume", master_volume))
	music_volume = float(c.get_value("audio", "music_volume", music_volume))
	sfx_volume = float(c.get_value("audio", "sfx_volume", sfx_volume))
	fullscreen = bool(c.get_value("display", "fullscreen", fullscreen))
	vsync = bool(c.get_value("display", "vsync", vsync))
	rpc_url = String(c.get_value("chain", "rpc_url", rpc_url))
	site_api_base = Contracts.site_api_for_saved(String(c.get_value("chain", "site_api_base", site_api_base)))
	site_api_enabled = bool(c.get_value("chain", "site_api_enabled", site_api_enabled))
	wallet_bridge_port = int(c.get_value("wallet", "bridge_port", wallet_bridge_port))
	wallet_browser = String(c.get_value("wallet", "browser", wallet_browser))
	update_dismissed = String(c.get_value("update", "dismissed", update_dismissed))
