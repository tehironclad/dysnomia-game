class_name StrikerStage
extends MidwayStage
## Test Your Affection on the real 7 m high striker (Funfair._high_striker): you hold the mallet,
## the meter swings, the mallet comes down on the pad, the puck runs up the gold track (the
## camera follows it) and the bell lights and rings at MidwaySim.BELL.

const TRACK_Y0 := 0.8      ## puck centre at 0 mm
const TRACK_Y1 := 7.27     ## puck centre at BELL (its top touches the bell)
const PIVOT := Vector3(0.22, 1.4, 1.6)
const HANDLE := 1.6

var _puck: MeshInstance3D
var _mallet: Node3D
var _bell_light: OmniLight3D
var _bell: MeshInstance3D
var _bell_idle: Material
var _bell_lit: Material
var _look_y := 3.0


func build() -> void:
	_puck = FairKit.box(self, Vector3(0.22, 0.16, 0.12), Vector3(0, TRACK_Y0, -0.06), FairKit.paint(Color(0.95, 0.95, 0.9), 0.3, 0.6))
	_bell_idle = FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	_bell_lit = FairKit.glow(Color(1.0, 0.85, 0.4), 9.0, 6.0)
	# A second bell shell just over the built one, so it can light up
	_bell = FairKit.mesh(self, FairKit.sphere_mesh(0.31, 16), Vector3(0, 7.65, -0.2), _bell_idle, Vector3.ZERO, false)
	_bell_light = OmniLight3D.new()
	_bell_light.position = Vector3(0, 7.6, 0.4)
	_bell_light.light_color = Color(1.0, 0.82, 0.45)
	_bell_light.omni_range = 9.0
	_bell_light.light_energy = 0.0
	_bell_light.visible = false
	add_child(_bell_light)
	# The mallet: a handle from the pivot (your hands) with a heavy head at its end
	_mallet = Node3D.new()
	_mallet.position = PIVOT
	_mallet.visible = false
	add_child(_mallet)
	var wood := FairKit.paint(Color(0.85, 0.66, 0.42), 0.6, 0.0)
	var handle := FairKit.cyl(_mallet, 0.025, 0.03, HANDLE, Vector3(0, 0, -HANDLE * 0.5), wood, 10)
	handle.rotation.x = PI * 0.5
	var head := FairKit.cyl(_mallet, 0.13, 0.13, 0.46, Vector3(0, 0, -HANDLE), FairKit.paint(Color(0.82, 0.84, 0.9), 0.3, 0.9, 0.6), 18)
	head.rotation.z = PI * 0.5
	for sx in [-1.0, 1.0]:
		FairKit.cyl(_mallet, 0.135, 0.135, 0.04, Vector3(sx * 0.2, 0, -HANDLE), FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95), 18).rotation.z = PI * 0.5


func _begin() -> void:
	_mallet.visible = true
	_look_y = 3.0


func _idle() -> void:
	_mallet.visible = false
	_puck.position.y = TRACK_Y0
	_bell.material_override = _bell_idle
	_bell_light.visible = false


## At the pad with the mallet while you swing; then a step back, following the puck up the pole.
func eye() -> Transform3D:
	if sim == null or sim.phase in ["ready", "swing"]:
		return look(Vector3(0.0, 1.72, 2.6), Vector3(0.0, 1.55, -0.2))
	return look(Vector3(0.0, 1.75, 6.0), Vector3(0.0, _look_y, -0.2))


func fov() -> float:
	return 70.0


func meter() -> float:
	return sim.meter / 1000.0 if sim and sim.phase == "ready" else -1.0


func render() -> void:
	if sim == null:
		return
	var y := TRACK_Y0 + (TRACK_Y1 - TRACK_Y0) * float(sim.puck_y) / MidwaySim.BELL
	_puck.position.y = y
	# The mallet: raised and bobbing with the meter, then down onto the pad
	var th := 0.5 + 0.3 * sim.meter / 1000.0
	if sim.phase == "swing":
		th = lerpf(1.35, -0.63, smooth(float(sim.phase_t) / MidwaySim.SWING_T))
	elif sim.phase == "fly":
		th = -0.63 + minf(1.0, sim.phase_t / 20.0) * 1.2
	_mallet.rotation.x = th
	# The camera follows the puck up the pole
	var want := 3.0 if sim.phase in ["ready", "swing"] else clampf(lerpf(3.0, y, 0.5), 3.0, 4.3)
	_look_y = want
	var lit := sim.rang and sim.phase in ["fly", "show"]
	_bell.material_override = _bell_lit if lit else _bell_idle
	_bell_light.visible = lit
	if lit:
		_bell_light.light_energy = 6.0 * (0.6 + 0.4 * sin(sim.tick * 0.9))
