class_name ArcadeWorld
extends Node3D
## A dive-in world: the 3D place you land in when you dive into a cabinet.
##
## The game itself stays the cabinet's 2D ArcadeGame: its simulation is the source of truth for the
## run, the score and game_over (and keeps every unit test), and the cabinet's own screen keeps
## showing it. A world only READS the game's state each frame and stages it in 3D, in its own
## World3D inside ArcadeDive's SubViewport. It may set `game.input_remap` so the keys match its camera.
##
## Subclasses: _build() once, _sync(delta) every frame, hud() for the overlay, and optionally
## prepare_demo() / prepare_run(credit) (async) when the world takes something from the chain.

const ICE := Color("#7fe9ff")
const GOLD := Color("#ffd36b")
const MAGENTA := Color("#ff4fd8")
const INK := Color("#e9edf4")
const DIM := Color("#5d6578")

var game: ArcadeGame
var camera: Camera3D
var env: Environment
var accent := ICE
var ctx: Dictionary = {}  ## {qing, territory: Dictionary, model: the player's HumanAvatar (for the head)}
var source_label := ""  ## where this run's numbers came from, shown on the overlay
var _t := 0.0


func bind(p_game: ArcadeGame, p_ctx: Dictionary) -> void:
	game = p_game
	ctx = p_ctx
	accent = p_ctx.get("accent", accent)
	_build()
	game.input_remap = controls_remap()


## Hands the game back to its own (2D) controls.
func unbind() -> void:
	if game:
		game.input_remap = {}


## Keyboard → game bits while this world is on screen (see ArcadeGame.input_remap).
func controls_remap() -> Dictionary:
	return {}


## One line for the overlay: how to play in this view.
func controls_hint() -> String:
	return ""


## The controls in this view as [[key, words]] (GameHowto's card and strip, the dive's menu).
func controls_list() -> Array:
	return GameHowto.parse_hint(controls_hint())


## Overlay data: {stats: PackedStringArray, bars: [[label, 0..1, Color]], center: String,
## center_color: Color, flash: float, flash_color: Color}.
func hud() -> Dictionary:
	return {}


## The idle demo is about to show (async in subclasses that read the chain).
func prepare_demo() -> void:
	pass


## A paid run is about to start with this credit ({tx, block}). Returns the run's seed.
func prepare_run(credit: Dictionary) -> int:
	return seed_from_tx(String(credit.get("tx", "")))


## The cabinet's seed rule: the credit's tx hash, first 12 hex digits.
static func seed_from_tx(tx: String) -> int:
	return tx.substr(2, 12).hex_to_int()


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	_t += delta
	_sync(delta)


func _build() -> void:
	pass


func _sync(_delta: float) -> void:
	pass


# ── building blocks ──────────────────────────────────────────────────────────


func make_environment(bg: Color, fog_color: Color, fog_density: float, glow_strength: float = 1.0) -> Environment:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.75)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7 * glow_strength
	env.glow_strength = 1.0
	# Tight glow only: the wide levels wash the dark floors grey.
	for lv in 7:
		env.set_glow_level(lv, [0.0, 1.0, 1.0, 0.5, 0.0, 0.0, 0.0][lv])
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	if fog_density > 0.0:
		env.fog_enabled = true
		env.fog_light_color = fog_color
		env.fog_density = fog_density
		env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	return env


func make_camera(fov: float = 70.0) -> Camera3D:
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.05
	camera.far = 600.0
	camera.current = true
	add_child(camera)
	return camera


static func glow_mat(c: Color, e: float = 2.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## Neon: unshaded, HDR-bright (energy > 1 feeds the glow), tinted by vertex / MultiMesh colours.
## `additive` = a see-through light (blend add, no depth write).
static func neon_mat(c: Color, energy: float = 2.0, additive: bool = false, alpha: float = 1.0) -> ShaderMaterial:
	var key := "add" if additive else "solid"
	if not _neon.has(key):
		var sh := Shader.new()
		sh.code = NEON_ADD if additive else NEON_SOLID
		_neon[key] = sh
	var m := ShaderMaterial.new()
	m.shader = _neon[key]
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("alpha", alpha)
	return m


const NEON_SOLID := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float alpha = 1.0;
void fragment() {
	ALBEDO = color.rgb * COLOR.rgb * energy;
}
"""
const NEON_ADD := """shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float alpha = 1.0;
void fragment() {
	ALBEDO = color.rgb * COLOR.rgb * energy * alpha * COLOR.a;
}
"""
static var _neon := {}


static func mat(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func add_mesh(mesh: Mesh, material: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


static func box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## A static star dome (decoration, not data): n billboards on a sphere of `radius`.
func starfield(n: int, radius: float, star_seed: int, size: float = 0.6, tint: Color = Color(0.85, 0.9, 1.0)) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mm.mesh = q
	mm.instance_count = n
	var r := RandomNumberGenerator.new()
	r.seed = star_seed
	for i in n:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.35, 1), r.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * r.randf_range(0.4, 1.6)), d * radius))
		mm.set_instance_color(i, Color(tint, r.randf_range(0.25, 1.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _dot_texture()
	m.disable_fog = true
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


static var _dot: ImageTexture


static func _dot_texture() -> ImageTexture:
	if _dot:
		return _dot
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2.0))
	_dot = ImageTexture.create_from_image(img)
	return _dot


func label3d(text: String, size: int, color: Color, mono: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = DeepFieldTheme.mono_font() if mono else DeepFieldTheme.display_font()
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.shaded = false
	l.double_sided = true
	l.no_depth_test = false
	add_child(l)
	return l


## The player's avatar, wearing the head their LAU asks for (copied from the arcade's player model).
func make_avatar() -> Node3D:
	var path := "res://scripts/player/human_avatar.gd"
	if not ResourceLoader.exists(path):
		return null
	var a: Node3D = load(path).new()
	add_child(a)
	var model: Node = ctx.get("model")
	if model and is_instance_valid(model) and "head_kind" in model:
		if "body_kind" in model and model.body_kind != a.body_kind and a.has_method("set_body"):
			a.set_body(model.body_kind)
		if "outfit_kind" in model and a.has_method("set_outfit"):
			a.set_outfit(String(model.outfit_kind), int(model.outfit_seed))
		a.set_head(String(model.head_kind))
	return a


## Places `n` copies of a mesh with per-instance colour; returns the MultiMesh to fill each frame.
func pool_multimesh(mesh: Mesh, material: Material, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm
