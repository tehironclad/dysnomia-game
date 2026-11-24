class_name RocketRide
extends RideBase
## Upsilon Rocket — the fair's landmark. A 34 m checker-banded rocket with a glass
## passenger capsule stands on a raised pad beside an orange launch tower.
##
## Ride timeline (seconds):
##   0.0–4.6   elevator up the tower            "BOARDING"
##   4.6–6.2   walk the gantry arm into the capsule, hatch seals, arm swings away
##   7 / 8 / 9 "T-3" "T-2" "T-1", ignition at 9.4 (flame, pad smoke, flare light)
##   10.0      "LIFTOFF" — 8 s burn at 6 m/s², "MAX Q", "MECO" at 18 s
##   ~27.2     coast to "APOGEE 412 m" — the whole territory below
##   30.0      "FREE FALL" (lunar g, 3.27 m/s²)
##   39.0      "CHUTES OUT" — three canopies, swaying drift back over the pad
##   ~47.7     "RETRO BURN" at 45 m, ~51.6 "TOUCHDOWN", "WELCOME BACK", set down at 55 s

const PAD_H := 1.4
const PAD_R := 5.6
const SCALE := 1.3                    # rocket model scale (modelled at 1.0, built at 1.3×)
const ROCKET_BASE := PAD_H + 1.85 * SCALE   # rocket origin (engine skirt) above the ground
const CAPSULE_FLOOR := 21.0           # capsule deck, rocket space (unscaled)
const DECK_Y := ROCKET_BASE + CAPSULE_FLOOR * SCALE   # capsule deck height on the pad
const SEAT := Vector3(0.0, CAPSULE_FLOOR + 0.05, 0.35)
const TOWER_C := Vector3(-8.5, 0, 0)
const TOWER_W := 3.0
const TOWER_H := 46.0
const ARM_X0 := -7.0                  # tower face
const ARM_X1 := -1.75 * SCALE         # arm tip, next to the hatch

const T_UP := Vector2(0.6, 4.6)
const T_WALK := Vector2(4.6, 6.2)
const T_IGN := 9.4
const T_LIFT := 10.0
const BURN_A := 6.0
const BURN_T := 8.0
const APOGEE := 412.0
const T_FALL := 30.0
const T_CHUTE := 39.0
const LUNAR_G := 3.27
const CHUTE_VT := 22.0
const RETRO_H := 45.0
const DT := 0.02

var _rocket: Node3D
var _arm: Node3D
var _elevator: Node3D
var _flame: Node3D
var _flame_mat: ShaderMaterial
var _hull_mat: ShaderMaterial
var _flare: OmniLight3D
var _cabin_light: OmniLight3D
var _pad_smoke: GPUParticles3D
var _trail: GPUParticles3D
var _vent: GPUParticles3D
var _chutes: Node3D
var _capsule_glow: StandardMaterial3D
var _beacon_mat: StandardMaterial3D

var _t_apo := 0.0
var _t_retro := 0.0
var _t_touch := 0.0
var _desc := PackedFloat32Array()     # altitude table from _t_apo, DT steps
var _captions: Array = []
var _cap_idx := 0
var _arm_idle := 0.0
## Piloted voyage (RocketVoyage): at T_LIFT + VOYAGE_AT the player takes the controls.
signal voyage_handoff(ride: RocketRide)
const VOYAGE_AT := 3.0
var voyage := false
var _handed := false


func _init() -> void:
	ride_id = "rocket"
	booth_local_position = Vector3(6.2, 0, 11.0)
	exit_local_position = Vector3(3.6, 0.0, 10.5)
	booth_radius = 2.6
	reach_radius = 13.0   # walk up to the pad itself, not only the booth


# ─── Flight profile ─────────────────────────────────────────────────────

func _plan_flight() -> void:
	## Ascent is analytic (burn then coast to exactly APOGEE); descent is integrated once
	## here so the ride stays a pure function of t (free fall → chute drag → retro burn).
	var v1 := BURN_A * BURN_T
	var h1 := 0.5 * BURN_A * BURN_T * BURN_T
	var dec := v1 * v1 / (2.0 * (APOGEE - h1))
	_t_apo = T_LIFT + BURN_T + v1 / dec
	var h := APOGEE
	var v := 0.0
	var t := _t_apo
	var retro := -1.0
	_desc = PackedFloat32Array([h])
	while t < 90.0:
		var a := 0.0
		if t < T_FALL:
			a = -LUNAR_G * 0.08
		elif t < T_CHUTE:
			a = -LUNAR_G
		elif retro < 0.0:
			var open := clampf((t - T_CHUTE) / 1.5, 0.0, 1.0)
			a = -LUNAR_G + (LUNAR_G / (CHUTE_VT * CHUTE_VT)) * v * v * open
			if h < RETRO_H:
				retro = v * v / (2.0 * h)
				_t_retro = t
		if retro >= 0.0:
			a = retro
		v += a * DT
		h += v * DT
		t += DT
		if retro >= 0.0 and (v >= 0.0 or h <= 0.0):
			_desc.append(0.0)
			break
		_desc.append(maxf(h, 0.0))
	_t_touch = t
	_captions = [
		[0.1, "BOARDING"], [6.2, "HATCH SEALED"], [7.0, "T-3"], [8.0, "T-2"], [9.0, "T-1"],
		[T_LIFT, "LIFTOFF"], [13.5, "MAX Q"], [T_LIFT + BURN_T, "MECO"],
		[_t_apo, "APOGEE %d m" % int(round(APOGEE))], [T_FALL, "FREE FALL"],
		[T_CHUTE, "CHUTES OUT"], [_t_retro, "RETRO BURN"], [_t_touch, "TOUCHDOWN"],
		[_t_touch + 1.8, "WELCOME BACK"],
	]


func altitude(t: float) -> float:
	if t < T_LIFT:
		return 0.0
	var tau := t - T_LIFT
	if tau < BURN_T:
		return 0.5 * BURN_A * tau * tau
	if t < _t_apo:
		var v1 := BURN_A * BURN_T
		var h1 := 0.5 * BURN_A * BURN_T * BURN_T
		var dec := v1 * v1 / (2.0 * (APOGEE - h1))
		var s := tau - BURN_T
		return h1 + v1 * s - 0.5 * dec * s * s
	var f := (t - _t_apo) / DT
	var i := int(f)
	if i >= _desc.size() - 1:
		return 0.0
	return lerpf(_desc[i], _desc[i + 1], f - float(i))


func throttle(t: float) -> float:
	if t >= T_IGN and t < T_LIFT:
		return lerpf(0.3, 1.0, (t - T_IGN) / (T_LIFT - T_IGN))
	if t >= T_LIFT and t < T_LIFT + BURN_T:
		return 1.15
	if t >= _t_retro and t < _t_touch + 0.15 and _t_retro > 0.0:
		return 0.85
	return 0.0


# ─── Build ──────────────────────────────────────────────────────────────

func _build() -> void:
	_plan_flight()
	var batch := FairKit.Batch.new()
	_build_pad(batch)
	_build_tower(batch)
	_build_rocket()
	_build_effects()
	FairKit.ticket_booth(self, batch, booth_local_position, Vector3(signf(booth_local_position.x) * absf(0.25), 0, 1), item, Color(1.0, 0.35, 0.2))
	_build_props(batch)
	batch.flush(self)


func _build_pad(batch: FairKit.Batch) -> void:
	var concrete := FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3)
	var deck := FairKit.pbr("metal_plate", Color(0.75, 0.75, 0.78), 0.5, 1.0)
	var pad := FairKit.mesh(self, FairKit.cyl_mesh(PAD_R, PAD_R + 0.5, PAD_H, 8), Vector3(0, PAD_H * 0.5, 0), concrete)
	pad.rotation.y = PI / 8.0
	FairKit.mesh(self, FairKit.cyl_mesh(PAD_R - 0.4, PAD_R - 0.4, 0.06, 8), Vector3(0, PAD_H + 0.03, 0), deck).rotation.y = PI / 8.0
	# Flame trench grate + scorched ring
	FairKit.cyl(self, 2.3, 2.3, 0.03, Vector3(0, PAD_H + 0.07, 0), FairKit.paint(Color(0.03, 0.03, 0.03), 0.95, 0.3), 24)
	for i in 9:
		var x := -2.0 + i * 0.5
		var hw := sqrt(maxf(2.3 * 2.3 - x * x, 0.0))
		FairKit.box(self, Vector3(0.08, 0.06, hw * 2.0), Vector3(x, PAD_H + 0.1, 0), FairKit.paint(Color(0.18, 0.17, 0.16), 0.6, 0.8))
	# Hazard chevrons round the deck edge
	var yellow := FairKit.paint(Color(0.95, 0.72, 0.05), 0.55, 0.1)
	var black := FairKit.paint(Color(0.04, 0.04, 0.04), 0.6, 0.1)
	for i in 32:
		var a := TAU * i / 32.0
		var p := Vector3(cos(a), 0, sin(a)) * (PAD_R - 0.7) + Vector3(0, PAD_H + 0.075, 0)
		var b := FairKit.box(self, Vector3(0.95, 0.02, 0.35), p, yellow if i % 2 == 0 else black)
		b.rotation.y = -a + PI * 0.5
	# Hold-down clamps
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		FairKit.box(self, Vector3(0.6, 0.9, 0.6), d * 2.9 + Vector3(0, PAD_H + 0.45, 0), FairKit.paint(Color(0.25, 0.26, 0.28), 0.5, 0.7)).rotation.y = -a
	# Stairs up the pad toward the booth
	for s in 7:
		FairKit.box(self, Vector3(2.4, 0.2, 0.45), Vector3(2.2, 0.1 + s * 0.2, PAD_R + 1.5 - s * 0.42), concrete)
	# Pad edge lights
	var ring := FairKit.ring_points(Vector3(0, PAD_H + 0.12, 0), PAD_R - 0.15, 24)
	batch.bulb_line(ring, [Color(1.0, 0.25, 0.15), FairKit.BULB_WARM], 0.08, 0.06)
	batch.pool(Vector3(0, 0.08, 0), PAD_R + 4.0, Color(1.0, 0.5, 0.3) * 0.35)
	FairKit.solid_cyl(self, PAD_R, PAD_H, Vector3(0, PAD_H * 0.5, 0))
	# Floodlights aimed up the rocket (the landmark at night)
	for sx in [-1.0, 1.0]:
		var base := Vector3(3.0 * sx, PAD_H, 4.4)
		FairKit.box(self, Vector3(0.5, 0.35, 0.3), base + Vector3(0, 0.35, 0), FairKit.paint(Color(0.15, 0.15, 0.16), 0.5, 0.6))
		FairKit.box(self, Vector3(0.42, 0.28, 0.02), base + Vector3(0, 0.4, -0.16), FairKit.glow(Color(1.0, 0.95, 0.85), 6.0, 0.5))
		FairKit.spot(self, base + Vector3(0, 0.5, -0.3), Vector3(0, 20.0, 0), Color(1.0, 0.92, 0.82), 9.0, 45.0, 22.0, 0.0)


func _build_tower(batch: FairKit.Batch) -> void:
	var steel := FairKit.paint(Color(0.78, 0.25, 0.08), 0.55, 0.45)
	var grey := FairKit.paint(Color(0.32, 0.33, 0.35), 0.5, 0.7)
	var hw := TOWER_W * 0.5
	var corners := [Vector3(-hw, 0, -hw), Vector3(hw, 0, -hw), Vector3(hw, 0, hw), Vector3(-hw, 0, hw)]
	for c in corners:
		batch.strut(TOWER_C + c, TOWER_C + c + Vector3.UP * TOWER_H, 0.11, steel)
	var bay := 2.4
	var nb := int(TOWER_H / bay)
	for b in nb:
		var y0 := b * bay
		var y1 := y0 + bay
		for k in 4:
			var c0: Vector3 = corners[k]
			var c1: Vector3 = corners[(k + 1) % 4]
			batch.strut(TOWER_C + c0 + Vector3.UP * y1, TOWER_C + c1 + Vector3.UP * y1, 0.06, steel)
			if k == 1:
				continue  # rocket-facing side stays open for the elevator door
			if b % 2 == 0:
				batch.strut(TOWER_C + c0 + Vector3.UP * y0, TOWER_C + c1 + Vector3.UP * y1, 0.045, steel)
			else:
				batch.strut(TOWER_C + c1 + Vector3.UP * y0, TOWER_C + c0 + Vector3.UP * y1, 0.045, steel)
	# Base plinth, top platform, lightning mast
	FairKit.box(self, Vector3(TOWER_W + 1.0, 0.4, TOWER_W + 1.0), TOWER_C + Vector3(0, 0.2, 0), FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3))
	FairKit.box(self, Vector3(TOWER_W + 1.2, 0.18, TOWER_W + 1.2), TOWER_C + Vector3(0, TOWER_H, 0), FairKit.pbr("metal_plate", Color.WHITE, 0.5, 1.0))
	batch.strut(TOWER_C + Vector3(0, TOWER_H, 0), TOWER_C + Vector3(0, TOWER_H + 9.0, 0), 0.08, grey)
	_beacon_mat = FairKit.glow(Color(1.0, 0.08, 0.04), 8.0, 3.0)
	FairKit.mesh(self, FairKit.sphere_mesh(0.22, 12), TOWER_C + Vector3(0, TOWER_H + 9.1, 0), _beacon_mat, Vector3.ZERO, false)
	for c in corners:
		FairKit.mesh(self, FairKit.sphere_mesh(0.14, 8), TOWER_C + c * 1.15 + Vector3(0, TOWER_H + 0.2, 0), _beacon_mat, Vector3.ZERO, false)
	# Tower name boards
	var title := FairKit.label(self, "UPSILON", TOWER_C + Vector3(0, TOWER_H - 7.0, hw + 0.08), 150, Color(1.8, 1.6, 1.3), 0.0)
	title.outline_size = 18
	title.rotation.z = -PI * 0.5
	var title2 := FairKit.label(self, "UPSILON", TOWER_C + Vector3(0, TOWER_H - 7.0, -hw - 0.08), 150, Color(1.8, 1.6, 1.3), PI)
	title2.outline_size = 18
	title2.rotation.z = -PI * 0.5
	# Tower edge lights up all four chords
	for c in corners:
		var pts := PackedVector3Array()
		for i in 37:
			pts.append(TOWER_C + c * 1.06 + Vector3.UP * (1.0 + i * 1.22))
		batch.bulb_line(pts, [FairKit.BULB_WARM, Color(1.0, 0.4, 0.2)], 0.05, 0.06)
	# Elevator cage
	_elevator = Node3D.new()
	_elevator.position = TOWER_C
	add_child(_elevator)
	var cage := FairKit.paint(Color(0.85, 0.85, 0.82), 0.4, 0.6)
	FairKit.box(_elevator, Vector3(2.2, 0.1, 2.2), Vector3(0, 0.05, 0), FairKit.pbr("metal_plate", Color.WHITE, 0.6, 1.0))
	FairKit.box(_elevator, Vector3(2.2, 0.08, 2.2), Vector3(0, 2.4, 0), cage)
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		FairKit.beam(_elevator, c * 1.05, c * 1.05 + Vector3.UP * 2.4, 0.04, cage)
	FairKit.box(_elevator, Vector3(1.9, 0.04, 0.04), Vector3(0, 2.32, 0), FairKit.glow(Color(0.7, 0.9, 1.0), 4.0, 1.0))
	FairKit.solid_box(self, Vector3(TOWER_W, 3.0, TOWER_W), TOWER_C + Vector3(0, 1.5, 0))
	# Gantry arm (hinged at the tower face, swings clear before ignition)
	_arm = Node3D.new()
	_arm.position = Vector3(ARM_X0, DECK_Y, 0)
	add_child(_arm)
	var arm_len := ARM_X1 - ARM_X0
	FairKit.box(_arm, Vector3(arm_len, 0.12, 1.3), Vector3(arm_len * 0.5, -0.06, 0), FairKit.pbr("metal_plate", Color.WHITE, 0.6, 1.0))
	for z in [-0.62, 0.62]:
		FairKit.beam(_arm, Vector3(0, 1.05, z), Vector3(arm_len, 1.05, z), 0.03, grey)
		FairKit.beam(_arm, Vector3(0, -0.6, z), Vector3(arm_len, -0.1, z), 0.06, steel)
		for i in 5:
			var x := arm_len * i / 4.0
			FairKit.beam(_arm, Vector3(x, 0, z), Vector3(x, 1.05, z), 0.025, grey)
	FairKit.box(_arm, Vector3(0.5, 2.3, 1.5), Vector3(arm_len - 0.1, 1.15, 0), FairKit.paint(Color(0.92, 0.9, 0.86), 0.4, 0.3))
	FairKit.box(_arm, Vector3(0.52, 1.9, 0.9), Vector3(arm_len - 0.1, 0.95, 0), FairKit.paint(Color(0.05, 0.05, 0.06), 0.4, 0.3))
	FairKit.box(_arm, Vector3(arm_len, 0.04, 0.04), Vector3(arm_len * 0.5, 2.2, 0), FairKit.glow(Color(1.0, 0.8, 0.5), 3.0, 0.6))


func _build_rocket() -> void:
	_rocket = Node3D.new()
	_rocket.name = "Rocket"
	_rocket.position = Vector3(0, ROCKET_BASE, 0)
	_rocket.scale = Vector3.ONE * SCALE
	add_child(_rocket)
	_hull_mat = ShaderMaterial.new()
	_hull_mat.shader = load("res://assets/shaders/fair_rocket.gdshader")
	_hull_mat.set_shader_parameter("checker_lo", 11.5)
	_hull_mat.set_shader_parameter("checker_hi", 17.5)
	_hull_mat.set_shader_parameter("scorch", 0.4)
	# Lower hull: skirt → body → shoulder below the capsule
	var body := PackedVector2Array([
		Vector2(1.25, -0.2), Vector2(1.95, 0.0), Vector2(1.95, 0.35), Vector2(1.62, 1.3),
		Vector2(1.62, 20.4), Vector2(1.5, 20.8), Vector2(1.5, CAPSULE_FLOOR - 0.05)])
	FairKit.mesh(_rocket, FairKit.lathe(body, 40), Vector3.ZERO, _hull_mat)
	# Nose ogive above the capsule
	var nose := PackedVector2Array()
	var y0 := CAPSULE_FLOOR + 3.4
	nose.append(Vector2(1.5, y0 - 0.1))
	for i in 13:
		var u := float(i) / 12.0
		nose.append(Vector2(1.5 * sqrt(maxf(1.0 - u * u, 0.0)) * (1.0 - 0.15 * u), y0 + u * 6.4))
	FairKit.mesh(_rocket, FairKit.lathe(nose, 40), Vector3.ZERO, _hull_mat)
	var tip := FairKit.glow(Color(1.0, 0.12, 0.06), 6.0, 2.0)
	FairKit.mesh(_rocket, FairKit.sphere_mesh(0.12, 10), Vector3(0, y0 + 6.45, 0), tip, Vector3.ZERO, false)
	# Glass capsule: frame ribs, floor, seats, glow rings
	var frame := FairKit.paint(Color(0.85, 0.85, 0.86), 0.3, 0.85)
	FairKit.cyl(_rocket, 1.5, 1.5, 0.12, Vector3(0, CAPSULE_FLOOR - 0.06, 0), frame, 40)
	FairKit.cyl(_rocket, 1.5, 1.5, 0.12, Vector3(0, y0 - 0.06, 0), frame, 40)
	FairKit.cyl(_rocket, 1.38, 1.38, 3.4, Vector3(0, CAPSULE_FLOOR + 1.7, 0), FairKit.glass(Color(0.7, 0.85, 1.0, 0.12)), 40)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var d := Vector3(cos(a), 0, sin(a)) * 1.42
		FairKit.beam(_rocket, d + Vector3.UP * CAPSULE_FLOOR, d + Vector3.UP * y0, 0.05, frame)
	FairKit.cyl(_rocket, 1.36, 1.36, 0.06, Vector3(0, CAPSULE_FLOOR + 0.03, 0), FairKit.pbr("metal_plate", Color(0.8, 0.8, 0.85), 0.8, 1.0), 32)
	_capsule_glow = FairKit.glow(Color(0.35, 0.85, 1.0), 4.5, 1.5)
	FairKit.mesh(_rocket, FairKit.torus_mesh(1.3, 1.38, 40, 6), Vector3(0, CAPSULE_FLOOR + 0.1, 0), _capsule_glow, Vector3.ZERO, false)
	FairKit.mesh(_rocket, FairKit.torus_mesh(1.3, 1.38, 40, 6), Vector3(0, y0 - 0.15, 0), _capsule_glow, Vector3.ZERO, false)
	var seat := FairKit.paint(Color(0.12, 0.12, 0.14), 0.6, 0.1)
	for sx in [-0.55, 0.55]:
		FairKit.box(_rocket, Vector3(0.55, 0.45, 0.55), Vector3(sx, CAPSULE_FLOOR + 0.25, -0.55), seat)
		FairKit.box(_rocket, Vector3(0.55, 0.8, 0.12), Vector3(sx, CAPSULE_FLOOR + 0.8, -0.85), seat)
	FairKit.box(_rocket, Vector3(1.0, 0.9, 0.3), Vector3(0, CAPSULE_FLOOR + 0.45, 0.95), FairKit.paint(Color(0.2, 0.2, 0.22), 0.4, 0.6))
	FairKit.box(_rocket, Vector3(0.8, 0.3, 0.02), Vector3(0, CAPSULE_FLOOR + 0.85, 0.79), FairKit.glow(Color(0.3, 1.0, 0.7), 3.0, 1.2))
	# Fins (swept, extruded) and engine bell
	var fin_mat := FairKit.paint(Color(0.78, 0.07, 0.12), 0.35, 0.3, 0.6)
	var fin := FairKit.extrude(PackedVector2Array([
		Vector2(1.5, 0.2), Vector2(3.6, -1.75), Vector2(4.0, -1.75), Vector2(4.0, 0.9), Vector2(1.5, 6.5)]), 0.16)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var fm := FairKit.mesh(_rocket, fin, Vector3.ZERO, fin_mat)
		fm.rotation.y = -a
		var foot := FairKit.cyl(_rocket, 0.25, 0.32, 0.12, Vector3(cos(a) * 3.85, -1.75, sin(a) * 3.85), FairKit.paint(Color(0.2, 0.2, 0.2), 0.6, 0.7), 12)
		foot.position.y = -1.8
	var bell := PackedVector2Array([Vector2(0.55, 0.0), Vector2(0.75, -0.5), Vector2(1.2, -1.5), Vector2(1.25, -1.6)])
	FairKit.mesh(_rocket, FairKit.lathe(bell, 28), Vector3.ZERO, FairKit.paint(Color(0.22, 0.2, 0.2), 0.35, 0.9))
	var bell_in := PackedVector2Array([Vector2(1.2, -1.58), Vector2(0.7, -0.45), Vector2(0.5, 0.0)])
	FairKit.mesh(_rocket, FairKit.lathe(bell_in, 28), Vector3.ZERO, FairKit.paint(Color(0.35, 0.2, 0.12), 0.6, 0.6))
	# Name plate down the body
	var nm := FairKit.label(_rocket, "U P S I L O N", Vector3(0, 8.0, 1.64), 64, Color(0.08, 0.06, 0.08), 0.0, Color(0, 0, 0, 0))
	nm.rotation.z = PI * 0.5
	nm.shaded = true
	# Parachutes (hidden until deployed)
	_chutes = Node3D.new()
	_chutes.position = Vector3(0, y0 + 6.4, 0)
	_chutes.visible = false
	_rocket.add_child(_chutes)
	var cb := FairKit.Batch.new()
	var dome := PackedVector2Array()
	for i in 9:
		var a2 := PI * 0.5 * float(i) / 8.0
		dome.append(Vector2(sin(a2) * 5.0, cos(a2) * 2.6))
	var dmesh := FairKit.lathe(dome, 24)
	for k in 3:
		var a3 := TAU * k / 3.0
		var off := Vector3(cos(a3) * 4.2, 15.0, sin(a3) * 4.2)
		var d := FairKit.mesh(_chutes, dmesh, off, FairKit.shader_mat("fair_awning"))
		d.rotation = Vector3(sin(a3) * 0.28, 0, -cos(a3) * 0.28)
		d.set_instance_shader_parameter("color_a", Color(1.0, 0.45, 0.08))
		d.set_instance_shader_parameter("color_b", Color(0.96, 0.95, 0.92))
		d.set_instance_shader_parameter("stripes", 12.0)
		for j in 8:
			var aj := TAU * j / 8.0
			var rim := d.transform * Vector3(cos(aj) * 5.0, 0.0, sin(aj) * 5.0)
			cb.strut(Vector3.ZERO, rim, 0.02, FairKit.paint(Color(0.9, 0.9, 0.85), 0.7, 0.0))
	cb.flush(_chutes)


func _build_effects() -> void:
	_flame = Node3D.new()
	_flame.position = Vector3(0, -1.55, 0)
	_flame.visible = false
	_rocket.add_child(_flame)
	_flame_mat = FairKit.shader_mat("fair_flame", "rocket")
	var outer := PackedVector2Array([Vector2(1.15, 0.0), Vector2(1.25, -2.0), Vector2(0.9, -6.0), Vector2(0.0, -11.0)])
	var inner := PackedVector2Array([Vector2(0.85, 0.0), Vector2(0.6, -2.5), Vector2(0.0, -5.5)])
	FairKit.mesh(_flame, FairKit.lathe(outer, 24), Vector3.ZERO, _flame_mat, Vector3.ZERO, false)
	FairKit.mesh(_flame, FairKit.lathe(inner, 24), Vector3.ZERO, _flame_mat, Vector3.ZERO, false)
	_flare = OmniLight3D.new()
	_flare.light_color = Color(1.0, 0.62, 0.3)
	_flare.omni_range = 70.0
	_flare.omni_attenuation = 1.4
	_flare.shadow_enabled = false
	_flare.light_energy = 0.0
	_flare.visible = false
	_flare.position = Vector3(0, -4.0, 0)
	_rocket.add_child(_flare)
	# Cabin light so the rider reads inside the glass at night (only lit while riding)
	_cabin_light = OmniLight3D.new()
	_cabin_light.light_color = Color(0.75, 0.92, 1.0)
	_cabin_light.light_energy = 1.6
	_cabin_light.omni_range = 4.5
	_cabin_light.shadow_enabled = false
	_cabin_light.position = Vector3(0, CAPSULE_FLOOR + 2.8, 0.2)
	_cabin_light.visible = false
	_rocket.add_child(_cabin_light)
	# Ground cloud: billows out across the pad and beyond
	_pad_smoke = FairKit.smoke(220, 7.0, Vector2(3.0, 10.0), Color(0.78, 0.76, 0.74), 30.0,
		Vector2(0.5, 2.0), 5.5, Vector3(0, 0.12, 0), 2.2, true, Vector3.UP, 9.0)   # stops ~9 m out: stays on the pad
	_pad_smoke.position = Vector3(0, PAD_H + 0.3, 0)
	add_child(_pad_smoke)
	# Exhaust trail follows the rocket (world-space particles)
	_trail = FairKit.smoke(140, 4.0, Vector2(2.0, 7.0), Color(0.8, 0.78, 0.76), 10.0,
		Vector2(10.0, 16.0), 5.0, Vector3(0, 0.1, 0), 0.6, true, Vector3.DOWN)
	_trail.position = Vector3(0, -6.0, 0)
	_trail.visibility_aabb = AABB(Vector3(-60, -450, -60), Vector3(120, 500, 120))
	_rocket.add_child(_trail)
	# LOX boil-off vapour venting from the shoulder while it waits
	_vent = FairKit.smoke(26, 3.5, Vector2(0.6, 2.6), Color(0.92, 0.94, 0.97), 25.0,
		Vector2(0.8, 1.6), 0.6, Vector3(0, -0.35, 0), 0.15, false)
	_vent.position = Vector3(1.55, 19.8, 0.4)
	(_vent.process_material as ParticleProcessMaterial).direction = Vector3(1, -0.2, 0)
	_rocket.add_child(_vent)
	_vent.emitting = true


func _build_props(batch: FairKit.Batch) -> void:
	# Fuel lines from the tower base to the rocket skirt, barrels, a generator
	var pipe := FairKit.paint(Color(0.85, 0.85, 0.8), 0.35, 0.8)
	for z in [-0.5, 0.5]:
		batch.strut(TOWER_C + Vector3(1.6, 0.6, z), Vector3(-4.5, PAD_H + 0.25, z), 0.09, pipe)
		batch.strut(Vector3(-4.5, PAD_H + 0.25, z), Vector3(-2.2, PAD_H + 0.25, z), 0.09, pipe)
	for i in 5:
		var p := TOWER_C + Vector3(-1.0 + (i % 3) * 0.62, 0, -2.6 - int(i / 3) * 0.62)
		batch.prop("Barrel_01", Transform3D(Basis(Vector3.UP, i * 0.7), p + Vector3(0, 0.006, 0)))
	FairKit.model(self, "portable_generator", TOWER_C + Vector3(0.5, 0.4, 2.6), 0.3)
	FairKit.model(self, "wooden_crate_01", TOWER_C + Vector3(-1.6, 0.4, 2.6), 1.2)
	FairKit.model(self, "wooden_crate_01", TOWER_C + Vector3(-1.5, 0.75, 2.55), 1.5)


# ─── Animation ──────────────────────────────────────────────────────────

func _idle_tick(time: float, delta: float) -> void:
	_beacon_mat.emission_energy_multiplier = (8.0 if fmod(time, 1.6) < 0.25 else 0.4) * (0.5 + 0.5 * FairKit.night)
	_arm_idle = move_toward(_arm_idle, 0.0, delta * 0.4)
	_arm.rotation.y = _arm_idle
	_elevator.position.y = move_toward(_elevator.position.y, 0.0, delta * 4.0)
	_rocket.position = _rocket.position.move_toward(Vector3(0, ROCKET_BASE, 0), delta * 5.0)
	_rocket.rotation = Vector3.ZERO
	_vent.emitting = true
	_trail.emitting = false
	_pad_smoke.emitting = false
	_flame.visible = false
	_flare.visible = false
	_chutes.visible = false


func _on_ride_end() -> void:
	_cabin_light.visible = false


func _on_ride_start() -> void:
	_cabin_light.visible = true
	_cap_idx = 0
	_handed = false


func _ride_tick(t: float, _delta: float) -> void:
	if voyage and not _handed and t >= T_LIFT + VOYAGE_AT:
		_handed = true
		paused = true
		voyage_handoff.emit(self)
		return
	_beacon_mat.emission_energy_multiplier = (8.0 if fmod(t, 1.6) < 0.25 else 0.4) * (0.5 + 0.5 * FairKit.night)
	# Captions: emit the latest one we've passed (robust to frame skips)
	var cap := ""
	while _cap_idx < _captions.size() and t >= float(_captions[_cap_idx][0]):
		cap = _captions[_cap_idx][1]
		_cap_idx += 1
	if cap != "":
		ride_caption.emit(cap)
	# Elevator + arm
	_elevator.position.y = _elevator_y(t)
	var swing := smoothstep(6.4, 8.2, t) * (1.0 - smoothstep(_t_touch + 1.0, _t_touch + 3.0, t))
	_arm.rotation.y = swing * 1.75
	_arm_idle = _arm.rotation.y
	# Rocket
	var h := altitude(t)
	var thr := throttle(t)
	var shake := 0.0
	if thr > 0.0 and h < 60.0:
		shake = 0.035 * thr * (1.0 - h / 60.0)
	var drift := Vector3.ZERO
	var tilt := Vector3.ZERO
	if t > T_CHUTE and t < _t_touch:
		var u := (t - T_CHUTE) / (_t_touch - T_CHUTE)
		drift = Vector3(sin(PI * u) * 7.0, 0, sin(PI * u * 2.0) * 3.0)
		tilt = Vector3(sin(t * 1.3) * 0.05, 0, sin(t * 0.9) * 0.06) * sin(PI * u)
	elif t > T_LIFT and t < _t_apo:
		var u2 := (t - T_LIFT) / (_t_apo - T_LIFT)
		tilt = Vector3(0, 0, sin(PI * u2) * 0.03)   # tiny gravity-turn lean, back to vertical at apogee
	_rocket.position = Vector3(0, ROCKET_BASE + h, 0) + drift + Vector3(sin(t * 91.0), 0, cos(t * 77.0)) * shake
	_rocket.rotation = tilt
	_rocket.rotation.y = t * 0.02 * float(t > T_LIFT and t < _t_touch)
	# Engine
	_flame.visible = thr > 0.0
	_flame_mat.set_shader_parameter("throttle", thr)
	_flame.scale = Vector3(1.0, 0.55 + 0.6 * thr + 0.06 * sin(t * 47.0), 1.0)
	_flare.visible = thr > 0.0
	_flare.light_energy = 16.0 * thr * (0.9 + 0.1 * sin(t * 53.0))
	_hull_mat.set_shader_parameter("scorch", 0.4 + 0.6 * smoothstep(T_LIFT, T_LIFT + 6.0, t))
	_pad_smoke.emitting = (t > T_IGN and t < T_LIFT + 3.5) or (thr > 0.0 and h < 25.0 and t > _t_apo)
	_trail.emitting = thr > 0.0 and t > T_LIFT and h < 45.0   # exhaust cloud stays low, near the pad
	_vent.emitting = t < T_IGN
	# Chutes
	var chute := 0.0
	if t > T_CHUTE:
		chute = smoothstep(T_CHUTE, T_CHUTE + 1.5, t) * (1.0 - smoothstep(_t_touch - 0.5, _t_touch + 1.0, t))
	_chutes.visible = chute > 0.01
	_chutes.scale = Vector3(chute, maxf(chute, 0.05) * (0.8 + 0.2 * chute), chute)
	# Capsule lights pulse during the countdown
	if t > 6.5 and t < T_LIFT:
		_capsule_glow.emission_energy_multiplier = 4.0 + 3.0 * absf(sin(t * PI))


## The flying parts, for RocketVoyage (it reparents the rocket, then gives it back).
func rocket_node() -> Node3D:
	return _rocket


func set_engine(thr: float, t: float) -> void:
	_flame.visible = thr > 0.0
	_flame_mat.set_shader_parameter("throttle", thr)
	_flame.scale = Vector3(1.0, 0.55 + 0.9 * thr + 0.06 * sin(t * 47.0), 1.0)
	_flare.visible = thr > 0.0
	_flare.light_energy = 16.0 * thr
	_trail.emitting = false
	_pad_smoke.emitting = false


## Back from a voyage the player aborted: rocket home on the pad, rider set down.
func voyage_returned() -> void:
	var r := _rocket
	if r.get_parent() != self:
		r.get_parent().remove_child(r)
		add_child(r)
	r.position = Vector3(0, ROCKET_BASE, 0)
	r.rotation = Vector3.ZERO
	r.scale = Vector3.ONE * SCALE
	paused = false
	end_ride()


func _elevator_y(t: float) -> float:
	var top := DECK_Y
	if t < T_UP.x:
		return 0.0
	if t < T_UP.y:
		return top * smoothstep(T_UP.x, T_UP.y, t)
	return top * (1.0 - smoothstep(T_WALK.y + 0.5, T_WALK.y + 4.0, t))


func get_seat_transform(t: float) -> Transform3D:
	var top := DECK_Y
	var p: Vector3
	if t < T_UP.y:
		p = to_global(TOWER_C + Vector3(0.4, _elevator_y(t) + 0.08, 0.0))
	elif t < T_WALK.y:
		var u := smoothstep(T_WALK.x, T_WALK.y, t)
		var a := TOWER_C + Vector3(0.4, top + 0.02, 0)
		var b := Vector3(SEAT.x, top + 0.05, SEAT.z * SCALE)
		p = to_global(a.lerp(b, u))
	elif t < ride_duration() - 0.05:
		p = _rocket.global_transform * SEAT
	else:
		p = to_global(exit_local_position)
	return Transform3D(global_transform.basis, p)
