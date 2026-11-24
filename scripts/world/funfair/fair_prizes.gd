class_name FairPrizes
extends RefCounted
## The midway's prizes you can see. A paid round's score picks a tier (MidwayGame.PRIZES: a
## fraction of the game's par): a crystal trophy, a toy Upsilon rocket, a plush moon or a paper
## pennant. Each is a small model, built once per kind (one mesh, a surface per material).
##
## Prizes are LOCAL keepsakes, like the arcade's scores (`user://fair_prizes.cfg`, per QING):
## they prove nothing and claim nothing about the chain; every one carries the ticket it was won
## with. Each stall's shelf (`shelf` / `fill`) shows what it has left today (STOCK, restocked
## daily; a sold-out tier gives the next one down) and, on its bottom tier, the prizes this
## computer has won there, labelled. A practice round shows its prize but takes none home.

const PATH := "user://fair_prizes.cfg"
const KINDS := ["trophy", "rocket", "moon", "pennant"]
const STOCK := {"trophy": 1, "rocket": 2, "moon": 4, "pennant": 3}
const NAMES := {"trophy": "crystal trophy", "rocket": "toy Upsilon rocket", "moon": "plush moon", "pennant": "Dysnomia pennant"}
const SHELF_W := 0.9
const TIER_Y := [0.42, 0.84, 1.26, 1.68]  ## yours, pennants+moons, rockets, the trophy

static var _cfg: ConfigFile


static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg


static func today() -> String:
	return Time.get_date_string_from_system()


## Every prize won at this QING on this computer: [{kind, game, score, tx, at, day}], oldest first.
static func won(qing: String) -> Array:
	return _load().get_value(qing.to_lower(), "won", [])


## How many of `kind` the stall `game` has left today.
static func left(qing: String, game: String, kind: String) -> int:
	var n := int(STOCK.get(kind, 0))
	var d := today()
	for w in won(qing):
		if w.get("game", "") == game and w.get("kind", "") == kind and w.get("day", "") == d:
			n -= 1
	return maxi(0, n)


## The prize actually handed over for tier `kind` (a sold-out tier steps down; pennants never run out).
static func available(qing: String, game: String, kind: String) -> String:
	var i := KINDS.find(kind)
	if i < 0:
		return ""
	while i < KINDS.size() - 1 and left(qing, game, KINDS[i]) <= 0:
		i += 1
	return KINDS[i]


## Records a paid round's prize; returns the kind handed over ("" for none).
static func award(qing: String, game: String, kind: String, score: int, tx: String) -> String:
	var k := available(qing, game, kind)
	if k == "":
		return ""
	var list := won(qing)
	list.append({"kind": k, "game": game, "score": score, "tx": tx, "at": int(Time.get_unix_time_from_system()), "day": today()})
	_load().set_value(qing.to_lower(), "won", list)
	_cfg.save(PATH)
	return k


# --- The models ------------------------------------------------------------------------------

static func _mats(kind: String) -> Array:
	var gold := FairKit.paint(Color(1.0, 0.78, 0.3), 0.3, 0.6, 0.6)
	match kind:
		"trophy":
			return [gold, FairKit.pbr("dark_wooden_planks", Color(0.55, 0.4, 0.3), 2.0), FairKit.crystal_mat(Color(0.55, 0.85, 1.0))]
		"rocket":
			return [FairKit.paint(Color(0.94, 0.94, 0.9), 0.3, 0.2, 0.8), FairKit.paint(Color(0.88, 0.14, 0.2), 0.3, 0.3, 0.8),
				FairKit.glow(Color(0.45, 0.9, 1.0), 3.0, 1.5), gold]
		"moon":
			var plush: StandardMaterial3D = FairKit.paint(Color(0.93, 0.9, 0.98), 0.98, 0.0).duplicate()
			plush.rim_enabled = true
			plush.rim = 0.6
			plush.rim_tint = 0.7
			return [plush, FairKit.paint(Color(0.72, 0.68, 0.86), 0.98, 0.0), FairKit.paint(Color(0.06, 0.04, 0.08), 0.3, 0.0),
				FairKit.paint(Color(1.0, 0.6, 0.72), 0.95, 0.0)]
		_:
			return [FairKit.paint(Color(0.85, 0.75, 0.55), 0.7, 0.0), FairKit.paint(Color(0.45, 0.2, 0.85), 0.85, 0.0),
				FairKit.paint(Color(1.0, 0.82, 0.35), 0.8, 0.0)]


## [[mesh, transform, material index], …] merged into one ArrayMesh (a surface per material).
static func _merge(parts: Array, mats: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	for mi in mats.size():
		var st := SurfaceTool.new()
		var any := false
		for p in parts:
			if int(p[2]) != mi:
				continue
			var m: Mesh = p[0]
			for s in m.get_surface_count():
				st.append_from(m, s, p[1])
				any = true
		if any:
			st.commit(out)
			out.surface_set_material(out.get_surface_count() - 1, mats[mi])
	return out


static func mesh(kind: String) -> Mesh:
	return FairKit.cached_mesh("prize_" + kind, func() -> Mesh: return _build(kind))


static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


static func _build(kind: String) -> Mesh:
	var p: Array = []
	match kind:
		"trophy":  # ~0.36 m: a two-step plinth, a gold cup with handles, a crystal on top
			p.append([FairKit.box_mesh(Vector3(0.17, 0.05, 0.17)), _xf(Vector3(0, 0.025, 0)), 1])
			p.append([FairKit.box_mesh(Vector3(0.13, 0.04, 0.13)), _xf(Vector3(0, 0.07, 0)), 1])
			p.append([FairKit.box_mesh(Vector3(0.09, 0.022, 0.004)), _xf(Vector3(0, 0.026, 0.086)), 0])
			p.append([FairKit.cyl_mesh(0.016, 0.034, 0.07, 14), _xf(Vector3(0, 0.125, 0)), 0])
			p.append([FairKit.sphere_mesh(0.026, 10), _xf(Vector3(0, 0.165, 0)), 0])
			p.append([FairKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.06, 0.03), Vector2(0.078, 0.08),
				Vector2(0.086, 0.14), Vector2(0.09, 0.15), Vector2(0.08, 0.15), Vector2(0.07, 0.09), Vector2(0.0, 0.06)]), 24), _xf(Vector3(0, 0.175, 0)), 0])
			for sx in [-1.0, 1.0]:
				p.append([FairKit.torus_mesh(0.03, 0.042, 16, 6), _xf(Vector3(sx * 0.088, 0.27, 0), Vector3(0, 0, PI * 0.5)), 0])
			p.append([FairKit.crystal_mesh(), _xf(Vector3(0, 0.33, 0), Vector3(0, 0.4, 0), Vector3.ONE * 0.2), 2])
		"rocket":  # ~0.4 m: the Upsilon toy, white hull, red nose and fins, a porthole
			p.append([FairKit.lathe(PackedVector2Array([Vector2(0.0, 0.03), Vector2(0.045, 0.03), Vector2(0.058, 0.07), Vector2(0.06, 0.2),
				Vector2(0.052, 0.27)]), 20), _xf(Vector3.ZERO), 0])
			p.append([FairKit.lathe(PackedVector2Array([Vector2(0.052, 0.27), Vector2(0.04, 0.32), Vector2(0.02, 0.36), Vector2(0.0, 0.38)]), 20), _xf(Vector3.ZERO), 1])
			for i in 3:
				var a := TAU * i / 3.0
				p.append([FairKit.box_mesh(Vector3(0.008, 0.1, 0.07)), _xf(Vector3(sin(a) * 0.075, 0.075, cos(a) * 0.075), Vector3(0, a, 0)), 1])
			p.append([FairKit.cyl_mesh(0.03, 0.04, 0.03, 14), _xf(Vector3(0, 0.02, 0)), 3])
			p.append([FairKit.sphere_mesh(0.022, 12), _xf(Vector3(0, 0.2, 0.052), Vector3.ZERO, Vector3(1, 1, 0.5)), 2])
			p.append([FairKit.torus_mesh(0.022, 0.03, 14, 4), _xf(Vector3(0, 0.2, 0.055), Vector3(PI * 0.5, 0, 0)), 3])
			p.append([FairKit.box_mesh(Vector3(0.122, 0.012, 0.122)), _xf(Vector3(0, 0.13, 0), Vector3(0, PI * 0.25, 0)), 1])
		"moon":  # ~0.26 m: a plush moon with craters, sleepy eyes, cheeks and a smile
			p.append([FairKit.sphere_mesh(0.12, 20), _xf(Vector3(0, 0.12, 0)), 0])
			var craters := [Vector3(-0.6, 0.5, 0.3), Vector3(0.7, 0.2, 0.2), Vector3(0.1, 0.85, -0.3), Vector3(-0.3, -0.2, -0.9), Vector3(0.6, 0.5, -0.6), Vector3(-0.85, -0.1, -0.3)]
			for c in craters:
				var n: Vector3 = (c as Vector3).normalized()
				var b := Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT)
				p.append([FairKit.sphere_mesh(0.032, 10), Transform3D(b.scaled(Vector3(1, 1, 0.3)), Vector3(0, 0.12, 0) + n * 0.115), 1])
			for sx in [-1.0, 1.0]:
				p.append([FairKit.box_mesh(Vector3(0.028, 0.007, 0.01)), _xf(Vector3(sx * 0.04, 0.14, 0.113), Vector3(0, 0, sx * 0.25)), 2])
				p.append([FairKit.sphere_mesh(0.017, 8), _xf(Vector3(sx * 0.065, 0.105, 0.098), Vector3.ZERO, Vector3(1, 0.7, 0.4)), 3])
			for i in 5:
				var a := -0.6 + i * 0.3
				p.append([FairKit.sphere_mesh(0.006, 6), _xf(Vector3(sin(a) * 0.03, 0.1 - cos(a) * 0.012, 0.119)), 2])
		_:  # pennant: a stick and a purple felt triangle with a gold stripe
			p.append([FairKit.cyl_mesh(0.006, 0.006, 0.5, 6), _xf(Vector3(0, 0.25, 0)), 0])
			p.append([FairKit.extrude(PackedVector2Array([Vector2(0, 0), Vector2(0.36, 0.08), Vector2(0, 0.16)]), 0.004), _xf(Vector3(0.006, 0.33, 0)), 1])
			p.append([FairKit.extrude(PackedVector2Array([Vector2(0, 0.06), Vector2(0.24, 0.075), Vector2(0, 0.1)]), 0.006), _xf(Vector3(0.006, 0.33, -0.001)), 2])
			p.append([FairKit.sphere_mesh(0.012, 8), _xf(Vector3(0, 0.505, 0)), 2])
	return _merge(p, _mats(kind))


## One prize model as a node (its own materials ride on the mesh's surfaces).
static func model(kind: String, scl: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind)
	mi.scale = Vector3.ONE * scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- The stall's shelf -------------------------------------------------------------------------

## A four-tier prize shelf (its front faces local +Z) under `parent` at `xf`. Fill it with fill().
static func shelf(parent: Node3D, xf: Transform3D) -> Node3D:
	var s := Node3D.new()
	s.name = "PrizeShelf"
	s.transform = xf
	parent.add_child(s)
	var wood := FairKit.pbr("dark_wooden_planks", Color(0.7, 0.55, 0.42), 1.5)
	var trim := FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	FairKit.box(s, Vector3(SHELF_W, 1.95, 0.03), Vector3(0, 1.0, -0.15), FairKit.paint(Color(0.32, 0.08, 0.2), 0.9, 0.0))
	for sx in [-1.0, 1.0]:
		FairKit.box(s, Vector3(0.04, 2.0, 0.32), Vector3(sx * SHELF_W * 0.5, 1.0, 0), wood)
	for y in TIER_Y:
		FairKit.box(s, Vector3(SHELF_W, 0.03, 0.32), Vector3(0, y - 0.015, 0), wood)
		FairKit.box(s, Vector3(SHELF_W, 0.02, 0.01), Vector3(0, y - 0.02, 0.165), trim)
	FairKit.box(s, Vector3(SHELF_W + 0.06, 0.06, 0.36), Vector3(0, 2.02, 0), wood)
	var head := FairKit.label(s, "PRIZES", Vector3(0, 2.13, 0.05), 40, Color(1.0, 0.85, 0.45) * 1.6, 0.0, Color(0.1, 0.02, 0.08), 0.0035)
	head.outline_size = 8
	var bulbs := FairKit.glow(Color(1.0, 0.82, 0.45), 6.0, 3.0)
	var bm := FairKit.sphere_mesh(0.022, 6)
	for i in 7:
		FairKit.mesh(s, bm, Vector3(-SHELF_W * 0.5 + 0.05 + i * (SHELF_W - 0.1) / 6.0, 2.06, 0.19), bulbs, Vector3.ZERO, false)
	var items := Node3D.new()
	items.name = "Items"
	s.add_child(items)
	var labels: Array = []
	for i in TIER_Y.size():
		var l := FairKit.label(s, "", Vector3(0, float(TIER_Y[i]) - 0.05, 0.175), 18, Color(0.95, 0.92, 0.85), 0.0, Color(0.05, 0.02, 0.06), 0.0022)
		labels.append(l)
	s.set_meta("labels", labels)
	FairKit.omni(s, Vector3(0, 1.9, 0.5), Color(1.0, 0.85, 0.65), 0.8, 2.6)
	return s


## Re-stocks the shelf from what's left today and what this computer has won at this stall.
static func fill(s: Node3D, qing: String, game: String) -> void:
	if s == null:
		return
	var items: Node3D = s.get_node("Items")
	for c in items.get_children():
		c.queue_free()
	var labels: Array = s.get_meta("labels")
	# Top: the trophy · rockets · moons and pennants (what's left today)
	var t := left(qing, game, "trophy")
	if t > 0:
		_put(items, "trophy", Vector3(0, TIER_Y[3], 0.0), 1.15)
	labels[3].text = "GRAND PRIZE · %s" % ("1 left today" if t > 0 else "won today! back tomorrow")
	var r := left(qing, game, "rocket")
	for i in r:
		_put(items, "rocket", Vector3(-0.2 + i * 0.4, TIER_Y[2], 0.0), 1.0)
	labels[2].text = "TOY ROCKETS · %d left" % r
	var m := left(qing, game, "moon")
	for i in m:
		_put(items, "moon", Vector3(-0.33 + i * 0.2, TIER_Y[1], 0.03 - (i % 2) * 0.05), 0.68)
	var pn := left(qing, game, "pennant")
	for i in pn:
		var pi := _put(items, "pennant", Vector3(0.36 - i * 0.035, TIER_Y[1], -0.1), 0.62)
		pi.rotation = Vector3(0, -0.5, 0.18 - i * 0.12)
	labels[1].text = "PLUSH MOONS · %d left · PENNANTS" % m
	# Bottom: yours (this computer)
	var mine: Array = won(qing).filter(func(w): return w.get("game", "") == game)
	var last := mine.slice(maxi(0, mine.size() - 4))
	for i in last.size():
		var w: Dictionary = last[i]
		var x := -0.33 + i * 0.22
		_put(items, String(w.get("kind", "pennant")), Vector3(x, TIER_Y[0], 0.0), 0.62)
		var tag := FairKit.label(items, "%s\n%s" % [ArcadeScores.grouped(int(w.get("score", 0))), String(w.get("day", "")).substr(5)],
			Vector3(x, TIER_Y[0] + 0.02, 0.15), 12, Color(1.0, 0.9, 0.6), 0.0, Color(0.05, 0.02, 0.06), 0.0018)
		tag.shaded = false
	labels[0].text = "YOURS · won on this computer" if not last.is_empty() else "YOURS · win one with a ticket"


static func _put(parent: Node3D, kind: String, pos: Vector3, scl: float) -> MeshInstance3D:
	var mi := model(kind, scl)
	mi.position = pos
	mi.rotation.y = 0.35 if kind == "rocket" else 0.0
	mi.visibility_range_end = 30.0
	parent.add_child(mi)
	return mi
