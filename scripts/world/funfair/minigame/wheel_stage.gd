class_name WheelStage
extends MidwayStage
## Waat Wheel of Fortune: a 2.1 m wheel on the stall's back wall, twelve segments whose values
## (and the spin speed) come from the ticket. It turns by MidwaySim.angle; the gold pointer at the
## top reads MidwaySim.segment(). The 500 jackpot is gold.

const CENTER := Vector3(0.0, 1.75, -1.17)
const R := 1.05

var _wheel: Node3D
var _labels: Array = []
var _mesh: MeshInstance3D
var _hilite: MeshInstance3D
var _values: Array = []


func build() -> void:
	_wheel = Node3D.new()
	_wheel.position = CENTER
	add_child(_wheel)
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wheel.add_child(_mesh)
	for k in 12:
		var phi := (k + 0.5) * TAU / 12.0
		var lb := FairKit.label(_wheel, "", Vector3(-sin(phi), cos(phi), 0.0) * R * 0.7 + Vector3(0, 0, 0.02), 44, Color(0.05, 0.05, 0.08), 0.0, Color(1, 1, 1, 0.0), 0.0042)
		lb.rotation.z = phi
		lb.shaded = true
		_labels.append(lb)
	FairKit.cyl(_wheel, 0.14, 0.14, 0.08, Vector3(0, 0, 0.05), FairKit.glow(FairKit.NEON_CYAN, 4.0, 1.5), 16).rotation.x = PI * 0.5
	# The pointer: a gold wedge just above the rim, pointing down at the top segment
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-0.09, 0.16, 0), Vector3(0.09, 0.16, 0), Vector3(0, -0.06, 0)]:
		st.set_normal(Vector3.BACK)
		st.add_vertex(v)
	var ptr := MeshInstance3D.new()
	ptr.mesh = st.commit()
	ptr.material_override = FairKit.glow(Color(1.0, 0.82, 0.35), 5.0, 3.0)
	ptr.position = CENTER + Vector3(0, R + 0.02, 0.08)
	add_child(ptr)
	_hilite = FairKit.mesh(self, FairKit.torus_mesh(0.13, 0.17, 20, 4), CENTER + Vector3(0, R * 0.68, 0.06), FairKit.glow(Color(1.0, 0.9, 0.4), 7.0, 4.0), Vector3(PI * 0.5, 0, 0), false)
	_hilite.visible = false
	_set_values([10, 20, 25, 40, 50, 60, 75, 100, 120, 150, 200, 500])


## Rebuilds the segment colours for a ticket's values (only at the start of a round).
func _set_values(vals: Array) -> void:
	_values = vals.duplicate()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 12:
		var col := Color.from_hsv(float(k) / 12.0, 0.6, 0.9 if k % 2 == 0 else 0.7)
		if int(vals[k]) == 500:
			col = Color(1.0, 0.8, 0.3)
		var a0 := k * TAU / 12.0
		for j in 6:
			var p0 := a0 + j * TAU / 72.0
			var p1 := a0 + (j + 1) * TAU / 72.0
			for v in [Vector3.ZERO, Vector3(-sin(p1), cos(p1), 0) * R, Vector3(-sin(p0), cos(p0), 0) * R]:
				st.set_color(col)
				st.set_normal(Vector3.BACK)
				st.add_vertex(v)
		set_text(_labels[k], str(vals[k]))
	_mesh.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = Color(0.25, 0.22, 0.2)
	_mesh.material_override = m


func _begin() -> void:
	_set_values(sim.wheel)
	_hilite.visible = false


func _idle() -> void:
	_hilite.visible = false


func eye() -> Transform3D:
	return look(Vector3(0, 1.7, 2.1), Vector3(0, 1.78, -1.2))


func fov() -> float:
	return 58.0


func render() -> void:
	if sim == null:
		return
	_wheel.rotation.z = float(sim.angle) / MidwaySim.TURN * TAU
	_hilite.visible = sim.phase == "show" and (sim.phase_t / 6) % 2 == 0
