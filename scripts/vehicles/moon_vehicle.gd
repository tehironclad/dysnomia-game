class_name MoonVehicle
extends CharacterBody3D
## A drivable moon vehicle (rover, hoverbike, skimmer, hopper, crawler). The body
## is a CharacterBody3D that only yaws: it slides along the terrain's
## HeightMapShape3D and bumps into every Solid building. Everything that sells the
## feel is layered on top of it: a sprung body (bob, landing squash), pitch and
## roll from ground probes, wheels that follow the ground, drift, low-g hops,
## hover cushions and glides, thruster flames, dust plumes, headlights and an
## engine loop. Physics numbers live in VehicleSpecs (unit-tested).
##
## The driver (the player) is frozen while seated and placed on the seat each
## physics frame, so the player's own camera rig rides along; the garage
## (GarageSite) owns mounting and dismounting.

const HALF_SIZE := JuliaHeightfield.SIZE_M * 0.5 - 2.0

var kind := "rover"
var spec: Dictionary = {}
var tint := Color(0.6, 0.8, 1.0)
var driver: CharacterBody3D = null
## Stepping in: the driver swings from where they stood onto the seat.
const BOARD_S := 0.45
var _board := 1.0  ## 0 → 1 while boarding
var _board_from := Vector3.ZERO
var _board_yaw := 0.0
var bay := Transform3D()  ## where it parks at the garage (global)
var parts: Dictionary = {}
var body: Node3D
var height_fn: Callable  ## world (x, z) → terrain height (safety net)
var lights_on := true

var _susp := Vector2.ZERO  ## body offset (m), its velocity
var _tilt := Vector2.ZERO  ## pitch, roll (rad)
var _bank := 0.0
var _airborne_vy := 0.0
var _was_grounded := true
var _cushion := false
var _fuel := 0.0
var _thrust := 0.0
var _hop_cd := 0.0
var _wheel_roll := 0.0
var _track_scroll := 0.0
var _settling := 0.0
var _boosting := false
var _spots: Array = []
var _dust: GPUParticles3D
var _burst: GPUParticles3D
var _engine: AudioStreamPlayer3D
var _under_glow: OmniLight3D
var _ray_exclude: Array[RID] = []


func setup(p_kind: String, p_tint: Color, p_height_fn: Callable) -> void:
	kind = p_kind if VehicleSpecs.SPECS.has(p_kind) else "rover"
	spec = VehicleSpecs.spec(kind)
	tint = p_tint
	height_fn = p_height_fn
	name = kind.capitalize().replace(" ", "")
	_fuel = float(spec.get("fuel_s", 0.0))
	floor_max_angle = deg_to_rad(float(spec["floor_deg"]))
	floor_snap_length = float(spec["snap"])
	floor_stop_on_slope = true
	floor_constant_speed = false
	max_slides = 5
	safe_margin = 0.02
	_build_collision()
	parts = VehicleModels.build(kind, tint)
	body = parts["body"]
	add_child(body)
	for w in parts["wheels"]:
		add_child(w["node"])
	for at in parts["lights"]:
		var s := SpotLight3D.new()
		s.position = at
		s.rotation.x = deg_to_rad(-7.0)
		s.light_color = Color(1.0, 0.95, 0.86)
		s.light_energy = 4.0
		s.spot_range = 48.0
		s.spot_angle = 30.0
		s.spot_attenuation = 0.8
		s.shadow_enabled = false
		s.visible = false
		body.add_child(s)
		_spots.append(s)
	if spec["mode"] == "hover":
		_under_glow = OmniLight3D.new()
		_under_glow.light_color = DeepFieldTheme.ICE
		_under_glow.light_energy = 0.6
		_under_glow.omni_range = 4.0
		_under_glow.position = Vector3(0, 0.1, 0)
		body.add_child(_under_glow)
	_build_dust()
	_set_flames(0.0)
	_ray_exclude = [get_rid()]
	set_physics_process(false)


func _build_collision() -> void:
	## A rounded keel (a capsule along Z) for riding over bumps, plus a box over it
	## for walls and buildings. The origin is the ground contact point.
	var hull: Vector3 = spec["hull"]
	var keel_r := minf(hull.x, hull.y) * 0.45
	var keel := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = keel_r
	cap.height = maxf(hull.z, keel_r * 2.0 + 0.1)
	keel.shape = cap
	keel.rotation.x = PI * 0.5
	keel.position.y = keel_r
	add_child(keel)
	var top := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var lift := keel_r * 0.9
	box.size = Vector3(hull.x, maxf(0.2, hull.y - lift), hull.z * 0.94)
	top.shape = box
	top.position.y = lift + box.size.y * 0.5
	add_child(top)


func _build_dust() -> void:
	_dust = _make_dust(56, 1.7, false)
	_dust.name = "Dust"
	add_child(_dust)
	_burst = _make_dust(40, 1.4, true)
	_burst.name = "LandingDust"
	add_child(_burst)


func _make_dust(amount: int, life: float, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.95 if one_shot else 0.0
	p.randomness = 0.5
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-12, -3, -12), Vector3(24, 10, 24))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var hull: Vector3 = spec["hull"]
	m.emission_box_extents = Vector3(hull.x * 0.45, 0.05, 0.35) if not one_shot else Vector3(hull.x * 0.6, 0.05, hull.z * 0.45)
	m.direction = Vector3(0, 1, 0.6) if not one_shot else Vector3(0, 0.4, 0)
	m.spread = 50.0 if not one_shot else 85.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 3.0 if not one_shot else 5.5
	m.gravity = Vector3(0, -0.35, 0)  # moon dust hangs and settles slowly
	m.damping_min = 0.6
	m.damping_max = 1.6
	m.scale_min = 0.5
	m.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	var g := Gradient.new()
	var dust := Color(0.66, 0.64, 0.62).lerp(tint, 0.08)
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(dust, 0.0), Color(dust, 0.42), Color(dust, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = _puff()
	dm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = dm
	p.draw_pass_1 = quad
	return p


static var _puff_tex: Texture2D


static func _puff() -> Texture2D:
	if _puff_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_puff_tex = t
	return _puff_tex


# --- parking, mounting --------------------------------------------------------------

func park(xform: Transform3D) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, xform.basis.get_euler().y), xform.origin)
	velocity = Vector3.ZERO
	_susp = Vector2.ZERO
	_tilt = Vector2.ZERO
	_fuel = float(spec.get("fuel_s", 0.0))
	_settling = 0.0
	_apply_visuals(0.0, 0.0)
	set_physics_process(false)


func mount(p: CharacterBody3D) -> void:
	driver = p
	_board = 0.0
	_board_from = p.global_position
	_board_yaw = p.global_rotation.y
	_ray_exclude = [get_rid(), p.get_rid()]
	add_collision_exception_with(p)
	set_physics_process(true)
	_set_lights(lights_on)
	if _engine == null:
		_engine = AudioStreamPlayer3D.new()
		_engine.bus = "SFX"
		_engine.unit_size = 10.0
		_engine.max_db = 0.0
		_engine.volume_db = -8.0
		_engine.stream = VehicleAudio.engine(String(spec["engine"]))
		add_child(_engine)
	_engine.play()


func unmount() -> void:
	if driver:
		remove_collision_exception_with(driver)
	driver = null
	_ray_exclude = [get_rid()]
	_set_lights(false)
	_set_flames(0.0)
	_dust.emitting = false
	if _engine:
		_engine.stop()
	# Let it settle under gravity where it was left, then sleep.
	_settling = 4.0
	set_physics_process(true)


func is_driven() -> bool:
	return driver != null


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func toggle_lights() -> void:
	lights_on = not lights_on
	_set_lights(lights_on and driver != null)


func _set_lights(on: bool) -> void:
	for s in _spots:
		s.visible = on


func _set_flames(f: float) -> void:
	for fl in parts.get("flames", []):
		(fl as Node3D).scale = Vector3(1.0, maxf(0.05, f), 1.0)
		(fl as Node3D).visible = f > 0.02


## Upright again, a little above whatever is below (R).
func reset_upright() -> void:
	var p := global_position
	var ground := _ground_y(p, 40.0)
	if is_nan(ground) and height_fn.is_valid():
		ground = float(height_fn.call(p.x, p.z))
	global_position = Vector3(p.x, (p.y if is_nan(ground) else ground) + 1.5, p.z)
	velocity = Vector3.ZERO
	_susp = Vector2.ZERO
	_tilt = Vector2.ZERO


## Where the driver steps off: beside the seat on the left, on the ground.
func exit_point() -> Vector3:
	var side := -global_transform.basis.x
	var hull: Vector3 = spec["hull"]
	var at := global_position + side * (hull.x * 0.5 + 1.1)
	var g := _ground_y(at, 8.0)
	if is_nan(g):
		g = float(height_fn.call(at.x, at.z)) if height_fn.is_valid() else global_position.y
	# Bailing out mid-air: step off at the seat's height and fall (low g).
	var y := g + 0.2 if is_on_floor() or _cushion else maxf(g + 0.2, global_position.y + 0.3)
	return Vector3(at.x, y, at.z)


# --- physics ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if driver == null:
		_settle(delta)
		return
	var live := driver.is_inside_tree() and driver.process_mode != Node.PROCESS_MODE_DISABLED
	var throttle := Input.get_axis("move_back", "move_forward") if live else 0.0
	var steer := Input.get_axis("move_right", "move_left") if live else 0.0
	_boosting = live and Input.is_action_pressed("sprint") and throttle > 0.1
	var braking := live and Input.is_action_pressed("crouch_descend")
	var jump_pressed := live and Input.is_action_just_pressed("jump")
	var jump_held := live and Input.is_action_pressed("jump")
	var g := VehicleSpecs.GRAVITY * float(spec["gravity_scale"])
	var mode: String = spec["mode"]
	_hop_cd = maxf(0.0, _hop_cd - delta)

	# Ground under us (hover craft ride on it; everyone tilts with it)
	var clearance := -1.0
	var ground_n := Vector3.UP
	if mode == "hover":
		var hit := _ray(global_position + Vector3.UP * 0.6, float(spec["hover"]) * 4.0 + 0.8)
		if not hit.is_empty():
			clearance = global_position.y - float(hit["position"].y)
			ground_n = hit["normal"]
	var grounded := is_on_floor()
	if mode == "hover":
		_cushion = clearance >= 0.0 and clearance < float(spec["hover"]) * 2.2
		grounded = grounded or _cushion
	elif grounded:
		ground_n = get_floor_normal()

	# Steering (heading first, then the velocity is re-read in the new frame: drift)
	var fwd_now := velocity.dot(-global_transform.basis.z)
	var yaw_rate := VehicleSpecs.yaw_rate(steer, fwd_now, braking and mode == "wheels", spec)
	if mode == "wheels" and not grounded:
		yaw_rate *= 0.35
	rotation.y += yaw_rate * delta
	var f := -global_transform.basis.z
	var r := global_transform.basis.x
	var v2 := Vector2(velocity.dot(f), velocity.dot(r))
	var control_ground := grounded or mode == "thrust"
	v2 = VehicleSpecs.drive_step(v2, throttle, _boosting, braking and mode != "thrust", control_ground, spec, delta)
	var vy := velocity.y
	var planar := f * v2.x + r * v2.y
	planar.y = 0.0

	# Vertical
	match mode:
		"hover":
			vy += VehicleSpecs.hover_accel(clearance, vy, spec) * delta
			if jump_pressed and _cushion and _hop_cd <= 0.0:
				vy = maxf(vy, 0.0) + float(spec["jump"])
				_hop_cd = 0.7
				_kick(0.12)
			# Slopes still pull a little: a hover craft drifts downhill.
			if _cushion:
				planar += Vector3(ground_n.x, 0, ground_n.z) * g * 0.5 * delta
		"thrust":
			var fs := VehicleSpecs.fuel_step(_fuel, jump_held, is_on_floor(), spec, delta)
			_fuel = fs.x
			_thrust = lerpf(_thrust, fs.y, clampf(12.0 * delta, 0.0, 1.0))
			vy += (float(spec["thrust"]) * fs.y - g) * delta
			if braking and not is_on_floor():
				vy -= g * delta
			if is_on_floor() and fs.y <= 0.0:
				vy = minf(vy, 0.0)
			_set_flames(_thrust)
		_:
			if is_on_floor():
				vy = minf(vy, 0.0) - 0.4
				planar += Vector3(ground_n.x, 0, ground_n.z) * g * delta
				if jump_pressed and float(spec["jump"]) > 0.0 and _hop_cd <= 0.0:
					vy = float(spec["jump"])
					_hop_cd = 0.5
					_kick(0.18)
			else:
				vy -= g * delta
	vy = maxf(vy, -30.0)
	velocity = Vector3(planar.x, vy, planar.z)
	var pre_vy := velocity.y
	move_and_slide()

	# Landing: the body squashes, dust flies
	var now_grounded := is_on_floor() or (mode == "hover" and _cushion)
	if now_grounded and not _was_grounded:
		var impact := minf(_airborne_vy, pre_vy)
		var sq := VehicleSpecs.landing_squash(impact, spec)
		if sq > 0.0:
			_susp.y -= sq * 9.0
			if sq > 0.06:
				_burst.global_position = global_position + Vector3(0, 0.1, 0)
				_burst.restart()
	if not now_grounded:
		_airborne_vy = minf(_airborne_vy, velocity.y) if not _was_grounded else velocity.y
	else:
		_airborne_vy = 0.0
	_was_grounded = now_grounded

	_keep_in_bounds()
	_animate(delta, v2, yaw_rate, now_grounded, clearance)
	_seat_driver()


func _settle(delta: float) -> void:
	## A left vehicle falls (or sinks onto its cushion) and sleeps.
	_settling -= delta
	var g := VehicleSpecs.GRAVITY
	if is_on_floor():
		velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
		velocity.y = -0.3
	else:
		velocity.y -= g * delta
		velocity.x = move_toward(velocity.x, 0.0, 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 2.0 * delta)
	move_and_slide()
	_keep_in_bounds()
	_animate(delta, Vector2.ZERO, 0.0, is_on_floor(), -1.0)
	if _settling <= 0.0 and is_on_floor():
		set_physics_process(false)


func _keep_in_bounds() -> void:
	var p := global_position
	p.x = clampf(p.x, -HALF_SIZE, HALF_SIZE)
	p.z = clampf(p.z, -HALF_SIZE, HALF_SIZE)
	if height_fn.is_valid():
		var h: float = height_fn.call(p.x, p.z)
		if p.y < h - 4.0:
			p.y = h + 1.5
			velocity = Vector3.ZERO
	global_position = p


func _ray(from: Vector3, length: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length)
	q.exclude = _ray_exclude
	return space.intersect_ray(q)


func _ground_y(at: Vector3, length: float) -> float:
	var hit := _ray(at + Vector3.UP * 3.0, length + 3.0)
	return float(hit["position"].y) if not hit.is_empty() else NAN


func _kick(amount: float) -> void:
	_susp.y -= amount * 6.0


# --- the look -------------------------------------------------------------------------

func _animate(delta: float, v2: Vector2, yaw_rate: float, grounded: bool, clearance: float) -> void:
	var mode: String = spec["mode"]
	var travel: float = spec["travel"]
	# Ground probes: heights under the corners give pitch and roll.
	var probes: Array = parts.get("probes", [])
	var target_tilt := Vector2.ZERO
	if probes.size() == 4 and (grounded or mode != "thrust"):
		var hs: Array = []
		var reach := 2.5 if mode != "hover" else float(spec["hover"]) * 3.0 + 1.0
		for pr in probes:
			var gp := global_transform * (pr as Vector3)
			var y := _ground_y(gp, reach)
			hs.append(y if not is_nan(y) else global_position.y - reach)
		var wb := absf((probes[0] as Vector3).z - (probes[2] as Vector3).z)
		var tw := absf((probes[0] as Vector3).x - (probes[1] as Vector3).x)
		target_tilt = VehicleSpecs.body_tilt((hs[0] + hs[1]) * 0.5, (hs[2] + hs[3]) * 0.5, (hs[0] + hs[2]) * 0.5, (hs[1] + hs[3]) * 0.5, wb, tw)
	elif mode == "thrust" and not grounded:
		target_tilt = Vector2(-v2.x * 0.012, v2.y * 0.01)
	if not grounded and mode == "wheels":
		# In the air the nose follows the arc a little.
		target_tilt.x = clampf(velocity.y * 0.03, -0.35, 0.3)
	# Hover craft lean into turns; everything squats on acceleration a little.
	var lean := 0.0
	if mode == "hover":
		lean = clampf(-yaw_rate * absf(v2.x) * 0.03, -0.45, 0.45)
	_bank = lerpf(_bank, lean, clampf(5.0 * delta, 0.0, 1.0))
	_tilt = _tilt.lerp(target_tilt, clampf(9.0 * delta, 0.0, 1.0))
	# Suspension: a spring around rest (landing kicks feed it); hover craft bob.
	var rest := 0.0
	if mode == "hover":
		rest = 0.04 * sin(Time.get_ticks_msec() * 0.004)
	_susp = VehicleSpecs.spring_step(_susp.x, _susp.y, rest, float(spec["susp_k"]), float(spec["susp_c"]), delta)
	_susp.x = clampf(_susp.x, -travel, travel)
	_apply_visuals(_tilt.x, _tilt.y - _bank)
	# Wheels: follow the ground under each one, and roll.
	_wheel_roll += v2.x * delta
	for w in parts.get("wheels", []):
		var node: Node3D = w["node"]
		var rest_p: Vector3 = w["rest"]
		var rad: float = w["radius"]
		var gp := global_transform * Vector3(rest_p.x, 0.0, rest_p.z)
		var gy := _ground_y(gp, 1.5) if grounded else NAN
		var y := rest_p.y + _susp.x * 0.3
		if not is_nan(gy):
			y = clampf(gy - global_position.y + rad, rest_p.y - travel, rest_p.y + travel)
		elif not grounded:
			y = rest_p.y - travel * 0.8  # hanging off the springs mid-air
		node.position.y = lerpf(node.position.y, y, clampf(20.0 * delta, 0.0, 1.0))
		(w["spin"] as Node3D).rotation.x = -_wheel_roll / rad
	# Tracks scroll with speed
	_track_scroll += v2.x * delta * 0.09
	for tm in parts.get("tracks", []):
		(tm as StandardMaterial3D).uv1_offset = Vector3(0.0, _track_scroll, 0.0)
	var beacon: Node3D = parts.get("beacon", null)
	if beacon:
		beacon.rotation.y += delta * 4.0
		beacon.visible = driver != null or kind == "hopper"
	# Dust: from the ground under the rear, by speed (hover craft blow it up from under the hull)
	var spd := Vector2(velocity.x, velocity.z).length()
	var near_ground := grounded or (mode == "thrust" and _thrust > 0.2 and not is_nan(_ground_y(global_position, 6.0)))
	_dust.emitting = driver != null and near_ground and (spd > 3.0 or (mode == "thrust" and _thrust > 0.2))
	if _dust.emitting:
		var hull: Vector3 = spec["hull"]
		var at := global_transform * Vector3(0, 0, hull.z * 0.45 if mode != "hover" and mode != "thrust" else 0.0)
		var gy2 := _ground_y(at, 8.0)
		_dust.global_position = Vector3(at.x, (gy2 if not is_nan(gy2) else at.y) + 0.15, at.z)
		var pm := _dust.process_material as ParticleProcessMaterial
		pm.initial_velocity_max = 1.5 + spd * 0.18 + _thrust * 4.0
		_dust.amount_ratio = clampf(0.25 + spd / float(spec["max_speed"]) + _thrust, 0.0, 1.0)
	# Flames for the jet craft follow the throttle and the boost.
	if mode == "hover":
		_set_flames((0.25 + 0.75 * clampf(absf(v2.x) / float(spec["max_speed"]), 0.0, 1.0) + (0.4 if _boosting else 0.0)) if driver != null else 0.0)
		if _under_glow:
			_under_glow.light_energy = (1.4 if driver != null else 0.5) + 0.3 * sin(Time.get_ticks_msec() * 0.006)
	# Engine
	if _engine and _engine.playing:
		var ratio := clampf(spd / float(spec["max_speed"]), 0.0, 1.5)
		_engine.pitch_scale = 0.7 + 0.75 * ratio + (0.12 if _boosting else 0.0) + _thrust * 0.4
		_engine.volume_db = -14.0 + 8.0 * clampf(ratio + _thrust, 0.0, 1.0)


func _apply_visuals(pitch: float, roll: float) -> void:
	if body == null:
		return
	var squash := clampf(-_susp.x * 0.5, -0.06, 0.16)
	body.transform = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, -roll)).scaled(Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5)), Vector3(0, _susp.x, 0))


func body_tilt_basis() -> Basis:
	return Basis.from_euler(Vector3(_tilt.x, 0.0, -(_tilt.y - _bank)))


func _seat_driver() -> void:
	if driver == null:
		return
	var seat: Vector3 = spec["seat"]
	var t := body.global_transform.orthonormalized()
	var at := t * seat
	var yaw := rotation.y
	if _board < 1.0:  # a short hop up and in, turning to face forward
		_board = minf(1.0, _board + get_physics_process_delta_time() / BOARD_S)
		var e := _board * _board * (3.0 - 2.0 * _board)
		at = _board_from.lerp(at, e) + Vector3.UP * sin(e * PI) * 0.35
		yaw = lerp_angle(_board_yaw, yaw, e)
	driver.global_position = at
	driver.global_rotation = Vector3(0.0, yaw, 0.0)
	driver.velocity = Vector3.ZERO
	var model := driver.get_node_or_null("PlayerModel") as Node3D
	if model:
		model.transform = Transform3D(body_tilt_basis() * Basis(Vector3.UP, PI), Vector3.ZERO)


## Chase camera: swing the player's camera in behind the vehicle while driving,
## unless the mouse is steering it.
func _process(delta: float) -> void:
	if driver == null:
		return
	var rig := driver.get_node_or_null("CameraRig")
	if rig == null or not ("_yaw" in rig):
		return
	if rig.has_method("get_camera_mode_name") and rig.get_camera_mode_name() == "1ST":
		return
	var mouse_busy := Input.get_last_mouse_velocity().length() > 40.0 and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	var spd := speed()
	if mouse_busy or spd < 1.5:
		return
	var yaw: float = rig.get("_yaw")
	var vel_yaw := atan2(-velocity.x, -velocity.z)
	var fwd := velocity.dot(-global_transform.basis.z) >= 0.0
	var target := lerp_angle(rotation.y, vel_yaw, 0.35) if fwd else rotation.y
	rig.set("_yaw", lerp_angle(yaw, target, clampf(delta * (1.2 + spd * 0.06), 0.0, 1.0)))
