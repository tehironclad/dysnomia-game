extends Node

# Graphics
var render_distance: float = 500.0
var graphics_quality: int = 2 # 0=low, 1=medium, 2=high, 3=ultra

# Controls
var mouse_sensitivity: float = 0.003
var invert_y: bool = false
var fov: float = 70.0

# Audio
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var ambient_volume: float = 1.0

# Display
var fullscreen: bool = false
var vsync: bool = true

# Features
var screen_effects_enabled: bool = true
var helmet_hud_enabled: bool = true
var minimap_enabled: bool = true

# Chain
var rpc_url: String = "https://rpc.pulsechain.com"
## Optional accelerator (chain-backed site endpoints). The game works without it.
var site_api_base: String = "https://systm0.vercel.app"
var site_api_enabled: bool = true

# Identity
var lau_address: String = ""

# Wallet Bridge
var wallet_bridge_port: int = 38420

const SETTINGS_PATH = "user://settings.cfg"

# Quality preset definitions — what each level enables
const QUALITY_PRESETS: Array[Dictionary] = [
	{ # 0 = Low
		"ssr": false, "sdfgi": false, "volumetric_fog": false,
		"ssao": true, "ssil": false, "glow": true,
		"shadow_distance": 120.0, "terrain_resolution": 256,
	},
	{ # 1 = Medium
		"ssr": false, "sdfgi": false, "volumetric_fog": false,
		"ssao": true, "ssil": true, "glow": true,
		"shadow_distance": 180.0, "terrain_resolution": 256,
	},
	{ # 2 = High
		"ssr": true, "sdfgi": true, "volumetric_fog": true,
		"ssao": true, "ssil": true, "glow": true,
		"shadow_distance": 250.0, "terrain_resolution": 512,
	},
	{ # 3 = Ultra
		"ssr": true, "sdfgi": true, "volumetric_fog": true,
		"ssao": true, "ssil": true, "glow": true,
		"shadow_distance": 300.0, "terrain_resolution": 512,
	},
]


func _ready() -> void:
	load_settings()


func get_quality_preset() -> Dictionary:
	var idx := clampi(graphics_quality, 0, QUALITY_PRESETS.size() - 1)
	return QUALITY_PRESETS[idx]


func apply_quality_to_environment(env: Environment) -> void:
	## Apply the current quality preset to a WorldEnvironment.
	var preset := get_quality_preset()

	env.ssr_enabled = preset.get("ssr", false)
	env.sdfgi_enabled = preset.get("sdfgi", false)

	if preset.get("volumetric_fog", false):
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0015
		env.volumetric_fog_length = 200.0
	else:
		env.volumetric_fog_enabled = false

	env.ssao_enabled = preset.get("ssao", true)
	env.ssil_enabled = preset.get("ssil", false)
	env.glow_enabled = preset.get("glow", true)


func apply_quality_to_sun(sun: DirectionalLight3D) -> void:
	var preset := get_quality_preset()
	sun.directional_shadow_max_distance = preset.get("shadow_distance", 200.0)


func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("graphics", "render_distance", render_distance)
	config.set_value("graphics", "quality", graphics_quality)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	config.set_value("controls", "fov", fov)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "ambient_volume", ambient_volume)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync", vsync)
	config.set_value("features", "screen_effects", screen_effects_enabled)
	config.set_value("features", "helmet_hud", helmet_hud_enabled)
	config.set_value("features", "minimap", minimap_enabled)
	config.set_value("chain", "rpc_url", rpc_url)
	config.set_value("chain", "site_api_base", site_api_base)
	config.set_value("chain", "site_api_enabled", site_api_enabled)
	config.set_value("identity", "lau_address", lau_address)
	config.set_value("wallet", "bridge_port", wallet_bridge_port)
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	render_distance = config.get_value("graphics", "render_distance", render_distance)
	graphics_quality = config.get_value("graphics", "quality", graphics_quality)
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = config.get_value("controls", "invert_y", invert_y)
	fov = config.get_value("controls", "fov", fov)
	master_volume = config.get_value("audio", "master_volume", master_volume)
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)
	ambient_volume = config.get_value("audio", "ambient_volume", ambient_volume)
	fullscreen = config.get_value("display", "fullscreen", fullscreen)
	vsync = config.get_value("display", "vsync", vsync)
	screen_effects_enabled = config.get_value("features", "screen_effects", screen_effects_enabled)
	helmet_hud_enabled = config.get_value("features", "helmet_hud", helmet_hud_enabled)
	minimap_enabled = config.get_value("features", "minimap", minimap_enabled)
	rpc_url = config.get_value("chain", "rpc_url", rpc_url)
	site_api_base = config.get_value("chain", "site_api_base", site_api_base)
	site_api_enabled = config.get_value("chain", "site_api_enabled", site_api_enabled)
	lau_address = config.get_value("identity", "lau_address", lau_address)
	wallet_bridge_port = config.get_value("wallet", "bridge_port", wallet_bridge_port)
