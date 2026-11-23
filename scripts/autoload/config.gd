extends Node
## Autoload "Config": player settings, saved to user://settings.cfg. Every
## setting here is applied somewhere (WP 7.4); apply() pushes them to the
## display, the audio buses and any registered scene (environment, sun,
## camera) and emits `applied`.

signal applied

# Graphics
var graphics_quality: int = 1  # 0 low · 1 medium · 2 high · 3 ultra (Medium until the player picks)
var render_distance: float = 900.0  # camera far plane, metres

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
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
## What each quality level enables.
const QUALITY_PRESETS: Array[Dictionary] = [
	# scale: 3D render resolution (FSR upscales below 1.0) · iter: fractal iterations on the ground
	{"ssao": false, "ssil": false, "glow": true, "volumetric_fog": false, "shadow_distance": 90.0, "msaa": Viewport.MSAA_DISABLED, "scale": 0.6, "iter": 40, "shadows": false},
	{"ssao": false, "ssil": false, "glow": true, "volumetric_fog": false, "shadow_distance": 160.0, "msaa": Viewport.MSAA_DISABLED, "scale": 0.8, "iter": 64, "shadows": true},
	{"ssao": true, "ssil": true, "glow": true, "volumetric_fog": false, "shadow_distance": 260.0, "msaa": Viewport.MSAA_2X, "scale": 1.0, "iter": 96, "shadows": true},
	{"ssao": true, "ssil": true, "glow": true, "volumetric_fog": true, "shadow_distance": 320.0, "msaa": Viewport.MSAA_4X, "scale": 1.0, "iter": 128, "shadows": true},
]

var _terrain_material: ShaderMaterial
var _environment: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	load_settings()
	_ensure_buses()
	apply()


func preset() -> Dictionary:
	return QUALITY_PRESETS[clampi(graphics_quality, 0, QUALITY_PRESETS.size() - 1)]


## A scene registers what the graphics settings act on (territories do).
func register_scene(env: Environment, sun: DirectionalLight3D) -> void:
	_environment = env
	_sun = sun
	apply()


## The territory's ground shader: its fractal iteration count follows quality.
func register_terrain(m: ShaderMaterial) -> void:
	_terrain_material = m
	apply()


## Cameras read fov / render distance from here.
func apply_camera(cam: Camera3D) -> void:
	if cam:
		cam.fov = fov
		cam.far = render_distance


func apply() -> void:
	var p := preset()
	if is_instance_valid(_environment):
		_environment.ssao_enabled = p["ssao"]
		_environment.ssil_enabled = p["ssil"]
		_environment.glow_enabled = p["glow"]
		_environment.volumetric_fog_enabled = p["volumetric_fog"]
	if is_instance_valid(_sun):
		_sun.directional_shadow_max_distance = minf(p["shadow_distance"], render_distance)
		_sun.shadow_enabled = p["shadows"]
	if is_instance_valid(_terrain_material):
		_terrain_material.set_shader_parameter("max_iter", int(p["iter"]))
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
