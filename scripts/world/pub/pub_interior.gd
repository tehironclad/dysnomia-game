class_name PubInterior
extends RefCounted
## Furnishes the cantina: bar counter with taps and a stocked, backlit back bar,
## the drinks lightbox (AttractionCatalog.DRINKS), stools, the four game tables,
## high-tops, a lounge, darts, jukebox, holo-arcade, art, plants, rugs and the
## interior lighting rig. Everything placement-wise comes from PubLayout.

const FELT_COLORS := [
	Color(0.10, 0.42, 0.16),  # Green felt — Entropy Dice
	Color(0.48, 0.08, 0.09),  # Red felt — WAAT Slots
	Color(0.09, 0.17, 0.48),  # Blue felt — Territory Trivia
	Color(0.45, 0.32, 0.10),  # Gold felt — Card Match
]
const GAME_NAMES := ["ENTROPY DICE", "WAAT SLOTS", "TERRITORY TRIVIA", "CARD MATCH"]

var lights: Array[OmniLight3D] = []          # Interior rig (scaled by territory power, flared on cheer)
var light_base: Array[float] = []
var neon_nodes: Array[MeshInstance3D] = []
var tap_handles: Array[MeshInstance3D] = []
var qing_screen: PubQingScreen
var back_glow_mat: StandardMaterial3D
var bar_flash: OmniLight3D                   # Bar light pulsed when a drink is poured
var game_table_nodes: Array[Node3D] = []

var _root: Node3D
var _L: PubLayout
var _body: StaticBody3D
var _b: PubKit.Batch
var _rng := RandomNumberGenerator.new()
var _wood: BaseMaterial3D
var _top: BaseMaterial3D
var _steel: StandardMaterial3D
var _chrome: StandardMaterial3D
var _dark: StandardMaterial3D
var _brass: StandardMaterial3D


func build(root: Node3D, layout: PubLayout, body: StaticBody3D) -> void:
	_root = root
	_L = layout
	_body = body
	_rng.seed = int(layout.p["detail_seed"]) + 77
	_b = PubKit.Batch.new()
	_wood = PubKit.pbr("dark_planks", 1.2, Color(0.75, 0.6, 0.5))
	_top = PubKit.pbr("wood_table_001", 1.2, Color(0.9, 0.75, 0.62), true, 0.55)
	_steel = PubKit.flat(Color(0.13, 0.13, 0.14), 0.42, 0.85)
	_chrome = PubKit.flat(Color(0.8, 0.8, 0.82), 0.12, 1.0)
	_dark = PubKit.flat(Color(0.04, 0.04, 0.045), 0.55, 0.4)
	_brass = PubKit.flat(Color(0.78, 0.58, 0.3), 0.25, 1.0)

	_build_bar()
	_build_back_bar()
	_build_menu()
	_build_stools()
	_build_game_tables()
	_build_hightops()
	_build_lounge()
	_build_booths()
	_build_darts()
	_build_jukebox()
	_build_arcade()
	_build_display()
	_build_wall_art()
	_build_plants()
	_build_lights()
	_b.commit(_root, false, "Interior")


# ─── Bar ───────────────────────────────────────────────────────────────────

func _build_bar() -> void:
	var fy := PubLayout.FY
	var x0 := _L.bar_x0
	var x1 := _L.bar_x1
	var len := x1 - x0
	var cz := _L.counter_z
	var ch := PubLayout.COUNTER_H
	# Body: plank front, steel kick plate, lit underside of the top lip
	_b.box_at(Vector3(len, ch - 0.07, 0.6), Vector3(_L.bar_cx, fy + (ch - 0.07) * 0.5, cz), _wood)
	_b.box_at(Vector3(len, 0.16, 0.03), Vector3(_L.bar_cx, fy + 0.08, cz + 0.31), _steel)
	# Vertical battens for relief on the customer side
	var n := int(len / 0.6)
	for i in n + 1:
		_b.box_at(Vector3(0.05, ch - 0.25, 0.04), Vector3(x0 + 0.05 + float(i) * (len - 0.1) / float(n), fy + 0.16 + (ch - 0.25) * 0.5, cz + 0.315), _top)
	# Dysnomia cyan under the bar lip, and a violet kick strip at the floor
	_b.box_at(Vector3(len - 0.05, 0.025, 0.03), Vector3(_L.bar_cx, fy + ch - 0.1, cz + 0.36), PubKit.neon(Color(0.2, 0.9, 1.0), 4.0))
	_b.box_at(Vector3(len - 0.05, 0.02, 0.02), Vector3(_L.bar_cx, fy + 0.17, cz + 0.33), PubKit.neon(Color(0.6, 0.3, 1.0), 2.5))
	# Thick polished top
	_b.box_at(Vector3(len + 0.08, 0.07, 0.82), Vector3(_L.bar_cx, fy + ch - 0.035, cz + 0.06), _top)
	# Brass foot rail on brackets
	var rail_z := cz + 0.5
	_b.add_mesh(PubKit.cyl(0.03, 0.03, len - 0.2, 12), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(_L.bar_cx, fy + 0.22, rail_z)), _brass)
	for i in int(len / 1.4) + 1:
		var bx := x0 + 0.2 + float(i) * (len - 0.4) / float(int(len / 1.4))
		_b.box_at(Vector3(0.03, 0.03, 0.2), Vector3(bx, fy + 0.22, rail_z - 0.1), _brass)
	_coll(Vector3(len, ch, 0.85), Vector3(_L.bar_cx, fy + ch * 0.5, cz + 0.05))

	# Back counter with fridges, against the back wall
	var bz := _L.back_counter_z
	var bl := len - 0.6
	var bcx := x0 + bl * 0.5
	_b.box_at(Vector3(bl, 0.92, 0.58), Vector3(bcx, fy + 0.46, bz), _wood)
	_b.box_at(Vector3(bl + 0.04, 0.04, 0.62), Vector3(bcx, fy + 0.94, bz + 0.01), _chrome)
	var fridge_glass := PubKit.glass(Color(0.55, 0.75, 0.9, 0.5), Color(0.55, 0.8, 1.0), 0.9)
	for i in 3:
		var fx := x0 + 0.9 + float(i) * 0.75
		_b.box_at(Vector3(0.7, 0.72, 0.03), Vector3(fx, fy + 0.45, bz + 0.29), _steel)
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.6)
		PubKit.mesh_instance(q, Vector3(fx, fy + 0.45, bz + 0.31), fridge_glass, _root)
		# Cans/bottles silhouettes inside
		for k in 5:
			_b.add_mesh(PubKit.cyl(0.032, 0.032, 0.2, 8), Transform3D(Basis(), Vector3(fx - 0.22 + float(k) * 0.11, fy + 0.3, bz + 0.2)),
				PubKit.flat(Color.from_hsv(_rng.randf(), 0.6, 0.7), 0.3, 0.6))
	_coll(Vector3(bl, 0.95, 0.6), Vector3(bcx, fy + 0.47, bz))
	# Duckboard platform behind the counter (so the bartender stands tall over it)
	var ph := PubLayout.PLATFORM_H
	var pz0 := bz + 0.3
	var pz1 := cz - 0.3
	_b.box_at(Vector3(len - 0.05, ph, pz1 - pz0), Vector3(_L.bar_cx - 0.02, fy + ph * 0.5, (pz0 + pz1) * 0.5), _wood)
	for i in int((pz1 - pz0) / 0.16):
		_b.box_at(Vector3(len - 0.05, 0.01, 0.04), Vector3(_L.bar_cx - 0.02, fy + ph + 0.004, pz0 + 0.1 + float(i) * 0.16), _dark)
	_coll(Vector3(len - 0.05, ph, pz1 - pz0), Vector3(_L.bar_cx - 0.02, fy + ph * 0.5, (pz0 + pz1) * 0.5))

	# Beer taps: chrome tower with handles in the neon palette
	var tx := _L.tap_x
	var top_y := fy + ch
	var tz := cz - 0.12
	_b.box_at(Vector3(0.9, 0.03, 0.18), Vector3(tx, top_y + 0.015, tz + 0.16), _chrome)   # Drip tray
	for sx in [-0.4, 0.4]:
		_b.add_mesh(PubKit.cyl(0.035, 0.045, 0.42, 12), Transform3D(Basis(), Vector3(tx + sx, top_y + 0.21, tz)), _chrome)
	_b.add_mesh(PubKit.cyl(0.04, 0.04, 0.9, 14), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(tx, top_y + 0.42, tz)), _chrome)
	var handle_cols := [_L.p["neon_a"], Color(1.0, 0.75, 0.2), _L.p["neon_b"], Color(0.4, 1.0, 0.5)]
	for i in 4:
		var hx := tx - 0.3 + float(i) * 0.2
		_b.add_mesh(PubKit.cyl(0.012, 0.016, 0.12, 8), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(hx, top_y + 0.4, tz + 0.08)), _chrome)
		var hm := PubKit.mesh_instance(PubKit.cyl(0.018, 0.026, 0.2, 10), Vector3(hx, top_y + 0.56, tz), PubKit.neon(handle_cols[i], 1.6), _root)
		tap_handles.append(hm)
	# Upside-down glasses drying on a mat
	var gmat := PubKit.drinkware()
	for i in 10:
		var gx := tx + 0.65 + float(i % 5) * 0.1
		var gz := tz + float(i / 5) * 0.1
		_b.add_mesh(PubKit.cyl(0.035, 0.03, 0.14, 10), Transform3D(Basis(), Vector3(gx, top_y + 0.07, gz)), gmat)
	_b.box_at(Vector3(0.55, 0.01, 0.25), Vector3(tx + 0.85, top_y + 0.005, tz + 0.05), _dark)

	# Register at the far end, facing the bartender; a little succulent beside it
	PubKit.place(_root, "CashRegister_01", Vector3(x1 - 0.55, top_y, cz - 0.05), 180.0, 0.85)
	PubKit.place(_root, "potted_plant_04", Vector3(x0 + 0.45, top_y, cz + 0.1), _rng.randf_range(0, 360), 1.2)
	PubKit.place(_root, "potted_plant_04", Vector3(x1 - 1.2, top_y, cz + 0.2), _rng.randf_range(0, 360), 0.9)
	# Old CRT on the back counter showing static glow
	var tv := PubKit.place(_root, "Television_01", Vector3(x0 + 0.55, fy + 0.96, bz - 0.02), 0.0, 0.9)
	tv.name = "BackBarTV"


func _build_back_bar() -> void:
	var fy := PubLayout.FY
	var d := _L.d
	var cx := _L.bar_cx - 0.2
	var sw := minf(4.8, _L.bar_x1 - _L.bar_x0 - 2.2)
	var wall_z := -d + 0.03
	# Backlit amber panel behind the bottles
	var q := QuadMesh.new()
	q.size = Vector2(sw, 1.55)
	# Low-energy amber so the bottles silhouette against it instead of washing out
	back_glow_mat = PubKit.neon(Color(0.9, 0.42, 0.14), 0.32).duplicate()
	var glow := PubKit.mesh_instance(q, Vector3(cx, fy + 2.02, wall_z + 0.01), back_glow_mat, _root)
	glow.name = "BackBarGlow"
	# Uprights and three glass shelves
	for sx in [-0.5, 0.5]:
		_b.box_at(Vector3(0.08, 1.75, 0.3), Vector3(cx + sx * (sw + 0.08), fy + 2.02, wall_z + 0.15), _top)
	_b.box_at(Vector3(sw + 0.24, 0.1, 0.32), Vector3(cx, fy + 2.92, wall_z + 0.16), _top)
	var shelf_glass := PubKit.glass(Color(0.7, 0.85, 0.85, 0.35))
	var shelf_ys := [fy + 1.28, fy + 1.78, fy + 2.28]
	for y in shelf_ys:
		_b.box_at(Vector3(sw, 0.025, 0.28), Vector3(cx, y, wall_z + 0.15), shelf_glass)
		_b.box_at(Vector3(sw, 0.012, 0.012), Vector3(cx, y - 0.02, wall_z + 0.29), PubKit.neon(Color(1.0, 0.7, 0.4), 2.0))
	# Side cabinets: plank backs, two wooden shelves each, more stock
	var side_rows: Array = []
	var side_w := minf(1.7, (_L.bar_x1 - _L.bar_x0 - sw) * 0.5 - 0.35)
	for sx in [-1.0, 1.0]:
		var mx: float = cx + sx * (sw * 0.5 + 0.2 + side_w * 0.5)
		_b.box_at(Vector3(side_w, 1.55, 0.03), Vector3(mx, fy + 1.95, wall_z + 0.015), _wood)
		for k in 2:
			var y: float = fy + 1.45 + float(k) * 0.62
			_b.box_at(Vector3(side_w, 0.045, 0.3), Vector3(mx, y, wall_z + 0.15), _top)
			_b.box_at(Vector3(side_w - 0.1, 0.01, 0.01), Vector3(mx, y - 0.03, wall_z + 0.29), PubKit.neon(Color(1.0, 0.7, 0.4), 1.6))
			side_rows.append([y + 0.023, mx - side_w * 0.5 + 0.08, mx + side_w * 0.5 - 0.08, wall_z + 0.14])
		for ex in [-0.5, 0.5]:
			_b.box_at(Vector3(0.05, 1.6, 0.32), Vector3(mx + ex * side_w, fy + 1.95, wall_z + 0.16), _top)

	# Bottles: four real wine bottle meshes + tinted spirit variants, as MultiMeshes
	var src := PubKit.model("wine_bottles_01")
	var meshes: Array[Mesh] = []
	for m in src.find_children("*", "MeshInstance3D", true, false):
		meshes.append((m as MeshInstance3D).mesh)
	src.free()
	if meshes.is_empty():
		return
	# Spirits: tinted glass (no emission) in a spread of colours — amber whisky, green gin,
	# blue curacao, clear vodka, ruby liqueur, smoky rum, violet, citrus
	var spirit_cols := [Color(0.62, 0.3, 0.06, 0.8), Color(0.15, 0.42, 0.18, 0.75), Color(0.16, 0.3, 0.75, 0.7),
		Color(0.85, 0.88, 0.9, 0.35), Color(0.5, 0.06, 0.12, 0.82), Color(0.3, 0.16, 0.06, 0.88),
		Color(0.4, 0.18, 0.6, 0.75), Color(0.85, 0.7, 0.15, 0.7)]
	var kinds := meshes.size() + spirit_cols.size()
	var xfs: Array = []
	for k in kinds:
		xfs.append([])
	var rows: Array = []
	for y in shelf_ys:
		rows.append([y + 0.013, cx - sw * 0.5 + 0.08, cx + sw * 0.5 - 0.08, wall_z + 0.13])
	rows += side_rows
	rows.append([fy + 0.96, _L.bar_x0 + 1.3, _L.bar_x1 - 1.0, _L.back_counter_z - 0.12])  # Back counter
	for r in rows:
		var x: float = r[1]
		while x < r[2]:
			var k := _rng.randi() % kinds
			var s := _rng.randf_range(0.82, 1.12)
			var basis := Basis(Vector3.UP, _rng.randf_range(-0.6, 0.6)).scaled(Vector3(s, s * _rng.randf_range(0.78, 1.4), s))
			xfs[k].append(Transform3D(basis, Vector3(x, r[0], r[3] + _rng.randf_range(-0.04, 0.04))))
			x += _rng.randf_range(0.085, 0.13)
			if _rng.randf() < 0.06:
				x += 0.2   # Gaps where bottles are out being poured
	for k in kinds:
		if xfs[k].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k] if k < meshes.size() else meshes[k % meshes.size()]
		mm.instance_count = xfs[k].size()
		for i in xfs[k].size():
			mm.set_instance_transform(i, xfs[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Bottles%d" % k
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if k >= meshes.size():
			var c: Color = spirit_cols[k - meshes.size()]
			var gm := PubKit.glass(c).duplicate() as StandardMaterial3D
			gm.roughness = 0.08
			gm.metallic = 0.0
			gm.metallic_specular = 0.8
			mmi.material_override = gm
		_root.add_child(mmi)


func _build_menu() -> void:
	## Backlit drinks board above the back bar — names come straight from the catalog.
	var fy := PubLayout.FY
	var d := _L.d
	var cx := _L.bar_cx - 0.2
	var top := minf(_L.eave - 0.2, fy + 4.25)
	var hgt := clampf(top - (fy + 3.06), 0.95, 1.2)
	var cy := top - hgt * 0.5
	var mw := minf(4.6, _L.bar_x1 - _L.bar_x0 - 2.2)
	var z := -d + 0.06
	_b.box_at(Vector3(mw + 0.16, hgt + 0.16, 0.08), Vector3(cx, cy, z), _dark)
	var q := QuadMesh.new()
	q.size = Vector2(mw, hgt)
	PubKit.mesh_instance(q, Vector3(cx, cy, z + 0.045), PubKit.flat(Color(0.02, 0.025, 0.03), 0.8, 0.0, Color(0.1, 0.07, 0.16), 1.0), _root)
	var frame := PubKit.neon(_L.p["neon_b"], 3.0)
	for sy in [-0.5, 0.5]:
		_b.box_at(Vector3(mw + 0.1, 0.025, 0.03), Vector3(cx, cy + sy * (hgt + 0.08), z + 0.05), frame)
	_b.box_at(Vector3(0.015, hgt - 0.34, 0.01), Vector3(cx, cy - 0.12, z + 0.05), PubKit.flat(Color(0.3, 0.3, 0.35), 0.5))
	var title := PubKit.label("AFFECTION  ON  TAP", 56, Color(1.0, 0.78, 0.4), 0.0042)
	title.position = Vector3(cx, cy + hgt * 0.5 - 0.13, z + 0.06)
	_root.add_child(title)
	var drinks: Array = AttractionCatalog.DRINKS
	var per_col := int(ceil(float(drinks.size()) / 2.0))
	var line_h := (hgt - 0.34) / float(per_col)
	var col_w := mw * 0.5 - 0.22
	for i in drinks.size():
		var dr: Dictionary = drinks[i]
		var col := i / per_col
		var row := i % per_col
		var x0 := cx - mw * 0.5 + 0.14 + float(col) * (mw * 0.5 + 0.08)
		var ly := cy + hgt * 0.5 - 0.34 - float(row) * line_h
		var nm := String(dr.get("name", "?")).to_upper()
		var name_l := PubKit.label(nm, 30, Color(0.95, 0.95, 1.0), 0.0042)
		name_l.position = Vector3(x0 + _text_w(nm, 30, 0.0042) * 0.5, ly, z + 0.06)
		_root.add_child(name_l)
		var pr := AttractionCatalog.price_label(dr)
		var price := PubKit.label(pr, 22, (_L.p["neon_b"] as Color).lightened(0.35), 0.0042)
		price.position = Vector3(x0 + col_w - _text_w(pr, 22, 0.0042) * 0.5, ly - 0.005, z + 0.06)
		_root.add_child(price)


func _build_stools() -> void:
	for i in _L.stools.size():
		if i in _L.occupied_stools:
			continue   # A patron is standing here instead
		PubKit.place(_root, "metal_stool_01", _L.stools[i], _rng.randf_range(0, 360), 0.95)


# ─── Game tables ───────────────────────────────────────────────────────────

func _build_game_tables() -> void:
	var fy := PubLayout.FY
	var gs := PubLayout.GAME_TABLE_SIZE
	for i in _L.game_tables.size():
		var p: Vector3 = _L.game_tables[i]
		var g := Node3D.new()
		g.name = "GameTable%dVisual" % i
		g.position = p
		_root.add_child(g)
		game_table_nodes.append(g)
		var felt := PubKit.flat(FELT_COLORS[i], 0.95, 0.0)
		var gb := PubKit.Batch.new()
		# Solid wooden table: rail frame, felt bed, two end pedestals with a stretcher
		gb.box_at(Vector3(gs.x, 0.1, gs.z), Vector3(0, gs.y - 0.05, 0), _top)
		gb.box_at(Vector3(gs.x - 0.2, 0.025, gs.z - 0.2), Vector3(0, gs.y + 0.005, 0), felt)
		for sx in [-0.62, 0.62]:
			gb.box_at(Vector3(0.18, gs.y - 0.1, gs.z - 0.3), Vector3(sx, (gs.y - 0.1) * 0.5, 0), _wood)
			gb.box_at(Vector3(0.3, 0.05, gs.z - 0.1), Vector3(sx, 0.025, 0), _steel)
		gb.box_at(Vector3(1.1, 0.08, 0.08), Vector3(0, 0.25, 0), _steel)
		# Brass corner caps
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				gb.box_at(Vector3(0.08, 0.11, 0.08), Vector3(sx * (gs.x * 0.5 - 0.03), gs.y - 0.05, sz * (gs.z * 0.5 - 0.03)), _brass)
		gb.commit(g, false, "Table")
		_game_props(g, i, gs.y + 0.02)
		# Two chairs on the back side, the front left open for whoever walks up to play
		for k in 2:
			PubKit.place(g, "bar_chair_round_01", Vector3(-0.45 + float(k) * 0.9, 0, -0.95), _rng.randf_range(-15, 15), 1.0)
		# Tent card with the game's name, facing the room
		var card := PubKit.label(GAME_NAMES[i], 32, FELT_COLORS[i].lightened(0.65), 0.0032)
		card.position = Vector3(0, gs.y + 0.12, gs.z * 0.5 - 0.06)
		g.add_child(card)
		_b.box_at(Vector3(0.62, 0.12, 0.01), Vector3(p.x, fy + gs.y + 0.12, p.z + gs.z * 0.5 - 0.075), _dark)
		# Low pool-table lamp
		_pendant(Vector3(p.x, fy + 3.05, p.z), 0.9)
		_coll(Vector3(gs.x, gs.y + 0.05, gs.z), Vector3(p.x, fy + (gs.y + 0.05) * 0.5, p.z))


func _game_props(g: Node3D, idx: int, y: float) -> void:
	match idx:
		0:  # Dice + cup
			var dice := PubKit.flat(Color(0.95, 0.93, 0.88), 0.35)
			for k in 3:
				var m := PubKit.mesh_instance(_box(Vector3(0.06, 0.06, 0.06)), Vector3(-0.2 + float(k) * 0.13, y + 0.03, 0.05 * float(k % 2)), dice, g)
				m.rotation_degrees.y = _rng.randf_range(0, 90)
			PubKit.mesh_instance(PubKit.cyl(0.07, 0.06, 0.16, 16), Vector3(0.35, y + 0.08, -0.1), PubKit.flat(Color(0.25, 0.12, 0.06), 0.6), g)
		1:  # Tabletop slot machine with a glowing reel window
			_b.box_at(Vector3(0.4, 0.5, 0.3), g.position + Vector3(0, y + 0.25, -0.18), PubKit.flat(Color(0.55, 0.05, 0.08), 0.35, 0.6))
			var reel := QuadMesh.new()
			reel.size = Vector2(0.32, 0.14)
			PubKit.mesh_instance(reel, Vector3(0, y + 0.33, -0.029), PubKit.neon(Color(1.0, 0.85, 0.4), 2.2), g)
			var lever := PubKit.mesh_instance(PubKit.cyl(0.012, 0.012, 0.3, 6), Vector3(0.23, y + 0.38, -0.18), _chrome, g)
			lever.rotation_degrees.z = -12.0
			PubKit.mesh_instance(_sphere(0.035), Vector3(0.26, y + 0.53, -0.18), PubKit.neon(Color(1.0, 0.2, 0.2), 2.0), g)
		2:  # Trivia buzzers + a floating holo question mark
			for k in 4:
				var bx := -0.6 + float(k) * 0.4
				PubKit.mesh_instance(PubKit.cyl(0.07, 0.08, 0.05, 14), Vector3(bx, y + 0.025, 0.25), _dark, g)
				PubKit.mesh_instance(PubKit.cyl(0.05, 0.05, 0.03, 14), Vector3(bx, y + 0.06, 0.25),
					PubKit.neon(Color.from_hsv(float(k) / 4.0, 0.8, 1.0), 2.0), g)
			var qm := MeshInstance3D.new()
			qm.mesh = PubKit.text_mesh("?", 0.012, 0.03)
			qm.material_override = PubKit.neon(Color(0.4, 0.75, 1.0), 4.0)
			qm.position = Vector3(0, y + 0.45, -0.05)
			g.add_child(qm)
			neon_nodes.append(qm)
		3:  # Card match: a grid of face-down cards, two flipped
			var back := PubKit.flat(Color(0.5, 0.08, 0.1), 0.6)
			var face := PubKit.flat(Color(0.95, 0.95, 0.9), 0.5)
			for r in 3:
				for c in 5:
					var flipped := (r == 1 and (c == 1 or c == 3))
					PubKit.mesh_instance(_box(Vector3(0.11, 0.004, 0.16)), Vector3(-0.32 + float(c) * 0.16, y + 0.003, -0.2 + float(r) * 0.2),
						face if flipped else back, g)


# ─── High-tops, lounge, darts ──────────────────────────────────────────────

func _build_hightops() -> void:
	var fy := PubLayout.FY
	for p in _L.hightops:
		PubKit.place(_root, "round_wooden_table_01", p, _rng.randf_range(0, 360), Vector3(0.7, 1.0, 0.7))
		var ty := fy + 1.0
		for k in _rng.randi_range(1, 3):
			var ang := _rng.randf_range(0, TAU)
			_drink_prop(Vector3(p.x + cos(ang) * 0.25, ty, p.z + sin(ang) * 0.25))
		# Candle lantern
		PubKit.mesh_instance(PubKit.cyl(0.04, 0.045, 0.1, 10), Vector3(p.x, ty + 0.05, p.z), PubKit.glass(Color(1.0, 0.6, 0.3, 0.6), Color(1.0, 0.55, 0.2), 3.0), _root)
		var c := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 0.45
		cs.height = 1.0
		c.shape = cs
		c.position = Vector3(p.x, fy + 0.5, p.z)
		_body.add_child(c)


	for p in _L.barrel_tables:
		PubKit.place(_root, "wine_barrel_01", p, _rng.randf_range(0, 360), Vector3(0.95, 1.18, 0.95))
		var ty := fy + 0.871 * 1.18
		for k in _rng.randi_range(1, 2):
			var ang := _rng.randf_range(0, TAU)
			_drink_prop(Vector3(p.x + cos(ang) * 0.18, ty, p.z + sin(ang) * 0.18))
		PubKit.place(_root, "metal_stool_01", p + Vector3(0.62, 0, 0.3), _rng.randf_range(0, 360), 1.0)
		var c := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = 0.38
		cs.height = 1.0
		c.shape = cs
		c.position = Vector3(p.x, fy + 0.5, p.z)
		_body.add_child(c)


func _drink_prop(pos: Vector3) -> void:
	var cols := [Color(1.0, 0.7, 0.2), Color(0.95, 0.3, 0.5), Color(0.3, 0.9, 0.5), Color(0.45, 0.6, 1.0)]
	var c: Color = cols[_rng.randi() % cols.size()]
	var h := _rng.randf_range(0.11, 0.17)
	PubKit.mesh_instance(PubKit.cyl(0.04, 0.034, h, 12), pos + Vector3(0, h * 0.5, 0), PubKit.drinkware(), _root)
	PubKit.mesh_instance(PubKit.cyl(0.034, 0.03, h * 0.7, 12), pos + Vector3(0, h * 0.36, 0), PubKit.glass(Color(c.r, c.g, c.b, 0.85), c, 0.6), _root)


func _build_lounge() -> void:
	## Two sofa groups by the front windows: a sofa against the wall, one facing it, coffee table, rug.
	for i in _L.lounges.size():
		var c: Vector3 = _L.lounges[i]
		PubKit.place(_root, "sofa_02", c + Vector3(0, 0, 1.15), 180.0, 1.0)
		PubKit.place(_root, "sofa_02", c + Vector3(0, 0, -1.15), 0.0, 1.0)
		for sz in [1.15, -1.15]:
			_coll(Vector3(1.85, 0.75, 0.85), c + Vector3(0, 0.37, sz))
		PubKit.place(_root, "round_wooden_table_01", c, _rng.randf_range(0, 360), Vector3(0.5, 0.48, 0.5))
		_drink_prop(c + Vector3(0.1, 0.48, 0.08))
		_drink_prop(c + Vector3(-0.12, 0.48, -0.06))
		PubKit.place(_root, "potted_plant_04", c + Vector3(-0.05, 0.48, -0.15), _rng.randf_range(0, 360), 0.9)
		_rug(Vector3(c.x, PubLayout.FY + 0.004, c.z - 0.05), Vector2(2.8, 3.3), 0.0, i == 1)


func _build_booths() -> void:
	## Diner-style booth row on the left wall: high-backed upholstered benches back to back,
	## a wooden table in each bay and a little lamp.
	var fy := PubLayout.FY
	var bx := _L.booth_x
	var depth := 1.4                       # Out from the wall
	var upholstery := PubKit.flat(Color(0.42, 0.07, 0.08), 0.5, 0.0)
	var bench_zs: Array[float] = []
	for zc in _L.booths:
		bench_zs.append(zc - 0.78)
		bench_zs.append(zc + 0.78)
	for i in bench_zs.size():
		var z: float = bench_zs[i]
		var facing := 1.0 if i % 2 == 0 else -1.0   # Seat faces the table in its bay
		var back_z := z - facing * 0.2
		_b.box_at(Vector3(depth, 0.4, 0.5), Vector3(bx, fy + 0.2, z), _wood)
		_b.box_at(Vector3(depth - 0.06, 0.1, 0.46), Vector3(bx, fy + 0.45, z + facing * 0.02), upholstery)
		_b.box_at(Vector3(depth - 0.06, 0.66, 0.12), Vector3(bx, fy + 0.82, back_z), upholstery)
		_b.box_at(Vector3(depth, 0.06, 0.16), Vector3(bx, fy + 1.18, back_z), _top)
		_b.box_at(Vector3(0.03, 0.03, 0.46), Vector3(bx + depth * 0.5 - 0.02, fy + 0.5, z + facing * 0.02), _brass)
	for zc in _L.booths:
		_b.box_at(Vector3(1.15, 0.06, 0.78), Vector3(bx + 0.05, fy + 0.74, zc), _top)
		_b.box_at(Vector3(0.12, 0.7, 0.12), Vector3(bx + 0.15, fy + 0.36, zc), _steel)
		_b.box_at(Vector3(0.5, 0.03, 0.5), Vector3(bx + 0.15, fy + 0.015, zc), _steel)
		PubKit.mesh_instance(PubKit.cyl(0.05, 0.06, 0.16, 12), Vector3(bx - 0.35, fy + 0.85, zc),
			PubKit.glass(Color(1.0, 0.55, 0.3, 0.7), Color(1.0, 0.5, 0.2), 2.5), _root)
		_drink_prop(Vector3(bx + 0.2, fy + 0.77, zc + 0.15))
		_drink_prop(Vector3(bx + 0.05, fy + 0.77, zc - 0.2))
		_coll(Vector3(depth, 1.2, 2.0), Vector3(bx, fy + 0.6, zc))


func _build_darts() -> void:
	var fy := PubLayout.FY
	PubKit.place(_root, "dartboard", _L.dart_pos, 90.0, 1.0)
	# Cabinet surround
	_b.box_at(Vector3(0.04, 0.75, 1.1), _L.dart_pos + Vector3(-0.005, 0.0, 0), _wood)
	# Darts stuck in the board
	for k in 3:
		var dm := PubKit.mesh_instance(PubKit.cyl(0.004, 0.008, 0.14, 6), _L.dart_pos + Vector3(0.1, _rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.08, 0.08)),
			PubKit.flat(Color.from_hsv(_rng.randf(), 0.7, 0.8), 0.5), _root)
		dm.rotation_degrees.z = 90.0
	# Oche line + chalk scoreboard
	_b.box_at(Vector3(0.05, 0.006, 0.6), Vector3(_L.dart_throw.x, fy + 0.003, _L.dart_throw.z), PubKit.flat(Color(0.9, 0.7, 0.1), 0.6))
	var board_z := _L.dart_pos.z + 0.95
	_b.box_at(Vector3(0.03, 0.6, 0.5), Vector3(_L.dart_pos.x + 0.01, _L.dart_pos.y, board_z), PubKit.flat(Color(0.06, 0.08, 0.07), 0.95))
	var score := PubKit.label("501\n 340\n  -- 60", 40, Color(0.9, 0.9, 0.85), 0.003)
	score.position = Vector3(_L.dart_pos.x + 0.035, _L.dart_pos.y, board_z)
	score.rotation_degrees.y = 90.0
	_root.add_child(score)


# ─── Jukebox, arcade, screen ───────────────────────────────────────────────

func _build_jukebox() -> void:
	var p := _L.jukebox_pos
	var j := Node3D.new()
	j.name = "Jukebox"
	j.position = p
	j.rotation_degrees.y = 180.0   # Face into the room (-Z)
	_root.add_child(j)
	var jb := PubKit.Batch.new()
	jb.box_at(Vector3(0.95, 1.15, 0.6), Vector3(0, 0.575, 0), _top)
	jb.box_at(Vector3(1.0, 0.08, 0.64), Vector3(0, 0.04, 0), _chrome)
	jb.add_mesh(PubKit.cyl(0.475, 0.475, 0.6, 24), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 1.15, 0)), _top)
	jb.commit(j, false, "JukeboxBody")
	var face := QuadMesh.new()
	face.size = Vector2(0.9, 1.55)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/pub_jukebox.gdshader")
	sm.set_shader_parameter("tint_a", _L.p["neon_a"])
	sm.set_shader_parameter("tint_b", _L.p["neon_b"])
	var fm := PubKit.mesh_instance(face, Vector3(0, 0.86, 0.305), sm, j)
	fm.name = "JukeboxFace"
	_coll(Vector3(1.0, 1.6, 0.65), p + Vector3(0, 0.8, 0))


func _build_arcade() -> void:
	var p := _L.arcade_pos
	var a := Node3D.new()
	a.name = "HoloArcade"
	a.position = p
	a.rotation_degrees.y = 180.0
	_root.add_child(a)
	var accent: Color = _L.p["accent_color"]
	var ab := PubKit.Batch.new()
	var body := PubKit.flat(Color(0.05, 0.05, 0.07), 0.4, 0.3)
	ab.box_at(Vector3(0.72, 1.0, 0.75), Vector3(0, 0.5, -0.02), body)
	ab.box_at(Vector3(0.72, 0.95, 0.45), Vector3(0, 1.45, -0.17), body)
	ab.box_at(Vector3(0.74, 0.25, 0.5), Vector3(0, 2.0, -0.12), body)
	for sx in [-1.0, 1.0]:
		ab.box_at(Vector3(0.02, 1.9, 0.02), Vector3(sx * 0.37, 1.05, 0.34), PubKit.neon(accent, 3.0))
	# Control deck
	ab.box_at(Vector3(0.74, 0.08, 0.32), Vector3(0, 1.02, 0.3), PubKit.flat(Color(0.12, 0.1, 0.16), 0.5, 0.4), Vector3(-0.25, 0, 0))
	ab.commit(a, false, "ArcadeBody")
	PubKit.mesh_instance(PubKit.cyl(0.012, 0.012, 0.1, 6), Vector3(-0.15, 1.1, 0.3), _chrome, a)
	PubKit.mesh_instance(_sphere(0.03), Vector3(-0.15, 1.16, 0.3), PubKit.neon(Color(1.0, 0.2, 0.2), 2.0), a)
	for k in 3:
		PubKit.mesh_instance(PubKit.cyl(0.025, 0.025, 0.02, 10), Vector3(0.05 + float(k) * 0.09, 1.08, 0.3 - float(k % 2) * 0.04),
			PubKit.neon(Color.from_hsv(float(k) * 0.3, 0.8, 1.0), 2.0), a)
	var scr := QuadMesh.new()
	scr.size = Vector2(0.6, 0.55)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/pub_arcade.gdshader")
	sm.set_shader_parameter("tint", _L.p["neon_b"])
	var s := PubKit.mesh_instance(scr, Vector3(0, 1.45, 0.065), sm, a)
	s.rotation_degrees.x = -12.0
	var marquee := QuadMesh.new()
	marquee.size = Vector2(0.68, 0.2)
	PubKit.mesh_instance(marquee, Vector3(0, 2.0, 0.135), PubKit.neon(accent.lightened(0.2), 1.4), a)
	var title := PubKit.label("LUNAR RAIDERS", 40, Color(0.05, 0.02, 0.08), 0.0035)
	title.position = Vector3(0, 2.0, 0.14)
	a.add_child(title)
	_coll(Vector3(0.75, 2.1, 0.8), p + Vector3(0, 1.05, 0))


func _build_display() -> void:
	## Live QING dashboard (map, charge chart, bars, ticker) in a bezel.
	var p := _L.display_pos
	_b.box_at(Vector3(3.3, 1.75, 0.1), p, _dark)
	_b.box_at(Vector3(3.36, 0.04, 0.12), p + Vector3(0, -0.89, 0.0), _chrome)
	qing_screen = PubQingScreen.new()
	qing_screen.name = "QingScreen"
	qing_screen.position = p + Vector3(0, 0, 0.056)
	_root.add_child(qing_screen)
	qing_screen.setup(Vector2(3.1, 1.55), int(_L.p["detail_seed"]), _L.p["accent_color"])


# ─── Decor ─────────────────────────────────────────────────────────────────

func _build_wall_art() -> void:
	var fy := PubLayout.FY
	var w := _L.w
	var d := _L.d
	# Framed art: between the game-room windows, beside the door, over the kegs
	PubKit.poster(_root, Vector3(w - 0.02, fy + 2.0, -d + 4.0), -90.0, Vector2(0.62, 0.9), "ERIS RISING", "tours nightly", _rng.randi(), _brass)
	PubKit.poster(_root, Vector3(-(PubLayout.DOOR_W * 0.5 + 0.95), fy + 2.05, d - 0.02), 180.0, Vector2(0.6, 0.85), "VISIT DYSNOMIA", "", _rng.randi(), _brass)
	# Event prints over the kegs
	var bills := [["AFFECTION FAIR", "rides all cycle"], ["WAAT SLOTS", "jackpot night"]]
	for i in bills.size():
		PubKit.poster(_root, Vector3(_L.bar_x1 + 1.35 + float(i) * 0.95, fy + 2.25, -d + 0.02), 0.0, Vector2(0.66, 0.92),
			bills[i][0], bills[i][1], _rng.randi(), _brass)
	# Neon script over the booth row
	var bz := d - 3.0
	if not _L.booths.is_empty():
		bz = 0.0
		for z in _L.booths:
			bz += z / float(_L.booths.size())
	var nm := MeshInstance3D.new()
	nm.mesh = PubKit.text_mesh("cold affection", 0.011, 0.02)
	nm.material_override = PubKit.neon(_L.p["neon_a"], 5.0)
	nm.position = Vector3(-w + 0.06, fy + 3.1, bz)
	nm.rotation_degrees.y = 90.0
	_root.add_child(nm)
	neon_nodes.append(nm)
	# Neon over the game tables (right wall, facing in)
	var gm := MeshInstance3D.new()
	gm.mesh = PubKit.text_mesh("GAME ROOM", 0.011, 0.02)
	gm.material_override = PubKit.neon(_L.p["neon_b"], 4.5)
	gm.position = Vector3(w - 0.06, fy + 3.25, -d + 4.0)
	gm.rotation_degrees.y = -90.0
	_root.add_child(gm)
	neon_nodes.append(gm)
	# Neon cocktail glass beside the drinks board
	var cg := PubKit.neon(_L.p["neon_a"], 4.5)
	# Sits clear of the board: left of its frame, level with its middle
	var gx := _L.bar_cx - 0.2 - minf(4.6, _L.bar_x1 - _L.bar_x0 - 2.2) * 0.5 - 0.7
	var gy := fy + 3.55
	var gz := -d + 0.06
	for sx in [-1.0, 1.0]:
		_b.box_at(Vector3(0.025, 0.42, 0.025), Vector3(gx + sx * 0.11, gy + 0.1, gz), cg, Vector3(0, 0, sx * 0.55))
	_b.box_at(Vector3(0.5, 0.025, 0.025), Vector3(gx, gy + 0.29, gz), cg)
	_b.box_at(Vector3(0.025, 0.3, 0.025), Vector3(gx, gy - 0.25, gz), cg)
	_b.box_at(Vector3(0.26, 0.025, 0.025), Vector3(gx, gy - 0.4, gz), cg)
	PubKit.mesh_instance(_sphere(0.04), Vector3(gx + 0.12, gy + 0.33, gz), PubKit.neon(Color(0.5, 1.0, 0.3), 5.0), _root)
	# Gig posters by the door
	var posters := [["THE GWATS", "every 7th block"], ["LAU MINT PARTY", "bring a seed"], ["LOW-G KARAOKE", "thursdays"]]
	for i in posters.size():
		PubKit.poster(_root, Vector3(PubLayout.DOOR_W * 0.5 + 0.45 + float(i) * 0.72, fy + 1.95 + _rng.randf_range(-0.06, 0.06), d - 0.02),
			180.0, Vector2(0.56, 0.8), posters[i][0], posters[i][1], _rng.randi(), _dark)
	# Rug under the first row of game tables
	var g0: Vector3 = _L.game_tables[0]
	_rug(Vector3(g0.x + 1.375, fy + 0.004, g0.z - 0.25), Vector2(5.6, 2.7), 0.0, true)


func _build_plants() -> void:
	var fy := PubLayout.FY
	var w := _L.w
	var d := _L.d
	var spots := [Vector3(-w + 0.45, fy, d - 0.45), Vector3(w - 0.45, fy, -d + 0.45), Vector3(PubLayout.DOOR_W * 0.5 + 0.4, fy, d - 0.45)]
	for p in spots:
		PubKit.place(_root, "potted_plant_04", p, _rng.randf_range(0, 360), 3.6)
	# Kegs stacked at the bar's open end
	PubKit.place(_root, "wine_barrel_01", Vector3(_L.bar_x1 + 0.2, fy, -d + 0.55), 30.0, 0.9)
	PubKit.place(_root, "Barrel_01", Vector3(_L.bar_x1 + 1.0, fy, -d + 0.45), 0.0, 0.85)
	_coll(Vector3(1.6, 0.9, 0.8), Vector3(_L.bar_x1 + 0.6, fy + 0.45, -d + 0.5))


# ─── Lighting ──────────────────────────────────────────────────────────────

func _build_lights() -> void:
	var fy := PubLayout.FY
	var warm := Color(1.0, 0.74, 0.46)
	var cz := _L.counter_z
	# Pendants over the bar ends only, so none hangs in front of the drinks board
	var mw := minf(4.6, _L.bar_x1 - _L.bar_x0 - 2.2)
	var menu_l := _L.bar_cx - 0.2 - mw * 0.5
	var menu_r := _L.bar_cx - 0.2 + mw * 0.5
	_pendant(Vector3((_L.bar_x0 + menu_l) * 0.5 - 0.3, fy + 2.95, _L.counter_front - 0.05), 0.8)
	_pendant(Vector3((menu_r + _L.bar_x1) * 0.5 + 0.2, fy + 2.95, _L.counter_front - 0.05), 0.8)
	bar_flash = _add_light(Vector3(_L.bar_cx - 1.8, fy + 2.0, cz + 0.3), warm, 1.6, 6.0)
	_add_light(Vector3(_L.bar_cx + 2.2, fy + 2.0, cz + 0.4), warm, 1.5, 6.0)
	# Game area
	var g0: Vector3 = _L.game_tables[0]
	var gl: Vector3 = _L.game_tables[_L.game_tables.size() - 1]
	_add_light(Vector3((g0.x + gl.x) * 0.5 + 0.7, fy + 2.3, (g0.z + gl.z) * 0.5), Color(1.0, 0.86, 0.66), 1.8, 7.0)
	# Sofa groups — warm, one blushed by the jukebox neon, the other by the booth neon
	var la: Vector3 = _L.lounges[0]
	var lb: Vector3 = _L.lounges[1]
	_add_light(Vector3(la.x + 1.2, fy + 2.2, la.z), warm.lerp(_L.p["neon_b"], 0.3), 1.4, 6.0)
	_add_light(Vector3((lb.x + _L.booth_x) * 0.5, fy + 2.3, lb.z - 0.6), warm.lerp(_L.p["neon_a"], 0.2), 1.4, 6.5)
	_crystal_chandelier(Vector3(_L.order_x - 1.6, _L.eave - 0.75, _L.counter_front + 1.6))
	_fairy_lights()
	# Rafter uplights sitting on the tie beams: wash the roof so the ceiling isn't a black void
	for sx in [-1.0, 1.0]:
		var ul := _add_light(Vector3(sx * _L.w * 0.45, _L.eave + 0.05, 0.0), Color(1.0, 0.72, 0.48), 1.1, maxf(_L.d, 6.0))
		ul.omni_attenuation = 0.8
		_b.box_at(Vector3(0.3, 0.08, 0.2), Vector3(sx * _L.w * 0.45, _L.eave - 0.02, 0.0), _dark)
	for l in lights:
		light_base.append(l.light_energy)


func _crystal_chandelier(pos: Vector3) -> void:
	## Dysnomia accent: a brass hoop hung with glowing cyan/violet crystal prisms.
	var cb := PubKit.Batch.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.56
	ring.rings = 32
	ring.ring_segments = 8
	cb.add_mesh(ring, Transform3D(Basis(), pos), _brass)
	for k in 3:
		var a := float(k) * TAU / 3.0
		var foot := pos + Vector3(cos(a) * 0.53, 0, sin(a) * 0.53)
		var top := Vector3(pos.x, _L.eave - 0.15, pos.z)
		var len := foot.distance_to(top)
		cb.add_mesh(PubKit.cyl(0.006, 0.006, len, 4), Transform3D(Basis(Quaternion(Vector3.UP, (top - foot) / len)), (foot + top) * 0.5), _dark)
	cb.commit(_root, false, "ChandelierFrame")
	var cyan := PubKit.glass(Color(0.3, 0.9, 1.0, 0.75), Color(0.25, 0.85, 1.0), 3.5)
	var violet := PubKit.glass(Color(0.7, 0.4, 1.0, 0.75), Color(0.6, 0.3, 1.0), 3.0)
	var xb := PubKit.Batch.new()
	var n := 22
	for i in n:
		var a := float(i) * TAU / float(n)
		var r := 0.53 if i % 2 == 0 else 0.3
		var l := _rng.randf_range(0.22, 0.55) * (1.0 if i % 2 == 0 else 1.3)
		var prism := PubKit.cyl(0.035, 0.0, l, 6)
		var p := pos + Vector3(cos(a) * r, -l * 0.5 - 0.02, sin(a) * r)
		xb.add_mesh(prism, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p), cyan if i % 3 != 0 else violet)
	xb.add_mesh(PubKit.cyl(0.08, 0.0, 0.8, 6), Transform3D(Basis(), pos + Vector3(0, -0.42, 0)), cyan)
	xb.commit(_root, false, "ChandelierCrystals")
	_add_light(pos + Vector3(0, -0.5, 0), Color(0.45, 0.85, 1.0), 0.9, 4.5)


func _fairy_lights() -> void:
	## Warm bulbs strung between the tie beams — the rafters stop being a black void.
	var pts: Array[Vector3] = []
	var n_ribs := int(ceil(2.0 * _L.d / 2.7))
	var y := _L.eave - 0.22
	for i in n_ribs:
		var z0 := lerpf(-_L.d + 0.25, _L.d - 0.25, float(i) / float(n_ribs))
		var z1 := lerpf(-_L.d + 0.25, _L.d - 0.25, float(i + 1) / float(n_ribs))
		# Two strands per bay criss-crossing the room
		for strand in 2:
			var xa := -_L.w + 0.4 if strand == 0 else _L.w - 0.4
			var a := Vector3(xa, y, z0)
			var b := Vector3(-xa, y, z1)
			var n := int(a.distance_to(b) / 0.5)
			for k in range(1, n):
				var t := float(k) / float(n)
				var p := a.lerp(b, t)
				p.y -= sin(t * PI) * 0.7
				pts.append(p)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _sphere(0.035)
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FairyLights"
	mmi.multimesh = mm
	mmi.material_override = PubKit.neon(Color(1.0, 0.7, 0.4), 6.0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)


func _pendant(pos: Vector3, scale: float) -> void:
	## Hanging industrial lamp (Poly Haven) with a cord up to the roof beams and a glowing bulb.
	var lamp := PubKit.place(_root, "hanging_industrial_lamp", pos, _rng.randf_range(0, 360), scale)
	lamp.name = "Pendant"
	var top := _L.eave - 0.2
	if top > pos.y + 0.05:
		_b.add_mesh(PubKit.cyl(0.008, 0.008, top - pos.y, 4), Transform3D(Basis(), Vector3(pos.x, (top + pos.y) * 0.5, pos.z)), _dark)
	PubKit.mesh_instance(_sphere(0.06), pos + Vector3(0, -1.22 * scale, 0), PubKit.neon(Color(1.0, 0.8, 0.55), 8.0), _root)


func _add_light(pos: Vector3, color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.light_specular = 0.7
	_root.add_child(l)
	lights.append(l)
	return l


func _rug(pos: Vector3, size: Vector2, rot: float, alt: bool = false) -> void:
	var q := PlaneMesh.new()
	q.size = size
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/pub_rug.gdshader")
	var accent: Color = _L.p["accent_color"]
	if alt:
		sm.set_shader_parameter("base_color", Color(0.08, 0.12, 0.2))
		sm.set_shader_parameter("pattern_color", accent.lightened(0.2))
		sm.set_shader_parameter("border_color", Color(0.3, 0.06, 0.05))
	else:
		sm.set_shader_parameter("base_color", accent.darkened(0.6))
		sm.set_shader_parameter("pattern_color", Color(0.85, 0.62, 0.3))
	sm.set_shader_parameter("size_m", size)
	var mi := PubKit.mesh_instance(q, pos, sm, _root)
	mi.rotation.y = rot


# ─── Helpers ───────────────────────────────────────────────────────────────

func _text_w(text: String, size: int, px: float) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * px


func _coll(size: Vector3, pos: Vector3) -> void:
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	c.position = pos
	_body.add_child(c)


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s
