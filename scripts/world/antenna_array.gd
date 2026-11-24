extends Node3D
## Comm Array — the territory's relay station at (-50, 0) on a site main.gd levels for it.
##   - concrete compound with paved walkways inside a chain-link fence (barbed outriggers,
##     post lights) and a lit "COMM ARRAY" gate arch with a station ID plate
##   - tapered lattice mast in aviation orange/white with platforms, sector panels,
##     microwave drums, rotating radar, obstruction lights, cyan relay coils and crystal
##     resonators (glow = territory activity)
##   - two ground dishes on az/el pedestal mounts, slowly tracking
##   - telecom cabinets (louvres, labels, grime, LEDs, link screens) under a canopy with
##     cable trays, a relay shelter with waveguide bridge, generator + day tank, parked rover
## The uplink beam, LED blink rate, relay glow and screens follow HYPO/EPI and CHARGE.
## Deterministic from the territory seed.

const Kit = preload("res://scripts/world/structures/struct_kit.gd")
const CHAINLINK_SHADER := preload("res://assets/shaders/struct_chainlink.gdshader")

const TOWER_HEIGHT: float = 20.0
const BASE_W: float = 3.2
const TOP_W: float = 1.0
const BEACON_BLINK_INTERVAL: float = 1.5
const FENCE_HALF: float = 10.5

var _dish_pivots: Array[Node3D] = []   # Ground dishes: azimuth pivots
var _dish_elev: Array[Node3D] = []     # ...and their elevation pivots
var _dish_speeds: Array[float] = []
var _radar: Node3D
var _beacon_light: OmniLight3D
var _beacon_material: StandardMaterial3D
var _obstruction_mat: StandardMaterial3D
var _led_mats: Array[StandardMaterial3D] = []
var _link_screens: Array[ShaderMaterial] = []
var _uplink: MeshInstance3D
var _beacon_timer: float = 0.0
var _beacon_on: bool = true
var _activity: float = 0.3
var _power: float = 0.3
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _relay_mat: StandardMaterial3D
var _gate_half: float = 2.1


func initialize(seed_value: int) -> void:
	_rng.seed = seed_value + 4400
	_build_compound_floor()
	_build_foundations()
	_build_mast()
	_build_mast_antennas()
	_build_beacon()
	_build_relay_crystals()
	_build_ground_dishes()
	_build_equipment()
	_build_shelter()
	_build_fence()
	_build_gate_arch()
	_build_access_road()
	_build_rover()
	_build_crate_stack()
	_build_lighting()
	_build_crew(seed_value)
	var keep: Array = [_radar]
	keep.append_array(_dish_pivots)
	Kit.merge_static(self, keep)
	if not GameManager.territory_state_changed.is_connected(_on_territory_state_changed):
		GameManager.territory_state_changed.connect(_on_territory_state_changed)
	_apply_territory_state()


func _on_territory_state_changed(_data: Dictionary) -> void:
	_apply_territory_state()


func _apply_territory_state() -> void:
	_power = clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
	var hypo := clampf(float(GameManager.territory_hypobar) / 1e12, 0.0, 1.0)
	var epi := clampf(float(GameManager.territory_epibar) / 1e12, 0.0, 1.0)
	_activity = clampf(hypo + epi, 0.0, 1.0)
	for m in _link_screens:
		m.set_shader_parameter("value_a", _power)
		m.set_shader_parameter("value_b", maxf(hypo, _activity * 0.6))
		m.set_shader_parameter("value_c", epi)
	if _uplink:
		_uplink.set_instance_shader_parameter("tint", Color(0.35, 0.8, 1.0, 0.1 + _activity * 0.35))


func _process(delta: float) -> void:
	_time += delta
	Kit.update_night()
	# Ground dishes slew slowly (az) and nod (el); the radar sweeps
	for i in _dish_pivots.size():
		_dish_pivots[i].rotation.y += _dish_speeds[i] * delta
		_dish_elev[i].rotation.x = -0.75 + sin(_time * 0.11 + float(i) * 2.0) * 0.25
	if _radar:
		_radar.rotation.y += delta * 1.1

	# Obstruction lights: synchronised slow blink (beacon + mid-mast)
	_beacon_timer += delta
	if _beacon_timer >= BEACON_BLINK_INTERVAL:
		_beacon_timer -= BEACON_BLINK_INTERVAL
		_beacon_on = not _beacon_on
		if _beacon_light:
			_beacon_light.light_energy = 3.0 if _beacon_on else 0.0
		if _beacon_material:
			_beacon_material.emission_energy_multiplier = 6.0 if _beacon_on else 0.1
		if _obstruction_mat:
			_obstruction_mat.emission_energy_multiplier = 4.0 if _beacon_on else 0.2

	if _relay_mat:
		_relay_mat.emission_energy_multiplier = 1.8 + _activity * 3.0 + sin(_time * (1.5 + _activity * 4.0)) * 0.8

	# Cabinet LEDs: data traffic — faster flicker with more territory activity
	var rate := 2.0 + _activity * 14.0
	for i in _led_mats.size():
		var on := fmod(_time * rate * (0.6 + float(i % 5) * 0.17) + float(i) * 0.37, 1.0) < 0.55
		_led_mats[i].emission_energy_multiplier = 3.5 if on else 0.3


# ─── Terrain ────────────────────────────────────────────────────────

func _h(x: float, z: float) -> float:
	## Ground height at local (x, z), relative to this node. 0 if no terrain is reachable.
	var p := get_parent()
	if p == null:
		return 0.0
	var terr = p.get("territory")
	if terr and is_instance_valid(terr) and terr.has_method("get_height_at"):
		return float(terr.get_height_at(position.x + x, position.z + z)) - position.y
	return 0.0


# ─── Mast ───────────────────────────────────────────────────────────

var _mast_base_y: float = 0.0


func _build_foundations() -> void:
	_mast_base_y = _footing(Vector3.ZERO, Vector2(BASE_W + 1.6, BASE_W + 1.6))


func _leg(k: int, y: float) -> Vector3:
	## Leg k (0..3) position at height y above the mast base (tapered square).
	var t := y / TOWER_HEIGHT
	var w := lerpf(BASE_W, TOP_W, t) * 0.5
	var c := [Vector3(w, 0, w), Vector3(-w, 0, w), Vector3(-w, 0, -w), Vector3(w, 0, -w)][k] as Vector3
	return c + Vector3(0, _mast_base_y + y, 0)


func _build_mast() -> void:
	## Lattice mast painted in aviation orange/white bands (one MultiMesh per colour).
	var orange: Array = []
	var white: Array = []
	var bands := 7
	var bay := 1.6
	var n := int(TOWER_HEIGHT / bay)
	for i in n:
		var y0 := float(i) * bay
		var y1 := float(i + 1) * bay
		var band := int(y0 / (TOWER_HEIGHT / float(bands)))
		var out: Array = orange if band % 2 == 0 else white
		for k in 4:
			out.append(Kit.beam_xform(_leg(k, y0), _leg(k, y1), 0.075 - 0.03 * (y0 / TOWER_HEIGHT)))
			var k2 := (k + 1) % 4
			# X-bracing on each face + horizontal girt
			out.append(Kit.beam_xform(_leg(k, y0), _leg(k2, y1), 0.025))
			out.append(Kit.beam_xform(_leg(k2, y0), _leg(k, y1), 0.025))
			out.append(Kit.beam_xform(_leg(k, y1), _leg(k2, y1), 0.03))
	var m_or := Kit.paint(Color(0.92, 0.32, 0.08), 0.5, 0.45)
	var m_wh := Kit.paint(Color(0.88, 0.88, 0.86), 0.5, 0.45)
	Kit.multi(self, Kit.unit_cylinder(6), orange, m_or)
	Kit.multi(self, Kit.unit_cylinder(6), white, m_wh)
	# Base plates + anchor bolts
	for k in 4:
		var p := _leg(k, 0.0)
		Kit.box(self, Vector3(0.5, 0.06, 0.5), p + Vector3(0, 0.03, 0), Kit.paint(Color(0.3, 0.3, 0.32), 0.5, 0.9))
	# Climbing ladder with safety cage up the +X face
	var steel := Kit.paint(Color(0.55, 0.56, 0.58), 0.4, 0.9)
	var rungs: Array = []
	for i in int(TOWER_HEIGHT / 0.35):
		var y := 0.3 + float(i) * 0.35
		if y > TOWER_HEIGHT - 1.2:
			break
		var w := lerpf(BASE_W, TOP_W, y / TOWER_HEIGHT) * 0.5
		rungs.append(Kit.beam_xform(Vector3(w + 0.05, _mast_base_y + y, -0.22), Vector3(w + 0.05, _mast_base_y + y, 0.22), 0.015))
	Kit.multi(self, Kit.unit_cylinder(6), rungs, steel, false)
	for s: float in [-0.22, 0.22]:
		Kit.beam(self, Vector3(BASE_W * 0.5 + 0.05, _mast_base_y, s), Vector3(TOP_W * 0.5 + 0.05, _mast_base_y + TOWER_HEIGHT - 1.2, s), 0.02, steel, 6, false)
	# Platforms at 9 m and 18 m: grating deck + toe rail
	for py: float in [9.0, 18.0]:
		var w := lerpf(BASE_W, TOP_W, py / TOWER_HEIGHT) + 1.3
		Kit.box(self, Vector3(w, 0.06, w), Vector3(0, _mast_base_y + py, 0), Kit.pbr("metal_plate", 1.2, Color(0.5, 0.5, 0.52), false))
		var rails: Array = []
		var hw := w * 0.5
		var cs := [Vector3(hw, 0, hw), Vector3(-hw, 0, hw), Vector3(-hw, 0, -hw), Vector3(hw, 0, -hw)]
		for k in 4:
			var a: Vector3 = cs[k] + Vector3(0, _mast_base_y + py, 0)
			var b: Vector3 = cs[(k + 1) % 4] + Vector3(0, _mast_base_y + py, 0)
			rails.append(Kit.beam_xform(a + Vector3(0, 1.0, 0), b + Vector3(0, 1.0, 0), 0.025))
			rails.append(Kit.beam_xform(a + Vector3(0, 0.5, 0), b + Vector3(0, 0.5, 0), 0.02))
			rails.append(Kit.beam_xform(a, a + Vector3(0, 1.0, 0), 0.03))
		Kit.multi(self, Kit.unit_cylinder(6), rails, Kit.paint(Color(0.85, 0.62, 0.1), 0.45, 0.6))


func _build_mast_antennas() -> void:
	var white := Kit.paint(Color(0.86, 0.86, 0.84), 0.55, 0.1)
	var grey := Kit.paint(Color(0.45, 0.46, 0.48), 0.45, 0.85)
	var top := _mast_base_y + TOWER_HEIGHT
	# Sector panel antennas on mount pipes, 3 per face at the top (cellular-style)
	for f in 4:
		var a := float(f) * PI * 0.5
		var out := Vector3(sin(a), 0, cos(a))
		var side := Vector3(cos(a), 0, -sin(a))
		for k in 3:
			var p := out * (TOP_W * 0.5 + 0.65) + side * (float(k) - 1.0) * 0.45 + Vector3(0, top - 1.9, 0)
			Kit.beam(self, p - Vector3(0, 0.9, 0), p + Vector3(0, 0.9, 0), 0.03, grey, 6, false)
			Kit.box(self, Vector3(0.3, 1.5, 0.12), p + out * 0.1, white, Vector3(0.06, a, 0))
		# Mount arm back to the mast
		Kit.beam(self, out * (TOP_W * 0.5) + Vector3(0, top - 1.4, 0), out * (TOP_W * 0.5 + 0.65) + Vector3(0, top - 1.4, 0), 0.04, grey, 6, false)
	# Microwave drum antennas (radome-covered) at ~14 m, pointing at seeded bearings
	for k in 3:
		var a := _rng.randf() * TAU
		var y := 13.0 + float(k) * 1.1
		var w := lerpf(BASE_W, TOP_W, y / TOWER_HEIGHT) * 0.5
		var d := Vector3(sin(a), 0, cos(a))
		var root := Node3D.new()
		root.position = d * (w + 0.55) + Vector3(0, _mast_base_y + y, 0)
		root.rotation.y = a
		add_child(root)
		var r := _rng.randf_range(0.35, 0.55)
		Kit.cyl(root, r, r, 0.45, Vector3.ZERO, grey, 20, Vector3(PI * 0.5, 0, 0))
		Kit.cyl(root, r * 0.98, r * 0.98, 0.04, Vector3(0, 0, 0.24), white, 20, Vector3(PI * 0.5, 0, 0), false)
		Kit.beam(self, root.position - d * 0.3, d * w + Vector3(0, _mast_base_y + y, 0), 0.04, grey, 6, false)
	# Rotating surveillance radar above the top platform
	var radar_y := top + 0.5
	Kit.cyl(self, 0.18, 0.25, 0.9, Vector3(0, top + 0.05, 0), grey, 12)
	_radar = Node3D.new()
	_radar.name = "Radar"
	_radar.position = Vector3(0, radar_y + 0.05, 0)
	add_child(_radar)
	Kit.box(_radar, Vector3(3.2, 0.42, 0.12), Vector3(0, 0.3, 0.12), Kit.paint(Color(0.82, 0.82, 0.8), 0.5, 0.3))
	Kit.box(_radar, Vector3(3.0, 0.04, 0.4), Vector3(0, 0.08, 0.05), grey)
	Kit.cyl(_radar, 0.2, 0.2, 0.2, Vector3.ZERO, grey, 12)
	# Whip antennas
	for k in 2:
		Kit.cyl(self, 0.015, 0.025, 3.0, Vector3(0.35 - float(k) * 0.7, top + 1.5, -0.35), grey, 6)
	# Cable bundle running down the -X leg into the ground
	var cable := Kit.paint(Color(0.03, 0.03, 0.035), 0.7, 0.0)
	var pts: Array[Vector3] = []
	for i in 12:
		var y := TOWER_HEIGHT - 1.5 - float(i) * (TOWER_HEIGHT - 1.5) / 11.0
		var p := _leg(2, y) + Vector3(0.12, 0, 0.12)
		pts.append(p)
	pts.append(Vector3(-BASE_W * 0.5 + 0.12, _mast_base_y + 0.05, -BASE_W * 0.5 + 0.6))
	Kit.tube(self, pts, 0.06, cable)


func _build_beacon() -> void:
	var beacon_y := _mast_base_y + TOWER_HEIGHT + 3.15
	_beacon_material = Kit.glow(Color(1.0, 0.1, 0.05), 6.0, false)
	Kit.ball(self, 0.15, Vector3(0.35, beacon_y, -0.35), _beacon_material)
	_beacon_light = Kit.omni(self, Vector3(0.35, beacon_y, -0.35), Color(1.0, 0.15, 0.05), 3.0, 30.0)
	_beacon_light.name = "BeaconLight"
	_beacon_light.omni_attenuation = 1.8
	# Mid-mast obstruction lights on two corners (emissive only)
	_obstruction_mat = Kit.glow(Color(1.0, 0.12, 0.05), 4.0, false)
	for y: float in [9.0, 18.0]:
		for k in [0, 2]:
			Kit.ball(self, 0.1, _leg(k, y + 0.3) + (_leg(k, y + 0.3) - Vector3(0, _mast_base_y + y + 0.3, 0)).normalized() * 0.15, _obstruction_mat)


# ─── Ground dishes ──────────────────────────────────────────────────

func _build_ground_dishes() -> void:
	## Two parabolic dishes on azimuth/elevation pedestal mounts.
	var spots := [[Vector3(-6.0, 0, -6.0), 1.9], [Vector3(6.4, 0, -6.4), 1.2]]
	var white := Kit.paint(Color(0.88, 0.88, 0.86), 0.45, 0.2)
	var grey := Kit.paint(Color(0.4, 0.41, 0.43), 0.45, 0.85)
	for i in spots.size():
		var c: Vector3 = spots[i][0]
		var r: float = spots[i][1]
		var top := _footing(c, Vector2(r * 1.4 + 0.6, r * 1.4 + 0.6))
		var base := Vector3(c.x, top, c.z)
		# Pedestal + az bearing
		Kit.cyl(self, r * 0.22, r * 0.3, r * 0.9, base + Vector3(0, r * 0.45, 0), grey, 12)
		var az := Node3D.new()
		az.position = base + Vector3(0, r * 0.9, 0)
		az.rotation.y = _rng.randf() * TAU
		add_child(az)
		Kit.cyl(az, r * 0.28, r * 0.28, 0.12, Vector3.ZERO, Kit.paint(Color(0.15, 0.15, 0.16), 0.5, 0.8), 16)
		# Yoke arms
		for s: float in [-1.0, 1.0]:
			Kit.box(az, Vector3(0.08, r * 0.75, 0.22), Vector3(s * r * 0.2, r * 0.37, 0), grey)
		var el := Node3D.new()
		el.position = Vector3(0, r * 0.7, 0)
		az.add_child(el)
		Kit.cyl(el, 0.06, 0.06, r * 0.5, Vector3.ZERO, grey, 8, Vector3(0, 0, PI * 0.5))
		# Reflector faces local +Z: build in a holder rotated so dish +Y → +Z
		var holder := Node3D.new()
		holder.rotation.x = PI * 0.5
		holder.position = Vector3(0, 0, r * 0.18)
		el.add_child(holder)
		var dish := MeshInstance3D.new()
		dish.mesh = Kit.dish_mesh(r, r * 0.32, 32, 8)
		var dm := white.duplicate() as StandardMaterial3D
		dm.cull_mode = BaseMaterial3D.CULL_DISABLED
		dish.material_override = dm
		dish.position = Vector3(0, r * 0.32, 0)
		holder.add_child(dish)
		Kit.ring(holder, r, 0.03, Vector3(0, r * 0.32, 0), grey, Vector3.ZERO, 32)
		# Backing truss
		for k in 4:
			var a := float(k) * PI * 0.5 + PI * 0.25
			Kit.beam(holder, Vector3(cos(a), 0, sin(a)) * r * 0.75 + Vector3(0, r * 0.18, 0), Vector3(0, -r * 0.16, 0), 0.025, grey, 6, false)
		Kit.cyl(holder, r * 0.12, r * 0.16, r * 0.14, Vector3(0, -r * 0.1, 0), grey, 12)
		# Feed horn on a tripod at the focus
		var focus := Vector3(0, r * 0.78, 0)
		for k in 3:
			var a := float(k) * TAU / 3.0
			Kit.beam(holder, Vector3(cos(a), 0, sin(a)) * r * 0.92 + Vector3(0, r * 0.32, 0), focus, 0.02, grey, 6, false)
		Kit.cyl(holder, 0.05, 0.11, 0.25, focus, Kit.paint(Color(0.2, 0.2, 0.22), 0.4, 0.8), 10)
		_dish_pivots.append(az)
		_dish_elev.append(el)
		_dish_speeds.append(_rng.randf_range(0.03, 0.08) * (1.0 if i == 0 else -1.0))
		if i == 0:
			# Faint uplink beam from the big dish (strength = territory activity)
			_uplink = Kit.light_cone(holder, focus, Vector3.UP, 18.0, 0.1, 0.9, Color(0.35, 0.8, 1.0), 0.3)


# ─── Compound ground ────────────────────────────────────────────────

func _build_compound_floor() -> void:
	## Level concrete compound (main.gd flattens a 28 m site) with paved walkways:
	## gate -> mast, a spur up to the cabinets, and across to the shelter door.
	var slab := Kit.box(self, Vector3(FENCE_HALF * 2.0 + 0.8, 0.5, FENCE_HALF * 2.0 + 0.8), Vector3(0, -0.19, 0),
		Kit.ground_slab(2, Vector2(FENCE_HALF + 0.4, FENCE_HALF + 0.4), Kit.CYAN, _rng.randi()), Vector3.ZERO, false)
	slab.name = "CompoundFloor"
	Kit.skirt(self, Vector2(FENCE_HALF + 0.4, FENCE_HALF + 0.4), 0.06, 3.0, Kit.pbr("brushed_concrete", 0.35, Color(0.42, 0.41, 0.4)))
	var paver := Kit.pbr("brushed_concrete", 0.9, Color(0.78, 0.78, 0.75))
	var paths := [[Vector3(2.6, 0, 0), Vector3(FENCE_HALF + 2.5, 0, 0)], [Vector3(7.2, 0, 0.6), Vector3(7.2, 0, 6.8)],
		[Vector3(-4.6, 0, 6.8), Vector3(7.8, 0, 6.8)]]
	for pth in paths:
		var a: Vector3 = pth[0]
		var b: Vector3 = pth[1]
		var n := int(a.distance_to(b) / 1.0)
		for i in n:
			var p := a.lerp(b, (float(i) + 0.5) / float(n))
			Kit.box(self, Vector3(0.92, 0.05, 0.92), p + Vector3(0, 0.085, 0), paver, Vector3(0, 0.04 * float((i * 7) % 3 - 1), 0), false)


func _footing(center: Vector3, size: Vector2, clearance: float = 0.15) -> float:
	## Level concrete footing on the compound floor with a chamfered cap and anchor bolts.
	var top := _h(center.x, center.z) + clearance
	var conc := Kit.pbr("brushed_concrete", 0.5, Color(0.6, 0.6, 0.58))
	Kit.box(self, Vector3(size.x, top + 0.5, size.y), Vector3(center.x, (top - 0.5) * 0.5, center.z), conc)
	Kit.box(self, Vector3(size.x + 0.12, 0.08, size.y + 0.12), Vector3(center.x, 0.1, center.z), Kit.paint(Color(0.32, 0.32, 0.31), 0.9, 0.0), Vector3.ZERO, false)
	var bolts: Array = []
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var c := Vector3(center.x + sx * (size.x - 0.3), top, center.z + sz * (size.y - 0.3))
			bolts.append(Transform3D(Basis.from_scale(Vector3(0.03, 0.08, 0.03)), c + Vector3(0, 0.04, 0)))
	Kit.multi(self, Kit.unit_cylinder(6), bolts, Kit.paint(Color(0.5, 0.5, 0.5), 0.3, 1.0), false)
	return top


# ─── Cyan relay hardware ────────────────────────────────────────────

func _build_relay_crystals() -> void:
	## Dysnomia relay coils (glowing rings around the mast) and crystal resonators on the
	## 9 m platform and the mast head. Glow follows territory activity.
	_relay_mat = Kit.glow(Kit.CYAN, 3.0, false)
	for y: float in [5.0, 12.0, 16.5]:
		var w := lerpf(BASE_W, TOP_W, y / TOWER_HEIGHT) * 0.5
		var r := w * 1.42 + 0.18
		Kit.ring(self, r, 0.06, Vector3(0, _mast_base_y + y, 0), _relay_mat, Vector3.ZERO, 32)
		Kit.ring(self, r, 0.025, Vector3(0, _mast_base_y + y + 0.18, 0), _relay_mat, Vector3.ZERO, 32)
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 1.0
	crystal.height = 1.0
	crystal.radial_segments = 6
	crystal.rings = 1
	var xs: Array = []
	var pw := lerpf(BASE_W, TOP_W, 9.0 / TOWER_HEIGHT) * 0.5 + 0.45
	for k in 4:
		var a := float(k) * PI * 0.5 + PI * 0.25
		var base := Vector3(cos(a), 0, sin(a)) * pw * 1.3 + Vector3(0, _mast_base_y + 9.05, 0)
		for c in 3:
			var h := _rng.randf_range(0.5, 1.0)
			var tilt := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.05, 0.4))
			var off := Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2))
			xs.append(Transform3D(tilt * Basis.from_scale(Vector3(0.09, h, 0.09)), base + off + tilt * Vector3(0, h * 0.5, 0)))
			xs.append(Transform3D(tilt * Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.09, 0.15, 0.09)), base + off + tilt * Vector3(0, -0.075, 0)))
	var top := _mast_base_y + TOWER_HEIGHT
	for k in 5:
		var a := float(k) * TAU / 5.0
		var h := _rng.randf_range(0.6, 1.1)
		var b := Vector3(cos(a), 0, sin(a)) * 0.28 + Vector3(0, top + 0.05, 0)
		var tilt := Basis(Vector3(-sin(a), 0, cos(a)), 0.3)
		xs.append(Transform3D(tilt * Basis.from_scale(Vector3(0.08, h, 0.08)), b + tilt * Vector3(0, h * 0.5, 0)))
	Kit.multi(self, crystal, xs, _relay_mat, false)
	var l := Kit.omni(self, Vector3(0, _mast_base_y + 9.8, 0), Kit.CYAN, 1.2, 9.0)
	l.name = "RelayGlow"


# ─── Equipment shelter, cabinets, generator ─────────────────────────

func _build_equipment() -> void:
	## Outdoor telecom cabinets under a canopy: relief-textured steel, louvres, labels,
	## grime, status LEDs and link screens; cable trays to the mast; conduits into handholes.
	var c := Vector3(4.2, 0, 5.0)
	var top := _footing(c, Vector2(4.6, 1.8), 0.2)
	var cab_mat := Kit.painted("metal_plate", Color(0.6, 0.62, 0.58), 1.2)
	var dark := Kit.paint(Color(0.06, 0.06, 0.07), 0.5, 0.4)
	var grime := Kit.paint(Color(0.22, 0.2, 0.17), 0.95, 0.0)
	var led_colors := [Color(0.2, 1.0, 0.35), Color(0.2, 1.0, 0.35), Color(1.0, 0.65, 0.1), Kit.CYAN]
	var labels := ["BTS-1  RELAY", "RECTIFIER 48V", "BATT  STRING A"]
	for i in 3:
		var x := c.x - 1.5 + float(i) * 1.05
		var h := 1.85 if i != 1 else 1.6
		var cab := Node3D.new()
		cab.position = Vector3(x, top, c.z)
		add_child(cab)
		Kit.box(cab, Vector3(0.95, h, 0.75), Vector3(0, h * 0.5, 0), cab_mat)
		Kit.box(cab, Vector3(1.0, 0.06, 0.8), Vector3(0, h + 0.03, 0), Kit.paint(Color(0.45, 0.46, 0.44), 0.5, 0.5))
		Kit.box(cab, Vector3(0.96, 0.22, 0.76), Vector3(0, 0.11, 0), grime, Vector3.ZERO, false)
		Kit.box(cab, Vector3(0.008, h - 0.15, 0.01), Vector3(0, h * 0.5, 0.38), dark, Vector3.ZERO, false)
		Kit.box(cab, Vector3(0.04, 0.22, 0.03), Vector3(0.1, h * 0.55, 0.39), Kit.paint(Color(0.15, 0.15, 0.15), 0.4, 0.7), Vector3.ZERO, false)
		# Louvred vents (perforated) top and bottom of the door, plus side louvres
		Kit.box(cab, Vector3(0.7, 0.3, 0.01), Vector3(0, 0.45, 0.383), Kit.grille(Color(0.3, 0.31, 0.3), 0.02), Vector3.ZERO, false)
		for v in 4:
			Kit.box(cab, Vector3(0.012, 0.04, 0.5), Vector3(0.478, h - 0.45 - float(v) * 0.08, 0), dark, Vector3.ZERO, false)
		Kit.label(cab, labels[i], Vector3(0, h - 0.12, 0.386), 30, Color(0.1, 0.1, 0.1), 0.0)
		Kit.box(cab, Vector3(0.22, 0.12, 0.005), Vector3(0.28, h - 0.38, 0.384), Kit.paint(Color(0.95, 0.75, 0.1), 0.6, 0.0), Vector3.ZERO, false)
		for l in 4:
			var m := Kit.glow(led_colors[l], 3.0, false)
			_led_mats.append(m)
			Kit.box(cab, Vector3(0.035, 0.035, 0.01), Vector3(-0.3 + float(l) * 0.06, h - 0.25, 0.38), m, Vector3.ZERO, false)
		if i != 1:
			var scr := Kit.screen(3 if i == 0 else 0, Kit.CYAN, 91 + i)
			Kit.box(cab, Vector3(0.44, 0.3, 0.02), Vector3(-0.18, h - 0.6, 0.38), dark, Vector3.ZERO, false)
			Kit.quad(cab, Vector2(0.4, 0.26), Vector3(-0.18, h - 0.6, 0.392), scr)
			_link_screens.append(scr)
	# Canopy + overhead cable tray along the cabinet tops
	var post := Kit.paint(Color(0.5, 0.51, 0.52), 0.4, 0.9)
	for sx: float in [-2.2, 2.2]:
		for sz: float in [-0.8, 0.8]:
			Kit.beam(self, Vector3(c.x + sx, top, c.z + sz), Vector3(c.x + sx, top + 2.45, c.z + sz), 0.04, post, 6)
	Kit.box(self, Vector3(4.8, 0.06, 2.1), Vector3(c.x, top + 2.5, c.z), Kit.painted("container_side", Color(0.5, 0.52, 0.54), 0.6), Vector3(0.05, 0, 0))
	var trayy := top + 2.05
	Kit.box(self, Vector3(4.2, 0.06, 0.35), Vector3(c.x, trayy, c.z - 0.1), Kit.grille(Color(0.45, 0.46, 0.47), 0.05))
	var cable := Kit.paint(Color(0.03, 0.03, 0.035), 0.7, 0.0)
	for i in 3:
		var x := c.x - 1.5 + float(i) * 1.05
		var hh := 1.85 if i != 1 else 1.6
		Kit.cable(self, Vector3(x, top + hh + 0.06, c.z - 0.2), Vector3(x + 0.2, trayy, c.z - 0.1), 0.0, 0.025, cable, 4)
	# Ice bridge (cable tray) from the canopy to the mast at 2.4 m
	var tray_a := Vector3(c.x - 2.0, trayy, c.z - 0.2)
	var tray_b := Vector3(BASE_W * 0.35, _mast_base_y + 2.4, BASE_W * 0.35)
	var tray := Kit.box(self, Vector3(0.6, 0.05, tray_a.distance_to(tray_b)), (tray_a + tray_b) * 0.5, Kit.grille(Color(0.55, 0.56, 0.57), 0.05))
	tray.basis = Basis.looking_at(tray_b - tray_a, Vector3.UP)
	var tside := (tray_b - tray_a).cross(Vector3.UP).normalized() * 0.3
	for sd: float in [-1.0, 1.0]:
		Kit.beam(self, tray_a + tside * sd + Vector3(0, 0.08, 0), tray_b + tside * sd + Vector3(0, 0.08, 0), 0.025, Kit.paint(Color(0.95, 0.7, 0.1), 0.5, 0.5), 6, false)
	var mid := (tray_a + tray_b) * 0.5
	Kit.beam(self, Vector3(mid.x, 0.06, mid.z), mid - Vector3(0, 0.05, 0), 0.05, post, 6)
	for k in 3:
		var o := Vector3((float(k) - 1.0) * 0.1, 0.06, 0)
		Kit.cable(self, tray_a + o, tray_b + o, 0.05, 0.03, cable, 8)
	# Conduits from the plinth's -X end diving into ground handholes
	for k in 3:
		var hx := c.x - 3.1
		var hz := c.z - 0.6 + float(k) * 0.6
		Kit.box(self, Vector3(0.5, 0.12, 0.5), Vector3(hx, 0.1, hz), Kit.pbr("brushed_concrete", 1.0, Color(0.5, 0.5, 0.48)))
		Kit.box(self, Vector3(0.42, 0.02, 0.42), Vector3(hx, 0.17, hz), Kit.pbr("metal_plate", 1.5, Color(0.4, 0.4, 0.42), false))
		var pts: Array[Vector3] = [Vector3(c.x - 1.95, top + 0.3, hz), Vector3(c.x - 2.35, top + 0.12, hz), Vector3(hx + 0.2, 0.4, hz), Vector3(hx + 0.05, -0.2, hz)]
		Kit.tube(self, pts, 0.045, Kit.paint(Color(0.12, 0.28, 0.5), 0.5, 0.2))


func _build_shelter() -> void:
	## Prefab relay shelter with lit window, waveguide port to the mast, generator + tank.
	var sh := Kit.cabin(self, Vector3(-6.5, 0, 5.5), PI * 0.5, Vector3(5.0, 2.6, 2.6), "RELAY SHELTER 07", Color(0.75, 0.92, 1.0), true, Color(0.72, 0.7, 0.62))
	sh.name = "RelayShelter"
	# Waveguide bridge from the shelter wall (+X face is the front) to the mast
	var cable := Kit.paint(Color(0.03, 0.03, 0.035), 0.7, 0.0)
	var a := Vector3(-5.1, 2.3, 3.6)
	var b := Vector3(-BASE_W * 0.35, _mast_base_y + 2.2, BASE_W * 0.35)
	var tray := Kit.box(self, Vector3(0.35, 0.05, a.distance_to(b)), (a + b) * 0.5, Kit.grille(Color(0.45, 0.46, 0.47), 0.05))
	tray.basis = Basis.looking_at(b - a, Vector3.UP)
	var mid := (a + b) * 0.5
	Kit.beam(self, Vector3(mid.x, 0.06, mid.z), mid - Vector3(0, 0.05, 0), 0.05, Kit.paint(Color(0.5, 0.51, 0.52), 0.4, 0.9), 6)
	for k in 2:
		Kit.cable(self, a + Vector3(0, 0.06, (float(k) - 0.5) * 0.12), b + Vector3(0, 0.06, (float(k) - 0.5) * 0.12), 0.05, 0.03, cable, 8)
	# Generator on a skid with a day tank
	var g := Vector3(-8.2, 0, 0.4)
	var gtop := _footing(g, Vector2(2.2, 1.4), 0.12)
	Kit.prop(self, "portable_generator", Vector3(g.x - 0.3, gtop, g.z), 0.0)
	Kit.cyl(self, 0.32, 0.32, 1.0, Vector3(g.x + 0.6, gtop + 0.4, g.z), Kit.paint(Color(0.75, 0.2, 0.1), 0.5, 0.4), 16, Vector3(PI * 0.5, 0, 0))
	Kit.label(self, "DIESEL", Vector3(g.x + 0.6, gtop + 0.4, g.z + 0.51), 34, Color(0.95, 0.95, 0.9), 0.0)
	Kit.prop(self, "small_lpg_tank", Vector3(-9.2, 0.06, -1.4), 0.8)
	Kit.prop(self, "barrel_03", Vector3(-9.0, 0.06, 2.0), 0.5)
	Kit.prop(self, "wooden_crate_02", Vector3(-8.6, 0.06, -2.2), 1.4)
	var feed: Array[Vector3] = [Vector3(g.x - 0.6, gtop + 0.3, g.z + 0.3), Vector3(g.x - 0.8, 0.1, g.z + 1.0), Vector3(-6.6, 0.1, 2.4), Vector3(-6.4, 0.5, 2.9)]
	Kit.tube(self, feed, 0.04, cable)


func _build_rover() -> void:
	## Six-wheeled crew rover parked outside the gate.
	var root := Node3D.new()
	root.name = "Rover"
	root.position = Vector3(FENCE_HALF + 3.6, _h(FENCE_HALF + 3.6, -4.2) + 0.07, -4.2)
	root.rotation.y = 0.35
	add_child(root)
	var body := Kit.hull_material(Color(0.82, 0.8, 0.74), false)
	var dark := Kit.paint(Color(0.05, 0.05, 0.055), 0.7, 0.2)
	var steel := Kit.paint(Color(0.45, 0.46, 0.48), 0.4, 0.9)
	Kit.box(root, Vector3(1.9, 0.35, 4.2), Vector3(0, 0.75, 0), steel)
	Kit.box(root, Vector3(1.8, 1.05, 2.0), Vector3(0, 1.45, 0.75), body)
	Kit.box(root, Vector3(1.6, 0.55, 0.05), Vector3(0, 1.65, 1.76), Kit.glass(Color(0.35, 0.5, 0.6, 0.6)), Vector3(-0.3, 0, 0), false)
	Kit.box(root, Vector3(1.8, 0.5, 1.6), Vector3(0, 1.15, -1.2), body)
	for s: float in [-1.0, 1.0]:
		for zz: float in [-1.5, 0.0, 1.5]:
			Kit.cyl(root, 0.42, 0.42, 0.32, Vector3(s * 1.05, 0.42, zz), dark, 16, Vector3(0, 0, PI * 0.5))
			Kit.cyl(root, 0.2, 0.2, 0.34, Vector3(s * 1.05, 0.42, zz), steel, 10, Vector3(0, 0, PI * 0.5), false)
		Kit.box(root, Vector3(0.05, 0.3, 0.9), Vector3(s * 0.91, 1.5, 0.8), Kit.glass(Color(0.35, 0.5, 0.6, 0.6)), Vector3.ZERO, false)
	Kit.box(root, Vector3(1.4, 0.08, 0.15), Vector3(0, 2.02, 1.4), dark)
	for x: float in [-0.5, 0.0, 0.5]:
		Kit.box(root, Vector3(0.2, 0.08, 0.04), Vector3(x, 2.02, 1.48), Kit.glow(Color(1.0, 0.92, 0.8), 4.0), Vector3.ZERO, false)
	Kit.cyl(root, 0.015, 0.02, 1.4, Vector3(-0.7, 2.6, -0.2), steel, 6)
	Kit.ball(root, 0.05, Vector3(-0.7, 3.32, -0.2), _obstruction_mat)
	Kit.label(root, "DYS-ROVER 3", Vector3(0.91, 1.15, -1.2), 50, Color(0.15, 0.15, 0.17), PI * 0.5)
	Kit.light_cone(root, Vector3(0, 2.0, 1.5), Vector3(0, -0.25, 1), 6.0, 0.15, 1.2, Color(1.0, 0.92, 0.8), 0.6)


func _build_gate_arch() -> void:
	## Big cyan neon "COMM ARRAY" arch over the gate, facing the approach (+X), plus a station
	## ID plate on the gate post.
	var gx := FENCE_HALF + 0.05
	var gh := _gate_half + 1.3
	var steel := Kit.paint(Color(0.2, 0.21, 0.23), 0.45, 0.8)
	for s: float in [-1.0, 1.0]:
		Kit.beam(self, Vector3(gx, 0.0, s * gh), Vector3(gx, 5.6, s * gh), 0.12, steel)
		Kit.box(self, Vector3(0.5, 0.18, 0.5), Vector3(gx, 0.09, s * gh), Kit.pbr("brushed_concrete", 0.8, Color(0.6, 0.6, 0.6)))
	Kit.box(self, Vector3(0.26, 1.45, gh * 2.0 + 0.4), Vector3(gx, 4.9, 0), Kit.paint(Color(0.03, 0.03, 0.035), 0.5, 0.4))
	for side: float in [1.0, -1.0]:
		var fx := gx + side * 0.14
		var l := Kit.label(self, "COMM ARRAY", Vector3(fx, 4.98, 0), 250, Color(0.6, 0.95, 1.0), side * PI * 0.5, 3.0)
		l.outline_size = 22
		l.outline_modulate = Color(0.1, 0.7, 1.0, 0.9)
		Kit.box(self, Vector3(0.02, 0.06, gh * 2.0 + 0.2), Vector3(fx, 4.25, 0), Kit.glow(Kit.CYAN, 5.0), Vector3.ZERO, false)
		Kit.box(self, Vector3(0.02, 0.06, gh * 2.0 + 0.2), Vector3(fx, 5.58, 0), Kit.glow(Kit.CYAN, 5.0), Vector3.ZERO, false)
	Kit.sign_board(self, "STATION ID\nDYS-RLY-07\nPULSECHAIN 369", Vector3(gx + 0.12, 1.55, -gh - 0.6), PI * 0.5, Vector2(0.8, 0.6), Color(0.85, 0.86, 0.84), Color(0.08, 0.1, 0.14), 30)
	Kit.beam(self, Vector3(gx + 0.1, 0.0, -gh - 0.6), Vector3(gx + 0.1, 1.3, -gh - 0.6), 0.03, steel)
	Kit.light_pool(self, Vector3(gx + 1.6, 0.08, 0), 4.0, Kit.CYAN, 1.0)


func _build_access_road() -> void:
	## Concrete access road from the gate out to the edge of the levelled site, widening into
	## a parking apron for the rover; follows the real terrain, with reflective edge studs.
	var mat := Kit.pbr("brushed_concrete", 0.4, Color(0.42, 0.42, 0.41))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := FENCE_HALF + 0.3
	var x1 := FENCE_HALF + 9.5
	var nx := int(x1 - x0)
	var zs := [-7.4, -2.4, 0.0, 2.4]
	for i in nx:
		var xa := x0 + float(i)
		var xb := xa + 1.0
		for j in zs.size() - 1:
			var za: float = zs[j]
			var zb: float = zs[j + 1]
			if j == 0 and xa > FENCE_HALF + 7.0:
				continue  # Apron only beside the gate end
			var v := [Vector3(xa, _h(xa, za) + 0.07, za), Vector3(xb, _h(xb, za) + 0.07, za), Vector3(xb, _h(xb, zb) + 0.07, zb), Vector3(xa, _h(xa, zb) + 0.07, zb)]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_uv(Vector2(v[idx].x, v[idx].z) * 0.3)
				st.add_vertex(v[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "AccessRoad"
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	var studs: Array = []
	for i in int((x1 - x0) / 2.0):
		var x := x0 + 1.0 + float(i) * 2.0
		studs.append(Transform3D(Basis.from_scale(Vector3(0.12, 0.05, 0.12)), Vector3(x, _h(x, 2.3) + 0.1, 2.3)))
		if x > FENCE_HALF + 7.0:
			studs.append(Transform3D(Basis.from_scale(Vector3(0.12, 0.05, 0.12)), Vector3(x, _h(x, -2.3) + 0.1, -2.3)))
	Kit.multi(self, Kit.unit_box(), studs, Kit.glow(Color(1.0, 0.7, 0.15), 3.0), false)
	# Parking bay lines on the apron
	for z: float in [-7.2, -2.6]:
		var a := Vector3(x0 + 1.0, 0, z)
		var b := Vector3(FENCE_HALF + 6.8, 0, z)
		a.y = _h(a.x, z) + 0.09
		b.y = _h(b.x, z) + 0.09
		Kit.beam(self, a, b, 0.04, Kit.paint(Color(0.95, 0.9, 0.8), 0.6, 0.0), 4, false)


func _build_crate_stack() -> void:
	## Spares stacked in the compound corner nearest the approach.
	var p := Vector3(8.3, 0.06, 8.2)
	Kit.prop(self, "wooden_crate_02", p, 0.1)
	Kit.prop(self, "wooden_crate_02", p + Vector3(0.6, 0, 0.05), -0.05)
	Kit.prop(self, "wooden_crate_02", p + Vector3(0.3, 0.46, 0.0), 0.25)
	Kit.prop(self, "old_military_crate", p + Vector3(-1.2, 0, -0.6), 1.5, 0.7)
	Kit.prop(self, "old_military_crate", p + Vector3(-1.2, 0.22, -0.6), 1.45, 0.7)
	Kit.prop(self, "barrel_03", p + Vector3(-0.4, 0, -1.4), 0.3)
	Kit.prop(self, "barrel_03", p + Vector3(0.3, 0, -1.5), 1.3)
	Kit.cyl(self, 0.55, 0.55, 0.06, p + Vector3(-2.2, 0.55, 0.2), Kit.paint(Color(0.36, 0.26, 0.16), 0.85, 0.0), 18, Vector3(PI * 0.5, 0, 0))
	Kit.cyl(self, 0.55, 0.55, 0.06, p + Vector3(-2.2, 0.55, -0.5), Kit.paint(Color(0.36, 0.26, 0.16), 0.85, 0.0), 18, Vector3(PI * 0.5, 0, 0))
	Kit.cyl(self, 0.38, 0.38, 0.65, p + Vector3(-2.2, 0.55, -0.15), Kit.paint(Color(0.04, 0.04, 0.045), 0.6, 0.0), 18, Vector3(PI * 0.5, 0, 0))


func get_board_anchor() -> Transform3D:
	## Reserved spot for a 3.2 x 1.8 m media billboard (bottom 1.2 m up) just outside the
	## fence beside the access road, facing the approach from spawn (+X). Board front = -Z.
	var p := Vector3(FENCE_HALF + 2.2, 0, 6.6)
	p.y = _h(p.x, p.z) + 1.2 + 0.9
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), p)


# ─── Fence & gate ───────────────────────────────────────────────────

func _build_fence() -> void:
	## Chain-link compound fence following the ground, with a swing gate on the +X side.
	var mesh_mat := ShaderMaterial.new()
	mesh_mat.shader = CHAINLINK_SHADER
	var post_mat := Kit.paint(Color(0.55, 0.57, 0.58), 0.4, 0.9)
	var hf := FENCE_HALF
	var corners := [Vector3(hf, 0, hf), Vector3(-hf, 0, hf), Vector3(-hf, 0, -hf), Vector3(hf, 0, -hf)]
	var gate_half := _gate_half  # Two fence bays (segment count forced even)
	var lamps: Array = []
	var posts: Array = []
	var rails: Array = []
	var arms: Array = []
	var wires: Array = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := 0.0
	for side in 4:
		var a: Vector3 = corners[(side + 3) % 4]
		var b: Vector3 = corners[side]
		# side 0 runs (hf,-hf)→(hf,hf): the +X side with the gate in the middle
		var len_ := a.distance_to(b)
		var segs := int(ceil(len_ / 2.4))
		segs += segs % 2
		_gate_half = len_ / float(segs)
		gate_half = _gate_half
		for i in segs:
			var t0 := float(i) / float(segs)
			var t1 := float(i + 1) / float(segs)
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			if side == 0 and absf((p0.z + p1.z) * 0.5) < gate_half:
				u += p0.distance_to(p1)
				continue
			var g0 := _h(p0.x, p0.z)
			var g1 := _h(p1.x, p1.z)
			var d := p0.distance_to(p1)
			_fence_quad(st, Vector3(p0.x, g0 + 0.04, p0.z), Vector3(p1.x, g1 + 0.04, p1.z), 2.0, u, d)
			u += d
			for pp: Vector3 in [Vector3(p0.x, g0, p0.z), Vector3(p1.x, g1, p1.z)]:
				posts.append(Kit.beam_xform(pp - Vector3(0, 0.4, 0), pp + Vector3(0, 2.15, 0), 0.04))
				# Barbed-wire outrigger leaning outward
				var outward := Vector3(pp.x, 0, pp.z).normalized() * 0.32
				arms.append(Kit.beam_xform(pp + Vector3(0, 2.1, 0), pp + Vector3(0, 2.45, 0) + outward, 0.015))
			rails.append(Kit.beam_xform(Vector3(p0.x, g0 + 2.08, p0.z), Vector3(p1.x, g1 + 2.08, p1.z), 0.025))
			if (i + side) % 4 == 0:
				lamps.append(Vector3(p0.x, g0, p0.z) - Vector3(p0.x, 0, p0.z).normalized() * 0.09)
			var ow0 := Vector3(p0.x, 0, p0.z).normalized()
			var ow1 := Vector3(p1.x, 0, p1.z).normalized()
			for k in 3:
				var f := 0.12 + float(k) * 0.11
				wires.append(Kit.beam_xform(Vector3(p0.x, g0 + 2.1 + f * 1.05, p0.z) + ow0 * f, Vector3(p1.x, g1 + 2.1 + f * 1.05, p1.z) + ow1 * f, 0.006))
	var mi := MeshInstance3D.new()
	mi.name = "ChainLink"
	mi.mesh = st.commit()
	mi.material_override = mesh_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	Kit.multi(self, Kit.unit_cylinder(8), posts, post_mat)
	Kit.multi(self, Kit.unit_cylinder(6), rails, post_mat, false)
	Kit.multi(self, Kit.unit_cylinder(4), arms, post_mat, false)
	Kit.multi(self, Kit.unit_cylinder(4), wires, Kit.paint(Color(0.4, 0.4, 0.42), 0.5, 0.9), false)
	# Fence-post lamps facing inward, each with a pool of light on the compound floor
	var heads: Array = []
	var lenses: Array = []
	for lp: Vector3 in lamps:
		var inward := -Vector3(lp.x, 0, lp.z).normalized()
		heads.append(Transform3D(Basis.from_scale(Vector3(0.16, 0.1, 0.16)), lp + Vector3(0, 1.85, 0) + inward * 0.06))
		lenses.append(Transform3D(Basis.from_scale(Vector3(0.12, 0.02, 0.12)), lp + Vector3(0, 1.79, 0) + inward * 0.06))
		var k := float(heads.size())
		var rr := 1.6 + 0.9 * absf(sin(k * 2.3))
		var pst := 0.18 + 0.16 * absf(cos(k * 1.7))
		Kit.light_pool(self, lp + inward * (0.9 + 0.5 * absf(sin(k))) + Vector3(0, 0.1, 0), rr, Color(1.0, 0.8 + 0.08 * sin(k), 0.55), pst)
	Kit.multi(self, Kit.unit_box(), heads, Kit.paint(Color(0.1, 0.1, 0.11), 0.5, 0.7), false)
	Kit.multi(self, Kit.unit_box(), lenses, Kit.glow(Color(1.0, 0.85, 0.6), 5.0), false)

	# Gate: heavy posts and two leaves (one swung half open)
	var gx := hf
	for s: float in [-1.0, 1.0]:
		var gp := Vector3(gx, _h(gx, s * gate_half), s * gate_half)
		Kit.beam(self, gp - Vector3(0, 0.5, 0), gp + Vector3(0, 2.4, 0), 0.07, post_mat)
		Kit.ball(self, 0.08, gp + Vector3(0, 2.45, 0), post_mat)
		var leaf := Node3D.new()
		leaf.position = gp
		leaf.rotation.y = 0.0 if s < 0.0 else -1.1
		add_child(leaf)
		# Leaf spans from the hinge toward the centre (along -s Z)
		var lw := gate_half - 0.08
		var frame: Array = []
		var lz := -s * lw
		frame.append(Kit.beam_xform(Vector3(0, 0.08, -s * 0.06), Vector3(0, 0.08, lz), 0.03))
		frame.append(Kit.beam_xform(Vector3(0, 1.95, -s * 0.06), Vector3(0, 1.95, lz), 0.03))
		frame.append(Kit.beam_xform(Vector3(0, 0.08, lz), Vector3(0, 1.95, lz), 0.03))
		frame.append(Kit.beam_xform(Vector3(0, 0.08, -s * 0.06), Vector3(0, 1.95, lz), 0.02))
		Kit.multi(leaf, Kit.unit_cylinder(6), frame, post_mat)
		var gst := SurfaceTool.new()
		gst.begin(Mesh.PRIMITIVE_TRIANGLES)
		_fence_quad(gst, Vector3(0, 0.1, -s * 0.06), Vector3(0, 0.1, lz), 1.83, 0.0, lw)
		var gm := MeshInstance3D.new()
		gm.mesh = gst.commit()
		gm.material_override = mesh_mat
		leaf.add_child(gm)
	# Signage on the fence beside the gate (facing +X, outward)
	Kit.sign_board(self, "DYSNOMIA RELAY\nCOMM ARRAY 07", Vector3(gx + 0.06, _h(gx, -4.8) + 1.35, -4.8), PI * 0.5, Vector2(1.4, 0.55), Color(0.08, 0.18, 0.42), Color(0.95, 0.95, 0.95), 40)
	Kit.sign_board(self, "DANGER\nRF RADIATION", Vector3(gx + 0.06, _h(gx, 3.8) + 1.35, 3.8), PI * 0.5, Vector2(0.9, 0.55), Color(0.95, 0.75, 0.1), Color(0.05, 0.05, 0.05), 40)
	Kit.sign_board(self, "AUTHORISED\nPERSONNEL ONLY", Vector3(gx + 0.06, _h(gx, -6.8) + 1.35, -6.8), PI * 0.5, Vector2(1.1, 0.5), Color(0.92, 0.92, 0.9), Color(0.7, 0.05, 0.05), 34)


func _fence_quad(st: SurfaceTool, a: Vector3, b: Vector3, h: float, u0: float, d: float) -> void:
	var n := (b - a).cross(Vector3.UP).normalized()
	var v := [a, b, b + Vector3(0, h, 0), a + Vector3(0, h, 0)]
	var uv := [Vector2(u0, 0), Vector2(u0 + d, 0), Vector2(u0 + d, h), Vector2(u0, h)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uv[idx])
		st.add_vertex(v[idx])


# ─── Lighting & crew ────────────────────────────────────────────────

func _build_lighting() -> void:
	# Floodlight masts in three corners (none between the approach and the shelter/cabinets)
	var hf := FENCE_HALF - 0.6
	Kit.flood_mast(self, Vector3(-hf, 0.06, -hf), 6.0, Vector3(0, 0, 0), Color(1.0, 0.92, 0.8), 2, true, 2.2)
	Kit.flood_mast(self, Vector3(hf, 0.06, -hf), 6.0, Vector3(3.0, 0, 1.0), Color(1.0, 0.92, 0.8), 2, true, 2.2)
	Kit.flood_mast(self, Vector3(-hf, 0.06, hf), 6.0, Vector3(-2.5, 0, 4.0), Color(1.0, 0.92, 0.8), 2, true, 2.0)
	Kit.light_pool(self, Vector3(2.0, 0.1, 2.4), 6.0, Color(1.0, 0.9, 0.75), 0.6)
	Kit.light_pool(self, Vector3(-3.0, 0.1, -3.0), 6.0, Color(1.0, 0.9, 0.75), 0.5)
	# Gate lamp on the arch
	var gl := Vector3(FENCE_HALF + 0.25, 3.35, 0.0)
	Kit.box(self, Vector3(0.22, 0.1, 0.5), gl, Kit.paint(Color(0.1, 0.1, 0.1), 0.5, 0.7), Vector3.ZERO, false)
	Kit.box(self, Vector3(0.18, 0.02, 0.46), gl - Vector3(0, 0.055, 0), Kit.glow(Color(1.0, 0.82, 0.55), 5.0), Vector3.ZERO, false)
	Kit.omni(self, gl + Vector3(0.6, -0.8, 0), Color(1.0, 0.82, 0.55), 1.4, 8.0)
	# Cool fill from the cabinet screens
	Kit.omni(self, Vector3(3.6, 1.8, 6.6), Color(0.4, 0.8, 1.0), 0.7, 3.5)


func _build_crew(seed_value: int) -> void:
	## A technician at the cabinets, a crew member doing rounds gate -> cabinets -> shelter,
	## and the rover driver waiting by the gate.
	Kit.npc(self, seed_value + 404, [], Vector3(0, 0, -1), Callable(), Vector3(3.6, 0.08, 6.45))
	Kit.npc(self, seed_value + 505, [
		Vector3(FENCE_HALF + 1.8, 0.0, 0.3), Vector3(7.2, 0.1, 0.3), Vector3(7.2, 0.1, 6.8), Vector3(-4.3, 0.1, 6.9),
		Vector3(7.2, 0.1, 6.8), Vector3(7.2, 0.1, 0.3)])
	Kit.npc(self, seed_value + 606, [], Vector3(-0.6, 0, 1), Callable(), Vector3(FENCE_HALF + 2.3, 0.0, -2.4))
