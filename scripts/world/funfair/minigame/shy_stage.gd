class_name ShyStage
extends MidwayStage
## Crystal Shy: two steel rails across the back of the stall, five crystals sliding along each
## (speeds and spacing from the ticket). The sight sits on the rail you aim at; a thrown ball
## takes MidwaySim.SHY_FLY ticks to get there, so you lead the crystal. A hit knocks it off.

const RAIL_Y := [1.35, 1.95]
const RAIL_Z := [-0.55, -0.85]
const HAND := Vector3(0.36, 1.2, 1.42)
const EDGE := 1.85   ## crystals beyond this are behind the side walls

var _crystals: Array = []    ## [row][i] Node3D
var _fell: Array = []        ## [row][i] the tick it was seen knocked (-1)
var _ball: MeshInstance3D


func build() -> void:
	var steel := FairKit.paint(Color(0.3, 0.32, 0.36), 0.4, 0.8)
	var glow := FairKit.glow(FairKit.NEON_CYAN, 2.0, 0.8)
	for row in 2:
		FairKit.box(self, Vector3(3.9, 0.04, 0.07), Vector3(0, RAIL_Y[row] - 0.02, RAIL_Z[row]), steel)
		FairKit.box(self, Vector3(3.9, 0.012, 0.012), Vector3(0, RAIL_Y[row] - 0.045, RAIL_Z[row] + 0.04), glow)
		for sx in [-1.0, 1.0]:
			FairKit.box(self, Vector3(0.05, RAIL_Y[row] - 0.1, 0.05), Vector3(sx * 1.9, (RAIL_Y[row] + 0.08) * 0.5, RAIL_Z[row]), steel)
		var list: Array = []
		var fell: Array = []
		for i in MidwaySim.RAIL_N:
			var n := Node3D.new()
			add_child(n)
			var m := FairKit.mesh(n, FairKit.crystal_mesh(), Vector3.ZERO, FairKit.crystal_mat(FairKit.CRYSTAL_COLORS[(i + row) % 4]), Vector3.ZERO, false)
			m.scale = Vector3.ONE * 0.44
			m.name = "Gem"
			# A gold base under each (lit for the gold crystal of its rail)
			var base := FairKit.cyl(n, 0.06, 0.075, 0.04, Vector3(0, -0.02, 0), FairKit.paint(Color(0.3, 0.32, 0.36), 0.4, 0.8), 12)
			base.name = "Base"
			list.append(n)
			fell.append(-1)
		_crystals.append(list)
		_fell.append(fell)
	_ball = FairKit.mesh(self, FairKit.sphere_mesh(0.045, 12), HAND, FairKit.paint(Color(0.92, 0.92, 0.86), 0.6, 0.0))
	_ball.visible = false
	_make_reticle(0.09, Color(1.0, 0.85, 0.3))
	_idle()


func _idle() -> void:
	_ball.visible = false
	# Crystals stand evenly spaced while nobody plays (no processing when idle)
	for row in 2:
		for i in MidwaySim.RAIL_N:
			var n: Node3D = _crystals[row][i]
			n.visible = true
			n.rotation = Vector3.ZERO
			n.position = Vector3(-1.6 + i * 0.8 + row * 0.4, RAIL_Y[row], RAIL_Z[row])
			_fell[row][i] = -1


func _begin() -> void:
	_ball.visible = true
	if _gold == null:
		_gold = FairKit.crystal_mat(Color(1.0, 0.82, 0.3))
		_gold_base = FairKit.glow(Color(1.0, 0.8, 0.3), 6.0, 3.0)
	for row in 2:
		for i in MidwaySim.RAIL_N:
			_fell[row][i] = -1
			var n: Node3D = _crystals[row][i]
			var g := i == int(sim.gold[row])
			var gem: MeshInstance3D = n.get_node("Gem")
			if _plain.size() < 2 * MidwaySim.RAIL_N:
				_plain.append(gem.material_override)
			gem.material_override = _gold if g else _plain[row * MidwaySim.RAIL_N + i]
			gem.scale = Vector3.ONE * (0.6 if g else 0.44)
			(n.get_node("Base") as MeshInstance3D).material_override = _gold_base if g else null


func eye() -> Transform3D:
	return look(Vector3(0, 1.64, 2.05), Vector3(0, 1.55, -0.7))


func render() -> void:
	if sim == null:
		return
	for row in 2:
		for i in MidwaySim.RAIL_N:
			var n: Node3D = _crystals[row][i]
			var x := sim.crystal_x(row, i, sim.tick) / 1000.0
			var knocked: bool = (int(sim.knocked[row]) >> i) & 1 == 1
			if knocked and int(_fell[row][i]) < 0:
				_fell[row][i] = sim.tick
			if knocked:
				var ft := sim.tick - int(_fell[row][i])
				n.visible = ft < 40
				n.position.y = RAIL_Y[row] - 0.5 * 0.0006 * ft * ft * 9.0
				n.position.z = RAIL_Z[row] - ft * 0.004
				n.rotation.x = -ft * 0.08
			else:
				n.visible = absf(x) < EDGE
				n.position = Vector3(x, RAIL_Y[row], RAIL_Z[row])
	var row_aim := 1 if aim.y > 0.0 else 0
	_reticle.visible = sim.phase == "ready"
	_reticle_feedback()
	match sim.phase:
		"ready":
			_ball.position = HAND
			_reticle.position = Vector3(clampf(aim.x, -MidwaySim.AIM, MidwaySim.AIM) * 1700.0 / MidwaySim.AIM / 1000.0, RAIL_Y[row_aim] + 0.13, RAIL_Z[row_aim] + 0.06)
			_reticle.rotation = Vector3(PI * 0.5, 0, 0)
		"fly":
			var u := float(sim.phase_t) / sim.shot_t
			var row := sim.shot_to.y
			var to := Vector3(sim.shot_to.x / 1000.0, RAIL_Y[row] + 0.12, RAIL_Z[row])
			_ball.position = arc(HAND, to, u, 0.25)
			FairFx.stretch(_ball, 0.6 * (1.0 - u))
		"show":
			_ball.position = Vector3(sim.shot_to.x / 1000.0, 0.3, RAIL_Z[sim.shot_to.y] + 0.2)
			_ball.scale = Vector3.ONE


var _gold: Material
var _gold_base: Material
var _plain: Array = []


func _idle_gems() -> void:
	pass


## A crystal will be under the sight when a ball thrown now arrives.
func aim_hot() -> bool:
	if sim == null or sim.phase != "ready":
		return false
	var row := 1 if aim.y > 0.0 else 0
	var x := int(clampf(aim.x, -MidwaySim.AIM, MidwaySim.AIM) * 1700.0 / MidwaySim.AIM)
	for i in MidwaySim.RAIL_N:
		if (int(sim.knocked[row]) >> i) & 1:
			continue
		if absi(sim.crystal_x(row, i, sim.tick + MidwaySim.SHY_FLY[row]) - x) <= MidwaySim.SHY_HIT:
			return true
	return false


func impact_pos() -> Vector3:
	return Vector3(sim.shot_to.x / 1000.0, RAIL_Y[sim.shot_to.y] + 0.1, RAIL_Z[sim.shot_to.y] + 0.05) if sim else Vector3(0, 1.6, -0.6)


func result_sound() -> String:
	return "smash" if sim.last_points > 0 else ""


func on_result() -> void:
	if sim.last_points > 0:
		var c: Color = Color(1.0, 0.82, 0.3) if sim.last_bonus else FairKit.CRYSTAL_COLORS[(sim.hit_index + sim.shot_to.y) % 4]
		fx.burst(impact_pos(), c, 1.6 if sim.last_bonus else 1.1)
		fx.sparks(impact_pos(), c.lightened(0.4), 1.0, Vector3(0, 0.6, -1.0))
		kick(0.05 if not sim.last_bonus else 0.09, 0.06 if not sim.last_bonus else 0.12)
