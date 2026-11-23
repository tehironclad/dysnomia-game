class_name DeepFieldSky
extends Node
## Drives the Deep Field sky and the sun from real numbers (WP 2.3):
## stars seeded from the territory's address, the territory's c marked on the
## Mandelbrot set, and the sun placed by DysnomiaTime from the latest block's
## timestamp (advanced locally between reads).

const SHADER := preload("res://assets/shaders/deep_field_sky.gdshader")
## Dysnomia orbits ~37,350 km from Eris (radius ~1,163 km): ~3.6° across.
const ERIS_ANGULAR_DIAMETER_DEG := 3.57
const RESYNC_S := 600.0
const SUN_MAX_ENERGY := 0.28

@export var environment_path: NodePath
@export var sun_path: NodePath

var material: ShaderMaterial
var block_timestamp := -1  ## unix seconds of the block we synced to
var block_number := -1
var _synced_at_ms := 0
var _last_fraction := -1.0
var _sun: DirectionalLight3D


func setup(params: Dictionary, address: String) -> void:
	var env: WorldEnvironment = get_node(environment_path)
	_sun = get_node(sun_path)
	material = ShaderMaterial.new()
	material.shader = SHADER
	var sky := Sky.new()
	sky.sky_material = material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	var c: Array = params["c"]
	material.set_shader_parameter("c", Vector2(c[0], c[1]))
	material.set_shader_parameter("star_seed", float(BigInt.mod_int(BigInt.from_hex(address), 100003)))
	material.set_shader_parameter("eris_radius_deg", ERIS_ANGULAR_DIAMETER_DEG * 0.5)
	material.set_shader_parameter("mark_color", Vector3(params["color"][0], params["color"][1], params["color"][2]))
	material.set_shader_parameter("neb_a", Vector3(params["color"][0], params["color"][1], params["color"][2]))
	material.set_shader_parameter("neb_b", Vector3(params["color2"][0], params["color2"][1], params["color2"][2]))
	_explain(params)
	sync_time()


## Reads the latest block's timestamp (one RPC call). Until it answers, the sky
## keeps a neutral time and the inspector says the time is unknown.
## A City's aurora (0 = none), from Development.
func set_aurora(strength: float) -> void:
	_aurora = strength
	if material:
		material.set_shader_parameter("aurora", strength)


var _aurora := 0.0
var _aurora_t := 0.0


func sync_time() -> void:
	var r := await Chain.rpc.get_block("latest")
	if r.get("ok", false) and r["result"] is Dictionary:
		block_timestamp = String(r["result"]["timestamp"]).hex_to_int()
		block_number = String(r["result"]["number"]).hex_to_int()
		_synced_at_ms = Time.get_ticks_msec()
		_last_fraction = -1.0
	_explain_time()


func now_unix() -> int:
	if block_timestamp < 0:
		return -1
	return block_timestamp + (Time.get_ticks_msec() - _synced_at_ms) / 1000


## Preview-only override (--day-fraction=0..1, used by screenshot tooling).
var _fraction_override := -1.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--day-fraction="):
			_fraction_override = float(a.substr(15))


func _process(delta: float) -> void:
	if _aurora > 0.0 and material:
		_aurora_t += delta
		if fmod(_aurora_t, 0.25) < delta:  # 4 Hz: the curtains drift, the sky isn't redrawn every frame
			material.set_shader_parameter("sky_time", _aurora_t)
	var ts := now_unix()
	var frac := 0.3 if ts < 0 else float(DysnomiaTime.from_unix(ts)["fraction"])
	if _fraction_override >= 0.0:
		frac = _fraction_override
	if absf(frac - _last_fraction) > 0.0005:  # ~1 DysnomiaTime minute
		_last_fraction = frac
		_place_sun(frac)
	if ts >= 0 and (Time.get_ticks_msec() - _synced_at_ms) / 1000.0 > RESYNC_S:
		_synced_at_ms = Time.get_ticks_msec()  # avoid re-entry while the call is in flight
		sync_time()


## Sun path: one turn per Dysnomia day around a tilted axis; noon at 0.5.
func _place_sun(frac: float) -> void:
	if _sun == null:
		return
	var angle := (frac - 0.5) * TAU
	var dir := Vector3(sin(angle), cos(angle), 0.0).rotated(Vector3.RIGHT, deg_to_rad(-28.0))
	# DirectionalLight3D shines along its -Z; point -Z away from the sun.
	_sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)
	var elev := dir.y
	# ~96 AU from the Sun, daylight is ~1/9,000 of Earth's: the sun is "just
	# another star". Keep it faint; the land is lit mostly by its filaments.
	_sun.light_energy = clampf(elev * 3.0, 0.0, 1.0) * SUN_MAX_ENERGY
	_sun.visible = elev > -0.05


func _explain(params: Dictionary) -> void:
	Inspector.register(self, "Sky",
		"Stars: hashed per direction, seeded from the territory's address.\nThe faint figure: the Mandelbrot set; the marked point is this territory's c = %.5f %+.5fi — its Julia set is the ground.\nEris: fixed (Dysnomia is tidally locked), %.2f° across (radius ~1,163 km at ~37,350 km)." % [
			params["c"][0], params["c"][1], ERIS_ANGULAR_DIAMETER_DEG])


func _explain_time() -> void:
	var t := now_unix()
	var line := "Time of day: unknown (latest block not read yet)" if t < 0 else \
		"Time of day: %s, from block %d's timestamp (DysnomiaTime: 34 h × 100 min × 34 s)." % [DysnomiaTime.format(t), block_number]
	Inspector.register(_time_anchor(), "Time of day", line)


var _anchor: Node = null


func _time_anchor() -> Node:
	if _anchor == null:
		_anchor = Node.new()
		_anchor.name = "TimeExplanation"
		add_child(_anchor)
	return _anchor
