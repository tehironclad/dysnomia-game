class_name OrbitalCarousel
extends RideBase
## Orbital Carousel — a mirrored, bulb-lit carousel whose mounts are little rocket sleds
## bobbing on brass poles, under a striped canopy topped by a turning orrery.
##
## Ride timeline (32 s):
##   0–2     "ALL ABOARD"
##   2–6     spin up                         "LAUNCH"
##   6–27    cruising at ~0.75 rad/s         "IN ORBIT"
##   27–30.5 spin down                       "DEORBIT"
##   30.5    "WELCOME BACK"

const PLAT_R := 7.2
const PLINTH_H := 0.5
const DECK_Y := 0.62
const CANOPY_Y := 5.6
const OUTER := 12
const INNER := 6
const R_OUT := 5.7
const R_IN := 3.6
const RIDE_W := 0.75
const IDLE_W := 0.18

var _turntable: Node3D
var _sleds: Array[Node3D] = []
var _sled_phase: Array[float] = []
var _orrery: Array = []        # [pivot Node3D, speed]
var _theta := 0.0
var _theta0 := 0.0
var _rider_k := 0
var _captions: Array = []
var _cap_idx := 0


func _init() -> void:
	ride_id = "carousel"
	booth_local_position = Vector3(6.5, 0, 10.0)
	exit_local_position = Vector3(4.2, 0.0, 10.2)
	booth_radius = 2.6


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 909
	var batch := FairKit.Batch.new()
	var concrete := FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3)
	var gold := FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	var brass := FairKit.paint(Color(0.92, 0.7, 0.35), 0.18, 1.0)
	var red := FairKit.paint(Color(0.62, 0.06, 0.12), 0.35, 0.3, 0.7)
	# Static plinth with skirt lights and steps
	FairKit.mesh(self, FairKit.cyl_mesh(PLAT_R + 0.6, PLAT_R + 0.8, PLINTH_H, 32), Vector3(0, PLINTH_H * 0.5, 0), concrete)
	FairKit.solid_cyl(self, PLAT_R + 0.8, PLINTH_H + 0.4, Vector3(0, (PLINTH_H + 0.4) * 0.5, 0))
	batch.bulb_line(FairKit.ring_points(Vector3(0, PLINTH_H - 0.12, 0), PLAT_R + 0.72, 72), [FairKit.BULB_WARM, Color(1.0, 0.4, 0.6)], 0.04, 0.06)
	batch.pool(Vector3(0, 0.1, 0), PLAT_R + 5.0, Color(1.0, 0.7, 0.4) * 0.45)
	# ── Turntable: deck, mirrored core, sleds, rounding board, canopy ──
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	add_child(_turntable)
	var tb := FairKit.Batch.new()
	FairKit.mesh(_turntable, FairKit.cyl_mesh(PLAT_R, PLAT_R, 0.14, 48), Vector3(0, DECK_Y - 0.07, 0), FairKit.pbr("brown_planks_05", Color(0.85, 0.62, 0.42), 0.8))
	FairKit.mesh(_turntable, FairKit.torus_mesh(PLAT_R - 0.05, PLAT_R + 0.08, 64, 6), Vector3(0, DECK_Y - 0.05, 0), gold)
	# Mirrored core: 12 mirror panels between gilded pilasters
	FairKit.mesh(_turntable, FairKit.cyl_mesh(1.7, 1.7, CANOPY_Y - DECK_Y, 12), Vector3(0, (CANOPY_Y + DECK_Y) * 0.5, 0), red)
	var mirror := FairKit.paint(Color(0.9, 0.92, 0.95), 0.03, 1.0)
	for i in 12:
		var a := TAU * (i + 0.5) / 12.0
		var d := Vector3(cos(a), 0, sin(a))
		var m := FairKit.box(_turntable, Vector3(0.72, 2.4, 0.03), d * 1.68 + Vector3(0, 2.6, 0), mirror)
		m.rotation.y = -a + PI * 0.5
		var fr := FairKit.box(_turntable, Vector3(0.82, 2.55, 0.02), d * 1.665 + Vector3(0, 2.6, 0), gold)
		fr.rotation.y = -a + PI * 0.5
		tb.bulb(d * 1.75 + Vector3(0, 4.15, 0), FairKit.BULB_WARM, i * 0.08, 0.07)
		tb.bulb(d * 1.75 + Vector3(0, 1.1, 0), FairKit.BULB_WARM, i * 0.08 + 0.5, 0.07)
	# Rounding board (the decorated band under the canopy edge) with bulbs + names
	FairKit.mesh(_turntable, FairKit.cyl_mesh(PLAT_R + 0.3, PLAT_R + 0.3, 1.0, 48), Vector3(0, CANOPY_Y - 0.5, 0), red)
	FairKit.mesh(_turntable, FairKit.torus_mesh(PLAT_R + 0.25, PLAT_R + 0.42, 64, 6), Vector3(0, CANOPY_Y - 1.0, 0), gold)
	FairKit.mesh(_turntable, FairKit.torus_mesh(PLAT_R + 0.25, PLAT_R + 0.42, 64, 6), Vector3(0, CANOPY_Y, 0), gold)
	tb.bulb_line(FairKit.ring_points(Vector3(0, CANOPY_Y - 0.2, 0), PLAT_R + 0.36, 96), [FairKit.BULB_WARM, Color(1.0, 0.85, 0.5)], 0.03, 0.06)
	tb.bulb_line(FairKit.ring_points(Vector3(0, CANOPY_Y - 0.82, 0), PLAT_R + 0.36, 96), [Color(1.0, 0.35, 0.6), FairKit.BULB_WARM], -0.03, 0.06)
	for i in 6:
		var a := TAU * i / 6.0
		var l := FairKit.label(_turntable, "ORBITAL CAROUSEL", Vector3(sin(a), 0, cos(a)) * (PLAT_R + 0.32) + Vector3(0, CANOPY_Y - 0.5, 0), 38, Color(2.0, 1.7, 1.1), a)
		l.outline_size = 6
	# Canopy cone (striped canvas, scalloped rim) and a small upper drum
	var cone := PackedVector2Array()
	for i in 9:
		var u := float(i) / 8.0
		cone.append(Vector2(lerpf(0.3, PLAT_R + 0.9, u), CANOPY_Y + 2.4 - 2.6 * u + 0.5 * sin(u * PI) * 0.5))
	var canopy := FairKit.mesh(_turntable, FairKit.lathe(cone, 48), Vector3.ZERO, FairKit.shader_mat("fair_awning"))
	canopy.set_instance_shader_parameter("color_a", Color(0.78, 0.08, 0.14))
	canopy.set_instance_shader_parameter("color_b", Color(0.96, 0.9, 0.78))
	canopy.set_instance_shader_parameter("stripes", 24.0)
	FairKit.mesh(_turntable, FairKit.cyl_mesh(0.6, 0.9, 0.9, 16), Vector3(0, CANOPY_Y + 2.7, 0), gold)
	# Crank rods + sleds
	for k in OUTER + INNER:
		var outer := k < OUTER
		var n := OUTER if outer else INNER
		var idx := k if outer else k - OUTER
		var a := TAU * idx / n + (0.0 if outer else PI / INNER)
		var r := R_OUT if outer else R_IN
		var p := Vector3(cos(a), 0, sin(a)) * r
		tb.strut(p + Vector3.UP * DECK_Y, p + Vector3.UP * (CANOPY_Y - 1.0), 0.045, brass)
		var sled := _make_sled(k, rng)
		sled.position = p
		sled.rotation.y = PI - a   # nose (−Z) points along the direction of travel
		_turntable.add_child(sled)
		_sleds.append(sled)
		_sled_phase.append(float(k) * 1.7)
	tb.flush(_turntable)
	FairKit.omni(self, Vector3(0, CANOPY_Y - 1.4, 3.5), Color(1.0, 0.78, 0.5), 2.2, 14.0, 0.0)
	_build_orrery()
	FairKit.ticket_booth(self, batch, booth_local_position, Vector3(signf(booth_local_position.x) * absf(0.2), 0, 1), item, Color(1.0, 0.75, 0.2))
	batch.flush(self)


func _make_sled(k: int, rng: RandomNumberGenerator) -> Node3D:
	## A one-seat rocket sled: lathed body lying along -Z (nose forward), fins, saddle.
	var s := Node3D.new()
	var inner := Node3D.new()
	inner.name = "Bob"
	s.add_child(inner)
	var cols := [Color(0.1, 0.45, 0.8), Color(0.92, 0.6, 0.08), Color(0.12, 0.6, 0.45), Color(0.6, 0.18, 0.62),
		Color(0.85, 0.85, 0.88), Color(0.85, 0.2, 0.2)]
	var body_m := FairKit.paint(cols[k % cols.size()], 0.3, 0.45, 0.8)
	var prof := PackedVector2Array([Vector2(0.0, -0.9), Vector2(0.18, -0.85), Vector2(0.3, -0.55), Vector2(0.34, -0.1),
		Vector2(0.34, 0.35), Vector2(0.26, 0.6), Vector2(0.0, 0.62)])
	var hull := FairKit.cached_mesh("sled_hull", func() -> Mesh: return FairKit.lathe(prof, 16))
	var b := FairKit.mesh(inner, hull, Vector3.ZERO, body_m)
	b.rotation.x = PI * 0.5   # lathe +Y (tail) → +Z, so the nose (−Y end) points −Z
	var fin := FairKit.cached_mesh("sled_fin", func() -> Mesh:
		return FairKit.extrude(PackedVector2Array([Vector2(0.25, 0.1), Vector2(0.62, 0.35), Vector2(0.62, 0.62), Vector2(0.25, 0.55)]), 0.05))
	var fin_m := FairKit.paint(Color(0.92, 0.88, 0.8), 0.3, 0.6)
	for i in 3:
		var fm := FairKit.mesh(inner, fin, Vector3.ZERO, fin_m)
		# fin polygon is (radial, along) in XY: tip it so "along" runs +Z, then roll about Z
		fm.basis = Basis(Vector3.BACK, TAU * i / 3.0 + PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)
	FairKit.mesh(inner, FairKit.cyl_mesh(0.16, 0.22, 0.18, 12), Vector3(0, 0, 0.66), FairKit.paint(Color(0.2, 0.2, 0.22), 0.4, 0.9)).rotation.x = PI * 0.5
	FairKit.mesh(inner, FairKit.sphere_mesh(0.07, 8), Vector3(0, 0, 0.78), FairKit.glow(Color(1.0, 0.5, 0.2), 5.0, 1.0), Vector3.ZERO, false)
	FairKit.box(inner, Vector3(0.36, 0.1, 0.5), Vector3(0, 0.36, 0.1), FairKit.paint(Color(0.35, 0.12, 0.08), 0.5, 0.1))
	FairKit.box(inner, Vector3(0.05, 0.25, 0.05), Vector3(0, 0.45, -0.25), FairKit.paint(Color(0.92, 0.7, 0.35), 0.2, 1.0))
	return s


func _build_orrery() -> void:
	## Static mount above the canopy: glowing sun and five planets on arms, each turning
	## at its own rate (outer planets slower, like the real thing).
	var top := CANOPY_Y + 3.15
	var brass := FairKit.paint(Color(0.92, 0.7, 0.35), 0.2, 1.0)
	FairKit.cyl(self, 0.06, 0.1, 1.8, Vector3(0, top + 0.9, 0), brass, 8)
	FairKit.mesh(self, FairKit.sphere_mesh(0.75, 24), Vector3(0, top + 2.3, 0), FairKit.glow(Color(1.0, 0.72, 0.3), 6.0, 2.5), Vector3.ZERO, false)
	FairKit.mesh(self, FairKit.torus_mesh(0.95, 1.0, 32, 4), Vector3(0, top + 2.3, 0), brass).rotation.x = 0.4
	var planets := [
		[1.7, 0.18, Color(0.7, 0.5, 0.4), 0.9], [2.5, 0.26, Color(0.9, 0.75, 0.45), 0.6],
		[3.4, 0.3, Color(0.25, 0.5, 0.85), 0.45], [4.3, 0.22, Color(0.8, 0.3, 0.15), 0.33],
		[5.4, 0.48, Color(0.85, 0.7, 0.5), 0.2]]
	for i in planets.size():
		var p: Array = planets[i]
		var pivot := Node3D.new()
		pivot.position = Vector3(0, top + 2.3 - 0.12 * i, 0)
		pivot.rotation.y = i * 1.9
		add_child(pivot)
		FairKit.beam(pivot, Vector3.ZERO, Vector3(p[0], -0.3, 0), 0.025, brass)
		FairKit.beam(pivot, Vector3(p[0], -0.3, 0), Vector3(p[0], 0.0, 0), 0.02, brass)
		FairKit.mesh(pivot, FairKit.sphere_mesh(p[1], 16), Vector3(p[0], 0.05 + p[1], 0), FairKit.paint(p[2], 0.55, 0.1))
		if i == 4:
			var ring := FairKit.mesh(pivot, FairKit.torus_mesh(0.62, 0.85, 32, 4), Vector3(p[0], 0.05 + p[1], 0), FairKit.paint(Color(0.9, 0.82, 0.6), 0.4, 0.2))
			ring.scale = Vector3(1, 0.08, 1)
			ring.rotation.z = 0.35
		_orrery.append([pivot, p[3]])


func _animate(time: float) -> void:
	_turntable.rotation.y = -_theta
	var spin := clampf(absf(_ride_w) / RIDE_W, 0.0, 1.0)
	for k in _sleds.size():
		var bob: Node3D = _sleds[k].get_child(0)
		var amp := lerpf(0.06, 0.32, spin)
		bob.position.y = 1.25 + sin(_theta * 3.0 + _sled_phase[k]) * amp + 0.06 * sin(time * 1.3 + k)
		bob.rotation.x = cos(_theta * 3.0 + _sled_phase[k]) * 0.08 * spin
	for i in _orrery.size():
		(_orrery[i][0] as Node3D).rotation.y = float(_orrery[i][1]) * time * 0.5 + i * 1.9


var _ride_w := IDLE_W


func _idle_tick(time: float, delta: float) -> void:
	_ride_w = move_toward(_ride_w, IDLE_W, delta * 0.2)
	_theta += _ride_w * delta
	_animate(time)


func _on_ride_start() -> void:
	# Ride the outer sled currently closest to the booth side (+Z).
	_theta0 = _theta
	var best := 0
	var best_d := 1e9
	for k in OUTER:
		var a := TAU * k / OUTER + _theta
		var p := Vector3(cos(a), 0, sin(a))
		var d := p.distance_to(Vector3(0, 0, 1))
		if d < best_d:
			best_d = d
			best = k
	_rider_k = best
	_cap_idx = 0
	_captions = [[0.1, "ALL ABOARD"], [2.0, "LAUNCH"], [6.0, "IN ORBIT"], [27.0, "DEORBIT"], [30.5, "WELCOME BACK"]]


func _w(t: float) -> float:
	if t < 2.0:
		return lerpf(IDLE_W, 0.0, smoothstep(0.0, 1.0, t))
	if t < 6.0:
		return RIDE_W * smoothstep(2.0, 6.0, t)
	if t < 27.0:
		return RIDE_W
	return RIDE_W * (1.0 - smoothstep(27.0, 30.5, t))


func _theta_at(t: float) -> float:
	## Integral of _w (closed-form enough via fine trapezoid steps; t ≤ 32 s).
	var acc := 0.0
	var steps := int(t / 0.05)
	var prev := _w(0.0)
	for i in steps:
		var cur := _w((i + 1) * 0.05)
		acc += (prev + cur) * 0.025
		prev = cur
	return acc


func _ride_tick(t: float, _delta: float) -> void:
	var cap := ""
	while _cap_idx < _captions.size() and t >= float(_captions[_cap_idx][0]):
		cap = _captions[_cap_idx][1]
		_cap_idx += 1
	if cap != "":
		ride_caption.emit(cap)
	_ride_w = _w(t)
	_theta = _theta0 + _theta_at(t)
	_animate(_idle_t)


func get_seat_transform(_time: float) -> Transform3D:
	var bob: Node3D = _sleds[_rider_k].get_child(0)
	return Transform3D(global_transform.basis, bob.global_transform * Vector3(0, 0.4, 0.1))
