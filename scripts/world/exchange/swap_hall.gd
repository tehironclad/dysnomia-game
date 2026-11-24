class_name SwapHall
extends Node3D
## The Swap Hall: each territory's trading floor for PLS ⇄ Dysnomia tokens on
## PulseX. Built from territory state only (the Development tier) and the pools'
## public reserves, so every viewer sees the same hall and the same boards:
##   Wild (tier 0)  a surveyed lot: a terrace, survey stakes, a sign, and two field
##                  terminals (the swap counter and a YUE desk) that already work;
##   Outpost+       the hall: a curved glass front under a wing roof, a price pylon,
##                  a ticker over the door, a quote wall and a hanging four-face board
##                  inside (PulseX getReserves at one block), the swap counter, and a
##                  YUE Exchange counter when the territory has no tower (Settlement+
##                  towers carry the YUE Exchange in their sky lobby instead).
## The site is found like the fair's and the pad's (on land, flattest, clear of the
## Core's landmarks, the skyline ring, the fair, the pad, the tower and its ring), on
## a terrace in the terrain's own material so it reads as built ground.
## Local frame: +Z faces the Core (the door).

signal use_swap
signal use_yue

const RADIUS := 20.0             ## the terrace
const W := 24.0                  ## hall width (x)
const BACK := -8.0               ## back wall z
const SIDE_FRONT := 2.0          ## where the side walls meet the curved glass front
const BULGE := 6.0               ## how far the front arcs out at the middle (to z = 8)
const H := 8.0                   ## wall height
const DOOR_HALF := 2.6
const REACH := 2.4
const BOARD_EVERY_S := 90.0
const PREFER_FRAC := Vector2(0.3, -0.08)  ## preferred spot as a fraction of the map size (east, a little north)

var site: Dictionary = {}
var tier := -1
var board: Dictionary = {}       ## PulseX.read_board() for the boards (no wallet: same for everyone)
var tower_note := ""             ## where the YUE Exchange is when a tower carries it ("" = this hall's counter)
var _qing := ""
var _asset := ""
var _player: CharacterBody3D
var _hud: Node
var _tint := Color("#7fd3ff")
var _ground_mat: Material
var _height_fn: Callable
var _built: Node3D
var _wall_board: Label3D
var _hang: Array[Label3D] = []
var _ticker: Label3D
var _pylon: Label3D
var _yue_sign: Label3D
var _ticker_text := ""
var _ticker_i := 0
var _t := 0.0
var _next_read := 0.0
var _hang_i := 0
var _focus := ""
var zones := {}                  ## name → local Vector3 where Use works


## Pure: the hall's site. `others`: [[centre, radius], …] (fair, pad, tower plaza, ring).
static func find_site(height_fn: Callable, others: Array) -> Dictionary:
	var avoid: Array = [[Vector2.ZERO, 70.0 + RADIUS]]
	for k in LandmarkPlan.KEEP_CLEAR:
		avoid.append([k, RADIUS + 22.0])
	for o in others:
		avoid.append([o[0], float(o[1]) + RADIUS + 8.0])
	return LandmarkPlan.find_site(height_fn, RADIUS, avoid, PREFER_FRAC * JuliaHeightfield.SIZE_M)


func setup(qing: String, asset: String, hud: Node, player: CharacterBody3D, height_fn: Callable, tint: Color, ground_mat: Material, others: Array) -> void:
	_qing = qing.to_lower()
	_asset = asset.to_lower()
	_hud = hud
	_player = player
	_height_fn = height_fn
	_tint = tint
	_ground_mat = ground_mat
	site = find_site(height_fn, others)
	var at: Vector2 = site.get("at", PREFER_FRAC * JuliaHeightfield.SIZE_M)
	position = Vector3(at.x, float(site.get("top", 0.0)) + 0.12, at.y)
	# Face the Core
	rotation.y = atan2(-at.x, -at.y)
	_build_terrace(position.y - float(site.get("low", position.y)) + 1.5)
	print("[SwapHall] site %s (on land: %s, relief %.1f m)" % [str(at), site.get("ok"), float(site.get("top", 0.0)) - float(site.get("low", 0.0))])


func set_tier(t: int, p_tower_note: String) -> void:
	tower_note = p_tower_note
	var lot := t <= 0
	if tier >= 0 and (tier <= 0) == lot:
		tier = t
		_update_yue_sign()
		return
	tier = t
	if _built:
		_built.queue_free()
	_built = Node3D.new()
	_built.name = "Lot" if lot else "Hall"
	add_child(_built)
	_hang.clear()
	zones.clear()
	if lot:
		_build_lot()
	else:
		_build_hall()
	_update_yue_sign()
	_paint_boards()
	if _next_read <= _t:
		_read_board()


# --- Reads ------------------------------------------------------------------------

func _read_board() -> void:
	_next_read = _t + BOARD_EVERY_S
	var toks: Array = PulseX.TOKENS.duplicate()
	toks.append([_qing, ""])
	if _asset != "":
		toks.append([_asset, ""])
	var b: Dictionary = await PulseX.read_board(toks, "")
	if b.get("ok", false):
		board = b
		print("[SwapHall] pools read at block %d" % b["block"])
	elif board.is_empty():
		board = b  # an outage shows "—", never a made-up price
	_paint_boards()


## The quote wall's text: one line per token, from the reserves at one block.
static func wall_text(b: Dictionary, qing: String) -> String:
	if b.is_empty():
		return "LIVE FROM THE POOLS\nreading PulseX…"
	if not b.get("ok", false):
		return "LIVE FROM THE POOLS\n— the chain did not answer (%s)" % String(b.get("error", ""))
	var lines: Array = ["LIVE FROM THE POOLS · PulseX getReserves · block %s" % TokenFormat.group(str(b["block"])), ""]
	lines.append("%-16s %16s  %14s  %s" % ["TOKEN", "PLS EACH", "WPLS DEEP", "DEX"])
	for t in b["tokens"]:
		var nm := String(t["name"]).left(15) + ("*" if t["address"] == qing else "")
		if t["best"] == "" or t["decimals"] < 0:
			lines.append("%-16s %16s" % [nm, "no pool on PulseX" if t["decimals"] >= 0 else "—"])
			continue
		var p: Dictionary = t["pools"][t["best"]]
		lines.append("%-16s %16s  %14s  %s" % [nm, PulseX.fmt(PulseX.price_wei(p["wpls"], p["token"], t["decimals"]), 18, 4),
			PulseX.fmt(p["wpls"], 18, 1), t["best"] + (" +" + ("V1" if t["best"] == "V2" else "V2") if t["pools"].size() > 1 else "")])
	lines.append("")
	lines.append("* this territory's own token · mid price from the deeper pool · 0.29% fee per swap")
	return "\n".join(lines)


## A price face (hanging board / pylon): the i-th pooled token.
static func face_text(b: Dictionary, i: int) -> String:
	if not b.get("ok", false):
		return "PulseX\n—"
	var pooled: Array = b["tokens"].filter(func(t): return t["best"] != "" and t["decimals"] >= 0)
	if pooled.is_empty():
		return "PulseX\nno pools"
	var t: Dictionary = pooled[posmod(i, pooled.size())]
	var p: Dictionary = t["pools"][t["best"]]
	return "%s\n%s PLS\n%s · block %s" % [String(t["name"]).to_upper(), PulseX.fmt(PulseX.price_wei(p["wpls"], p["token"], t["decimals"]), 18, 4), t["best"], TokenFormat.group(str(b["block"]))]


static func ticker_text(b: Dictionary) -> String:
	if not b.get("ok", false):
		return "   PULSEX · prices —   "
	var parts: Array = []
	for t in b["tokens"]:
		if t["best"] == "" or t["decimals"] < 0:
			continue
		var p: Dictionary = t["pools"][t["best"]]
		parts.append("%s %s PLS" % [String(t["symbol"]), PulseX.fmt(PulseX.price_wei(p["wpls"], p["token"], t["decimals"]), 18, 4)])
	return "   ◆   ".join(PackedStringArray(parts)) + "   ◆   block %s   ◆   " % TokenFormat.group(str(b["block"]))


func _paint_boards() -> void:
	if _wall_board:
		_wall_board.text = wall_text(board, _qing)
	for i in _hang.size():
		_hang[i].text = face_text(board, _hang_i + i)
	if _pylon:
		_pylon.text = face_text(board, _hang_i + 4)
	_ticker_text = ticker_text(board)


# --- Building ---------------------------------------------------------------------

func _build_terrace(depth: float) -> void:
	var slope := clampf(depth * 2.2, 3.0, 12.0)
	var m := CylinderMesh.new()
	m.top_radius = RADIUS
	m.bottom_radius = RADIUS + slope
	m.height = depth
	m.radial_segments = 56
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.name = "Terrace"
	mi.mesh = m
	mi.material_override = _ground_mat if _ground_mat else Landmark._metal(Color(0.45, 0.45, 0.48))
	mi.position = Vector3(0, -depth * 0.5 - 0.02, 0)
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = m.create_convex_shape()
	cs.position = mi.position
	body.add_child(cs)
	add_child(body)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = RADIUS - 0.1
	t.outer_radius = RADIUS + 0.1
	t.rings = 80
	ring.mesh = t
	ring.material_override = Landmark._glow(_tint, 1.2)
	ring.scale = Vector3(1, 0.25, 1)
	ring.position.y = 0.03
	add_child(ring)


func _box(size: Vector3, at: Vector3, mat: Material, yaw: float = 0.0, solid: bool = false, parent: Node3D = null) -> MeshInstance3D:
	var p := parent if parent else _built
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.rotation.y = yaw
	mi.material_override = mat
	p.add_child(mi)
	if solid:
		Solid.box(p, size, at, yaw)
	return mi


func _label(text: String, at: Vector3, px: float, size: int, color: Color, mono: bool = true, yaw: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = DeepFieldTheme.mono_font() if mono else DeepFieldTheme.display_font()
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.position = at
	l.rotation.y = yaw
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_built.add_child(l)
	return l


static func _front_z(x: float) -> float:
	## The curved glass front: z along an ellipse from the side walls to the bulge.
	var f := clampf(absf(x) / (W * 0.5), 0.0, 1.0)
	return SIDE_FRONT + BULGE * sqrt(maxf(0.0, 1.0 - f * f))


func _build_hall() -> void:
	# Satin panels, not mirror metal: a metal wall shows the (black) sky it reflects, so the hall
	# read as a dark box at Low quality (no SSIL/SSAO); these take the hall's own lights.
	var wall := Landmark._metal(Color(0.42, 0.44, 0.5))
	wall.metallic = 0.12
	wall.roughness = 0.55
	var dark := Landmark._metal(Color(0.07, 0.075, 0.09))
	dark.metallic = 0.4
	dark.roughness = 0.15
	var glow := Landmark._glow(_tint, 2.2)
	var gold := Landmark._glow(Color("#ffd27a"), 2.0)
	# Floor: a polished trading floor with lit lanes
	_box(Vector3(W, 0.12, (_front_z(0) - BACK)), Vector3(0, 0.06, (BACK + _front_z(0)) * 0.5), dark)
	for k in range(-2, 3):
		_box(Vector3(0.08, 0.02, 9.0), Vector3(k * 3.6, 0.13, 0.5), Landmark._glow(_tint, 0.9))
	# Back and side walls (solid), a band of light at the top
	_box(Vector3(W, H, 0.5), Vector3(0, H * 0.5, BACK), wall, 0.0, true)
	for s in [-1.0, 1.0]:
		var side_len := SIDE_FRONT - BACK
		_box(Vector3(0.5, H, side_len), Vector3(s * W * 0.5, H * 0.5, (BACK + SIDE_FRONT) * 0.5), wall, 0.0, true)
		_box(Vector3(0.12, 0.25, side_len), Vector3(s * (W * 0.5 + 0.28), H - 0.6, (BACK + SIDE_FRONT) * 0.5), glow)
	# The curved glass front: panels along the arc, the door open in the middle
	var n := 10
	var glass := Landmark._glass(0.18)
	for i in n:
		var x0 := lerpf(-W * 0.5, W * 0.5, float(i) / n)
		var x1 := lerpf(-W * 0.5, W * 0.5, float(i + 1) / n)
		var xm := (x0 + x1) * 0.5
		if absf(xm) < DOOR_HALF:
			continue
		var a := Vector2(x0, _front_z(x0))
		var b := Vector2(x1, _front_z(x1))
		var mid := (a + b) * 0.5
		var yaw := -atan2(b.y - a.y, b.x - a.x)
		_box(Vector3(a.distance_to(b) + 0.05, H - 0.4, 0.12), Vector3(mid.x, (H - 0.4) * 0.5, mid.y), glass, yaw, true)
		_box(Vector3(0.14, H, 0.14), Vector3(a.x, H * 0.5, a.y), glow)  # mullion
	# Door frame (gold), the door gap stays open
	for s in [-1.0, 1.0]:
		_box(Vector3(0.18, 4.2, 0.3), Vector3(s * DOOR_HALF, 2.1, _front_z(DOOR_HALF)), gold)
	_box(Vector3(DOOR_HALF * 2.0 + 0.3, 0.18, 0.3), Vector3(0, 4.2, _front_z(0)), gold)
	_box(Vector3(DOOR_HALF * 2.0, H - 4.6, 0.12), Vector3(0, 4.4 + (H - 4.6) * 0.5, _front_z(0)), glass)
	# The wing roof: a slab tilted up toward the front, overhanging the glass
	var roof := Node3D.new()
	# (At 5° from H + 0.2 its back edge dipped ~0.9 m into the hall, cutting the quote wall's
	# top lines and light band; 2° from H + 0.55 keeps its underside at the back wall's top.)
	roof.position = Vector3(0, H + 0.55, 0.5)
	roof.rotation.x = deg_to_rad(-2.0)
	_built.add_child(roof)
	_box(Vector3(W + 3.0, 0.5, 19.0), Vector3(0, 0, 0.5), Landmark._metal(Color(0.22, 0.23, 0.27)), 0.0, false, roof)
	_box(Vector3(W + 3.1, 0.12, 0.2), Vector3(0, -0.05, 10.0), glow, 0.0, false, roof)
	Solid.box(_built, Vector3(W, 0.5, 18.0), Vector3(0, H + 0.55, 0.0))
	# The roof lantern: a glowing glass box over the trading floor
	_box(Vector3(12.0, 2.2, 6.0), Vector3(0, H + 1.6, -1.5), Landmark._glass(0.35))
	_box(Vector3(12.2, 0.1, 6.2), Vector3(0, H + 2.75, -1.5), glow)
	# Columns either side of the door (the kit's Astra column)
	for s in [-1.0, 1.0]:
		var c := PlaceBase.load_piece("Column_Astra")
		c.position = Vector3(s * (DOOR_HALF + 1.3), 0.1, _front_z(DOOR_HALF + 1.3) + 0.6)
		c.scale = Vector3(1.2, 1.6, 1.2)
		_built.add_child(c)
		Solid.cylinder(_built, 0.45, 6.0, c.position)
	# The sign and the ticker over the door
	var fz := _front_z(0) + 0.35
	var title := _label("SWAP HALL", Vector3(0, H - 1.25, fz), 0.02, 120, DeepFieldTheme.INK, false)
	title.outline_size = 14
	_ticker = _label("", Vector3(0, H - 2.55, fz), 0.009, 48, Color("#ffd27a"))
	_box(Vector3(10.6, 0.7, 0.08), Vector3(0, H - 2.55, fz - 0.06), Landmark._metal(Color(0.03, 0.03, 0.04)))
	_label("PulseX · PLS ⇄ Dysnomia tokens · prices from the pools, each with its block", Vector3(0, 4.75, fz + 0.05), 0.0065, 40, Color(1, 1, 1, 0.8))
	# The price pylon at the corner: a slim tower with a face that cycles the tokens
	var pz := SIDE_FRONT + 3.0
	var px := W * 0.5 + 2.6
	_box(Vector3(1.6, 14.0, 1.6), Vector3(px, 7.0, pz), wall, 0.0, true)
	_box(Vector3(1.7, 0.15, 1.7), Vector3(px, 14.05, pz), gold)
	for k in 3:
		_box(Vector3(1.66, 0.08, 1.66), Vector3(px, 3.0 + k * 4.0, pz), glow)
	_pylon = _label("", Vector3(px, 10.5, pz + 0.85), 0.008, 64, Color("#ffd27a"))
	_label("S\nW\nA\nP", Vector3(px, 5.4, pz + 0.85), 0.016, 96, _tint.lerp(Color.WHITE, 0.5), false)
	# Inside: the quote wall on the back wall
	_box(Vector3(W - 3.0, 6.4, 0.1), Vector3(0, 4.45, BACK + 0.3), Landmark._glow(Color(0.02, 0.03, 0.05), 1.0))
	_box(Vector3(W - 2.8, 0.08, 0.12), Vector3(0, 7.7, BACK + 0.32), glow)
	# A left-aligned Label3D starts at its position: the ~9.5 m block sits mid-wall, under the
	# light band, top-aligned so a long token list grows down the screen, not off its top.
	_wall_board = _label("", Vector3(-4.9, 7.45, BACK + 0.38), 0.0042, 64, DeepFieldTheme.INK)
	_wall_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_wall_board.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_wall_board.outline_size = 10
	_wall_board.outline_modulate = Color(0, 0, 0.02, 0.95)
	# Ceiling light panels over the floor (self-lit, so the hall reads bright at any quality)
	for k in [-1.0, 1.0]:
		_box(Vector3(6.0, 0.06, 1.2), Vector3(k * 5.5, H - 0.08, -1.0), Landmark._glow(Color(1.0, 0.97, 0.92), 1.4))
	# The hanging four-face board over the floor
	var hang := Node3D.new()
	hang.position = Vector3(0, 5.9, 2.6)
	_built.add_child(hang)
	_box(Vector3(4.2, 2.2, 4.2), Vector3.ZERO, Landmark._metal(Color(0.03, 0.03, 0.04)), 0.0, false, hang)
	_box(Vector3(4.3, 0.08, 4.3), Vector3(0, 1.12, 0), glow, 0.0, false, hang)
	_box(Vector3(4.3, 0.08, 4.3), Vector3(0, -1.12, 0), Landmark._metal(Color(0.1, 0.11, 0.13)), 0.0, false, hang)
	for k in 4:
		var yaw := PI * 0.5 * k
		var l := Label3D.new()
		l.font = DeepFieldTheme.mono_font()
		l.font_size = 64
		l.pixel_size = 0.0068
		l.modulate = Color("#ffd27a")
		l.outline_size = 4
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector3(sin(yaw), 0, cos(yaw)) * 2.12
		l.rotation.y = yaw
		hang.add_child(l)
		_hang.append(l)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.04, H - 7.0, 0.04), Vector3(s * 1.8, 7.0 + (H - 7.0) * 0.5, 2.6), Landmark._metal())
	# The swap counter: a long desk with three terminals behind it
	_box(Vector3(10.0, 1.1, 1.2), Vector3(0, 0.55, -4.4), wall, 0.0, true)
	_box(Vector3(10.1, 0.06, 1.3), Vector3(0, 1.13, -4.4), gold)
	for k in 3:
		var term := PlaceBase.load_piece("Prop_Computer")
		term.position = Vector3(-3.4 + k * 3.4, 0.1, -5.5)
		_built.add_child(term)
	# On the desk's front face (it used to float over the desk, across the terminals)
	_label("SWAP COUNTER · PulseX", Vector3(0, 0.62, -3.77), 0.0075, 56, DeepFieldTheme.ICE, false)
	zones["swap"] = Vector3(0, 0, -3.1)
	# The YUE counter (or the sign saying where the YUE Exchange is)
	var yx := W * 0.5 - 1.6
	_box(Vector3(1.2, 1.1, 4.0), Vector3(yx, 0.55, -3.0), wall, 0.0, true)
	_box(Vector3(1.3, 0.06, 4.1), Vector3(yx, 1.13, -3.0), Landmark._glow(Color("#ff8fd0"), 1.8))
	_yue_sign = _label("", Vector3(yx - 0.7, 2.8, -3.0), 0.0075, 48, Color("#ffb8e6"), true, -PI * 0.5)
	# Lights
	for p in [Vector3(-6, H - 1.0, -2), Vector3(6, H - 1.0, -2), Vector3(0, H - 1.0, 4), Vector3(0, 2.5, -1.5)]:
		var o := OmniLight3D.new()
		o.position = p
		o.light_color = Color(1.0, 0.96, 0.9).lerp(_tint, 0.25)
		o.light_energy = 6.0
		o.omni_range = 20.0
		_built.add_child(o)
	var sign_l := OmniLight3D.new()
	sign_l.position = Vector3(0, H - 2.0, _front_z(0) + 2.5)
	sign_l.light_color = Color("#ffd27a")
	sign_l.light_energy = 1.6
	sign_l.omni_range = 10.0
	_built.add_child(sign_l)


func _build_lot() -> void:
	## The surveyed lot: stakes and tape around the footprint, a sign, two terminals.
	var stake := Landmark._glow(Color("#ffd27a"), 1.6)
	var corners := [Vector2(-W * 0.5, BACK), Vector2(W * 0.5, BACK), Vector2(W * 0.5, SIDE_FRONT + BULGE), Vector2(-W * 0.5, SIDE_FRONT + BULGE)]
	for i in 4:
		var c: Vector2 = corners[i]
		var d: Vector2 = corners[(i + 1) % 4]
		_box(Vector3(0.12, 1.4, 0.12), Vector3(c.x, 0.7, c.y), stake)
		var mid := (c + d) * 0.5
		_box(Vector3(c.distance_to(d), 0.05, 0.03), Vector3(mid.x, 1.1, mid.y), Landmark._glow(_tint, 1.4, 0.8), -atan2(d.y - c.y, d.x - c.x))
	_label("SWAP HALL · SURVEYED LOT\nopens at Outpost development (any Hypobar here)\nthe counters below already trade, live", Vector3(0, 6.4, -2.0), 0.009, 56, DeepFieldTheme.INK, false)
	for k in 2:
		var term := PlaceBase.load_piece("Prop_Computer")
		term.position = Vector3(-2.0 + k * 4.0, 0.0, 3.0)
		_built.add_child(term)
		Solid.wrap(term)
	_label("SWAP · PulseX", Vector3(-2.0, 2.1, 3.6), 0.007, 48, DeepFieldTheme.ICE, false)
	_yue_sign = _label("", Vector3(2.0, 2.1, 3.6), 0.007, 48, Color("#ffb8e6"), false)
	zones["swap"] = Vector3(-2.0, 0, 4.4)
	zones["yue"] = Vector3(2.0, 0, 4.4)
	_wall_board = _label("", Vector3(-3.8, 2.9, -1.9), 0.003, 64, DeepFieldTheme.INK)
	_wall_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_box(Vector3(8.0, 4.8, 0.1), Vector3(0, 2.9, -2.05), Landmark._glow(Color(0.02, 0.03, 0.05), 1.0))
	for s in [-1.0, 1.0]:
		_box(Vector3(0.12, 5.4, 0.12), Vector3(s * 4.05, 2.7, -2.05), Landmark._metal())


func _update_yue_sign() -> void:
	if _yue_sign == null:
		return
	if tower_note != "":
		_yue_sign.text = "YUE EXCHANGE\nHong / Hung at fixed rates\n→ %s" % tower_note
		zones.erase("yue")
	else:
		_yue_sign.text = "YUE EXCHANGE\nHong / Hung at fixed rates\nany YUE's stock"
		if tier > 0:
			zones["yue"] = Vector3(W * 0.5 - 2.9, 0, -3.0)


# --- Use ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _t >= _next_read and tier >= 0 and _player_near(160.0):
		_read_board()
	if _ticker and _ticker_text != "":
		_ticker_i = int(_t * 6.0) % _ticker_text.length()
		var s := _ticker_text + _ticker_text
		_ticker.text = s.substr(_ticker_i, 58)
	var hi := int(_t / 6.0)
	if hi != _hang_i:
		_hang_i = hi
		for i in _hang.size():
			_hang[i].text = face_text(board, _hang_i + i)
		if _pylon:
			_pylon.text = face_text(board, _hang_i + 4)
	if _player == null or not _player.is_physics_processing():
		_set_focus("")
		return
	var lp := to_local(_player.global_position)
	var z := ""
	for k in zones:
		var p: Vector3 = zones[k]
		if Vector2(lp.x - p.x, lp.z - p.z).length() < REACH and absf(lp.y) < 3.0:
			z = k
	_set_focus(z)


func _player_near(d: float) -> bool:
	return _player == null or _player.global_position.distance_to(global_position) < d or not _player.is_inside_tree()


func _set_focus(z: String) -> void:
	if z == _focus:
		return
	_focus = z
	if _hud == null:
		return
	var k := ControlsHelp.key_of("interact")
	match z:
		"":
			_hud.hide_prompt()
		"swap":
			_hud.show_prompt("%s  Swap counter: PLS ⇄ Dysnomia tokens on PulseX (quoted, simulated, you sign)" % k)
		"yue":
			_hud.show_prompt("%s  YUE Exchange: Hong / Hung QING tokens at fixed rates" % k)


func _unhandled_input(event: InputEvent) -> void:
	if _focus == "" or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	var f := _focus
	_set_focus("")
	_focus = "?"
	if f == "swap":
		use_swap.emit()
	else:
		use_yue.emit()


## A camera for screenshots: "out" (the exterior from the approach) or "in" (the floor).
func preview_transform(view: String) -> Transform3D:
	var t := Transform3D()
	if view == "in":
		t.origin = to_global(Vector3(-1.5, 2.0, 1.2))
		return t.looking_at(to_global(Vector3(0.4, 3.9, BACK)), Vector3.UP)
	t.origin = to_global(Vector3(-9.0, 4.0, 27.0))
	return t.looking_at(to_global(Vector3(0.5, 4.5, 0.0)), Vector3.UP)
