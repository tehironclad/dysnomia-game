class_name RingStage
extends MidwayStage
## Regolith Ring Toss: a sloped regolith board inside the stall with a 3 × 3 grid of pegs
## (MidwaySim.PEGS_U × PEGS_V). The sight shows where a ring would land now, your aim plus the
## hand's sway; a throw arcs the ring onto the board, and it stays where it fell.

const O := Vector3(0.0, 0.95, 0.25)            ## the board at v = 0, u = 0
const UP_LEN := 1.25                            ## metres of board per 1000 mm of v
const HAND := Vector3(0.34, 1.2, 1.4)

var _b := Vector3(0.0, 0.9, -1.1).normalized()  ## up the board
var _n := Vector3(0.0, 1.1, 0.9).normalized()   ## out of the board
var _rings: Array = []
var _seen_round := -1


func board_point(u: float, v: float) -> Vector3:
	return O + Vector3(u / 1000.0, 0, 0) + _b * (v / 1000.0 * UP_LEN)


func build() -> void:
	var basis := Basis(Vector3.RIGHT, _n, -_b)
	var bd := FairKit.box(self, Vector3(2.2, 0.06, 1.45), Vector3.ZERO, FairKit.pbr("asphalt_02", Color(0.8, 0.8, 0.85), 1.5))
	bd.transform = Transform3D(basis, board_point(0, 500) - _n * 0.03)
	var frame := FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	for sx in [-1.0, 1.0]:
		var f := FairKit.box(self, Vector3(0.05, 0.08, 1.45), Vector3.ZERO, frame)
		f.transform = Transform3D(basis, board_point(sx * 1100.0, 500))
	# Legs from the deck to the board's top edge
	for sx in [-0.95, 0.95]:
		var top := board_point(sx * 1000.0, 1000) - _n * 0.05
		FairKit.box(self, Vector3(0.05, top.y - 0.12, 0.05), Vector3(top.x, (top.y + 0.12) * 0.5, top.z), frame)
	var rock := FairKit.pbr("asphalt_02", Color(0.85, 0.85, 0.9), 2.0)
	var k := 0
	for u in MidwaySim.PEGS_U:
		for v in MidwaySim.PEGS_V:
			var p := board_point(float(u), float(v))
			var peg := FairKit.cyl(self, 0.03, 0.045, 0.24, Vector3.ZERO, rock, 8)
			peg.transform = Transform3D(Basis(Vector3.RIGHT, _n, -_b), p + _n * 0.12)
			FairKit.mesh(self, FairKit.sphere_mesh(0.035, 8), p + _n * 0.25, FairKit.glow(FairKit.CRYSTAL_COLORS[k % 4], 4.0, 1.5), Vector3.ZERO, false)
			k += 1
	for i in MidwaySim.rounds("regolith"):
		var r := FairKit.mesh(self, FairKit.torus_mesh(0.07, 0.1, 16, 6), Vector3.ZERO, FairKit.glow(FairKit.NEON_CYAN if i % 2 == 0 else FairKit.NEON_VIOLET, 1.3, 0.8))
		_rings.append(r)
	_make_reticle(0.05, Color(1.0, 0.85, 0.3))
	_idle()


func _stack(i: int) -> Vector3:
	return Vector3(1.3, 1.095 + i * 0.03, 1.2)


func _begin() -> void:
	_seen_round = -1
	for i in _rings.size():
		_rings[i].transform = Transform3D(Basis(), _stack(i))


func _idle() -> void:
	_begin()


func eye() -> Transform3D:
	return look(Vector3(0, 1.72, 2.05), board_point(0, 480))


func fov() -> float:
	return 56.0


func _on_board(u: float, v: float, lift: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, _n, -_b), board_point(u, v) + _n * lift)


func render() -> void:
	if sim == null:
		return
	var i := mini(sim.round_i, _rings.size() - 1)
	var cur: MeshInstance3D = _rings[i]
	_reticle.visible = sim.phase == "ready"
	match sim.phase:
		"ready":
			var s := sim.sway()
			var u := clampf(aim.x, -MidwaySim.AIM, MidwaySim.AIM) * 900.0 / MidwaySim.AIM + s.x
			var v := 500.0 + clampf(aim.y, -MidwaySim.AIM, MidwaySim.AIM) * 500.0 / MidwaySim.AIM + s.y
			_reticle.transform = _on_board(u, v, 0.26)
			cur.transform = Transform3D(Basis(Vector3.RIGHT, 0.6), HAND)
		"fly":
			var t := float(sim.phase_t) / sim.shot_t
			var to := _on_board(sim.shot_to.x, sim.shot_to.y, 0.2)
			cur.transform = Transform3D(Basis(Vector3.RIGHT, 0.6).slerp(to.basis, t).rotated(_n, t * 8.0), arc(HAND, to.origin, t, 0.45))
		"show":
			if _seen_round != sim.round_i:
				_seen_round = sim.round_i
				var near := _nearest_peg(sim.shot_to)
				# A ringer drops down its peg; anything else lies on the board
				var at := _on_board(near.x, near.y, 0.03) if sim.last_points == 100 else _on_board(sim.shot_to.x, sim.shot_to.y, 0.04)
				_rings[mini(sim.round_i - 1, _rings.size() - 1)].transform = at


func _nearest_peg(p: Vector2i) -> Vector2:
	var best := Vector2(p)
	var bd := INF
	for u in MidwaySim.PEGS_U:
		for v in MidwaySim.PEGS_V:
			var d := Vector2(float(u - p.x), float(v - p.y)).length()
			if d < bd:
				bd = d
				best = Vector2(u, v)
	return best
