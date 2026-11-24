class_name WorldLattice
extends Node3D
## WORLD around a territory (WP 6.2). Map adjacency means nothing on-chain and
## a range of ±Yeo raw units is microscopic at degree scale, so WORLD is drawn
## as a local lattice around the territory's own centre cell (its Compliment
## words), log-scaled, as the site's world.html does.
##
## - The lattice and the centre cell are territory state: faint while WORLD is
##   latent, lit when World watch verifies a wired WORLD on-chain.
## - The plinth behind the Room opens the range preview.
## - The range square is the viewer's own (±Yeo from their Beat here), so it
##   is an overlay shown only when they ask for it, like the HUD.

const CELL := 3.0
const EXTENT := 21.0
const PLINTH_AT := Vector3(0.0, 0.0, -11.5)

var lattice_mat: StandardMaterial3D
var centre_mat: StandardMaterial3D
var plinth_label: Label3D
var _range: MeshInstance3D
var _range_label: Label3D


func build(tint: Color) -> void:
	lattice_mat = _line_mat(tint, 0.10)
	centre_mat = _line_mat(Color("#ffd27a"), 0.55)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, lattice_mat)
	var n := int(EXTENT / CELL)
	for i in range(-n, n + 1):
		var v := i * CELL + CELL * 0.5
		if absf(v) > EXTENT:
			continue
		for e in [[Vector3(v, 0.04, -EXTENT), Vector3(v, 0.04, EXTENT)], [Vector3(-EXTENT, 0.04, v), Vector3(EXTENT, 0.04, v)]]:
			im.surface_add_vertex(e[0])
			im.surface_add_vertex(e[1])
	im.surface_end()
	var grid := MeshInstance3D.new()
	grid.name = "Lattice"
	grid.mesh = im
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid)
	add_child(_square("CentreCell", CELL * 0.5, centre_mat, 0.06))
	# The plinth.
	var root := Node3D.new()
	root.name = "Plinth"
	root.position = PLINTH_AT
	add_child(root)
	var body := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(1.2, 2.4, 1.2)
	body.mesh = pm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.02, 0.022, 0.03)
	bm.metallic = 0.7
	bm.roughness = 0.2
	bm.emission_enabled = true
	bm.emission = Color("#ffd27a") * 0.15
	body.material_override = bm
	body.position.y = 1.2
	root.add_child(body)
	Solid.box(root, Vector3(1.0, 2.4, 1.0), Vector3(0.0, 1.2, 0.0))
	CoreDressing.base_under(root, 1.2, 1.2, Color("#ffd27a"))
	plinth_label = Label3D.new()
	plinth_label.font = DeepFieldTheme.mono_font()
	plinth_label.font_size = 40
	plinth_label.pixel_size = 0.01
	plinth_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	plinth_label.modulate = Color("#ffd27a")
	plinth_label.position.y = 3.2
	plinth_label.text = "WORLD\nchecking…"
	root.add_child(plinth_label)
	_range = _square("MyRange", 4.0, _line_mat(DeepFieldTheme.ICE, 0.9), 0.1)
	_range.visible = false
	add_child(_range)
	_range_label = Label3D.new()
	_range_label.font = DeepFieldTheme.mono_font()
	_range_label.font_size = 32
	_range_label.pixel_size = 0.01
	_range_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_range_label.modulate = DeepFieldTheme.ICE
	_range_label.visible = false
	add_child(_range_label)
	set_status(World.status, World.headline())
	World.changed.connect(func(): set_status(World.status, World.headline()))


static func _line_mat(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.6
	return m


static func _square(nm: String, half: float, mat: Material, y: float) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p in [Vector3(-half, y, -half), Vector3(half, y, -half), Vector3(half, y, half), Vector3(-half, y, half), Vector3(-half, y, -half)]:
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Lit only when WORLD is verified live; otherwise faint.
func set_status(status: String, headline: String) -> void:
	var live := status == "live"
	lattice_mat.albedo_color.a = 0.35 if live else 0.10
	lattice_mat.emission_energy_multiplier = 2.0 if live else 0.6
	plinth_label.text = "WORLD\n%s" % ({"latent": "not deployed", "stirring": "deployer moved", "unverified": "unverified code",
		"live": "LIVE", "unknown": "—"}.get(status, status))


## Pure: the half-size of the range square for a Yeo (raw units), log-scaled
## onto the lattice: Yeo 0 = the centre cell only.
static func range_half(yeo: PackedInt64Array) -> float:
	if BigInt.is_zero(yeo):
		return CELL * 0.5
	return clampf(CELL * 0.5 + 0.8 * BigInt.log10(yeo), CELL * 0.5, EXTENT)


func show_range(yeo: PackedInt64Array, on: bool) -> void:
	_range.visible = on
	_range_label.visible = on
	if not on:
		return
	var h := range_half(yeo)
	_range.scale = Vector3(h / 4.0, 1.0, h / 4.0)
	_range_label.position = Vector3(h, 1.2, h)
	_range_label.text = "your range here: ±%s raw units\n(log scale; 0 = centre cell only)" % TokenFormat.group(BigInt.to_decimal(yeo))


func range_visible() -> bool:
	return _range.visible
