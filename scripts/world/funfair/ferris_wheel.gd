class_name FerrisWheel
extends RideBase
## Rho Wheel — a 30 m observation wheel with 14 lantern gondolas that stay level.
## The wheel turns slowly all the time; ride-local +Z faces the midway (wheel plane XY).
##
## Ride timeline (48 s):
##   0–3     the nearest gondola is eased to the boarding platform   "BOARDING"
##   3–21    half a revolution up the front                          "HOLD ON"
##   21–26   stopped at the very top                                 "TOP 35 m"
##   26–44   second half back down                                   "COMING DOWN"
##   44–48   unload                                                  "WELCOME BACK"

const RADIUS := 15.0
const HUB_H := 18.5
const N := 14
const RIM_Z := 1.35          # the two rim planes
const HANG := 2.6            # pivot → gondola floor
const T_BOARD := 3.0
const T_TOP := 21.0
const T_RESUME := 26.0
const T_DOWN := 44.0
const IDLE_SPEED := TAU / 150.0

var _wheel: Node3D
var _gondolas: Array[Node3D] = []
var _phi := 0.0
var _phi_start := 0.0
var _phi_board := 0.0
var _rider_k := 0
var _captions: Array = []
var _cap_idx := 0


func _init() -> void:
	ride_id = "wheel"
	booth_local_position = Vector3(8.5, 0, 9.5)
	exit_local_position = Vector3(6.2, 0.0, 9.0)
	booth_radius = 2.6


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 501
	_phi = rng.randf() * TAU
	var batch := FairKit.Batch.new()
	var steel := FairKit.paint(Color(0.9, 0.9, 0.92), 0.35, 0.55)
	var dark := FairKit.paint(Color(0.18, 0.19, 0.21), 0.45, 0.7)
	var concrete := FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3)
	# Apron + footings
	FairKit.box(self, Vector3(22.0, 0.12, 9.0), Vector3(0, 0.06, 0), FairKit.pbr("metal_plate_02", Color(0.85, 0.88, 0.92), 0.5, 1.0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot := Vector3(sx * 8.0, 0.35, sz * 3.2)
			FairKit.box(self, Vector3(1.6, 0.7, 1.6), foot, concrete)
			FairKit.solid_box(self, Vector3(1.6, 0.7, 1.6), foot)
			# A-frame legs up to the axle bearing
			batch.strut(foot + Vector3(0, 0.3, 0), Vector3(0, HUB_H, sz * 2.9), 0.32, steel)
		# Side bracing between the legs
	for sz in [-1.0, 1.0]:
		for h in [5.0, 10.5]:
			var u: float = h / HUB_H
			var xl := 8.0 * (1.0 - u)
			batch.strut(Vector3(-xl, h, sz * (3.2 - 0.3 * u)), Vector3(xl, h, sz * (3.2 - 0.3 * u)), 0.14, steel)
		FairKit.cyl(self, 0.9, 0.9, 0.7, Vector3(0, HUB_H, sz * 2.9), dark, 20).rotation.x = PI * 0.5
	var axle := FairKit.cyl(self, 0.45, 0.45, 6.4, Vector3(0, HUB_H, 0), dark, 20)
	axle.rotation.x = PI * 0.5
	# Boarding platform with steps
	var deck := FairKit.pbr("metal_plate", Color(0.85, 0.85, 0.88), 0.6, 1.0)
	FairKit.box(self, Vector3(4.6, 0.85, 3.4), Vector3(0, 0.425, 0), deck)
	FairKit.solid_box(self, Vector3(4.6, 0.85, 3.4), Vector3(0, 0.425, 0))
	for s in 4:
		var sh := 0.2125 * (s + 1)
		FairKit.box(self, Vector3(0.4, sh, 1.6), Vector3(2.5 + 0.4 * (3 - s), sh * 0.5, 0), concrete)
	for sz in [-1.0, 1.0]:
		batch.strut(Vector3(-2.3, 0.85, sz * 1.7), Vector3(-2.3, 1.9, sz * 1.7), 0.03, steel)
		batch.strut(Vector3(-2.3, 1.85, sz * 1.7), Vector3(2.3, 1.85, sz * 1.7), 0.03, steel)
	batch.pool(Vector3(0, 0.14, 0), 9.0, Color(1.0, 0.6, 0.85) * 0.35)

	# ── Rotating wheel ──
	_wheel = Node3D.new()
	_wheel.name = "Wheel"
	_wheel.position = Vector3(0, HUB_H, 0)
	add_child(_wheel)
	var wb := FairKit.Batch.new()
	var rim_m := FairKit.paint(Color(0.92, 0.92, 0.94), 0.3, 0.6)
	for z in [-RIM_Z, RIM_Z]:
		var t1 := FairKit.mesh(_wheel, FairKit.torus_mesh(RADIUS - 0.16, RADIUS + 0.16, 96, 8), Vector3(0, 0, z), rim_m)
		t1.rotation.x = PI * 0.5
		var t2 := FairKit.mesh(_wheel, FairKit.torus_mesh(RADIUS - 2.1, RADIUS - 1.85, 96, 6), Vector3(0, 0, z), rim_m)
		t2.rotation.x = PI * 0.5
		var hubdisc := FairKit.cyl(_wheel, 1.6, 1.6, 0.25, Vector3(0, 0, z * 1.25), FairKit.paint(Color(0.85, 0.15, 0.35), 0.35, 0.5, 0.5), 32)
		hubdisc.rotation.x = PI * 0.5
	var spokes := 28
	for i in spokes:
		var a := TAU * i / spokes
		var d := Vector3(cos(a), sin(a), 0)
		var d2 := Vector3(cos(a + PI / spokes), sin(a + PI / spokes), 0)
		for z in [-RIM_Z, RIM_Z]:
			wb.strut(d * 1.4 + Vector3(0, 0, z * 1.3), d * RADIUS + Vector3(0, 0, z), 0.05, rim_m)
			# zig-zag truss between inner and outer rims
			wb.strut(d * (RADIUS - 1.95) + Vector3(0, 0, z), d2 * RADIUS + Vector3(0, 0, z), 0.04, rim_m)
			var spoke_pts := PackedVector3Array()
			for j in 9:
				spoke_pts.append(d * (2.2 + j * 1.5) + Vector3(0, 0, z * 1.08 + signf(z) * 0.06))
			wb.bulb_line(spoke_pts, [FairKit.PALETTE[i % 6]], 0.09, 0.07)
		# Cross ties between the two rims
		if i % 2 == 0:
			wb.strut(d * RADIUS + Vector3(0, 0, -RIM_Z), d * RADIUS + Vector3(0, 0, RIM_Z), 0.06, rim_m)
	for z in [-RIM_Z, RIM_Z]:
		var rim_pts := FairKit.ring_points(Vector3.ZERO, RADIUS + 0.3, 140)
		var rp := PackedVector3Array()
		for p in rim_pts:
			rp.append(Vector3(p.x, p.z, z + signf(z) * 0.1))
		wb.bulb_line(rp, [Color(1.0, 0.35, 0.65), FairKit.BULB_WARM, Color(0.3, 0.8, 1.0)], 0.035, 0.085)
		# Continuous neon hub ring (a ring of bulbs here read as a dashed gizmo outline)
		var hr := FairKit.mesh(_wheel, FairKit.torus_mesh(1.68, 1.8, 48, 6), Vector3(0, 0, z * 1.32), FairKit.glow(FairKit.NEON_CYAN, 3.0, 0.8), Vector3.ZERO, false)
		hr.rotation.x = PI * 0.5
	wb.flush(_wheel)
	FairKit.label(_wheel, "RHO", Vector3(0, 0, RIM_Z * 1.36), 120, Color(2.2, 1.9, 1.4)).outline_size = 14
	FairKit.omni(self, Vector3(0, HUB_H, 4.5), Color(1.0, 0.7, 0.85), 3.5, 30.0, 0.0)

	# ── Gondolas (children of the ride, kept level) ──
	var cols := [Color(0.82, 0.12, 0.2), Color(0.1, 0.42, 0.75), Color(0.95, 0.66, 0.1), Color(0.12, 0.55, 0.42),
		Color(0.55, 0.2, 0.7), Color(0.92, 0.42, 0.12), Color(0.1, 0.6, 0.7)]
	for k in N:
		_gondolas.append(_make_gondola(cols[k % cols.size()], k))
	FairKit.ticket_booth(self, batch, booth_local_position, Vector3(signf(booth_local_position.x) * absf(0.15), 0, 1), item, Color(1.0, 0.3, 0.6))
	batch.flush(self)
	_place(_phi, 0.0)


func _make_gondola(c: Color, k: int) -> Node3D:
	var g := Node3D.new()
	g.name = "Gondola%d" % k
	add_child(g)
	var body := FairKit.paint(c, 0.4, 0.35, 0.7)
	var trim := FairKit.paint(Color(0.92, 0.82, 0.5), 0.3, 0.9)
	var gb := FairKit.Batch.new()
	# Hanger from the pivot axle
	for z in [-0.9, 0.9]:
		gb.strut(Vector3(0, 0, z), Vector3(0, -0.55, z * 0.4), 0.04, trim)
	FairKit.cyl(g, 0.05, 0.05, RIM_Z * 2.0, Vector3.ZERO, trim, 8).rotation.x = PI * 0.5
	# Lantern body: floor, skirt, glass band, roof
	var f := -HANG
	FairKit.mesh(g, FairKit.cyl_mesh(1.05, 0.8, 0.5, 8), Vector3(0, f - 0.2, 0), body)
	FairKit.mesh(g, FairKit.cyl_mesh(1.1, 1.1, 0.9, 8), Vector3(0, f + 0.45, 0), body)
	FairKit.mesh(g, FairKit.cyl_mesh(1.08, 1.08, 1.1, 8), Vector3(0, f + 1.45, 0), FairKit.glass(Color(0.85, 0.9, 1.0, 0.1)), Vector3.ZERO, false)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		gb.strut(Vector3(cos(a) * 1.1, f + 0.9, sin(a) * 1.1), Vector3(cos(a) * 1.1, f + 2.0, sin(a) * 1.1), 0.035, trim)
	var roof := PackedVector2Array([Vector2(1.25, f + 2.0), Vector2(1.2, f + 2.12), Vector2(0.5, f + 2.45), Vector2(0.08, f + 2.55), Vector2(0.0, f + 2.55)])
	FairKit.mesh(g, FairKit.cached_mesh("gondola_roof", func() -> Mesh: return FairKit.lathe(roof, 8)), Vector3.ZERO, body)
	FairKit.mesh(g, FairKit.torus_mesh(1.08, 1.16, 24, 4), Vector3(0, f + 0.92, 0), trim)
	# Warm lantern band inside + bench
	FairKit.mesh(g, FairKit.torus_mesh(0.98, 1.03, 24, 4), Vector3(0, f + 1.98, 0), FairKit.glow(Color(1.0, 0.78, 0.45), 4.0, 0.8), Vector3.ZERO, false)
	FairKit.box(g, Vector3(1.4, 0.42, 0.45), Vector3(0, f + 0.21, -0.6), FairKit.paint(Color(0.3, 0.12, 0.08), 0.6, 0.1))
	FairKit.cyl(g, 0.98, 0.98, 0.05, Vector3(0, f + 0.0, 0), FairKit.pbr("brown_planks_05", Color(0.8, 0.65, 0.5), 1.5), 8)
	var ring := FairKit.ring_points(Vector3(0, f + 2.08, 0), 1.24, 12)
	gb.bulb_line(ring, [FairKit.BULB_WARM], 0.0, 0.05)
	gb.flush(g)
	return g


func _place(phi: float, t: float) -> void:
	_wheel.rotation.z = phi
	for k in N:
		var a := phi + TAU * k / N
		var g := _gondolas[k]
		g.position = Vector3(cos(a) * RADIUS, HUB_H + sin(a) * RADIUS, 0)
		# Stay level, with a slight lag-swing from the wheel's motion
		g.rotation = Vector3(0, 0, sin(t * 0.9 + k) * 0.025)


func _idle_tick(time: float, delta: float) -> void:
	_phi = wrapf(_phi + IDLE_SPEED * delta, 0.0, TAU)
	_place(_phi, time)


func _on_ride_start() -> void:
	# Choose the gondola that reaches the bottom (-90°) soonest, ease it to the platform.
	_phi_start = _phi
	var best := 0
	var best_d := 1e9
	for k in N:
		var target := -PI * 0.5 - TAU * k / N
		var d := wrapf(target - _phi, 0.0, TAU)
		if d < best_d:
			best_d = d
			best = k
	_rider_k = best
	_phi_board = _phi + best_d
	_cap_idx = 0
	_captions = [[0.1, "BOARDING"], [T_BOARD, "HOLD ON"], [T_TOP, "TOP %d m" % int(HUB_H + RADIUS + 1.5)],
		[T_RESUME, "COMING DOWN"], [T_DOWN, "WELCOME BACK"]]


func _ride_phi(t: float) -> float:
	if t < T_BOARD:
		return lerpf(_phi_start, _phi_board, smoothstep(0.0, T_BOARD, t))
	if t < T_TOP:
		return _phi_board + PI * smoothstep(T_BOARD, T_TOP, t)
	if t < T_RESUME:
		return _phi_board + PI
	return _phi_board + PI + PI * smoothstep(T_RESUME, T_DOWN, t)


func _ride_tick(t: float, _delta: float) -> void:
	var cap := ""
	while _cap_idx < _captions.size() and t >= float(_captions[_cap_idx][0]):
		cap = _captions[_cap_idx][1]
		_cap_idx += 1
	if cap != "":
		ride_caption.emit(cap)
	_phi = wrapf(_ride_phi(t), 0.0, TAU)
	_place(_phi, t)


func get_seat_transform(_time: float) -> Transform3D:
	var g := _gondolas[_rider_k]
	return Transform3D(global_transform.basis, g.global_transform * Vector3(0, -HANG + 0.03, 0.25))
