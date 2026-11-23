extends SceneTree
## Affection Fair preview renderer (no main scene, no chain).
##
##   tools/fair_preview.sh [preset] [outdir]       (software Vulkan under Xvfb, see shot.sh)
##   godot --path . --resolution 1600x900 -s tools/fair_preview.gd -- [preset] [outdir]
##
## Builds a flat ground, the game's sky/environment (sky.tscn), a Funfair at the origin
## (as main would place it, spawn lies toward local +X/−Z), then captures each shot of the
## preset: time of day, camera, and optionally a ride started with a dummy teddy rider and
## fast-forwarded to time t (camera can follow the rider).
## Presets: all (default), r2, tiers, night, noon, rides, rocket, wheel, drop, carousel.
## A shot may set "tier" (0..3, default 3); the fair is rebuilt when it changes.
## Env: PREVIEW_ONLY=substr renders only matching shots; PREVIEW_FULL=1 keeps SDFGI/SSIL/volumetric fog (slow on lavapipe).

const SPAWN_DIR := Vector3(100, 0, -80)   # fair at world (-100,h,80), spawn at (0,h,0)

var _shots: Array = []
var _idx := -1
var _frames := 0
var _wait := 0
var _outdir := "/tmp/claude-0/shots"
var _fair: Node3D
var _fair_tier := -1
var _world: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _env: Environment
var _rider: CharacterBody3D
var _ride
var _shot: Dictionary


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var preset := args[0] if args.size() > 0 else "all"
	if args.size() > 1:
		_outdir = args[1]
	DirAccess.make_dir_recursive_absolute(_outdir)
	_shots = _preset(preset)
	# PREVIEW_ONLY=substr keeps only the shots whose name contains it
	var only := OS.get_environment("PREVIEW_ONLY")
	if only != "":
		_shots = _shots.filter(func(sh: Dictionary) -> bool: return String(sh["name"]).contains(only))
	var gm = root.get_node_or_null("GameManager")
	if gm:
		gm.territory_name = "Sunny QING"
		gm.day_cycle_speed = 0.0
	_build_world.call_deferred()


func _preset(p: String) -> Array:
	var spawn_cam := Vector3(52, 14, -44)
	var s := {
		"night": [
			{"name": "fair_night_spawn", "tod": 0.02, "cam": spawn_cam, "look": Vector3(-4, 9, 4)},
			{"name": "fair_night_midway", "tod": 0.02, "cam": Vector3(25.0, 1.9, -20.2), "look": Vector3(7.8, 3.2, -6.2)},
			{"name": "fair_night_stalls", "tod": 0.02, "cam": Vector3(19.4, 1.7, -17.4), "look": Vector3(21.9, 1.9, -10.3)},
			{"name": "fair_night_aerial", "tod": 0.02, "cam": Vector3(40, 46, 42), "look": Vector3(-2, 0, -2)},
		],
		"noon": [
			{"name": "fair_noon_spawn", "tod": 0.5, "cam": spawn_cam, "look": Vector3(-4, 9, 4)},
			{"name": "fair_noon_midway", "tod": 0.5, "cam": Vector3(25.0, 1.9, -20.2), "look": Vector3(7.8, 3.2, -6.2)},
			{"name": "fair_noon_aerial", "tod": 0.45, "cam": Vector3(-44, 40, -40), "look": Vector3(0, 0, 4)},
		],
		"rocket": [
			{"name": "fair_rocket_idle", "tod": 0.02, "ride": "rocket", "cam_ride": Vector3(14, 6, 26), "look_ride": Vector3(-2, 16, 0)},
			{"name": "fair_rocket_liftoff", "tod": 0.02, "ride": "rocket", "t": 12.2, "lead": 3.2, "cam_ride": Vector3(-16, 4, 34), "look_ride": Vector3(0, 15, 0)},
			{"name": "fair_rocket_ascent", "tod": 0.02, "ride": "rocket", "t": 16.0, "lead": 2.5, "follow": Vector3(4, 3, 7), "look_fair": true},
			{"name": "fair_rocket_apogee", "tod": 0.27, "ride": "rocket", "t": 28.5, "follow": Vector3(2.5, 3.0, 4.0), "look_fair": true},
			{"name": "fair_rocket_chutes", "tod": 0.27, "ride": "rocket", "t": 43.0, "follow": Vector3(18, 4, 22), "follow_look": Vector3(0, 6, 0)},
			{"name": "fair_rocket_retro", "tod": 0.02, "ride": "rocket", "t": 49.5, "lead": 1.5, "cam_ride": Vector3(-14, 3, 30), "look_ride": Vector3(0, 14, 0)},
		],
		"wheel": [
			{"name": "fair_wheel_ride", "tod": 0.02, "ride": "wheel", "t": 22.0, "follow": Vector3(1.6, 2.4, 3.6), "look_fair": true},
			{"name": "fair_wheel_side", "tod": 0.03, "ride": "wheel", "t": 12.0, "cam_ride": Vector3(10, 6, 34), "look_ride": Vector3(0, 16, 0)},
		],
		"drop": [
			{"name": "fair_drop_top", "tod": 0.02, "ride": "drop", "t": 16.0, "follow": Vector3(0.3, 2.5, -0.9), "look_fair": true},
			{"name": "fair_drop_fall", "tod": 0.02, "ride": "drop", "t": 21.0, "cam_ride": Vector3(7, 1.8, 15), "look_ride": Vector3(0, 30, 0)},
		],
		"carousel": [
			{"name": "fair_carousel", "tod": 0.02, "ride": "carousel", "t": 12.0, "cam_ride": Vector3(-8.5, 2.6, 9.5), "look_ride": Vector3(0, 2.4, 0)},
		],
	}
	s["tiers"] = [
		{"name": "fair_tier0", "tier": 0, "tod": 0.02, "cam": Vector3(44, 7, -38), "look": Vector3(4, 6, 2)},
		{"name": "fair_tier1", "tier": 1, "tod": 0.02, "cam": Vector3(44, 10, -38), "look": Vector3(-2, 4, 2)},
		{"name": "fair_tier2", "tier": 2, "tod": 0.02, "cam": spawn_cam, "look": Vector3(-4, 9, 4)},
		{"name": "fair_tier3", "tier": 3, "tod": 0.02, "cam": spawn_cam, "look": Vector3(-4, 14, 4), "lead_s": 2.0},
	]
	s["r2"] = [
		{"name": "r2_fair_tier0", "tier": 0, "tod": 0.02, "cam": Vector3(44, 7, -38), "look": Vector3(4, 6, 2)},
		{"name": "r2_fair_tier3", "tier": 3, "tod": 0.02, "cam": spawn_cam, "look": Vector3(-4, 14, 4), "lead_s": 2.0},
		{"name": "r2_fair_night_midway", "tod": 0.02, "cam": Vector3(25.0, 1.9, -20.2), "look": Vector3(7.8, 3.2, -6.2)},
		{"name": "r2_fair_stalls", "tod": 0.02, "cam": Vector3(19.4, 1.7, -17.4), "look": Vector3(21.9, 1.9, -10.3)},
		{"name": "r2_fair_noon_aerial", "tod": 0.45, "cam": Vector3(-44, 40, -40), "look": Vector3(0, 0, 4)},
		{"name": "r2_fair_liftoff", "tod": 0.02, "ride": "rocket", "t": 12.2, "lead": 3.2, "cam_ride": Vector3(12, 3, 31), "look_ride": Vector3(0, 15, 0)},
		{"name": "r2_fair_carousel", "tod": 0.02, "ride": "carousel", "t": 12.0, "lead": 1.0, "cam_ride": Vector3(-8.5, 2.4, 9.5), "look_ride": Vector3(0, 2.0, 0)},
	]
	if p == "all":
		return s["tiers"] + s["night"] + s["noon"] + s["rocket"] + s["wheel"] + s["drop"] + s["carousel"]
	if p == "rides":
		return s["rocket"] + s["wheel"] + s["drop"] + s["carousel"]
	return s.get(p, s["night"])


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "PreviewWorld"
	root.add_child(world)
	var sky: Node3D = load("res://scenes/world/sky.tscn").instantiate()
	world.add_child(sky)
	_sun = sky.get_node("SunLight")
	_fill = sky.get_node_or_null("FillLight")
	var we: WorldEnvironment = sky.get_node("WorldEnvironment")
	_env = we.environment
	if OS.get_environment("PREVIEW_FULL") != "1":
		_env.sdfgi_enabled = false
		_env.ssil_enabled = false
		_env.volumetric_fog_enabled = false
	_sky_mat = _env.sky.sky_material as ShaderMaterial
	# Ground: dusty regolith
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	ground.mesh = pm
	var gmat := ORMMaterial3D.new()
	gmat.albedo_texture = load("res://assets/textures/polyhaven/asphalt_02/diff.jpg")
	gmat.albedo_color = Color(0.62, 0.62, 0.66)
	gmat.normal_enabled = true
	gmat.normal_texture = load("res://assets/textures/polyhaven/asphalt_02/nor_gl.jpg")
	gmat.orm_texture = load("res://assets/textures/polyhaven/asphalt_02/arm.jpg")
	gmat.uv1_scale = Vector3(600, 600, 1)
	ground.material_override = gmat
	world.add_child(ground)
	_world = world
	_make_fair(3)
	# Dummy rider (teddy astronaut via AmbientNPC's model)
	_rider = CharacterBody3D.new()
	_rider.add_to_group("player")
	world.add_child(_rider)
	var teddy: Node3D = load("res://scripts/world/npc/ambient_npc.gd").new()
	_rider.add_child(teddy)
	teddy.call("setup", 77, [], Vector3.FORWARD)
	_rider.position = Vector3(0, -300, 0)   # parked out of frame until it rides
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 4000.0
	world.add_child(_cam)
	_cam.make_current()
	_next_shot()


func _make_fair(tier: int) -> void:
	# Loaded at runtime: these scripts reference autoloads, which -s scripts can't see at compile time
	if _fair:
		_fair.free()
	_fair = load("res://scripts/world/funfair/funfair.gd").new()
	_fair.name = "Funfair"
	_world.add_child(_fair)
	_fair.call("initialize", 1234567, tier)
	_fair.call("set_unlock_hint", "Unlocks at Standing 250  ·  this QING: 180")
	_fair_tier = tier
	for r in _fair.call("get_rides"):
		var rid: String = r.ride_id
		r.ride_caption.connect(func(c: String) -> void: print("[caption] ", rid, ": ", c))


func _next_shot() -> void:
	if _ride and _ride.is_riding():
		_ride.end_ride()
	_ride = null
	_idx += 1
	if _idx >= _shots.size():
		quit()
		return
	_shot = _shots[_idx]
	_frames = 0
	_wait = 40 if _idx == 0 else 10
	_rider.position = Vector3(0, -300, 0)
	if int(_shot.get("tier", 3)) != _fair_tier:
		_make_fair(int(_shot.get("tier", 3)))
		_wait = 30
	_wait = maxi(_wait, int(float(_shot.get("lead_s", 0.0)) * 30.0))
	_set_time(float(_shot.get("tod", 0.0)))
	var rid: String = _shot.get("ride", "")
	if rid != "":
		for r in _fair.call("get_rides"):
			if r.ride_id == rid:
				_ride = r
		if _ride and _shot.has("t"):
			# Start a little before t and let the ride run in (fixed 30 fps) so particles,
			# captions and motion are live rather than frozen.
			var lead: float = _shot.get("lead", 0.4)
			_ride.start_ride(_rider)
			_ride._t = maxf(float(_shot["t"]) - lead, 0.0)
			_wait = maxi(_wait, int(lead * 30.0))


func _set_time(t: float) -> void:
	var gm = root.get_node_or_null("GameManager")
	if gm:
		gm.time_of_day = t
	var sun_angle := t * TAU - PI / 2.0
	var sun_dir := Vector3(0.0, sin(sun_angle), -cos(sun_angle)).normalized()
	_sun.rotation = Vector3(-sun_angle, 0.6, 0)
	var day := smoothstep(-0.1, 0.2, sun_dir.y)
	var ext := clampf(smoothstep(-0.05, 0.5, sun_dir.y), 0.0, 1.0) * 0.65 + 0.35
	_sun.light_energy = clampf(day * 1.2 * ext, 0.02, 1.2)
	if _sky_mat:
		_sky_mat.set_shader_parameter("sun_direction", sun_dir)
		_sky_mat.set_shader_parameter("time_of_day", t)


func _process(_delta: float) -> bool:
	if _shot.is_empty() or _cam == null:
		return false
	_frames += 1
	var cam_pos: Vector3
	var look: Vector3
	if _shot.has("follow") and _ride:
		var seat: Vector3 = _rider.global_position if _ride.is_riding() else _ride.get_seat_transform(float(_shot["t"])).origin
		cam_pos = seat + _ride.global_transform.basis * _shot["follow"]
		look = seat + Vector3.UP * 1.2 + _ride.global_transform.basis * _shot.get("follow_look", Vector3.ZERO)
		if _shot.get("look_fair", false):
			look = _fair.global_position + Vector3(0, 4, 0)
	elif _shot.has("cam_ride") and _ride:
		cam_pos = _ride.to_global(_shot["cam_ride"])
		look = _ride.to_global(_shot["look_ride"])
	else:
		cam_pos = _shot["cam"]
		look = _shot["look"]
	_cam.global_position = cam_pos
	_cam.look_at(look)
	if _frames == _wait:
		var path := "%s/%s.png" % [_outdir, _shot["name"]]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("[fair_preview] saved ", path, "  ride_t=", _ride._t if _ride and _ride.is_riding() else -1.0)
		_next_shot()
	return false


func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
