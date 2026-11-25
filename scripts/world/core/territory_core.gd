class_name TerritoryCore
extends Node3D
## The Core at a territory's centre (WP 2.4), built from its numbers:
## - Rod & Cone: twin pylons; each carries a plate drawing the territory's
##   Julia set, the Rod for c and the Cone for its mirror c̄ (the Rod/Cone
##   pairing that must mirror or a reaction reverts). Inscribed with the values.
## - The Room: a ring wall between them with a door (the QING's chat room;
##   admission rules bind to the door in WP 5.3).
## - The Heart: floating above, where Beat happens.
## - Three wells: what the territory itself holds of Fornax (Hypobar per Su),
##   Eris (Charge base) and Tethys (VITUS per future Code). Levels are Facts.

const DOOR_SHADER := preload("res://assets/shaders/door_field.gdshader")
const PYLON_GAP := 9.0
const ROOM_RADIUS := 6.0
const WELL_RADIUS := 17.0
const WELLS := [
	{"key": "fornax", "label": "FORNAX", "what": "Hypobar per Su (Ω)", "color": Color("#ffb070"), "angle": 210.0},
	{"key": "eris", "label": "ERIS", "what": "Charge base (QI)", "color": Color("#e9edf4"), "angle": 270.0},
	{"key": "tethys", "label": "TETHYS", "what": "VITUS per Code (Dione)", "color": Color("#64e3a8"), "angle": 330.0},
]

var params: Dictionary = {}
var territory: Dictionary = {}
var base_y := 0.0
var heart: HeartOrrery
var door_material: ShaderMaterial
var _wells := {}  # key → {column: MeshInstance3D, label: Label3D, mat: StandardMaterial3D}
var _t := 0.0
var _pulse := 0.0
var _sparks: Array = []  # [{node, t, from, to}] cascade sparks in flight
var _wall_lines: Array = []  # Label3D etched on the Room's back wall, newest first
const WALL_LINES := 6


func build(p: Dictionary, q: Dictionary, ground_y: float) -> void:
	params = p
	territory = q
	base_y = ground_y
	position = Vector3(0.0, ground_y, 0.0)
	var col := DeepField.to_color(p["color"])
	var col2 := DeepField.to_color(p["color2"])
	_build_pylon("Rod", Vector3(-PYLON_GAP, 0, 0), false, col)
	_build_pylon("Cone", Vector3(PYLON_GAP, 0, 0), true, col2)
	_build_room(col)
	var dressing := CoreDressing.new()
	dressing.name = "Dressing"
	add_child(dressing)
	dressing.build(col, ROOM_RADIUS)
	_build_heart(col)
	for w in WELLS:
		_build_well(w)
	var c: Array = p["c"]
	Inspector.register(self, "The Core",
		"Rod plate: Julia set at c = %.6f %+.6fi; Cone plate: its mirror c̄ = %.6f %+.6fi (Rod and Cone must mirror).\nPylon height from log10(Entropy) = %.2f; %d-sided from the set's %d arms.\nWells: Fornax, Eris and Tethys held by this QING (balanceOf(QING)); '—' until read." % [
			c[0], c[1], c[0], -c[1], _log_entropy(), _sides(), int(p["arms"])])


func _log_entropy() -> float:
	return BigInt.log10(BigInt.from_decimal(String(territory.get("entropy", "1"))))


func _sides() -> int:
	return clampi(int(params.get("arms", 0)), 3, 9) if int(params.get("arms", 0)) > 0 else 6


static func _glass(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.025, 0.04)
	m.metallic = 0.6
	m.roughness = 0.18
	m.rim_enabled = true
	m.rim = 0.35
	m.emission_enabled = true
	m.emission = tint * 0.08
	return m


static func _glow(tint: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = tint
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	return m


func _label(text: String, size: int = 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = DeepFieldTheme.mono_font()
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = DeepFieldTheme.INK
	l.outline_size = maxi(6, size / 6)  # readable over bright towers and the sky
	l.outline_modulate = Color(0.01, 0.015, 0.03, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	return l


func _build_pylon(pname: String, at: Vector3, mirror: bool, tint: Color) -> void:
	var height := clampf(10.0 + (_log_entropy() - 11.0) * 2.5, 10.0, 22.0)
	var root := Node3D.new()
	root.name = pname
	root.position = at
	add_child(root)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.radial_segments = _sides()
	cyl.rings = 1
	cyl.top_radius = 0.55
	cyl.bottom_radius = 1.1
	cyl.height = height
	body.mesh = cyl
	body.material_override = _glass(tint)
	body.position.y = height * 0.5
	root.add_child(body)
	Solid.cylinder(root, 0.95, height, Vector3.ZERO)
	# Edge light running up the pylon.
	var seam := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.06, height, 0.06)
	seam.mesh = bx
	seam.material_override = _glow(tint, 3.0)
	seam.position = Vector3(0.0, height * 0.5, 0.95 if not mirror else -0.95)
	root.add_child(seam)
	# The monument's base: two stepped plinths of the same polygon, a lit trim
	# between them, and two collars up the shaft (detail only; the numbers are
	# the height, the sides and the plate).
	var metal := CoreDressing.dark_metal()
	var step1 := MeshInstance3D.new()
	step1.mesh = CoreDressing._cyl(1.95, 2.1, 0.32, _sides())
	step1.material_override = metal
	step1.position.y = 0.16
	root.add_child(step1)
	var step2 := MeshInstance3D.new()
	step2.mesh = CoreDressing._cyl(1.45, 1.6, 0.36, _sides())
	step2.material_override = metal
	step2.position.y = 0.5
	root.add_child(step2)
	var trim := MeshInstance3D.new()
	trim.mesh = CoreDressing._cyl(1.62, 1.62, 0.05, _sides())
	trim.material_override = _glow(tint, 1.8)
	trim.position.y = 0.345
	root.add_child(trim)
	for f in [0.38, 0.72]:
		var r := lerpf(1.1, 0.55, f) + 0.06
		var collar := MeshInstance3D.new()
		collar.mesh = CoreDressing._cyl(r, r + 0.05, 0.22, _sides())
		collar.material_override = metal
		collar.position.y = height * f
		root.add_child(collar)
	# The plate: the territory's Julia set (c on the Rod, c̄ on the Cone).
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = false
	var view := DeepFieldView.new()
	view.size = Vector2(256, 256)
	view.max_iter = 120
	vp.add_child(view)
	root.add_child(vp)
	view.apply_params(params)
	view.set_mirror(mirror)
	DeepFieldView.throttle(vp, 6.0)
	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(5.0, 5.0)
	plate.mesh = quad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_texture = vp.get_texture()
	pm.emission_enabled = true
	pm.emission_texture = vp.get_texture()
	pm.emission_energy_multiplier = 1.6
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	plate.material_override = pm
	plate.position = Vector3(0.0, height + 3.4, 0.0)
	plate.rotation_degrees.y = 18.0 if not mirror else -18.0  # face the approach (+Z), turned slightly inward
	root.add_child(plate)
	var c: Array = params["c"]
	var tag := "ROD · c\n%.5f %+.5fi" % [c[0], c[1]] if not mirror else "CONE · c̄\n%.5f %+.5fi" % [c[0], -c[1]]
	var lab := _label(tag, 72)
	lab.position = Vector3(0.0, height + 6.4, 0.0)
	root.add_child(lab)


func _build_room(tint: Color) -> void:
	var room := Node3D.new()
	room.name = "Room"
	add_child(room)
	# The building: a ring of sci-fi wall panels with top sections (Modular
	# Sci-Fi MegaKit, Quaternius, CC0), 10 around, the one facing +Z left open
	# for the door frame. A panel's decorated face looks along local +X and sits
	# ~2.17 m from its origin along -X; facing outward: yaw = −angle and
	# origin = (R + 2.17)·dir.
	var door_half := deg_to_rad(16.0)
	for i in 10:
		var a_deg := 90.0 + 36.0 * i
		if i == 0:
			continue
		var a := deg_to_rad(a_deg)
		var dir := Vector3(cos(a), 0.0, sin(a))
		for piece in ["WallAstra_Straight", "TopAstra_Straight"]:
			var n := PlaceBase.load_piece(piece)
			n.position = dir * (ROOM_RADIUS + 2.17)
			n.rotation_degrees.y = -a_deg
			n.scale = Vector3(1.0, 0.9, 1.0)
			room.add_child(n)
			if piece == "WallAstra_Straight":
				Solid.wrap(n, 1.0)  # the walls are solid; the doorway (+Z) stays open
	var frame := PlaceBase.load_piece("Door_Frame_Square")
	frame.position = Vector3(0.0, 0.0, ROOM_RADIUS + 0.1)
	frame.scale = Vector3(0.8, 0.8, 0.8)
	room.add_child(frame)
	# Crown light ring above the panels.
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = ROOM_RADIUS + 0.5
	tor.outer_radius = ROOM_RADIUS + 0.62
	tor.rings = 64
	ring.mesh = tor
	ring.material_override = _glow(tint, 1.5)
	ring.position.y = 4.6
	room.add_child(ring)
	# The door field.
	var door := MeshInstance3D.new()
	door.name = "Door"
	var q := QuadMesh.new()
	q.size = Vector2(2.0 * ROOM_RADIUS * sin(door_half), 2.8)
	door.mesh = q
	door_material = ShaderMaterial.new()
	door_material.shader = DOOR_SHADER
	door_material.set_shader_parameter("color", Vector3(tint.r, tint.g, tint.b))
	door.material_override = door_material
	door.position = Vector3(0.0, 1.4, ROOM_RADIUS * cos(door_half))
	room.add_child(door)
	var sign := _label(String(territory.get("name", "")).to_upper(), 56)
	sign.name = "RoomSign"
	sign.position = Vector3(0.0, 5.3, ROOM_RADIUS + 0.4)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	room.add_child(sign)
	# Under the name: what the building is, and how it is talking (ChatLife keeps it).
	var tag := _label("THE ROOM", 30)
	tag.name = "RoomTag"
	tag.modulate = tint.lerp(DeepFieldTheme.ICE, 0.5)
	tag.position = Vector3(0.0, 4.86, ROOM_RADIUS + 0.42)  # under the name: above it, the beacons speak
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	room.add_child(tag)


## Door state from the room's admission rules (WP 5.3): closed when a cover applies.
func set_door_closed(closed: bool) -> void:
	if door_material:
		door_material.set_shader_parameter("closed", 1.0 if closed else 0.0)


func _build_heart(tint: Color) -> void:
	heart = HeartOrrery.new()
	heart.name = "Heart"
	heart.position = Vector3(0.0, 11.0, 0.0)
	add_child(heart)
	heart.build(params, tint, DeepField.to_color(params.get("color2", "#ffb070")))


## Development (tier from the Hypobar total, energy from the Epibar total):
## the Heart's rings and their speed. Same for every viewer.
func set_development(tier: int, energy: float) -> void:
	if heart:
		heart.set_development(tier, energy)


## A new block was read here: the Heart ticks with the chain's clock.
func block_tick() -> void:
	if heart:
		heart.tick()


## A heartbeat (Beat confirmed): the Heart swells and fades.
func pulse() -> void:
	_pulse = 1.0
	if heart:
		heart.beat(1.0)


## Bars moved here (a Su or a CHOA.Chat landed): sparks run up both pylons
## and into the Heart, which swells a little. `strength` 0..1 from the size.
func cascade(strength: float = 0.5) -> void:
	var tint := DeepField.to_color(params.get("color", "#7fd3ff")) if not params.is_empty() else DeepFieldTheme.ICE
	for x in [-PYLON_GAP, PYLON_GAP]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.7
		s.mesh = sm
		s.material_override = _glow(tint.lerp(Color.WHITE, 0.5), 4.0)
		add_child(s)
		_sparks.append({"node": s, "t": 0.0, "from": Vector3(x, 0.3, 0.0), "mid": Vector3(x, 14.0, 0.0), "to": Vector3(0.0, 11.0, 0.0)})
	_pulse = maxf(_pulse, 0.25 + 0.35 * clampf(strength, 0.0, 1.0))
	if heart:
		heart.beat(0.35 + 0.35 * clampf(strength, 0.0, 1.0))


## A room line (LogEvent from this QING) etched on the Room's back wall.
func etch_line(text: String, block: int) -> void:
	var l := _label("%s  · %d" % [text.left(64), block], 28)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.modulate = Color(DeepFieldTheme.ICE, 0.0)
	l.position = Vector3(0.0, 2.45, -ROOM_RADIUS + 0.45)
	add_child(l)
	_wall_lines.push_front(l)
	while _wall_lines.size() > WALL_LINES:
		(_wall_lines.pop_back() as Node).queue_free()
	for i in _wall_lines.size():
		var w: Label3D = _wall_lines[i]
		w.position.y = 2.45 - i * 0.32
		var a := 1.0 - i * 0.13
		var tw := create_tween()
		tw.tween_property(w, "modulate:a", a, 0.8 if i == 0 else 0.3)


func _build_well(w: Dictionary) -> void:
	var a := deg_to_rad(float(w["angle"]))
	var at := Vector3(cos(a) * WELL_RADIUS, 0.0, sin(a) * WELL_RADIUS)  # 270° = behind the Room (-Z)
	var root := Node3D.new()
	root.name = "Well_" + w["key"]
	root.position = at
	add_child(root)
	# A metal rim with a lit lip; the column inside is the well's level.
	var rim := MeshInstance3D.new()
	rim.mesh = CoreDressing._cyl(1.35, 1.5, 0.5, 24)
	rim.material_override = CoreDressing.dark_metal()
	rim.position.y = 0.25
	root.add_child(rim)
	var basin := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.05
	t.outer_radius = 1.3
	t.rings = 48
	basin.mesh = t
	basin.material_override = _glow(w["color"], 1.0)
	basin.position.y = 0.5
	basin.scale = Vector3(1.0, 0.4, 1.0)
	root.add_child(basin)
	var pool := MeshInstance3D.new()
	pool.mesh = CoreDressing._cyl(1.05, 1.05, 0.02, 24)
	pool.material_override = _glow(Color(w["color"]).darkened(0.7), 0.6)
	pool.position.y = 0.49
	root.add_child(pool)
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 1.0
	column.mesh = cyl
	var mat := _glow(w["color"], 2.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.75
	column.material_override = mat
	column.scale = Vector3(1, 0.05, 1)
	column.position.y = 0.025
	root.add_child(column)
	var lab := _label("%s\n—" % w["label"], 48)
	lab.position = Vector3(0.0, 2.2, 0.0)
	root.add_child(lab)
	_wells[w["key"]] = {"column": column, "label": lab, "def": w}


## Sets a well from a Fact holding a balance (wei, as a BigInt hex string or
## PackedInt64Array). Height is log-scaled; the label shows the token amount.
func set_well(key: String, f: Fact) -> void:
	if not _wells.has(key):
		return
	var w: Dictionary = _wells[key]
	var lab: Label3D = w["label"]
	var name: String = w["def"]["label"]
	if not f.has_value():
		lab.text = "%s\n%s" % [name, f.display()]
		_set_column(w["column"], 0.05)
		return
	var wei := BigInt.coerce(f.value)
	var tokens := TokenFormat.wei_to_tokens(wei)
	lab.text = "%s\n%s" % [name, tokens]
	var lg := BigInt.log10(wei) - 18.0  # log10(tokens)
	var h := 0.05 if is_inf(lg) else clampf(1.0 + (lg + 3.0) * 1.2, 0.2, 9.0)
	_set_column(w["column"], h)


func _set_column(col: MeshInstance3D, h: float) -> void:
	col.scale = Vector3(1.0, h, 1.0)
	col.position.y = h * 0.5


func _process(delta: float) -> void:
	_t += delta
	if heart:
		_pulse = maxf(0.0, _pulse - delta * 0.8)
		heart.position.y = 11.0 + 0.2 * sin(_t * 0.7)
	for i in range(_sparks.size() - 1, -1, -1):  # backwards: removal without a copy
		var sp: Dictionary = _sparks[i]
		sp["t"] += delta * 0.9
		var u: float = sp["t"]
		var n: MeshInstance3D = sp["node"]
		if u >= 1.0:
			n.queue_free()
			_sparks.remove_at(i)
			continue
		var a: Vector3 = sp["from"].lerp(sp["mid"], u)
		var b: Vector3 = sp["mid"].lerp(sp["to"], u)
		n.position = a.lerp(b, u)  # quadratic Bézier: up the pylon, then into the Heart
