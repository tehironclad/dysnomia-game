extends Node
## Autoload "Config": player settings, saved to user://settings.cfg. Every
## setting here is applied somewhere (WP 7.4); apply() pushes them to the
## display, the audio buses and any registered scene (environment, sun,
## camera) and emits `applied`.

signal applied
## The automatic graphics picked or changed a level (a line for the HUD).
signal auto_changed(text: String)

# Graphics
var graphics_quality: int = 2  # 0 potato · 1 low · 2 medium · 3 high · 4 ultra (Medium until the player picks)
var render_distance: float = 900.0  # camera far plane, metres
## Pick the level from the hardware on first launch, then follow the frame rate.
var auto_quality := true
## The renderer the hardware asks for ("forward_plus" | "gl_compatibility"; "" until detected).
var renderer_pref := ""
var detected := ""  # what was found, for the settings menu
var last_note := ""  # the latest auto change, for a HUD that arrives after it

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
var site_api_base: String = "https://systm0.vercel.app"
var site_api_enabled: bool = true

# Wallet relay (local HTTP + WebSocket)
var wallet_bridge_port: int = 38420

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Potato (no GPU)", "Low", "Medium", "High", "Ultra"]
## What each quality level enables.
const QUALITY_PRESETS: Array[Dictionary] = [
	# scale: 3D render resolution (FSR upscales below 1.0) · iter: fractal iterations on the ground
	# simple_sky: stars/Eris/sun only · detail: regolith + city lights on the ground · warp_iter: the dive
	{"ssao": false, "ssil": false, "glow": false, "volumetric_fog": false, "shadow_distance": 60.0, "msaa": Viewport.MSAA_DISABLED, "scale": 0.5, "iter": 24, "shadows": false, "simple_sky": true, "detail": 0.0, "warp_iter": 40},
	{"ssao": false, "ssil": false, "glow": true, "volumetric_fog": false, "shadow_distance": 90.0, "msaa": Viewport.MSAA_DISABLED, "scale": 0.6, "iter": 40, "shadows": false, "simple_sky": false, "detail": 0.6, "warp_iter": 70},
	{"ssao": false, "ssil": false, "glow": true, "volumetric_fog": false, "shadow_distance": 160.0, "msaa": Viewport.MSAA_DISABLED, "scale": 0.8, "iter": 64, "shadows": true, "simple_sky": false, "detail": 1.0, "warp_iter": 110},
	{"ssao": true, "ssil": true, "glow": true, "volumetric_fog": false, "shadow_distance": 260.0, "msaa": Viewport.MSAA_2X, "scale": 1.0, "iter": 96, "shadows": true, "simple_sky": false, "detail": 1.0, "warp_iter": 160},
	{"ssao": true, "ssil": true, "glow": true, "volumetric_fog": true, "shadow_distance": 320.0, "msaa": Viewport.MSAA_4X, "scale": 1.0, "iter": 128, "shadows": true, "simple_sky": false, "detail": 1.0, "warp_iter": 200},
]

## Frame-rate follow: a 10 s window, after a 12 s settle on every new scene.
const WINDOW_S := 10.0
const SETTLE_S := 12.0
const MAX_CHANGES := 4
const AUTO_TOP := 3  # auto never goes past High (Ultra is a choice)

var _mon_time := 0.0
var _mon_frames := 0
var _settle := SETTLE_S
var _changes := 0
var _went_down := false
var _explicit_quality := false
var _explicit_renderer := false

var _terrain_material: ShaderMaterial
var _sky_material: ShaderMaterial
var _environment: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	var first_run := not FileAccess.file_exists(SETTINGS_PATH)
	load_settings()
	# `-- --quality=0` (Potato) … 4 (Ultra) on the command line: applied and saved, and fixed for this session.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			graphics_quality = clampi(int(a.substr(10)), 0, QUALITY_NAMES.size() - 1)
			_explicit_quality = true
			save_settings()
	var args := OS.get_cmdline_args()
	_explicit_renderer = args.has("--rendering-method") or args.has("--rendering-driver")
	_ensure_buses()
	if _interactive():
		var rec := recommend(RenderingServer.get_video_adapter_type(), RenderingServer.get_video_adapter_name(),
			OS.get_processor_count(), float(OS.get_memory_info().get("physical", 0)) / 1073741824.0,
			RenderingServer.get_current_rendering_method())
		detected = rec["why"]
		if auto_quality and not _explicit_quality and (first_run or renderer_pref == ""):
			graphics_quality = rec["quality"]
			renderer_pref = rec["renderer"]
			save_settings()
			_note("Graphics set to %s for this PC (%s). F2 to change." % [QUALITY_NAMES[graphics_quality], detected])
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		if auto_quality and not _explicit_renderer and renderer_pref != "" and renderer_pref != RenderingServer.get_current_rendering_method():
			_relaunch.call_deferred(renderer_pref)
			return
	apply()


## A real window with a player at it (not the headless tests or a -s tool script).
func _interactive() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var args := OS.get_cmdline_args()
	return not (args.has("-s") or args.has("--script"))


## Starts the game again with another renderer (the renderer can't change
## while running), then quits this one.
func _relaunch(method: String) -> void:
	var args: Array = ["--path", ProjectSettings.globalize_path("res://"), "--rendering-method", method]
	var user := OS.get_cmdline_user_args()
	if not user.is_empty():
		args.append("--")
		args.append_array(user)
	if OS.create_process(OS.get_executable_path(), PackedStringArray(args)) > 0:
		get_tree().quit()
	else:
		apply()  # couldn't start it: carry on as we are


## The level and renderer the hardware asks for. Pure (tests call it).
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
	if software:
		kind = "software rendering"
		q = 0
		renderer = "gl_compatibility"
	elif name.contains("apple m"):
		# Apple silicon reports as integrated, but its GPUs are strong: Medium, High for the Pro/Max/Ultra parts.
		kind = "Apple silicon"
		q = 3 if (name.contains("pro") or name.contains("max") or name.contains("ultra")) else 2
	elif adapter_type == 1 or (method == "gl_compatibility" and adapter_type == 0 and name.contains("intel")):
		# Older Intel HD/UHD chips: the lightweight renderer at Potato. Newer iGPUs (Iris Xe, Arc, Radeon) cope with Low.
		if name.contains("intel") and (name.contains("hd graphics") or name.contains("uhd graphics")):
			q = 0
			renderer = "gl_compatibility"
		else:
			q = 1
		kind = "integrated GPU"
	elif adapter_type == 2 or name.contains("nvidia") or name.contains("geforce") or name.contains("radeon rx") or name.contains("arc a"):
		kind = "dedicated GPU"
		var strong := RegEx.create_from_string("rtx\\s*(20[6-8]0|30[6-9]0|40[6-9]0|50[6-9]0)|rx\\s*(6[7-9]00|7[6-9]00|9[0-9]{3})|arc\\s*a7[0-9]0")
		var weak := RegEx.create_from_string("gt\\s*[0-9]{3,4}\\b|gtx\\s*[67][0-9]{2}\\b|\\br[57]\\s|mx\\s*[0-9]{3}")
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
## Returns the new level (or the same one).
static func decide(q: int, fps: float, gpu_ms: float, cpu_ms: float, went_down: bool) -> int:
	if fps < 24.0 and q > 0:
		return q - 1
	# Headroom: steady 55+ fps and each frame costs well under a third of its budget.
	if not went_down and q < AUTO_TOP and fps >= 55.0 and gpu_ms > 0.0 and gpu_ms < 5.5 and cpu_ms < 7.0:
		return q + 1
	return q


func _process(delta: float) -> void:
	if not auto_quality or _explicit_quality or not is_instance_valid(_environment) or _changes >= MAX_CHANGES:
		return
	if not _interactive() or not DisplayServer.window_is_focused() or get_tree().paused:
		_mon_time = 0.0
		_mon_frames = 0
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
	var rid := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var q := decide(graphics_quality, fps, gpu, cpu, _went_down)
	if q != graphics_quality:
		var down := q < graphics_quality
		_went_down = _went_down or down
		graphics_quality = q
		_changes += 1
		_settle = SETTLE_S
		save_settings()
		apply()
		_note("Graphics %s to %s (%.0f fps). F2 to change." % ["lowered" if down else "raised", QUALITY_NAMES[q], fps])
	elif graphics_quality == 0 and fps < 14.0 and RenderingServer.get_current_rendering_method() != "gl_compatibility" and renderer_pref != "gl_compatibility":
		renderer_pref = "gl_compatibility"
		_changes = MAX_CHANGES
		save_settings()
		_note("Still slow at Potato (%.0f fps): the next launch uses the lightweight renderer." % fps)


func _note(text: String) -> void:
	last_note = text
	auto_changed.emit(text)


func preset() -> Dictionary:
	return QUALITY_PRESETS[clampi(graphics_quality, 0, QUALITY_PRESETS.size() - 1)]


## A scene registers what the graphics settings act on (territories do).
func register_scene(env: Environment, sun: DirectionalLight3D) -> void:
	_environment = env
	_sun = sun
	_settle = SETTLE_S  # loading hitches aren't the game's speed
	_mon_time = 0.0
	_mon_frames = 0
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
		cam.far = render_distance


func apply() -> void:
	var p := preset()
	if is_instance_valid(_environment):
		# The Compatibility (OpenGL) renderer, for PCs without a real GPU, lights
		# the scene darker than Forward+: lift it so the ground stays readable.
		# Its ambient light doesn't come from a custom sky shader, so give it a fill.
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			_environment.ambient_light_color = Color(0.55, 0.6, 0.75)
			_environment.ambient_light_energy = 1.1
			_environment.adjustment_enabled = true
			_environment.adjustment_brightness = 1.25
		_environment.ssao_enabled = p["ssao"]
		_environment.ssil_enabled = p["ssil"]
		_environment.glow_enabled = p["glow"]
		_environment.volumetric_fog_enabled = p["volumetric_fog"]
	if is_instance_valid(_sun):
		_sun.directional_shadow_max_distance = minf(p["shadow_distance"], render_distance)
		_sun.shadow_enabled = p["shadows"]
	if is_instance_valid(_terrain_material):
		_terrain_material.set_shader_parameter("max_iter", int(p["iter"]))
		_terrain_material.set_shader_parameter("detail_strength", float(p["detail"]))
		var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
		_terrain_material.set_shader_parameter("ground_lift", 4.0 if compat else 1.0)
	if is_instance_valid(_sky_material):
		_sky_material.set_shader_parameter("simple", bool(p["simple_sky"]))
	var vp := get_viewport()
	if vp and DisplayServer.get_name() != "headless":
		vp.msaa_3d = p["msaa"]
		var sc: float = p["scale"]
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if sc < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = sc
		var cam := vp.get_camera_3d()
		apply_camera(cam)
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
	c.save(SETTINGS_PATH)


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) != OK:
		return
	graphics_quality = int(c.get_value("graphics", "quality", graphics_quality))
	render_distance = float(c.get_value("graphics", "render_distance", render_distance))
	auto_quality = bool(c.get_value("graphics", "auto", auto_quality))
	renderer_pref = String(c.get_value("graphics", "renderer", renderer_pref))
	mouse_sensitivity = float(c.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	invert_y = bool(c.get_value("controls", "invert_y", invert_y))
	fov = float(c.get_value("controls", "fov", fov))
	master_volume = float(c.get_value("audio", "master_volume", master_volume))
	music_volume = float(c.get_value("audio", "music_volume", music_volume))
	sfx_volume = float(c.get_value("audio", "sfx_volume", sfx_volume))
	fullscreen = bool(c.get_value("display", "fullscreen", fullscreen))
	vsync = bool(c.get_value("display", "vsync", vsync))
	rpc_url = String(c.get_value("chain", "rpc_url", rpc_url))
	site_api_base = String(c.get_value("chain", "site_api_base", site_api_base))
	site_api_enabled = bool(c.get_value("chain", "site_api_enabled", site_api_enabled))
	wallet_bridge_port = int(c.get_value("wallet", "bridge_port", wallet_bridge_port))
