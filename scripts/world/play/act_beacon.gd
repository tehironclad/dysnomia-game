class_name ActBeacon
extends Node3D
## One act's marker in the world (personal UI, like the HUD: it shows what *this*
## player can do here; the territory's own visuals never depend on it).
## A ring on the ground, a soft shaft, a turning waypoint diamond and a label
## (title · detail). A blocked act is drawn dim, its label saying why.

const SHAFT := preload("res://assets/shaders/light_shaft.gdshader")
const LABEL_NEAR_M := 26.0   # beyond this only the diamond shows (labels never pile up)
const DETAIL_NEAR_M := 14.0  # the detail line only up close
const FAR_LABEL_M := 110.0   # border markers: their title from further away

const KIND_COLORS := {
	"su": Color("#7fd3ff"), "beat": Color("#ffd59a"), "room": Color("#64e3a8"), "crown": Color("#ffd27a"),
	"border": Color("#b07bff"), "well": Color("#8e97a9"),
}

var key := ""
var kind := ""
var always_label := false
var lift := 3.2   # the diamond's height above the anchor
var _diamond: MeshInstance3D
var _dmat: StandardMaterial3D
var _ring: MeshInstance3D
var _rmat: StandardMaterial3D
var _shaft_mat: ShaderMaterial
var _label: Label3D
var _t := 0.0
var _flare := 0.0
var _check := 0.0
var _title := ""
var _detail := ""


static func color_of(k: String) -> Color:
	return KIND_COLORS.get(k, Color("#a8e6ff"))


func build(p_kind: String, p_lift: float = 3.2) -> void:
	kind = p_kind
	lift = p_lift
	var col := color_of(kind)
	_rmat = _glow(col, 1.4, 0.55)
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.25
	t.outer_radius = 1.36
	t.rings = 48
	t.ring_segments = 4
	_ring.mesh = t
	_ring.material_override = _rmat
	_ring.position.y = 0.08
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var shaft := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.18
	c.bottom_radius = 0.5
	c.height = lift
	c.radial_segments = 12
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	shaft.mesh = c
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = SHAFT
	_shaft_mat.set_shader_parameter("color", Vector3(col.r, col.g, col.b))
	_shaft_mat.set_shader_parameter("height", lift)
	_shaft_mat.set_shader_parameter("intensity", 0.55)
	_shaft_mat.set_shader_parameter("fade_power", 1.1)
	shaft.material_override = _shaft_mat
	shaft.position.y = lift * 0.5
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)
	_diamond = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.32
	s.height = 0.9
	s.radial_segments = 4
	s.rings = 1
	_diamond.mesh = s
	_dmat = _glow(col.lerp(Color.WHITE, 0.25), 2.6, 1.0)
	_diamond.material_override = _dmat
	_diamond.position.y = lift
	_diamond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_diamond)
	_label = Label3D.new()
	_label.font = DeepFieldTheme.mono_font()
	_label.font_size = 28
	_label.outline_size = 9
	_label.outline_modulate = Color(0.01, 0.015, 0.03, 0.9)
	_label.modulate = col.lerp(Color.WHITE, 0.55)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0007
	_label.no_depth_test = true
	_label.render_priority = 2
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.position.y = lift + 0.7
	add_child(_label)


static func _glow(c: Color, e: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## Text and state from a PlayLoop act.
func show_act(a: Dictionary) -> void:
	key = String(a["key"])
	var doable: bool = a.get("doable", false)
	var detail := String(a.get("detail", "")) if doable or String(a.get("blocker", "")) == "" else String(a.get("blocker", ""))
	_title = String(a["title"]).to_upper()
	_detail = detail
	_label.text = _title
	var dim := 1.0 if doable else 0.4
	_dmat.albedo_color.a = 1.0
	_dmat.emission_energy_multiplier = 2.6 * dim
	_rmat.emission_energy_multiplier = 1.4 * dim
	_shaft_mat.set_shader_parameter("intensity", 0.55 * dim)
	_label.modulate.a = 1.0 if doable else 0.7


## Completed here: a short flare.
func flare() -> void:
	_flare = 1.0


func _process(delta: float) -> void:
	_t += delta
	_flare = maxf(0.0, _flare - delta * 0.6)
	_diamond.rotation.y += delta * (1.2 + 6.0 * _flare)
	_diamond.position.y = lift + 0.18 * sin(_t * 1.6)
	_diamond.scale = Vector3.ONE * (1.0 + 0.8 * _flare)
	_ring.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 2.1) + 1.5 * _flare)
	_check -= delta
	if _check <= 0.0:
		_check = 0.3
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam:
			var d := cam.global_position.distance_to(global_position)
			_label.visible = d < (FAR_LABEL_M if always_label else LABEL_NEAR_M)
			var want := (_title + "\n" + _detail) if d < DETAIL_NEAR_M and _detail != "" else _title
			if _label.text != want:
				_label.text = want
