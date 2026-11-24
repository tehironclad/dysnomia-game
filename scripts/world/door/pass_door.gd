class_name PassDoor
extends Node3D
## A doorway that opens: "slide" (two panels part sideways, a lit seam where
## they meet) or "curtain" (a light curtain that parts from the middle; with
## round = true a disc, for a portal ring). The origin is the middle of the
## threshold on the floor; the doorway faces ±Z.
##
## On its own it opens when the player comes within `reach` (an automatic
## door) and shuts after. A DoorSequence takes it over (held = true) and sets
## `open` itself. A visual only: never solid, and the same for every viewer.

const CURTAIN := preload("res://assets/shaders/light_curtain.gdshader")

var style := "slide"
var width := 2.0
var height := 3.0
var color := Color(0.55, 0.85, 1.0)
var round := false
var reach := 2.2          ## 0 = no automatic opening
var speed := 2.4          ## open/shut per second when automatic
var open := 0.0:
	set(v):
		open = clampf(v, 0.0, 1.0)
		_apply()
var held := false
var _panels: Array[MeshInstance3D] = []
var _curtain: ShaderMaterial
var _player: Node3D


static func make(p_style: String, p_width: float, p_height: float, p_color: Color, p_round := false) -> PassDoor:
	var d := PassDoor.new()
	d.style = p_style
	d.width = p_width
	d.height = p_height
	d.color = p_color
	d.round = p_round
	d.name = "PassDoor"
	return d


func _ready() -> void:
	if style == "curtain":
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(width, height)
		mi.mesh = q
		mi.position = Vector3(0, height * 0.5, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_curtain = ShaderMaterial.new()
		_curtain.shader = CURTAIN
		_curtain.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
		_curtain.set_shader_parameter("round_mask", 1.0 if round else 0.0)
		mi.material_override = _curtain
		add_child(mi)
	else:
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.09, 0.1, 0.13)
		metal.metallic = 0.75
		metal.roughness = 0.35
		var seam := StandardMaterial3D.new()
		seam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		seam.albedo_color = color
		for side in [-1.0, 1.0]:
			var p := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(width * 0.5, height, 0.06)
			p.mesh = b
			p.material_override = metal
			p.set_meta("side", side)
			add_child(p)
			var s := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.04, height * 0.86, 0.08)
			s.mesh = sb
			s.material_override = seam
			s.position = Vector3(-side * (width * 0.25 - 0.03), 0.0, 0.0)  # the inner (meeting) edge
			p.add_child(s)
			var w := MeshInstance3D.new()  # a window strip at eye height
			var wb := BoxMesh.new()
			wb.size = Vector3(width * 0.3, 0.12, 0.07)
			w.mesh = wb
			w.material_override = seam
			w.position = Vector3(0.0, height * 0.12, 0.0)
			p.add_child(w)
			_panels.append(p)
	_apply()


func _apply() -> void:
	if _curtain:
		_curtain.set_shader_parameter("open", open)
	var e := open * open * (3.0 - 2.0 * open)  # eased: panels start and stop softly
	for p in _panels:
		var side: float = p.get_meta("side")
		p.position = Vector3(side * (width * 0.25 + e * width * 0.48), height * 0.5, 0.0)


## For a curtain shown only while someone passes (0 hidden … 1 full).
func set_strength(s: float) -> void:
	if _curtain:
		_curtain.set_shader_parameter("strength", clampf(s, 0.0, 1.0))


func _process(delta: float) -> void:
	if held or reach <= 0.0:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var p := to_local(_player.global_position)
	var near := Vector2(p.x, p.z).length() < reach and absf(p.y) < height + 1.0
	var want := 1.0 if near else 0.0
	if want != open:
		open = move_toward(open, want, speed * delta)
