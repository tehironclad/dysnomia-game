class_name VoidMonolith
extends Node3D
## The Void's monolith (WP 5.4): a black slab standing in every territory.
## The Void is one board for everyone: Fomalhaute's LogEvent lines (from block
## 21,000,000), written through LAU.Chat. Its face shows the latest line.

var face: Label3D


func build() -> void:
	var slab := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(2.4, 6.0, 0.5)
	slab.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.005, 0.006, 0.01)
	m.metallic = 0.9
	m.roughness = 0.08
	m.rim_enabled = true
	m.rim = 0.6
	slab.material_override = m
	slab.position.y = 3.0
	Solid.box(self, Vector3(2.4, 6.0, 0.5), Vector3(0.0, 3.0, 0.0))
	add_child(slab)
	var edge := MeshInstance3D.new()
	var e := BoxMesh.new()
	e.size = Vector3(2.5, 0.04, 0.55)
	edge.mesh = e
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = DeepFieldTheme.ICE
	em.emission_enabled = true
	em.emission = DeepFieldTheme.ICE
	em.emission_energy_multiplier = 2.0
	edge.material_override = em
	edge.position.y = 6.02
	add_child(edge)
	var title := Label3D.new()
	title.font = DeepFieldTheme.mono_font()
	title.font_size = 48
	title.pixel_size = 0.01
	title.text = "THE VOID"
	title.modulate = DeepFieldTheme.ICE
	title.position = Vector3(0.0, 5.3, 0.27)
	add_child(title)
	face = Label3D.new()
	face.font = DeepFieldTheme.mono_font()
	face.font_size = 26
	face.pixel_size = 0.01
	face.width = 210.0
	face.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	face.modulate = DeepFieldTheme.MUTED
	face.text = "Fomalhaute's log\n—"
	face.position = Vector3(0.0, 3.6, 0.27)
	add_child(face)


func show_line(l: Dictionary) -> void:
	if face:
		face.text = "%s:\n%s\nblock %d" % [l["name"] if l["name"] != "" else "?", String(l["text"]).left(90), l["block"]]
