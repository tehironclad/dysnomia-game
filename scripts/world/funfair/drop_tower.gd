class_name DropTower
extends RideBase
## Pi Drop Tower — a 55 m column with a ring of 12 outward-facing seats.
##
## Ride timeline (30 s):
##   0–2.5    restraints come down                       "HOLD ON"
##   2.5–15   slow haul to 51 m                          "51 m"
##   15–18.5  hold at the top                            "..."
##   18.5     magnet-assisted drop at 6 m/s² (lunar g is only 3.27) "DROP!"
##   ~22      magnetic brakes catch the ring at 14 m → damped bounce  "BRAKES"
##   25.5–28  lowered to the platform                    "WELCOME BACK" at 28

const TOWER_H := 55.0
const COL_R := 1.25
const RING_R := 2.75
const SEATS := 12
const Y0 := 1.05            # seat-pan height at the platform
const TOP := 51.0
const T_UP := Vector2(2.5, 15.0)
const T_DROP := 18.5
const DROP_A := 6.0
const BRAKE_Y := 14.0
const REST_Y := 7.0
const W := 3.0
const ZETA := 0.45
const T_LOWER := Vector2(25.5, 28.0)

var _car: Node3D
var _restraints: Array[Node3D] = []
var _t_brake := 0.0
var _v_brake := 0.0
var _y_lower0 := 0.0
var _captions: Array = []
var _cap_idx := 0
var _crown_mat: StandardMaterial3D


func _init() -> void:
	ride_id = "drop"
	booth_local_position = Vector3(5.5, 0, 8.5)
	exit_local_position = Vector3(3.5, 0.0, 8.0)
	booth_radius = 2.6


func _build() -> void:
	_t_brake = T_DROP + sqrt(2.0 * (TOP - BRAKE_Y) / DROP_A)
	_v_brake = DROP_A * (_t_brake - T_DROP)
	_y_lower0 = car_y(T_LOWER.x)
	_captions = [[0.1, "HOLD ON"], [T_UP.y, "%d m" % int(TOP)], [16.8, "..."], [T_DROP, "DROP!"],
		[_t_brake, "BRAKES"], [T_LOWER.y, "WELCOME BACK"]]
	var batch := FairKit.Batch.new()
	var concrete := FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3)
	var deck := FairKit.pbr("metal_plate", Color(0.85, 0.85, 0.88), 0.6, 1.0)
	var steel := FairKit.paint(Color(0.12, 0.13, 0.16), 0.4, 0.75)
	var white := FairKit.paint(Color(0.9, 0.9, 0.92), 0.3, 0.5, 0.5)
	# Plinth + loading deck
	FairKit.mesh(self, FairKit.cyl_mesh(4.6, 4.9, 0.5, 12), Vector3(0, 0.25, 0), concrete)
	FairKit.mesh(self, FairKit.cyl_mesh(4.3, 4.3, 0.06, 12), Vector3(0, 0.53, 0), deck)
	FairKit.solid_cyl(self, 4.9, 0.5, Vector3(0, 0.25, 0))
	FairKit.solid_cyl(self, COL_R + 0.2, 6.0, Vector3(0, 3.0, 0))
	# Column: dark steel core wrapped in white panels, with four LED strips
	var col := PackedVector2Array([Vector2(COL_R + 0.35, 0.0), Vector2(COL_R + 0.35, 1.2), Vector2(COL_R, 1.6),
		Vector2(COL_R, TOWER_H - 2.0), Vector2(COL_R * 0.85, TOWER_H)])
	FairKit.mesh(self, FairKit.lathe(col, 24), Vector3.ZERO, white)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		FairKit.box(self, Vector3(0.36, TOWER_H - 3.0, 0.36), d * (COL_R + 0.05) + Vector3(0, (TOWER_H - 3.0) * 0.5 + 1.5, 0), steel).rotation.y = -a
		var pts := PackedVector3Array()
		for j in 104:
			pts.append(d * (COL_R + 0.25) + Vector3(0, 2.0 + j * 0.5, 0))
		batch.bulb_line(pts, [FairKit.PALETTE[i], FairKit.PALETTE[(i + 2) % 6]], -0.035, 0.07)
	# Copper magnetic-brake fins up the lower column
	var copper := FairKit.paint(Color(0.72, 0.4, 0.22), 0.3, 0.95)
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		FairKit.box(self, Vector3(0.08, 13.0, 0.5), d * (COL_R + 0.25) + Vector3(0, 8.0, 0), copper).rotation.y = -a
	# Crown: flared cap, name boards, spire and beacon
	var crown := PackedVector2Array([Vector2(COL_R * 0.85, TOWER_H - 0.4), Vector2(3.6, TOWER_H + 0.3),
		Vector2(3.6, TOWER_H + 1.5), Vector2(2.2, TOWER_H + 2.6), Vector2(0.4, TOWER_H + 3.2), Vector2(0.0, TOWER_H + 3.25)])
	FairKit.mesh(self, FairKit.lathe(crown, 32), Vector3.ZERO, FairKit.paint(Color(0.12, 0.3, 0.62), 0.35, 0.5, 0.6))
	_crown_mat = FairKit.glow(Color(0.25, 0.9, 1.0), 4.0, 1.2)
	FairKit.mesh(self, FairKit.torus_mesh(3.55, 3.7, 48, 6), Vector3(0, TOWER_H + 0.9, 0), _crown_mat, Vector3.ZERO, false)
	for i in 4:
		var a := TAU * i / 4.0
		var l := FairKit.label(self, "PI DROP", Vector3(sin(a), 0, cos(a)) * 3.66 + Vector3(0, TOWER_H + 0.9, 0), 64, Color(2.0, 1.8, 1.3), a)
		l.outline_size = 10
	batch.strut(Vector3(0, TOWER_H + 3.2, 0), Vector3(0, TOWER_H + 8.0, 0), 0.07, steel)
	FairKit.mesh(self, FairKit.sphere_mesh(0.2, 10), Vector3(0, TOWER_H + 8.1, 0), FairKit.glow(Color(1.0, 0.08, 0.04), 8.0, 3.0), Vector3.ZERO, false)
	var crown_pts := FairKit.ring_points(Vector3(0, TOWER_H + 1.55, 0), 3.62, 64)
	batch.bulb_line(crown_pts, [FairKit.BULB_WARM, Color(0.3, 0.85, 1.0)], 0.05, 0.08)
	# Safety fence ring with a gap toward the booth
	var rail := FairKit.paint(Color(0.85, 0.75, 0.2), 0.4, 0.6)
	var fence_r := 6.2
	for i in 28:
		var a0 := TAU * i / 28.0
		var a1 := TAU * (i + 1) / 28.0
		if absf(wrapf(a0 - PI * 0.5, -PI, PI)) < 0.35:
			continue   # +Z gap for the queue
		var p0 := Vector3(cos(a0), 0, sin(a0)) * fence_r
		var p1 := Vector3(cos(a1), 0, sin(a1)) * fence_r
		batch.strut(p0, p0 + Vector3.UP * 1.1, 0.04, rail)
		batch.strut(p0 + Vector3.UP * 1.05, p1 + Vector3.UP * 1.05, 0.03, rail)
		batch.strut(p0 + Vector3.UP * 0.55, p1 + Vector3.UP * 0.55, 0.025, rail)
	batch.pool(Vector3(0, 0.1, 0), 9.0, Color(0.3, 0.8, 1.0) * 0.4)
	FairKit.omni(self, Vector3(0, 4.0, 4.5), Color(0.5, 0.85, 1.0), 2.5, 16.0, 0.0)
	# ── The seat ring (car) ──
	_car = Node3D.new()
	_car.name = "SeatRing"
	add_child(_car)
	FairKit.mesh(_car, FairKit.torus_mesh(COL_R + 0.3, RING_R + 0.35, 48, 8), Vector3(0, -0.15, 0), FairKit.paint(Color(0.85, 0.1, 0.2), 0.35, 0.5, 0.6))
	FairKit.mesh(_car, FairKit.torus_mesh(RING_R + 0.3, RING_R + 0.42, 48, 6), Vector3(0, -0.12, 0), FairKit.glow(Color(1.0, 0.3, 0.45), 3.0, 0.8), Vector3.ZERO, false)
	FairKit.mesh(_car, FairKit.cyl_mesh(COL_R + 0.45, COL_R + 0.45, 2.4, 24), Vector3(0, 0.7, 0), FairKit.paint(Color(0.2, 0.21, 0.24), 0.4, 0.8))
	# Moulded plastic bucket seats on a brushed-metal frame, over-the-shoulder harnesses
	var seat_m := FairKit.paint(Color(0.07, 0.16, 0.3), 0.28, 0.1, 0.8)       # glossy blue plastic shell
	var cushion_m := FairKit.paint(Color(0.12, 0.12, 0.14), 0.85, 0.0)        # padded vinyl
	var frame_m := FairKit.pbr("metal_plate_02", Color(0.75, 0.77, 0.8), 1.5, 1.0)
	var harness_m := FairKit.paint(Color(0.16, 0.16, 0.18), 0.6, 0.15)       # padded harness
	var accent_m := FairKit.paint(Color(0.95, 0.7, 0.1), 0.4, 0.3, 0.5)       # small yellow grab handle
	# Bucket seat: side profile (outward, up) extruded 0.62 m wide
	var seat_mesh := FairKit.extrude(PackedVector2Array([Vector2(-0.38, 0.0), Vector2(0.32, 0.0), Vector2(0.38, 0.14),
		Vector2(-0.16, 0.16), Vector2(-0.2, 1.28), Vector2(-0.3, 1.4), Vector2(-0.42, 1.3)]), 0.62)
	# Shoulder bar: side profile arcing from the hinge over the shoulder to the chest
	var bar_mesh := FairKit.extrude(PackedVector2Array([Vector2(0.0, 0.05), Vector2(0.3, 0.03), Vector2(0.5, -0.1),
		Vector2(0.62, -0.38), Vector2(0.64, -0.56), Vector2(0.56, -0.56), Vector2(0.54, -0.4), Vector2(0.43, -0.16),
		Vector2(0.27, -0.05), Vector2(0.0, -0.05)]), 0.11)
	for k in SEATS:
		var a := TAU * k / SEATS + PI * 0.5     # seat 0 faces +Z (booth side)
		var s := Node3D.new()
		s.rotation.y = -a + PI * 0.5
		_car.add_child(s)
		# In seat space: +Z = outward (rider faces out)
		var shell := FairKit.mesh(s, seat_mesh, Vector3(0, -0.06, RING_R + 0.05), seat_m)
		shell.rotation.y = -PI * 0.5   # profile X (outward) → seat +Z
		FairKit.box(s, Vector3(0.5, 0.06, 0.45), Vector3(0, 0.12, RING_R + 0.08), cushion_m)
		FairKit.box(s, Vector3(0.46, 0.75, 0.06), Vector3(0, 0.62, RING_R - 0.26), cushion_m)
		FairKit.box(s, Vector3(0.4, 0.06, 0.7), Vector3(0, -0.12, RING_R + 0.05), frame_m)
		FairKit.box(s, Vector3(0.5, 0.06, 0.26), Vector3(0, -0.8, RING_R + 0.45), frame_m)
		FairKit.beam(s, Vector3(0, -0.12, RING_R + 0.3), Vector3(0, -0.8, RING_R + 0.42), 0.03, frame_m)
		var r := Node3D.new()
		r.position = Vector3(0, 1.15, RING_R - 0.25)
		s.add_child(r)
		for sx in [-0.17, 0.17]:
			var bar := FairKit.mesh(r, bar_mesh, Vector3(sx, 0, 0), harness_m)
			bar.rotation.y = -PI * 0.5   # profile X → +Z (forward over the shoulder)
		FairKit.box(r, Vector3(0.46, 0.12, 0.1), Vector3(0, -0.5, 0.62), harness_m)
		FairKit.cyl(r, 0.022, 0.022, 0.3, Vector3(0, -0.6, 0.68), accent_m, 8).rotation.z = PI * 0.5
		_restraints.append(r)
	_car.position.y = Y0
	FairKit.ticket_booth(self, batch, booth_local_position, Vector3(signf(booth_local_position.x) * absf(0.1), 0, 1), item, Color(0.25, 0.8, 1.0))
	batch.flush(self)


func car_y(t: float) -> float:
	if t < T_UP.x:
		return Y0
	if t < T_UP.y:
		var u := smoothstep(T_UP.x, T_UP.y, t)
		return lerpf(Y0, TOP, u)
	if t < T_DROP:
		return TOP + sin(t * 9.0) * 0.015
	if t < _t_brake:
		var s := t - T_DROP
		return TOP - 0.5 * DROP_A * s * s
	var tau := t - _t_brake
	var y: float
	if t < T_LOWER.x or _y_lower0 == 0.0:
		# Damped spring about REST_Y: the magnets catch, bounce and settle
		var wd := W * sqrt(1.0 - ZETA * ZETA)
		var a := BRAKE_Y - REST_Y
		var b := (-_v_brake + ZETA * W * a) / wd
		y = REST_Y + exp(-ZETA * W * tau) * (a * cos(wd * tau) + b * sin(wd * tau))
		return maxf(y, Y0 + 0.6)
	return lerpf(_y_lower0, Y0, smoothstep(T_LOWER.x, T_LOWER.y, t))


func _ride_tick(t: float, _delta: float) -> void:
	var cap := ""
	while _cap_idx < _captions.size() and t >= float(_captions[_cap_idx][0]):
		cap = _captions[_cap_idx][1]
		_cap_idx += 1
	if cap != "":
		ride_caption.emit(cap)
	_car.position.y = car_y(t)
	var down := smoothstep(0.4, 2.0, t) * (1.0 - smoothstep(T_LOWER.y, T_LOWER.y + 1.2, t))
	for r in _restraints:
		r.rotation.x = lerpf(-1.3, 0.0, down)
	var flash := 1.0
	if t > 15.0 and t < T_DROP:
		flash = 1.0 + 2.5 * float(fmod(t, 0.5) < 0.25)
	_crown_mat.emission_energy_multiplier = 4.0 * flash * lerpf(0.4, 1.0, FairKit.night)


func _idle_tick(time: float, delta: float) -> void:
	_car.position.y = move_toward(_car.position.y, Y0, delta * 6.0)
	for r in _restraints:
		r.rotation.x = move_toward(r.rotation.x, -1.3, delta)


func _on_ride_start() -> void:
	_cap_idx = 0


func get_seat_transform(_time: float) -> Transform3D:
	# Seat 0 faces +Z; feet sit on the seat pan so the rider reads as seated on the ring.
	return Transform3D(global_transform.basis, _car.global_transform * Vector3(0, 0.06, RING_R + 0.05))
