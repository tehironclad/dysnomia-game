class_name FieldGlobe
extends Node3D
## The moon Dysnomia with every QING at its chain coordinates (HECKE.Compliment(Waat),
## projected as the site does). Shared by the Field and the front door's backdrop.
##
## - dots: one per QING, coloured by the caller (rarity, heat, age…); a developed
##   QING's dot is bigger (×1 + 0.45·tier) and carries a warm halo as bright as its
##   tier (city lights; DevelopmentSnapshot, with its block). Unmeasured = no halo.
## - your QINGs (founded or with your bars): an ice ring;
## - where you are: a larger white ring that breathes, and "YOU ARE HERE".
## Everything drawn is a real number: a dot's place is its Compliment, its halo its
## Hypobar total's tier. Nothing is placed or sized by the viewer.

const RADIUS := 1.0
const POINT_SIZE := 0.0075
const HALO := Color("#ffd27a")
const MINE := Color("#a8e6ff")

var territories: Array = []
var rows: Array = []
var dots: MultiMeshInstance3D
var halos: MultiMeshInstance3D
var rings: MultiMeshInstance3D
var moon: MeshInstance3D
var here_label: Label3D
var _here_i := -1
var _t := 0.0


func _init() -> void:
	moon = MeshInstance3D.new()
	moon.name = "Moon"
	var sm := SphereMesh.new()
	sm.radius = RADIUS * 0.995
	sm.height = RADIUS * 1.99
	sm.radial_segments = 96
	sm.rings = 48
	moon.mesh = sm
	var mat := StandardMaterial3D.new()
	var tex_path := "res://assets/textures/polyhaven/moon_meteor_01/moon_meteor_01_diff_1k.jpg"
	var nor_path := "res://assets/textures/polyhaven/moon_meteor_01/moon_meteor_01_nor_gl_1k.jpg"
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.uv1_triplanar = true
		mat.uv1_triplanar_sharpness = 2.0
		mat.uv1_scale = Vector3(1.3, 1.3, 1.3)
		if ResourceLoader.exists(nor_path):
			mat.normal_enabled = true
			mat.normal_texture = load(nor_path)
			mat.normal_scale = 1.4
		mat.albedo_color = Color(0.16, 0.17, 0.2)
	else:
		mat.albedo_color = Color(0.09, 0.1, 0.13)
	mat.roughness = 0.97
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.2
	moon.material_override = mat
	add_child(moon)
	dots = _multi("Dots", _dot_mesh())
	halos = _multi("Halos", _billboard(_radial(false), true))
	rings = _multi("Rings", _billboard(_radial(true), true))
	here_label = Label3D.new()
	here_label.text = "YOU ARE HERE"
	here_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	here_label.pixel_size = 0.0009
	here_label.font_size = 40
	here_label.outline_size = 10
	here_label.modulate = Color.WHITE
	here_label.no_depth_test = false
	here_label.visible = false
	var df := DeepFieldTheme.display_font()
	if df:
		here_label.font = df
	add_child(here_label)


func _multi(n: String, mesh: Mesh) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _dot_mesh() -> Mesh:
	var dot := SphereMesh.new()
	dot.radius = POINT_SIZE
	dot.height = POINT_SIZE * 2.0
	dot.radial_segments = 8
	dot.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	dot.material = mat
	return dot


static func _radial(ring: bool) -> Texture2D:
	var g := Gradient.new()
	if ring:
		g.offsets = PackedFloat32Array([0.0, 0.62, 0.74, 0.86, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _billboard(tex: Texture2D, additive: bool) -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = mat
	return q


## How light the regolith reads (albedo multiplier): dim on the Field, so the dots
## lead; brighter under the front door's low sun.
func set_moon_tone(v: float) -> void:
	var mat: StandardMaterial3D = moon.material_override
	if mat.albedo_texture != null:
		mat.albedo_color = Color(v, v * 1.03, v * 1.12)


## Registry records and their FieldIndex rows (same order).
func setup(p_territories: Array, p_rows: Array) -> void:
	territories = p_territories
	rows = p_rows
	var n := territories.size()
	dots.multimesh.instance_count = n
	halos.multimesh.instance_count = n
	rings.multimesh.instance_count = n
	for i in n:
		dots.multimesh.set_instance_transform(i, Transform3D(Basis(), pos(i)))


func pos(i: int, lift: float = 0.5) -> Vector3:
	var q: Dictionary = territories[i]
	return Coords.to_sphere(float(q.get("lat", 0.0)), float(q.get("lon", 0.0))) * (RADIUS + POINT_SIZE * lift)


func dev_scale(i: int) -> float:
	var t := int(rows[i]["tier"]) if i < rows.size() else -1
	return 1.0 + 0.45 * maxf(0.0, float(t))


## Draws every QING. colors: one per QING; visible: 1 shown / 0 filtered out;
## mine: {address: true}; here: the address you stand in ("" = none).
func paint(colors: PackedColorArray, visible_mask: PackedByteArray, selected: int, hovered: int, mine: Dictionary, here: String) -> void:
	var n := territories.size()
	_here_i = -1
	for i in n:
		var shown := visible_mask.is_empty() or visible_mask[i] == 1
		var a := String(rows[i]["address"]) if i < rows.size() else ""
		var c := colors[i] if i < colors.size() else DeepFieldTheme.MUTED
		var s := dev_scale(i)
		if not shown:
			c = Color(0.08, 0.09, 0.12)
			s = 0.8
		if i == selected:
			c = Color.WHITE
			s = maxf(s, 2.2) * 1.15
		elif i == hovered:
			s *= 1.5
		dots.multimesh.set_instance_color(i, c)
		dots.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), pos(i)))
		var t := int(rows[i]["tier"]) if i < rows.size() else -1
		var hp := pos(i, 3.0)
		if t >= 1 and shown:
			var hs := POINT_SIZE * (7.0 + 4.5 * t)
			var hc := HALO
			hc.a = 0.35 + 0.13 * t
			halos.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * hs), hp))
			halos.multimesh.set_instance_color(i, hc)
		else:
			halos.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), hp))
		var is_here := here != "" and a == here
		if is_here:
			_here_i = i
		if (mine.has(a) or is_here) and (shown or is_here):
			var rs := POINT_SIZE * (9.0 if not is_here else 15.0) * (1.0 + 0.15 * maxf(0.0, t))
			rings.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rs), hp))
			rings.multimesh.set_instance_color(i, Color(1, 1, 1, 0.95) if is_here else MINE)
		else:
			rings.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), hp))
	here_label.visible = _here_i >= 0
	if _here_i >= 0:
		here_label.position = pos(_here_i, 1.0) * 1.0 + pos(_here_i).normalized() * 0.06


func _process(delta: float) -> void:
	if _here_i < 0:
		return
	_t += delta
	# The "you are here" ring breathes (display only; its place and size are the chain's).
	var t := int(rows[_here_i]["tier"]) if _here_i < rows.size() else 0
	var rs := POINT_SIZE * 15.0 * (1.0 + 0.15 * maxf(0.0, t)) * (1.0 + 0.18 * sin(_t * 3.0))
	rings.multimesh.set_instance_transform(_here_i, Transform3D(Basis().scaled(Vector3.ONE * rs), pos(_here_i, 3.0)))
