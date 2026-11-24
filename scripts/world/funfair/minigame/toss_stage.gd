class_name TossStage
extends MidwayStage
## Entropy Toss: a felt board inside the stall with three scoring rings (where they sit, and the
## entropy drift that pushes every puck sideways, come from the ticket). You toss a puck over the
## counter: it arcs onto the board and slides to where MidwaySim says it stops.

const BOARD_Y := 0.945
const HAND := Vector3(0.3, 1.24, 1.42)

var _rings: Node3D
var _pucks: Array = []        ## one per toss; earlier ones stay where they stopped
var _aim_line: MeshInstance3D
var _drift: Label3D
var _drift_arrow: MeshInstance3D
var _seen_round := -1
var _land: MeshInstance3D       ## where the puck would land with no drift (the meter sets the distance)
var _bull: MeshInstance3D


func build() -> void:
	FairKit.box(self, Vector3(2.9, 0.05, 1.95), Vector3(0, BOARD_Y - 0.025, -0.2), FairKit.paint(Color(0.3, 0.16, 0.5), 0.95, 0.0))
	# Rails round the board
	var rail := FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	for sx in [-1.0, 1.0]:
		FairKit.box(self, Vector3(0.04, 0.05, 1.95), Vector3(sx * 1.47, BOARD_Y + 0.02, -0.2), rail)
	FairKit.box(self, Vector3(2.98, 0.05, 0.04), Vector3(0, BOARD_Y + 0.02, -1.17), rail)
	# Legs under the board's front edge (it stands on the deck)
	for sx in [-1.3, 1.3]:
		FairKit.box(self, Vector3(0.06, BOARD_Y - 0.12, 0.06), Vector3(sx, (BOARD_Y + 0.12) * 0.5, 0.6), rail)
	_rings = Node3D.new()
	add_child(_rings)
	var cols := [Color(0.3, 0.45, 1.0), Color(0.35, 0.95, 1.0), Color(1.0, 0.82, 0.3)]
	for i in 3:
		var r := float(MidwaySim.TOSS_RINGS[2 - i]) / 1000.0
		FairKit.cyl(_rings, r, r, 0.006, Vector3(0, 0.004 + i * 0.003, 0), FairKit.glow(cols[i], 0.7 + 0.3 * i, 0.5), 40)
		FairKit.mesh(_rings, FairKit.torus_mesh(r - 0.008, r, 40, 4), Vector3(0, 0.012 + i * 0.003, 0), FairKit.glow(Color(0.9, 0.95, 1.0), 1.0, 0.6), Vector3.ZERO, false)
	_bull = FairKit.cyl(_rings, 0.045, 0.045, 0.008, Vector3(0, 0.016, 0), FairKit.glow(Color(1.0, 0.85, 0.3), 5.0, 2.5), 24)
	FairKit.label(_rings, "150", Vector3(0, 0.022, 0), 28, Color(0.25, 0.1, 0.02), 0.0, Color(1, 1, 1, 0), 0.0024).rotation.x = -PI * 0.5
	_rings.position = Vector3(0.0, BOARD_Y, -0.45)
	var gold := FairKit.glow(Color(1.0, 0.78, 0.35), 0.8, 0.6)
	for i in MidwaySim.rounds("entropy"):
		var p := FairKit.cyl(self, 0.05, 0.05, 0.026, _rest(i), gold, 18)
		_pucks.append(p)
	_land = FairKit.mesh(self, FairKit.torus_mesh(0.035, 0.05, 20, 4), Vector3.ZERO, FairKit.glow(Color(0.5, 0.95, 1.0), 4.0, 2.0), Vector3.ZERO, false)
	_land.visible = false
	_aim_line = FairKit.box(self, Vector3(0.012, 0.004, 1.0), Vector3.ZERO, FairKit.glow(Color(0.5, 0.95, 1.0), 3.0, 2.0))
	_aim_line.visible = false
	# The drift: a sign on a stand at the board's far edge, an arrow under it the way it pushes
	FairKit.box(self, Vector3(1.5, 0.3, 0.03), Vector3(0, BOARD_Y + 0.32, -1.18), FairKit.paint(Color(0.04, 0.04, 0.07), 0.7, 0.2))
	_drift = FairKit.label(self, "", Vector3(0, BOARD_Y + 0.37, -1.16), 40, Color(0.8, 0.95, 1.0) * 1.6, 0.0, Color(0.01, 0.01, 0.02), 0.0035)
	_drift_arrow = FairKit.box(self, Vector3(0.6, 0.05, 0.02), Vector3(0, BOARD_Y + 0.24, -1.16), FairKit.glow(Color(0.5, 0.95, 1.0), 3.0, 2.0))
	_drift_arrow.visible = false


func _begin() -> void:
	_seen_round = -1
	for i in _pucks.size():
		_pucks[i].position = _rest(i)
		_pucks[i].scale = Vector3.ONE


func _idle() -> void:
	_aim_line.visible = false
	_land.visible = false
	_drift_arrow.visible = false
	set_text(_drift, "")
	_begin()


func eye() -> Transform3D:
	return look(Vector3(0, 1.9, 2.0), Vector3(0, 0.9, -0.55))


func meter() -> float:
	return sim.meter / 1000.0 if sim and sim.phase == "ready" else -1.0


func _board(v: Vector2i) -> Vector3:
	return Vector3(v.x / 1000.0, BOARD_Y + 0.013, v.y / 1000.0)


func render() -> void:
	if sim == null:
		return
	_rings.position = Vector3(sim.target.x / 1000.0, BOARD_Y, sim.target.y / 1000.0)
	set_text(_drift, "ENTROPY DRIFT %+d mm/m" % sim.wind)
	_drift_arrow.visible = sim.wind != 0
	_drift_arrow.scale.x = clampf(absf(sim.wind) / 150.0, 0.15, 1.0)
	_drift_arrow.position.x = signf(sim.wind) * 0.35 * _drift_arrow.scale.x
	var i := mini(sim.round_i, _pucks.size() - 1)
	var cur: MeshInstance3D = _pucks[i]
	match sim.phase:
		"ready":
			cur.position = HAND
			_aim_line.visible = true
			_land.visible = true
			# The line runs to where the puck would stop at this power with no drift: the drift is yours to read
			var d := (400.0 + sim.meter * 1.6) / 1000.0
			var dx := aim.x * 500.0 / MidwaySim.AIM / 1000.0
			var dir := Vector3(dx, 0.0, -1.0).normalized()
			var start := _board(Vector2i(0, MidwaySim.TOSS_Z0))
			var b := Basis.looking_at(dir, Vector3.UP)
			b.z *= d
			var end := start + Vector3(dx * d, 0, -d)
			_aim_line.transform = Transform3D(b, (start + end) * 0.5)
			_land.position = end + Vector3(0, 0.01, 0)
			_land.material_override = _land_mat(end)
		"fly":
			_aim_line.visible = false
			_land.visible = false
			var u := float(sim.phase_t) / sim.shot_t
			FairFx.stretch(cur, 0.5 * (1.0 - absf(u * 2.0 - 1.0)) if u < 0.5 else 0.0)
			var land := _board(Vector2i(sim.shot_from.x + (sim.shot_to.x - sim.shot_from.x) * 6 / 10, sim.shot_from.y + (sim.shot_to.y - sim.shot_from.y) * 6 / 10))
			var stop := _board(sim.shot_to)
			if u < 0.5:
				cur.position = arc(HAND, land, u / 0.5, 0.35)
			else:
				var v := 1.0 - pow(1.0 - (u - 0.5) / 0.5, 2.0)
				cur.position = land.lerp(stop, v)
			cur.rotation.y = u * 9.0
		"show":
			if _seen_round != sim.round_i:
				_seen_round = sim.round_i
				var stop2 := _board(sim.shot_to)
				var off := sim.shot_to.y < MidwaySim.TOSS_BACK or absi(sim.shot_to.x) > 1500
				_pucks[mini(sim.round_i - 1, _pucks.size() - 1)].position = Vector3(stop2.x, 0.2, stop2.z) if off else stop2


func _rest(i: int) -> Vector3:
	return Vector3(1.3 - (i % 3) * 0.12, 1.09 + (i / 3) * 0.03, 1.2 - (i / 3) * 0.06)


var _land_cold: Material
var _land_hot: Material


func _land_mat(end: Vector3) -> Material:
	if _land_cold == null:
		_land_cold = FairKit.glow(Color(0.5, 0.95, 1.0), 4.0, 2.0)
		_land_hot = FairKit.glow(Color(0.35, 1.0, 0.5), 6.0, 3.0)
	return _land_hot if aim_hot() else _land_cold


## The no-drift landing point sits inside the rings.
func aim_hot() -> bool:
	if sim == null or sim.phase != "ready":
		return false
	var d := 400 + sim.meter * 1600 / 1000
	var ex := (d * int(aim.x) * 500 / MidwaySim.AIM) / 1000
	var dx := ex - sim.target.x
	var dz := (MidwaySim.TOSS_Z0 - d) - sim.target.y
	return dx * dx + dz * dz <= 220 * 220


func impact_pos() -> Vector3:
	return _board(sim.shot_to) + Vector3(0, 0.08, 0) if sim else Vector3(0, 1.0, -0.4)


func on_result() -> void:
	var p: MeshInstance3D = _pucks[mini(sim.round_i - 1, _pucks.size() - 1)]
	FairFx.squash(p, 0.5 if sim.last_points > 0 else 0.25, Vector3.UP)
	if sim.last_bonus:
		FairFx.squash(_bull, 0.5, Vector3.UP)
		kick(0.08, 0.1)
