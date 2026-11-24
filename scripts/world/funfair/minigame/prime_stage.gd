class_name PrimeStage
extends MidwayStage
## Motzkin Prime Shooter: eight hinged targets on the back wall (MidwaySim.SLOTS_X × SLOTS_Y)
## pop up with a number each (the schedule comes from the ticket) and drop when shot or when
## their time is up. The crosshair sits on the wall; a shot draws a tracer from the counter gun.

const WALL_Z := -1.15
const MUZZLE := Vector3(0.0, 1.2, 0.85)
const EYE := Vector3(0, 1.62, 2.05)

var _pivots: Array = []      ## per slot: hinge Node3D (rotation.x: 0 up, PI/2 down, lying forward)
var _numbers: Array = []     ## per slot: Label3D
var _rims: Array = []        ## per slot: MeshInstance3D (its glow ring)
var _tracer: MeshInstance3D
var _rim_idle: Material
var _rim_good: Material
var _rim_bad: Material
var _slot_entry: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1])
var _scan_from := 0
var _shown: PackedInt32Array = PackedInt32Array([-2, -2, -2, -2, -2, -2, -2, -2])  ## entry whose number a slot shows


func build() -> void:
	var face := FairKit.paint(Color(0.92, 0.92, 0.9), 0.4, 0.1)
	_rim_idle = FairKit.glow(Color(1.0, 0.85, 0.35), 3.0, 1.2)
	_rim_good = FairKit.glow(Color(0.35, 1.0, 0.55), 6.0, 3.0)
	_rim_bad = FairKit.glow(Color(1.0, 0.25, 0.3), 6.0, 3.0)
	var steel := FairKit.paint(Color(0.3, 0.32, 0.36), 0.4, 0.8)
	for row in 2:
		FairKit.box(self, Vector3(3.6, 0.05, 0.12), Vector3(0, float(MidwaySim.SLOTS_Y[row]) / 1000.0 - 0.3, WALL_Z + 0.02), steel)
	for s in 8:
		var hinge := Node3D.new()
		hinge.position = Vector3(float(MidwaySim.SLOTS_X[s % 4]) / 1000.0, float(MidwaySim.SLOTS_Y[s / 4]) / 1000.0 - 0.28, WALL_Z + 0.06)
		hinge.rotation.x = PI * 0.5
		add_child(hinge)
		var disc := FairKit.cyl(hinge, 0.26, 0.26, 0.04, Vector3(0, 0.28, 0), face, 24)
		disc.rotation.x = PI * 0.5
		var rim := FairKit.mesh(hinge, FairKit.torus_mesh(0.21, 0.25, 24, 4), Vector3(0, 0.28, 0.025), _rim_idle, Vector3(PI * 0.5, 0, 0), false)
		var lb := FairKit.label(hinge, "", Vector3(0, 0.28, 0.03), 64, Color(0.1, 0.08, 0.12), 0.0, Color(0, 0, 0, 0), 0.004)
		lb.shaded = true
		_pivots.append(hinge)
		_numbers.append(lb)
		_rims.append(rim)
	_tracer = FairKit.box(self, Vector3(0.012, 0.012, 1.0), Vector3.ZERO, FairKit.glow(Color(1.0, 0.4, 0.35), 6.0, 4.0))
	_tracer.visible = false
	_make_reticle(0.11, Color(1.0, 0.3, 0.35))
	_idle()


func _idle() -> void:
	_tracer.visible = false
	# Idle: the first row shows primes, the second the composites they hide among
	var show := ["2", "3", "5", "7", "11", "13", "17", "19"]
	for s in 8:
		_pivots[s].rotation.x = 0.0
		set_text(_numbers[s], show[s])
		_rims[s].material_override = _rim_idle


func _begin() -> void:
	_scan_from = 0
	for s in 8:
		_slot_entry[s] = -1
		_shown[s] = -2
		_pivots[s].rotation.x = PI * 0.5
		set_text(_numbers[s], "")


func eye() -> Transform3D:
	return look(EYE, Vector3(0, 1.75, -1.2))


func fov() -> float:
	return 62.0


func render() -> void:
	if sim == null:
		return
	var t := sim.tick
	# Which schedule entry each slot shows: the latest one that has started
	while _scan_from < sim.schedule.size() and int(sim.schedule[_scan_from][1]) <= t:
		_slot_entry[int(sim.schedule[_scan_from][0])] = _scan_from
		_scan_from += 1
	for s in 8:
		var e := _slot_entry[s]
		var up := 0.0
		if e >= 0:
			var ent: Array = sim.schedule[e]
			var start := int(ent[1])
			var stop := int(ent[2])
			var shot := int(sim.shot_down[e])
			if shot >= 0:
				stop = shot
			up = clampf((t - start) / 8.0, 0.0, 1.0) * clampf((stop - t) / 8.0 + (0.6 if shot >= 0 and t - shot < 10 else 0.0), 0.0, 1.0)
			if _shown[s] != e:
				_shown[s] = e
				_numbers[s].text = str(int(ent[3]))
			_rims[s].material_override = (_rim_good if MidwaySim.is_prime(int(ent[3])) else _rim_bad) if shot >= 0 else _rim_idle
		_pivots[s].rotation.x = PI * 0.5 * (1.0 - up)
	_reticle.visible = not sim.done
	# The sight floats in front of the fallen targets, on the line from your eye to the wall point
	var wall := Vector3(clampf(aim.x, -MidwaySim.AIM, MidwaySim.AIM) * 1800.0 / MidwaySim.AIM / 1000.0,
		(1825.0 + clampf(aim.y, -MidwaySim.AIM, MidwaySim.AIM) * 700.0 / MidwaySim.AIM) / 1000.0, WALL_Z + 0.06)
	_reticle.position = EYE.lerp(wall, 0.75)
	_reticle.scale = Vector3.ONE * 0.75
	_reticle.rotation = Vector3(PI * 0.5, 0, 0)
	var since := t - sim.last_tick
	_tracer.visible = sim.last_tick >= 0 and since < 5
	if _tracer.visible:
		var hit := Vector3(sim.target.x / 1000.0, sim.target.y / 1000.0, WALL_Z + 0.08)
		var d := hit - MUZZLE
		var b := Basis.looking_at(d, Vector3.UP)
		b.z = b.z * d.length()
		_tracer.transform = Transform3D(b, (MUZZLE + hit) * 0.5)
