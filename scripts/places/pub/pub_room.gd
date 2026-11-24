class_name PubRoom
extends RefCounted
## The inside of Sunny's Pub: brick over plank wainscot, a plank floor and a
## beamed ceiling strung with fairy lights; the long bar with taps and a stocked,
## backlit back bar under the AFFECTION ON TAP board; stools, booths, two sofa
## lounges on rugs, high-tops, darts, kegs, framed Dysnomia prints, neon (the
## "cold affection" script, a cocktail glass, a cyan/violet crystal chandelier)
## and night-glass windows. Ported from the cantina prototype (branch
## claude/eager-cannon-ctzojh, scripts/world/pub/pub_interior.gd + pub_shell.gd)
## onto Sunny's v2 floor plan. Static geometry is batched per material.
##
## Room space (the pub's local space): x ∈ [-W, W], z ∈ [BACK, FRONT], floor at y = 0.
## Nothing here is chain data: the only numbers drawn come from the menu list.

const W := 10.0
const BACK := -8.0
const FRONT := 8.0
const H := 5.0
const T := 0.3
const IN_X := W - 0.15  # inner face of the side walls
const IN_BACK := BACK + 0.15

# The bar.
const COUNTER_X0 := -5.5
const COUNTER_X1 := 3.5
const COUNTER_Z := -5.4  # centre line; the customer face is at COUNTER_Z + 0.4
const COUNTER_H := 1.1
const ORDER_X := -1.0
const PLATFORM_H := 0.3  # duckboards behind the bar
const BACK_COUNTER_Z := -7.45
const BACKBAR_X := -1.0  # the bottle wall and the board above it are centred here
const SHELF_W := 4.6

const NEON_A := Color(1.0, 0.35, 0.85)  # violet-pink
const NEON_B := Color(0.25, 0.85, 1.0)  # Dysnomia cyan
const WARM := Color(1.0, 0.74, 0.46)

var lights: Array[OmniLight3D] = []
var light_base: Array[float] = []
var neon_mats: Array[StandardMaterial3D] = []
var tap_handles: Array[MeshInstance3D] = []
var back_glow_mat: StandardMaterial3D
var bar_flash: OmniLight3D
var stools: Array[Vector3] = []  # stool feet (seat ≈ 0.78 m)
var lounges: Array[Vector3] = [Vector3(-4.6, 0, 6.3), Vector3(4.9, 0, 6.3)]
var booths: Array[float] = [3.3, 5.7]  # booth bay centres (z) on the left wall
var booth_x := -IN_X + 0.72
var hightops: Array[Vector3] = [Vector3(-5.9, 0, -1.7), Vector3(1.9, 0, -1.9)]
var barrel_table := Vector3(7.0, 0, -6.0)
var dart_pos := Vector3(IN_X - 0.02, 1.73, -3.3)
var chandelier_at := Vector3(ORDER_X, H - 0.85, -2.7)

var _root: Node3D
var _b: PubKit.Batch
var _rng := RandomNumberGenerator.new()
var _wood: StandardMaterial3D
var _top: StandardMaterial3D
var _steel: StandardMaterial3D
var _chrome: StandardMaterial3D
var _dark: StandardMaterial3D
var _brass: StandardMaterial3D
var _brick: StandardMaterial3D


static func order_spot() -> Vector3:
	return Vector3(ORDER_X, 0, COUNTER_Z + 1.15)


func build(root: Node3D, menu_lines: Array) -> void:
	_root = root
	_rng.seed = 0x5a77
	_b = PubKit.Batch.new()
	_brick = PubKit.pbr("brick_wall_02", 2.4, Color(0.92, 0.8, 0.72))
	_wood = PubKit.pbr("dark_planks", 1.2, Color(0.75, 0.6, 0.5))
	_top = PubKit.pbr("wood_table_001", 1.2, Color(0.9, 0.75, 0.62), 0.55)
	_steel = PubKit.flat(Color(0.13, 0.13, 0.14), 0.42, 0.85)
	_chrome = PubKit.flat(Color(0.8, 0.8, 0.82), 0.12, 1.0)
	_dark = PubKit.flat(Color(0.04, 0.04, 0.045), 0.55, 0.4)
	_brass = PubKit.flat(Color(0.78, 0.58, 0.3), 0.25, 1.0)
	_shell()
	_bar()
	_back_bar()
	_menu(menu_lines)
	_seating()
	_decor()
	_lights()
	_b.commit(_root, "PubBatch")
	for l in lights:
		light_base.append(l.light_energy)


# --- The shell -------------------------------------------------------------------

func _shell() -> void:
	# Floor: dark planks over the whole room, with a collider.
	var floor_mat := PubKit.pbr("dark_wooden_planks", 2.2, Color(0.95, 0.88, 0.82))
	GamesPlace.box(_root, Vector3(W * 2, 0.2, FRONT - BACK), Vector3(0, -0.1, (FRONT + BACK) * 0.5), floor_mat, true)
	# Walls: brick, collidable. The front wall is the facade (built by the place).
	GamesPlace.box(_root, Vector3(W * 2, H, T), Vector3(0, H * 0.5, BACK), _brick, true)
	for sx in [-1.0, 1.0]:
		GamesPlace.box(_root, Vector3(T, H, FRONT - BACK), Vector3(sx * W, H * 0.5, 0), _brick, true)
	# Plank wainscot to 1.1 m with a top rail, on the three inner walls.
	var wains := PubKit.pbr("dark_planks", 1.4, Color(0.8, 0.7, 0.62))
	for sx in [-1.0, 1.0]:
		_b.box_at(Vector3(0.04, 1.1, FRONT - BACK - 0.3), Vector3(sx * (IN_X - 0.02), 0.55, 0), wains)
		_b.box_at(Vector3(0.08, 0.06, FRONT - BACK - 0.3), Vector3(sx * (IN_X - 0.04), 1.12, 0), _top)
	_b.box_at(Vector3(W * 2 - 0.3, 1.1, 0.04), Vector3(0, 0.55, IN_BACK + 0.02), wains)
	_b.box_at(Vector3(W * 2 - 0.3, 0.06, 0.08), Vector3(0, 1.12, IN_BACK + 0.04), _top)
	_b.box_at(Vector3(W * 2 - 0.3, 1.1, 0.04), Vector3(0, 0.55, FRONT - 0.22), wains)
	# Ceiling: dark boards, tie beams across, purlins along.
	_b.box_at(Vector3(W * 2, 0.12, FRONT - BACK), Vector3(0, H + 0.06, 0), PubKit.pbr("dark_planks", 1.6, Color(0.35, 0.28, 0.24)))
	for i in 5:
		var z := BACK + 1.6 + i * 3.2
		_b.box_at(Vector3(W * 2 - 0.3, 0.3, 0.26), Vector3(0, H - 0.15, z), _wood)
	for sx in [-0.5, 0.0, 0.5]:
		_b.box_at(Vector3(0.2, 0.18, FRONT - BACK - 0.3), Vector3(sx * W, H - 0.09, 0), _wood)
	# Night-glass windows on the inner faces: the front pair (behind the bay
	# windows the street sees) and two on the right wall.
	_window(Vector3(-4.2, 1.9, FRONT - 0.21), 180.0, Vector2(3.0, 1.8))
	_window(Vector3(4.2, 1.9, FRONT - 0.21), 180.0, Vector2(3.0, 1.8))
	_window(Vector3(IN_X - 0.01, 2.0, 0.6), -90.0, Vector2(1.6, 1.5))
	_window(Vector3(IN_X - 0.01, 2.0, 4.6), -90.0, Vector2(1.6, 1.5))


func _window(at: Vector3, yaw_deg: float, size: Vector2) -> void:
	var n := Node3D.new()
	n.position = at
	n.rotation_degrees.y = yaw_deg
	_root.add_child(n)
	var q := QuadMesh.new()
	q.size = size
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/pub_window.gdshader")
	sm.set_shader_parameter("size_m", size)
	PubKit.mesh_instance(q, Vector3(0, 0, 0.01), sm, n)
	# Frame and mullion in dark steel, a sill in wood.
	var fb := PubKit.Batch.new()
	for sy in [-1.0, 1.0]:
		fb.box_at(Vector3(size.x + 0.14, 0.07, 0.08), Vector3(0, sy * (size.y * 0.5 + 0.035), 0.02), _dark)
	for sx in [-1.0, 0.0, 1.0]:
		fb.box_at(Vector3(0.07 if sx != 0.0 else 0.04, size.y, 0.08), Vector3(sx * (size.x * 0.5 + 0.035), 0, 0.02), _dark)
	fb.box_at(Vector3(size.x + 0.3, 0.05, 0.22), Vector3(0, -size.y * 0.5 - 0.09, 0.09), _top)
	fb.commit(n, "Frame")


# --- The bar -----------------------------------------------------------------------

func _bar() -> void:
	var x0 := COUNTER_X0
	var x1 := COUNTER_X1
	var len := x1 - x0
	var cx := (x0 + x1) * 0.5
	var cz := COUNTER_Z
	var ch := COUNTER_H
	# Plank body, steel kick plate, battens on the customer face.
	_b.box_at(Vector3(len, ch - 0.07, 0.62), Vector3(cx, (ch - 0.07) * 0.5, cz), _wood)
	_b.box_at(Vector3(len, 0.16, 0.03), Vector3(cx, 0.08, cz + 0.32), _steel)
	var n := int(len / 0.6)
	for i in n + 1:
		_b.box_at(Vector3(0.05, ch - 0.27, 0.04), Vector3(x0 + 0.05 + float(i) * (len - 0.1) / float(n), 0.16 + (ch - 0.27) * 0.5, cz + 0.33), _top)
	# Dysnomia cyan under the lip, a violet kick strip at the floor.
	_b.box_at(Vector3(len - 0.05, 0.025, 0.03), Vector3(cx, ch - 0.1, cz + 0.37), PubKit.neon(NEON_B, 4.0))
	_b.box_at(Vector3(len - 0.05, 0.02, 0.02), Vector3(cx, 0.17, cz + 0.34), PubKit.neon(Color(0.6, 0.3, 1.0), 2.5))
	_b.box_at(Vector3(len + 0.1, 0.07, 0.86), Vector3(cx, ch - 0.035, cz + 0.06), _top)
	# Brass foot rail on brackets.
	_b.add_mesh(PubKit.cyl(0.03, 0.03, len - 0.2, 12), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(cx, 0.22, cz + 0.52)), _brass)
	for i in 7:
		_b.box_at(Vector3(0.03, 0.03, 0.2), Vector3(x0 + 0.2 + float(i) * (len - 0.4) / 6.0, 0.22, cz + 0.42), _brass)
	_collider(Vector3(len, ch, 0.9), Vector3(cx, ch * 0.5, cz + 0.05))
	# Back counter with glowing fridges, against the back wall.
	var bl := 7.8
	var bcx := -1.4
	var bz := BACK_COUNTER_Z
	_b.box_at(Vector3(bl, 0.92, 0.56), Vector3(bcx, 0.46, bz), _wood)
	_b.box_at(Vector3(bl + 0.04, 0.04, 0.6), Vector3(bcx, 0.94, bz + 0.01), _chrome)
	var fridge := PubKit.glass(Color(0.55, 0.75, 0.9, 0.5), Color(0.55, 0.8, 1.0), 0.9)
	for i in 4:
		var fx := bcx - bl * 0.5 + 0.7 + float(i) * 0.75
		_b.box_at(Vector3(0.7, 0.72, 0.03), Vector3(fx, 0.45, bz + 0.29), _steel)
		_b.box_at(Vector3(0.6, 0.6, 0.01), Vector3(fx, 0.45, bz + 0.31), fridge)
		for k in 5:
			_b.add_mesh(PubKit.cyl(0.032, 0.032, 0.2, 8), Transform3D(Basis(), Vector3(fx - 0.22 + float(k) * 0.11, 0.3, bz + 0.2)),
				PubKit.flat(Color.from_hsv(float((i * 5 + k) % 7) / 7.0, 0.6, 0.7), 0.3, 0.6))
	# Duckboards behind the counter, so Sunny stands tall over it.
	var pz0 := bz + 0.3
	var pz1 := cz - 0.31
	_b.box_at(Vector3(len - 0.05, PLATFORM_H, pz1 - pz0), Vector3(cx, PLATFORM_H * 0.5, (pz0 + pz1) * 0.5), _wood)
	for i in int((pz1 - pz0) / 0.16):
		_b.box_at(Vector3(len - 0.05, 0.01, 0.04), Vector3(cx, PLATFORM_H + 0.004, pz0 + 0.1 + float(i) * 0.16), _dark)
	_collider(Vector3(len - 0.05, PLATFORM_H, pz1 - pz0), Vector3(cx, PLATFORM_H * 0.5, (pz0 + pz1) * 0.5))
	# Beer taps: a chrome tower, handles in the neon palette.
	var tx := -3.2
	var top_y := ch
	var tz := cz - 0.14
	_b.box_at(Vector3(0.9, 0.03, 0.18), Vector3(tx, top_y + 0.015, tz + 0.16), _chrome)
	for sx in [-0.4, 0.4]:
		_b.add_mesh(PubKit.cyl(0.035, 0.045, 0.42, 12), Transform3D(Basis(), Vector3(tx + sx, top_y + 0.21, tz)), _chrome)
	_b.add_mesh(PubKit.cyl(0.04, 0.04, 0.9, 14), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(tx, top_y + 0.42, tz)), _chrome)
	var handle_cols := [NEON_A, Color(1.0, 0.75, 0.2), NEON_B, Color(0.4, 1.0, 0.5)]
	for i in 4:
		var hx := tx - 0.3 + float(i) * 0.2
		_b.add_mesh(PubKit.cyl(0.012, 0.016, 0.12, 8), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(hx, top_y + 0.4, tz + 0.08)), _chrome)
		var pivot := Node3D.new()
		pivot.position = Vector3(hx, top_y + 0.46, tz)
		_root.add_child(pivot)
		var hm := PubKit.mesh_instance(PubKit.cyl(0.018, 0.026, 0.2, 10), Vector3(0, 0.1, 0), PubKit.neon(handle_cols[i], 1.6), pivot)
		tap_handles.append(hm)
	# Glasses drying upside down on a mat beside the taps.
	var gmat := PubKit.drinkware()
	for i in 10:
		_b.add_mesh(PubKit.cyl(0.035, 0.03, 0.14, 10), Transform3D(Basis(), Vector3(tx + 0.65 + float(i % 5) * 0.1, top_y + 0.07, tz + float(i / 5) * 0.1)), gmat)
	_b.box_at(Vector3(0.55, 0.01, 0.25), Vector3(tx + 0.85, top_y + 0.005, tz + 0.05), _dark)
	# The register at the far end, a succulent at the near end.
	PubKit.place(_root, "CashRegister_01", Vector3(x1 - 0.55, top_y, cz - 0.05), 180.0, 0.85)
	PubKit.place(_root, "potted_plant_04", Vector3(x0 + 0.4, top_y, cz + 0.1), 40.0, 1.2)
	# Stools along the customer face, with a gap at the order spot.
	var x := x0 + 0.55
	while x < x1 - 0.3:
		if absf(x - ORDER_X) > 0.8:
			stools.append(Vector3(x, 0, cz + 0.95))
		x += 0.86
	for st in stools:
		_stool(st)
	# Kegs and a barrel at the bar's open end; a barrel table by the darts.
	PubKit.place(_root, "wine_barrel_01", Vector3(4.4, 0, -7.35), 30.0, 0.9)
	PubKit.place(_root, "Barrel_01", Vector3(5.3, 0, -7.4), 0.0, 0.85)
	PubKit.place(_root, "wine_barrel_01", Vector3(4.85, 0.85, -7.35), 75.0, 0.75)
	_collider(Vector3(1.8, 1.6, 0.9), Vector3(4.85, 0.8, -7.35))
	PubKit.place(_root, "wine_barrel_01", barrel_table, 20.0, Vector3(0.95, 1.18, 0.95))
	_stool(barrel_table + Vector3(-0.65, 0, 0.35))
	_drink(barrel_table + Vector3(0.12, 0.871 * 1.18, 0.05))
	_collider(Vector3(0.75, 1.0, 0.75), barrel_table + Vector3(0, 0.5, 0))


## A bar stool, batched: leather seat on a wooden rim, steel column, brass foot ring.
func _stool(at: Vector3) -> void:
	var seat := PubKit.flat(Color(0.42, 0.12, 0.08), 0.55)
	_b.add_mesh(PubKit.cyl(0.2, 0.19, 0.07, 16), Transform3D(Basis(), at + Vector3(0, 0.745, 0)), seat)
	_b.add_mesh(PubKit.cyl(0.205, 0.205, 0.035, 16), Transform3D(Basis(), at + Vector3(0, 0.7, 0)), _top)
	_b.add_mesh(PubKit.cyl(0.026, 0.026, 0.68, 8), Transform3D(Basis(), at + Vector3(0, 0.35, 0)), _steel)
	_b.add_mesh(PubKit.cyl(0.2, 0.22, 0.03, 16), Transform3D(Basis(), at + Vector3(0, 0.015, 0)), _steel)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.15
	ring.outer_radius = 0.17
	ring.rings = 16
	ring.ring_segments = 6
	_b.add_mesh(ring, Transform3D(Basis(), at + Vector3(0, 0.3, 0)), _brass)
	for k in 3:
		var a := TAU * k / 3.0
		_b.box_at(Vector3(0.15, 0.015, 0.015), at + Vector3(cos(a) * 0.08, 0.3, sin(a) * 0.08), _brass, Vector3(0, -a, 0))


func _back_bar() -> void:
	var cx := BACKBAR_X
	var sw := SHELF_W
	var wall_z := IN_BACK + 0.02
	# A low-energy amber panel behind the bottles, so they silhouette against it.
	var q := QuadMesh.new()
	q.size = Vector2(sw, 1.55)
	back_glow_mat = PubKit.neon(Color(0.9, 0.42, 0.14), 0.32).duplicate()
	PubKit.mesh_instance(q, Vector3(cx, 2.02, wall_z + 0.01), back_glow_mat, _root).name = "BackBarGlow"
	for sx in [-0.5, 0.5]:
		_b.box_at(Vector3(0.08, 1.75, 0.3), Vector3(cx + sx * (sw + 0.08), 2.02, wall_z + 0.15), _top)
	_b.box_at(Vector3(sw + 0.24, 0.1, 0.32), Vector3(cx, 2.92, wall_z + 0.16), _top)
	var shelf_glass := PubKit.glass(Color(0.7, 0.85, 0.85, 0.35))
	var shelf_ys := [1.28, 1.78, 2.28]
	for y in shelf_ys:
		_b.box_at(Vector3(sw, 0.025, 0.28), Vector3(cx, y, wall_z + 0.15), shelf_glass)
		_b.box_at(Vector3(sw, 0.012, 0.012), Vector3(cx, y - 0.02, wall_z + 0.29), PubKit.neon(Color(1.0, 0.7, 0.4), 2.0))
	# Side cabinets: plank backs, two wooden shelves each, more stock.
	var rows: Array = []
	for y in shelf_ys:
		rows.append([y + 0.013, cx - sw * 0.5 + 0.08, cx + sw * 0.5 - 0.08, wall_z + 0.13])
	var side_w := 1.5
	for sx in [-1.0, 1.0]:
		var mx: float = cx + sx * (sw * 0.5 + 0.2 + side_w * 0.5)
		_b.box_at(Vector3(side_w, 1.55, 0.03), Vector3(mx, 1.95, wall_z + 0.015), _wood)
		for k in 2:
			var y: float = 1.45 + float(k) * 0.62
			_b.box_at(Vector3(side_w, 0.045, 0.3), Vector3(mx, y, wall_z + 0.15), _top)
			_b.box_at(Vector3(side_w - 0.1, 0.01, 0.01), Vector3(mx, y - 0.03, wall_z + 0.29), PubKit.neon(Color(1.0, 0.7, 0.4), 1.6))
			rows.append([y + 0.023, mx - side_w * 0.5 + 0.08, mx + side_w * 0.5 - 0.08, wall_z + 0.14])
		for ex in [-0.5, 0.5]:
			_b.box_at(Vector3(0.05, 1.6, 0.32), Vector3(mx + ex * side_w, 1.95, wall_z + 0.16), _top)
	rows.append([0.96, -5.0, 0.6, BACK_COUNTER_Z - 0.12])  # on the back counter
	# Bottles: three lathed shapes (wine, spirit, liqueur) as MultiMeshes with
	# per-instance glass tints and a paper label band: ~230 bottles in 6 draw calls.
	var tints := [Color(0.62, 0.3, 0.06, 0.8), Color(0.15, 0.42, 0.18, 0.78), Color(0.16, 0.3, 0.75, 0.72),
		Color(0.85, 0.88, 0.9, 0.4), Color(0.5, 0.06, 0.12, 0.85), Color(0.3, 0.16, 0.06, 0.88),
		Color(0.4, 0.18, 0.6, 0.78), Color(0.85, 0.7, 0.15, 0.72), Color(0.08, 0.2, 0.1, 0.9)]
	var shapes := [BOTTLE_WINE, BOTTLE_SPIRIT, BOTTLE_LIQUEUR]
	var xfs: Array = [[], [], []]
	var cols: Array = [[], [], []]
	for r in rows:
		var x: float = r[1]
		while x < r[2]:
			var k := _rng.randi() % shapes.size()
			var s := _rng.randf_range(0.85, 1.12)
			var basis := Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.2), s))
			xfs[k].append(Transform3D(basis, Vector3(x, r[0], r[3] + _rng.randf_range(-0.04, 0.04))))
			cols[k].append(tints[_rng.randi() % tints.size()])
			x += _rng.randf_range(0.085, 0.13)
			if _rng.randf() < 0.06:
				x += 0.2  # a gap where a bottle is out being poured
	var glass_mat := StandardMaterial3D.new()
	glass_mat.vertex_color_use_as_albedo = true
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.08
	glass_mat.metallic_specular = 0.9
	glass_mat.rim_enabled = true
	glass_mat.rim = 0.4
	var label_mat := PubKit.flat(Color(0.86, 0.8, 0.66), 0.85)
	for k in shapes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _lathe(shapes[k], glass_mat, label_mat)
		mm.instance_count = xfs[k].size()
		for i in xfs[k].size():
			mm.set_instance_transform(i, xfs[k][i])
			mm.set_instance_color(i, cols[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Bottles%d" % k
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mmi)


# Bottle profiles: [radius, height] from the base up; the label band is [y0, y1].
const BOTTLE_WINE := {"p": [[0.036, 0.0], [0.037, 0.2], [0.03, 0.24], [0.014, 0.275], [0.012, 0.33], [0.015, 0.335], [0.0, 0.336]], "label": [0.06, 0.15]}
const BOTTLE_SPIRIT := {"p": [[0.04, 0.0], [0.041, 0.17], [0.036, 0.195], [0.015, 0.215], [0.013, 0.27], [0.016, 0.28], [0.0, 0.281]], "label": [0.05, 0.13]}
const BOTTLE_LIQUEUR := {"p": [[0.046, 0.0], [0.047, 0.11], [0.03, 0.15], [0.013, 0.18], [0.012, 0.21], [0.015, 0.215], [0.0, 0.216]], "label": [0.03, 0.09]}


## A low-poly lathed bottle: surface 0 glass (tinted per instance), surface 1 the label band.
static func _lathe(shape: Dictionary, glass_mat: Material, label_mat: Material, segs: int = 10) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var prof: Array = [[0.0, 0.0]] + shape["p"]
	for part in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rings: Array = prof
		if part == 1:
			var r0: float = shape["p"][0][0] + 0.0015
			rings = [[r0, shape["label"][0]], [r0, shape["label"][1]]]
		for i in rings.size() - 1:
			var a: Array = rings[i]
			var b: Array = rings[i + 1]
			for k in segs:
				var t0 := TAU * k / segs
				var t1 := TAU * (k + 1) / segs
				var p00 := Vector3(cos(t0) * a[0], a[1], sin(t0) * a[0])
				var p01 := Vector3(cos(t1) * a[0], a[1], sin(t1) * a[0])
				var p10 := Vector3(cos(t0) * b[0], b[1], sin(t0) * b[0])
				var p11 := Vector3(cos(t1) * b[0], b[1], sin(t1) * b[0])
				for v in [p00, p11, p10, p00, p01, p11]:  # clockwise seen from outside (Godot front faces)
					st.add_vertex(v)
		st.generate_normals()
		st.set_material(label_mat if part == 1 else glass_mat)
		st.commit(mesh)
	return mesh


## The backlit drinks board above the back bar. Its lines are the menu itself.
func _menu(menu_lines: Array) -> void:
	var cx := BACKBAR_X
	var hgt := 1.22
	var cy := 3.78
	var mw := 4.9
	var z := IN_BACK + 0.06
	_b.box_at(Vector3(mw + 0.16, hgt + 0.16, 0.08), Vector3(cx, cy, z), _dark)
	var q := QuadMesh.new()
	q.size = Vector2(mw, hgt)
	PubKit.mesh_instance(q, Vector3(cx, cy, z + 0.045), PubKit.flat(Color(0.02, 0.025, 0.03), 0.8, 0.0, Color(0.1, 0.07, 0.16), 1.0), _root)
	var frame := PubKit.neon(NEON_B, 3.0)
	neon_mats.append(frame)
	for sy in [-0.5, 0.5]:
		_b.box_at(Vector3(mw + 0.1, 0.025, 0.03), Vector3(cx, cy + sy * (hgt + 0.08), z + 0.05), frame)
	_b.box_at(Vector3(0.015, hgt - 0.36, 0.01), Vector3(cx, cy - 0.13, z + 0.05), PubKit.flat(Color(0.3, 0.3, 0.35), 0.5))
	var title := PubKit.label("AFFECTION  ON  TAP", 64, Color(1.0, 0.78, 0.4), 0.0042, DeepFieldTheme.display_font())
	title.position = Vector3(cx, cy + hgt * 0.5 - 0.14, z + 0.06)
	_root.add_child(title)
	var per_col := int(ceil(float(menu_lines.size()) / 2.0))
	var line_h := (hgt - 0.36) / float(maxi(per_col, 1))
	for i in menu_lines.size():
		var col := i / per_col
		var row := i % per_col
		var left := cx - mw * 0.5 + 0.16 + float(col) * (mw * 0.5)
		var ly := cy + hgt * 0.5 - 0.36 - float(row) * line_h
		var name_l := PubKit.label(String(menu_lines[i][0]).to_upper(), 30, Color(0.95, 0.95, 1.0), 0.0042, DeepFieldTheme.display_font())
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.position = Vector3(left, ly, z + 0.06)
		name_l.offset = Vector2(0, 0)
		_root.add_child(name_l)
		var price := PubKit.label(String(menu_lines[i][1]), 22, NEON_B.lightened(0.35), 0.0042, DeepFieldTheme.mono_font())
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.position = Vector3(left + mw * 0.5 - 0.3, ly - 0.005, z + 0.06)
		_root.add_child(price)
	# A neon cocktail glass to the board's left, a sun to its right (Sunny's mark).
	var cg := PubKit.neon(NEON_A, 4.5)
	neon_mats.append(cg)
	var gx := cx - mw * 0.5 - 0.75
	var gy := 3.7
	var gz := IN_BACK + 0.06
	for sx in [-1.0, 1.0]:
		_b.box_at(Vector3(0.025, 0.42, 0.025), Vector3(gx + sx * 0.11, gy + 0.1, gz), cg, Vector3(0, 0, sx * 0.55))
	_b.box_at(Vector3(0.5, 0.025, 0.025), Vector3(gx, gy + 0.29, gz), cg)
	_b.box_at(Vector3(0.025, 0.3, 0.025), Vector3(gx, gy - 0.25, gz), cg)
	_b.box_at(Vector3(0.26, 0.025, 0.025), Vector3(gx, gy - 0.4, gz), cg)
	PubKit.mesh_instance(PubKit.sphere(0.04), Vector3(gx + 0.12, gy + 0.33, gz), PubKit.neon(Color(0.5, 1.0, 0.3), 5.0), _root)


# --- Seating ----------------------------------------------------------------------

func _seating() -> void:
	# Two sofa lounges either side of the door: a sofa against the front wall,
	# one facing it across a low table, on a rug.
	for i in lounges.size():
		var c: Vector3 = lounges[i]
		PubKit.place(_root, "sofa_02", c + Vector3(0, 0, 1.1), 180.0, 1.0)
		PubKit.place(_root, "sofa_02", c + Vector3(0, 0, -1.1), 0.0, 1.0)
		for sz in [1.1, -1.1]:
			_collider(Vector3(1.85, 0.75, 0.85), c + Vector3(0, 0.37, sz))
		PubKit.place(_root, "round_wooden_table_01", c, 15.0 + i * 50.0, Vector3(0.5, 0.48, 0.5))
		_drink(c + Vector3(0.1, 0.48, 0.08))
		_drink(c + Vector3(-0.12, 0.48, -0.06))
		_candle(c + Vector3(0.0, 0.48, -0.12))
		_rug(Vector3(c.x, 0.004, c.z - 0.05), Vector2(2.8, 3.3), i == 1)
	# The booth row on the left wall: high-backed benches back to back.
	var upholstery := PubKit.flat(Color(0.42, 0.07, 0.08), 0.5)
	var depth := 1.4
	var bx := booth_x
	var bench_zs: Array[float] = []
	for zc in booths:
		bench_zs.append(zc - 0.78)
		bench_zs.append(zc + 0.78)
	for i in bench_zs.size():
		var z: float = bench_zs[i]
		var facing := 1.0 if i % 2 == 0 else -1.0
		var back_z := z - facing * 0.2
		_b.box_at(Vector3(depth, 0.4, 0.5), Vector3(bx, 0.2, z), _wood)
		_b.box_at(Vector3(depth - 0.06, 0.1, 0.46), Vector3(bx, 0.45, z + facing * 0.02), upholstery)
		_b.box_at(Vector3(depth - 0.06, 0.66, 0.12), Vector3(bx, 0.82, back_z), upholstery)
		_b.box_at(Vector3(depth, 0.06, 0.16), Vector3(bx, 1.18, back_z), _top)
	for zc in booths:
		_b.box_at(Vector3(1.15, 0.06, 0.78), Vector3(bx + 0.05, 0.74, zc), _top)
		_b.box_at(Vector3(0.12, 0.7, 0.12), Vector3(bx + 0.15, 0.36, zc), _steel)
		_b.box_at(Vector3(0.5, 0.03, 0.5), Vector3(bx + 0.15, 0.015, zc), _steel)
		_candle(Vector3(bx - 0.35, 0.77, zc))
		_drink(Vector3(bx + 0.2, 0.77, zc + 0.15))
		_drink(Vector3(bx + 0.05, 0.77, zc - 0.2))
		_collider(Vector3(depth, 1.2, 2.1), Vector3(bx, 0.6, zc))
	# High-tops with a candle lantern and a drink or two.
	for p in hightops:
		PubKit.place(_root, "round_wooden_table_01", p, _rng.randf_range(0, 360), Vector3(0.7, 1.0, 0.7))
		_candle(p + Vector3(0, 1.0, 0))
		_drink(p + Vector3(0.22, 1.0, 0.1))
		_collider(Vector3(0.8, 1.0, 0.8), p + Vector3(0, 0.5, 0))


# --- Decor --------------------------------------------------------------------------

func _decor() -> void:
	# Darts on the right wall, in a plank surround, with a chalk scoreboard.
	PubKit.place(_root, "dartboard", dart_pos, -90.0, 1.0)
	_b.box_at(Vector3(0.04, 0.75, 1.1), dart_pos + Vector3(0.005, 0, 0), _wood)
	for k in 3:
		var dm := PubKit.mesh_instance(PubKit.cyl(0.004, 0.008, 0.14, 6), dart_pos + Vector3(-0.1, _rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.08, 0.08)),
			PubKit.flat(Color.from_hsv(_rng.randf(), 0.7, 0.8), 0.5), _root)
		dm.rotation_degrees.z = 90.0
	_b.box_at(Vector3(0.6, 0.006, 0.05), Vector3(dart_pos.x - 2.37, 0.003, dart_pos.z), PubKit.flat(Color(0.9, 0.7, 0.1), 0.6))
	_b.box_at(Vector3(0.03, 0.6, 0.5), Vector3(dart_pos.x - 0.01, dart_pos.y, dart_pos.z + 0.95), PubKit.flat(Color(0.06, 0.08, 0.07), 0.95))
	var score := PubKit.label("DARTS\nchalk your\nown score", 34, Color(0.9, 0.9, 0.85), 0.003)
	score.position = Vector3(dart_pos.x - 0.03, dart_pos.y, dart_pos.z + 0.95)
	score.rotation_degrees.y = -90.0
	_root.add_child(score)
	# Framed Dysnomia prints (flavour, no numbers on them).
	PubKit.poster(_root, Vector3(IN_X - 0.02, 2.2, -1.5 + 0.0), -90.0, Vector2(0.62, 0.9), "ERIS RISING", "over Dysnomia", 11, _brass)
	PubKit.poster(_root, Vector3(IN_X - 0.02, 2.2, 2.6), -90.0, Vector2(0.62, 0.9), "VISIT DYSNOMIA", "", 23, _brass)
	PubKit.poster(_root, Vector3(5.6, 2.25, IN_BACK + 0.02), 0.0, Vector2(0.66, 0.92), "AFFECTION FAIR", "rides all cycle", 37, _brass)
	PubKit.poster(_root, Vector3(6.6, 2.25, IN_BACK + 0.02), 0.0, Vector2(0.66, 0.92), "THE VOID", "bring a lantern", 41, _brass)
	PubKit.poster(_root, Vector3(-IN_X + 0.02, 2.35, 4.5), 90.0, Vector2(0.6, 0.85), "SUNNY'S", "est. on PulseChain", 53, _dark)
	for i in 3:
		PubKit.poster(_root, Vector3(2.0 + i * 0.7, 2.0 + 0.05 * (i % 2), FRONT - 0.23), 180.0, Vector2(0.54, 0.78),
			["THE GWATS", "LOW-G KARAOKE", "POOL NIGHT"][i], ["every 7th block", "thursdays", "eight-ball, on the chain"][i], 60 + i, _dark)
	# Neon script over the booths, "GAME ROOM" over the pool table.
	var nm := MeshInstance3D.new()
	nm.mesh = PubKit.text_mesh("cold affection", 0.011, 0.02)  # the default font: the variable Inter has overlapping contours TextMesh rejects
	var nmat := PubKit.neon(NEON_A, 5.0)
	neon_mats.append(nmat)
	nm.material_override = nmat
	nm.position = Vector3(-IN_X + 0.06, 3.2, (booths[0] + booths[1]) * 0.5)
	nm.rotation_degrees.y = 90.0
	_root.add_child(nm)
	var gm := MeshInstance3D.new()
	gm.mesh = PubKit.text_mesh("GAME ROOM", 0.011, 0.02, DeepFieldTheme.display_font())
	var gmat := PubKit.neon(NEON_B, 4.5)
	neon_mats.append(gmat)
	gm.material_override = gmat
	gm.position = Vector3(IN_X - 0.06, 3.35, 1.6)
	gm.rotation_degrees.y = -90.0
	_root.add_child(gm)
	# Big plants in the corners.
	for p in [Vector3(-IN_X + 0.5, 0, FRONT - 0.6), Vector3(IN_X - 0.5, 0, FRONT - 0.6), Vector3(IN_X - 0.5, 0, BACK + 0.6)]:
		PubKit.place(_root, "potted_plant_04", p, _rng.randf_range(0, 360), 3.4)


func _drink(pos: Vector3) -> void:
	var cols := [Color(1.0, 0.7, 0.2), Color(0.95, 0.3, 0.5), Color(0.3, 0.9, 0.5), Color(0.45, 0.6, 1.0)]
	var c: Color = cols[_rng.randi() % cols.size()]
	var h := _rng.randf_range(0.11, 0.17)
	_b.add_mesh(PubKit.cyl(0.04, 0.034, h, 12), Transform3D(Basis(), pos + Vector3(0, h * 0.5, 0)), PubKit.drinkware())
	_b.add_mesh(PubKit.cyl(0.034, 0.03, h * 0.7, 12), Transform3D(Basis(), pos + Vector3(0, h * 0.36, 0)), PubKit.glass(Color(c.r, c.g, c.b, 0.85), c, 0.6))


func _candle(pos: Vector3) -> void:
	_b.add_mesh(PubKit.cyl(0.045, 0.05, 0.12, 10), Transform3D(Basis(), pos + Vector3(0, 0.06, 0)), PubKit.glass(Color(1.0, 0.6, 0.3, 0.7), Color(1.0, 0.55, 0.2), 3.0))


func _rug(pos: Vector3, size: Vector2, alt: bool) -> void:
	var q := PlaneMesh.new()
	q.size = size
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/pub_rug.gdshader")
	if alt:
		sm.set_shader_parameter("base_color", Color(0.08, 0.12, 0.2))
		sm.set_shader_parameter("pattern_color", NEON_B.lightened(0.1))
		sm.set_shader_parameter("border_color", Color(0.3, 0.06, 0.05))
	else:
		sm.set_shader_parameter("base_color", Color(0.3, 0.06, 0.05))
		sm.set_shader_parameter("pattern_color", Color(0.85, 0.62, 0.3))
	sm.set_shader_parameter("size_m", size)
	PubKit.mesh_instance(q, pos, sm, _root)


# --- Light --------------------------------------------------------------------------

func _lights() -> void:
	# Pendants over the bar ends (none hangs in front of the board), and over the pool table.
	_pendant(Vector3(-4.4, 3.05, COUNTER_Z + 0.35), 0.8)
	_pendant(Vector3(2.6, 3.05, COUNTER_Z + 0.35), 0.8)
	_pendant(Vector3(3.4, 3.2, 1.8), 0.85)
	_pendant(Vector3(4.6, 3.2, 1.8), 0.85)
	bar_flash = _add_light(Vector3(-2.8, 2.2, COUNTER_Z + 0.4), WARM, 1.6, 6.0)
	_add_light(Vector3(1.6, 2.2, COUNTER_Z + 0.5), WARM, 1.5, 6.0)
	_add_light(Vector3(BACKBAR_X, 2.5, BACK + 1.4), Color(1.0, 0.8, 0.5), 1.0, 4.5)
	_add_light(Vector3(4.0, 2.4, 1.8), Color(1.0, 0.86, 0.66), 1.8, 6.5)
	_add_light(Vector3(lounges[0].x + 0.6, 2.2, lounges[0].z - 0.4), WARM.lerp(NEON_A, 0.25), 1.4, 6.0)
	_add_light(Vector3(lounges[1].x - 0.6, 2.2, lounges[1].z - 0.4), WARM.lerp(NEON_B, 0.25), 1.4, 6.0)
	_add_light(Vector3(-7.4, 2.3, 3.6), WARM.lerp(NEON_A, 0.2), 1.3, 6.0)
	_add_light(Vector3(-7.6, 2.4, -1.4), Color(0.8, 0.85, 1.0), 0.9, 5.5)  # the arcade corner
	for sx in [-1.0, 1.0]:  # rafter uplights: the ceiling isn't a black void
		var ul := _add_light(Vector3(sx * W * 0.45, H - 0.35, 0.0), Color(1.0, 0.72, 0.48), 1.1, 9.0)
		ul.omni_attenuation = 0.8
	_crystal_chandelier(chandelier_at)
	_fairy_lights()


## Dysnomia's accent: a brass hoop hung with glowing cyan and violet crystal prisms.
func _crystal_chandelier(pos: Vector3) -> void:
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
		var top := Vector3(pos.x, H - 0.3, pos.z)
		var len := foot.distance_to(top)
		cb.add_mesh(PubKit.cyl(0.006, 0.006, len, 4), Transform3D(Basis(Quaternion(Vector3.UP, (top - foot) / len)), (foot + top) * 0.5), _dark)
	var cyan := PubKit.glass(Color(0.3, 0.9, 1.0, 0.75), Color(0.25, 0.85, 1.0), 3.5)
	var violet := PubKit.glass(Color(0.7, 0.4, 1.0, 0.75), Color(0.6, 0.3, 1.0), 3.0)
	neon_mats.append(cyan)
	neon_mats.append(violet)
	var n := 22
	for i in n:
		var a := float(i) * TAU / float(n)
		var r := 0.53 if i % 2 == 0 else 0.3
		var l := _rng.randf_range(0.22, 0.55) * (1.0 if i % 2 == 0 else 1.3)
		var p := pos + Vector3(cos(a) * r, -l * 0.5 - 0.02, sin(a) * r)
		cb.add_mesh(PubKit.cyl(0.035, 0.0, l, 6), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p), cyan if i % 3 != 0 else violet)
	cb.add_mesh(PubKit.cyl(0.08, 0.0, 0.8, 6), Transform3D(Basis(), pos + Vector3(0, -0.42, 0)), cyan)
	cb.commit(_root, "Chandelier")
	_add_light(pos + Vector3(0, -0.5, 0), Color(0.45, 0.85, 1.0), 0.9, 4.5)


## Warm bulbs strung between the tie beams, criss-crossing the room (one MultiMesh).
func _fairy_lights() -> void:
	var pts: Array[Vector3] = []
	var y := H - 0.32
	var n_bays := 5
	for i in n_bays:
		var z0 := lerpf(BACK + 0.5, FRONT - 0.5, float(i) / float(n_bays))
		var z1 := lerpf(BACK + 0.5, FRONT - 0.5, float(i + 1) / float(n_bays))
		for strand in 2:
			var xa := -W + 0.5 if strand == 0 else W - 0.5
			var a := Vector3(xa, y, z0)
			var b := Vector3(-xa, y, z1)
			var cnt := int(a.distance_to(b) / 0.5)
			for k in range(1, cnt):
				var t := float(k) / float(cnt)
				var p := a.lerp(b, t)
				p.y -= sin(t * PI) * 0.7
				pts.append(p)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PubKit.sphere(0.035, 8)
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FairyLights"
	mmi.multimesh = mm
	var bulb := PubKit.neon(Color(1.0, 0.7, 0.4), 6.0)
	neon_mats.append(bulb)
	mmi.material_override = bulb
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)


func _pendant(pos: Vector3, s: float) -> void:
	PubKit.place(_root, "hanging_industrial_lamp", pos, _rng.randf_range(0, 360), s)
	var top := H - 0.3
	if top > pos.y + 0.05:
		_b.add_mesh(PubKit.cyl(0.008, 0.008, top - pos.y, 4), Transform3D(Basis(), Vector3(pos.x, (top + pos.y) * 0.5, pos.z)), _dark)
	_b.add_mesh(PubKit.sphere(0.06), Transform3D(Basis(), pos + Vector3(0, -1.22 * s, 0)), PubKit.neon(Color(1.0, 0.8, 0.55), 8.0))


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


func _collider(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	_root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
