class_name OutfitTailor
## Sews an outfit (Outfits.DESIGNS) into ONE skinned mesh for a body: the
## garment parts are merged per texture atlas (Peasant, Ranger, skin: one
## surface each, their import LODs merged level by level), and the tailored
## pieces (coats, robe skirts, collars, ties, bands…) are generated as one
## more surface, fitted to the garments at rest and weighted to the bones.
## Built once per (body, design) and shared by every avatar wearing it.
##
## All parts are on the Universal rig (65 bones, the UAL1 clips play on it);
## mesh space is the skeleton's rest space (Y up, +Z forward, +X = left).

const DIR := "res://assets/characters/outfits/"
## A skeleton for each body (any part's glTF carries the full rig).
const RIG := {"male": DIR + "Male_Peasant_Legs.gltf", "female": DIR + "Female_Peasant_Legs.gltf"}
const ATLASES := ["Peasant", "Ranger", "skin", "tailored"]
## Tailored slots (outfit.gdshader: COLOR.r × 15).
enum Slot { MAIN, LIGHT, BOTTOM, LEATHER, BOOTS, METAL, ACCENT, SKIN, TRIM }

static var _cache := {}
static var _scenes := {}  # part path -> PackedScene


## {mesh: ArrayMesh, skin: Skin, atlases: Array (per surface), anchors: {chest, back, arm}}
static func build(body: String, kind: String) -> Dictionary:
	if body != "female":
		body = "male"
	if not Outfits.DESIGNS.has(kind):
		kind = "street"
	var key := body + "/" + kind
	if _cache.has(key):
		return _cache[key]
	var t := OutfitTailor.new()
	var out := t._sew(body, kind)
	_cache[key] = out
	return out


## The rig for a body: a fresh scene whose Armature/Skeleton3D has no meshes.
static func rig(body: String) -> Node3D:
	var s: Node3D = load(RIG.get(body, RIG["male"])).instantiate()
	for mi in s.find_children("*", "MeshInstance3D", true, false):
		mi.get_parent().remove_child(mi)
		mi.free()
	return s


# --- Merging the garment parts ---------------------------------------------------

var _groups := {}  # atlas -> accumulator Dictionary
var _pts := PackedVector3Array()  # every garment vertex at rest (for fitting)
var _rest := {}  # bone name -> global rest Transform3D
var _bind := {}  # bone name -> bind index in the shared Skin
var _skin: Skin
var _tail := {}  # the tailored accumulator


static func _acc() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(), "uv": PackedVector2Array(),
		"c": PackedColorArray(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array(),
		"lods": [], "edges": [], "pieces": 0}


func _sew(body: String, kind: String) -> Dictionary:
	var d := Outfits.design(kind)
	var prefix := "Female_" if body == "female" else "Male_"
	var skip: Array = d.get("skip", [])
	for part in d[body]:
		var path: String = DIR + prefix + part + ".gltf"
		if not ResourceLoader.exists(path):
			push_warning("OutfitTailor: missing part %s" % path)
			continue
		if not _scenes.has(path):
			_scenes[path] = load(path)  # kept: a later outfit reuses the part
		var scene: Node = (_scenes[path] as PackedScene).instantiate()
		if _rest.is_empty():
			var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
			for b in sk.get_bone_count():
				_rest[sk.get_bone_name(b)] = sk.get_bone_global_rest(b)
		var p := String(part)
		var flags := Color(1.0 if p.ends_with("_Legs") else 0.0, 1.0 if p.contains("_Feet") else 0.0,
			1.0 if (p.contains("Hood") or p.contains("Pauldron")) else 0.0, 1.0)
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var skipped := false
			for s in skip:
				if String(mi.name).contains(s):
					skipped = true
			if skipped or mi.skin == null:
				continue
			if _skin == null:
				_skin = mi.skin
				for i in _skin.get_bind_count():
					_bind[String(_skin.get_bind_name(i))] = i
			for si in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(si)
				var mname := mat.resource_name if mat else ""
				# The parts import with stub materials (stub_*.tres: no textures to load).
				var atlas := "Peasant" if mname.containsn("peasant") else ("Ranger" if mname.containsn("ranger") else "skin")
				_append(atlas, mi.mesh, si, flags, p.contains("Hood"))
		scene.free()
	_tail = _acc()
	_tailor(body, d.get("extras", []))
	var mesh := ArrayMesh.new()
	var atlases := []
	for atlas in ATLASES:
		var g: Dictionary = _tail if atlas == "tailored" else _groups.get(atlas, {})
		if g.is_empty() or (g["i"] as PackedInt32Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g["v"]
		arr[Mesh.ARRAY_NORMAL] = g["n"]
		if (g["t"] as PackedFloat32Array).size() == (g["v"] as PackedVector3Array).size() * 4:
			arr[Mesh.ARRAY_TANGENT] = g["t"]
		arr[Mesh.ARRAY_TEX_UV] = g["uv"]
		arr[Mesh.ARRAY_COLOR] = g["c"]
		arr[Mesh.ARRAY_BONES] = g["b"]
		arr[Mesh.ARRAY_WEIGHTS] = g["w"]
		arr[Mesh.ARRAY_INDEX] = g["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], _lods(g))
		atlases.append(atlas)
	return {"mesh": mesh, "skin": _skin, "atlases": atlases, "anchors": _anchors()}


## HOOD_SCALE: a hood is cut for a human head; the creature heads are bigger.
const HOOD_SCALE := 1.38


func _append(atlas: String, mesh: Mesh, si: int, flags: Color, hood: bool = false) -> void:
	if not _groups.has(atlas):
		_groups[atlas] = _acc()
	var g: Dictionary = _groups[atlas]
	var a := mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nv := verts.size()
	if hood:  # widen it about the head (its opening and drape stay in place below the chin)
		var c := _bone("Head") + Vector3(0.0, 0.06, 0.015)
		for k in nv:
			var d := verts[k] - c
			var lift := clampf((d.y + 0.12) / 0.12, 0.0, 1.0)  # neck-level folds widen less
			verts[k] = c + d * lerpf(1.08, HOOD_SCALE, lift) + Vector3(0, 0.02 * lift, 0)
	var base := (g["v"] as PackedVector3Array).size()
	g["v"].append_array(verts)
	g["n"].append_array(a[Mesh.ARRAY_NORMAL])
	if a[Mesh.ARRAY_TANGENT] != null:
		g["t"].append_array(a[Mesh.ARRAY_TANGENT])
	g["uv"].append_array(a[Mesh.ARRAY_TEX_UV])
	if atlas != "skin":
		_pts.append_array(verts)
	var cols := PackedColorArray()
	cols.resize(nv)
	cols.fill(flags)
	g["c"].append_array(cols)
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(1, nv)
	if per == 4:
		g["b"].append_array(bones)
		g["w"].append_array(weights)
	else:  # 8 influences → the strongest 4, renormalised
		for v in nv:
			var pairs := []
			for k in per:
				pairs.append([weights[v * per + k], bones[v * per + k]])
			pairs.sort_custom(func(x, y): return x[0] > y[0])
			var tot := 0.0
			for k in 4:
				tot += pairs[k][0]
			for k in 4:
				g["b"].append(pairs[k][1])
				g["w"].append(pairs[k][0] / tot if tot > 0.0 else (1.0 if k == 0 else 0.0))
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var shifted := PackedInt32Array()
	shifted.resize(idx.size())
	for k in idx.size():
		shifted[k] = idx[k] + base
	g["i"].append_array(shifted)
	# The part's own LODs (from the import), shifted the same way.
	var sd: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), si)
	var lods: Array = []
	var edges: Array = []
	var wide := nv > 65536
	for l in sd.get("lods", []):
		var bytes: PackedByteArray = l["index_data"]
		var n := bytes.size() / (4 if wide else 2)
		var li := PackedInt32Array()
		li.resize(n)
		for k in n:
			li[k] = (bytes.decode_u32(k * 4) if wide else bytes.decode_u16(k * 2)) + base
		lods.append(li)
		edges.append(float(l["edge_length"]))
	g["lods"].append({"full": shifted, "lods": lods, "edges": edges})


## Level k of the merged surface = every piece's level k (or its coarsest).
static func _lods(g: Dictionary) -> Dictionary:
	var pieces: Array = g["lods"]
	var levels := 0
	for p in pieces:
		levels = maxi(levels, (p["lods"] as Array).size())
	var out := {}
	for k in levels:
		var idx := PackedInt32Array()
		var edge := INF
		for p in pieces:
			var ls: Array = p["lods"]
			if ls.is_empty():
				idx.append_array(p["full"])
				continue
			idx.append_array(ls[mini(k, ls.size() - 1)])
			if k < ls.size():
				edge = minf(edge, float(p["edges"][k]))
		if edge < INF and not out.has(edge):
			out[edge] = idx
	return out


# --- Fitting ---------------------------------------------------------------------

func _bone(name: String) -> Vector3:
	return (_rest[name] as Transform3D).origin if _rest.has(name) else Vector3.ZERO


## Radius of the garments around `c` in the plane (u, v), per angle (θ = 0
## along v), within a slab of half-width `slab` along `axis`. Empty angles
## take the largest neighbour; a ±2 window max keeps it convex-ish.
func _fit(c: Vector3, axis: Vector3, u: Vector3, v: Vector3, slab: float, maxr: float, n: int) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(n)
	r.fill(0.0)
	for p in _pts:
		var d := p - c
		if absf(d.dot(axis)) > slab:
			continue
		var x := d.dot(u)
		var y := d.dot(v)
		var rr := sqrt(x * x + y * y)
		if rr > maxr:
			continue
		var j := int(round(fposmod(atan2(x, y), TAU) / TAU * n)) % n
		r[j] = maxf(r[j], rr)
	var mx := 0.0
	for x in r:
		mx = maxf(mx, x)
	var out := PackedFloat32Array()
	out.resize(n)
	for j in n:
		var m := 0.0
		for o in range(-2, 3):
			m = maxf(m, r[(j + o + n) % n])
		out[j] = m if m > 0.0 else mx
	return out


## The front (or back) surface of the garments at height y near x = 0.
func _surface_z(y: float, front: bool) -> float:
	var mid := _bone("spine_03").z
	var best := mid
	var found := false
	for p in _pts:
		if absf(p.y - y) < 0.025 and absf(p.x) < 0.06 and (p.z > mid) == front:
			if not found or (front and p.z > best) or (not front and p.z < best):
				best = p.z
				found = true
	return best if found else mid + (0.13 if front else -0.12)


func _anchors() -> Dictionary:
	var chest_y := _bone("spine_03").y + 0.045
	var arm := _bone("upperarm_l").lerp(_bone("lowerarm_l"), 0.35)
	var ax := (_bone("lowerarm_l") - _bone("upperarm_l")).normalized()
	var rr := _fit(arm, ax, Vector3.UP, Vector3(0, 0, 1), 0.03, 0.12, 8)
	var r := 0.0
	for x in rr:
		r = maxf(r, x)
	return {"chest": Vector3(0.0, chest_y, _surface_z(chest_y, true) + 0.008),
		"back": Vector3(0.0, _bone("spine_03").y - 0.02, _surface_z(_bone("spine_03").y - 0.02, false)),
		"arm": arm + Vector3(0.0, maxf(r, 0.045) + 0.004, 0.0)}


# --- Tailored pieces -------------------------------------------------------------

## A tube of rings. Each ring: {c, u, v, r: PackedFloat32Array (per angle),
## w: [[bone, weight], …]}; `gap` leaves the front open (radians each side).
## Weights may vary with angle: ring "w" may instead be a Callable(θ) → [[bone, w]…].
func _tube(rings: Array, slot: int, gap: float = 0.0, cap: bool = false) -> void:
	var g := _tail
	var n: int = (rings[0]["r"] as PackedFloat32Array).size()
	var segs := n if gap <= 0.0 else n - 1
	var base := (g["v"] as PackedVector3Array).size()
	var col := Color(float(slot) / 15.0, 0, 0, 1)
	for ring in rings:
		var r: PackedFloat32Array = ring["r"]
		for j in segs + (0 if gap <= 0.0 else 1):
			var th := float(j) / n * TAU if gap <= 0.0 else lerpf(gap, TAU - gap, float(j) / segs)
			var rj := r[int(round(th / TAU * n)) % n]
			var dir: Vector3 = ring["u"] * sin(th) + ring["v"] * cos(th)
			g["v"].append(ring["c"] + dir * rj)
			g["n"].append(dir)
			g["uv"].append(Vector2(th / TAU, 0.0))
			g["c"].append(col)
			var ws: Array = ring["w"].call(th) if ring["w"] is Callable else ring["w"]
			_weights(g, ws)
	var per := segs + (0 if gap <= 0.0 else 1)
	for i in rings.size() - 1:
		for j in segs:
			var a := base + i * per + j
			var b := base + i * per + (j + 1) % per if gap <= 0.0 else base + i * per + j + 1
			var c := a + per
			var d := b + per
			g["i"].append_array(PackedInt32Array([a, c, b, b, c, d]))
	if cap:  # close the last ring (a fan to its centre)
		var last: Dictionary = rings[rings.size() - 1]
		var ci := (g["v"] as PackedVector3Array).size()
		g["v"].append(last["c"])
		g["n"].append((last["u"] as Vector3).cross(last["v"]))
		g["uv"].append(Vector2.ZERO)
		g["c"].append(col)
		_weights(g, last["w"].call(0.0) if last["w"] is Callable else last["w"])
		var start := base + (rings.size() - 1) * per
		for j in segs:
			g["i"].append_array(PackedInt32Array([start + j, start + (j + 1) % per, ci]))


func _weights(g: Dictionary, ws: Array) -> void:
	var tot := 0.0
	for k in mini(4, ws.size()):
		tot += float(ws[k][1])
	for k in 4:
		if k < ws.size() and _bind.has(ws[k][0]):
			g["b"].append(_bind[ws[k][0]])
			g["w"].append(float(ws[k][1]) / maxf(tot, 0.0001))
		else:
			g["b"].append(0)
			g["w"].append(0.0)


func _tailor(body: String, extras: Array) -> void:
	_neck(body)
	for e in extras:
		match e:
			"coat_long":
				_skirt(_bone("thigh_l").y - 0.05, _bone("calf_l").y + 0.02, deg_to_rad(16.0), 0.25, Slot.MAIN)
			"coat_short":
				_skirt(_bone("thigh_l").y - 0.03, _bone("thigh_l").y - 0.2, deg_to_rad(22.0), 0.1, Slot.MAIN)
			"robe":  # the skirt matches the robe's top (the Peasant shirt reads as light cloth)
				_skirt(_bone("thigh_l").y - 0.0, 0.09, 0.0, 0.1, Slot.LIGHT)
				_hem_trim(0.09)
			"collar":
				_collar(0.012, 0.07, 0.03, Slot.ACCENT)
			"fur_collar":
				_collar(0.022, 0.06, 0.05, Slot.ACCENT)
			"hood_down":
				_hood_down()
			"tie":
				_tie()
			"sash":
				_band_around(Vector3(0, _bone("spine_01").y - 0.02, 0), 0.07, 0.018, Slot.ACCENT, [["pelvis", 0.5], ["spine_01", 0.5]])
			"bib":
				_bib()
			"bands":
				for s in ["_l", "_r"]:
					_limb_band("calf" + s, "foot" + s, 0.55, Slot.TRIM)
					_limb_band("lowerarm" + s, "hand" + s, 0.45, Slot.TRIM)


func _ring(c: Vector3, r: PackedFloat32Array, w: Variant, u: Vector3 = Vector3(1, 0, 0), v: Vector3 = Vector3(0, 0, 1)) -> Dictionary:
	# Default plane: horizontal, u = +X (left), v = +Z (front).
	return {"c": c, "u": u, "v": v, "r": r, "w": w}


static func _const(n: int, x: float) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(n)
	r.fill(x)
	return r


## The neck under a creature head (the garments stop at the collar).
func _neck(body: String) -> void:
	var a := _bone("neck_01") + Vector3(0, -0.03, 0)
	var b := _bone("Head") + Vector3(0, 0.02, 0)
	var r := 0.052 if body == "male" else 0.045
	var rings := []
	for i in 3:
		var t := i / 2.0
		rings.append(_ring(a.lerp(b, t) + Vector3(0, 0, 0.012), _const(12, r * (1.08 - 0.08 * t)),
			[["neck_01", 1.0 - 0.5 * t], ["Head", 0.5 * t]] if t > 0.0 else [["spine_03", 0.4], ["neck_01", 0.6]]))
	_tube(rings, Slot.SKIN, 0.0, true)


## A skirt from `top` down to `bottom` (heights at rest), open at the front by
## `gap`, flaring by `flare` m per m of drop. The top rides the pelvis; lower
## down each side follows its thigh.
func _skirt(top: float, bottom: float, gap: float, flare: float, slot: int) -> void:
	var n := 28
	var steps := maxi(4, int((top - bottom) / 0.07))
	var cx := _bone("pelvis")
	var prev := PackedFloat32Array()
	var rings := []
	for i in steps + 1:
		var t := float(i) / steps
		var y := lerpf(top, bottom, t)
		var c := Vector3(cx.x, y, cx.z - 0.01)
		var r := _fit(c, Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, 1), 0.045, 0.36, n)
		for j in n:
			r[j] += 0.018
			if not prev.is_empty():
				r[j] = maxf(r[j], prev[j] + flare * (top - bottom) / steps)
		prev = r
		var k := smoothstep(0.0, 0.55, t) * 0.92
		var wf := func(th: float) -> Array:
			var wl := clampf(0.5 + sin(th) * 1.1, 0.0, 1.0)
			return [["pelvis", 1.0 - k], ["thigh_l", k * wl], ["thigh_r", k * (1.0 - wl)]]
		rings.append(_ring(c, r.duplicate(), wf))
	_tube(rings, slot, gap)


func _hem_trim(y: float) -> void:
	var cx := _bone("pelvis")
	var c := Vector3(cx.x, y, cx.z - 0.01)
	var g := _tail
	# Re-use the robe's last ring: a thin glowing band just outside it.
	var r := _fit(c, Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, 1), 0.06, 0.6, 28)
	var verts: PackedVector3Array = g["v"]
	# Measure the robe's hem from its own vertices (the lowest ring).
	var hem := _const(28, 0.0)
	for p in verts:
		if absf(p.y - y) < 0.005:
			var d := p - c
			var j := int(round(fposmod(atan2(d.x, d.z), TAU) / TAU * 28)) % 28
			hem[j] = maxf(hem[j], Vector2(d.x, d.z).length())
	for j in 28:
		r[j] = maxf(r[j], hem[j]) + 0.004
	var wf := func(th: float) -> Array:
		var wl := clampf(0.5 + sin(th) * 1.1, 0.0, 1.0)
		return [["pelvis", 0.08], ["thigh_l", 0.92 * wl], ["thigh_r", 0.92 * (1.0 - wl)]]
	_tube([_ring(c, r, wf), _ring(c + Vector3(0, 0.03, 0), r, wf)], Slot.TRIM)


## A stand-up collar at the base of the neck: `margin` out from the garments,
## `h` tall, flaring by `flare` at its top edge.
func _collar(margin: float, h: float, flare: float, slot: int) -> void:
	var y := _bone("neck_01").y - 0.035
	var c := Vector3(0, y, _bone("neck_01").z + 0.005)
	var r := _fit(c, Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, 1), 0.03, 0.2, 20)
	var rings := []
	for i in 3:
		var t := i / 2.0
		var rr := PackedFloat32Array()
		for x in r:
			rr.append(x + margin + flare * t * t)
		rings.append(_ring(c + Vector3(0, h * t, -0.01 * t), rr, [["spine_03", 0.7 - 0.4 * t], ["neck_01", 0.3 + 0.4 * t]]))
	_tube(rings, slot, deg_to_rad(28.0))


## A hood worn down: a soft roll behind the neck and over the shoulders.
func _hood_down() -> void:
	var y := _bone("neck_01").y - 0.05
	var c := Vector3(0, y, _bone("neck_01").z - 0.005)
	var r := _fit(c, Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, 1), 0.03, 0.22, 20)
	var rings := []
	for i in 5:
		var t := i / 4.0
		var rr := PackedFloat32Array()
		for x in r:
			rr.append(x + 0.01 + 0.05 * sin(t * PI))
		rings.append(_ring(c + Vector3(0, 0.11 * t, -0.03 * sin(t * PI)), rr, [["spine_03", 0.8 - 0.4 * t], ["neck_01", 0.2 + 0.4 * t]]))
	_tube(rings, Slot.MAIN, deg_to_rad(70.0))


## A tie down the shirt front.
func _tie() -> void:
	var g := _tail
	var top := _bone("neck_01").y - 0.05
	var bottom := _bone("spine_01").y + 0.02
	var n := 7
	var base := (g["v"] as PackedVector3Array).size()
	var col := Color(float(Slot.ACCENT) / 15.0, 0, 0, 1)
	for i in n:
		var t := float(i) / (n - 1)
		var y := lerpf(top, bottom, t)
		var z := _surface_z(y, true) + 0.006
		var w := lerpf(0.018, 0.034, t) if t < 0.95 else 0.004
		var bone := "spine_03" if t < 0.35 else ("spine_02" if t < 0.75 else "spine_01")
		for s in [-1.0, 1.0]:
			g["v"].append(Vector3(s * w, y, z))
			g["n"].append(Vector3(0, 0, 1))
			g["uv"].append(Vector2.ZERO)
			g["c"].append(col)
			_weights(g, [[bone, 1.0]])
	for i in n - 1:
		var a := base + i * 2
		g["i"].append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))


## The bib of a pair of overalls: a front panel from the waist up the chest.
func _bib() -> void:
	var rings := []
	var top := _bone("spine_03").y + 0.02
	var bottom := _bone("spine_01").y - 0.04
	for i in 5:
		var t := i / 4.0
		var y := lerpf(bottom, top, t)
		var c := Vector3(0, y, -0.01)
		var r := _fit(c, Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, 1), 0.03, 0.3, 20)
		for j in r.size():
			r[j] += 0.008
		var bone := "spine_01" if t < 0.3 else ("spine_02" if t < 0.7 else "spine_03")
		rings.append(_ring(c, r, [[bone, 1.0]]))
	# Front only: open everywhere but ±50° about +Z.
	var g := _tail
	var n := 20
	var base := (g["v"] as PackedVector3Array).size()
	var col := Color(float(Slot.MAIN) / 15.0, 0, 0, 1)
	var cols := 7
	for ring in rings:
		for j in cols:
			var th := lerpf(-0.9, 0.9, float(j) / (cols - 1))
			var rr: float = ring["r"][int(round(fposmod(th, TAU) / TAU * n)) % n]
			var dir := Vector3(sin(th), 0, cos(th))
			g["v"].append(ring["c"] + dir * rr)
			g["n"].append(dir)
			g["uv"].append(Vector2.ZERO)
			g["c"].append(col)
			_weights(g, ring["w"])
	for i in rings.size() - 1:
		for j in cols - 1:
			var a := base + i * cols + j
			g["i"].append_array(PackedInt32Array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols]))


## A band around the body at `c` (horizontal), `h` tall.
func _band_around(c: Vector3, h: float, margin: float, slot: int, w: Array) -> void:
	var r := _fit(c, Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, 1), h * 0.5, 0.3, 20)
	for j in r.size():
		r[j] += margin
	_tube([_ring(c + Vector3(0, -h * 0.5, 0), r, w), _ring(c + Vector3(0, h * 0.5, 0), r, w)], slot)


## A thin band around a limb, a fraction `t` along bone a → b.
func _limb_band(a: String, b: String, t: float, slot: int) -> void:
	var pa := _bone(a)
	var pb := _bone(b)
	var axis := (pb - pa).normalized()
	var u := axis.cross(Vector3(0, 0, 1)).normalized()
	if u.length() < 0.5:
		u = axis.cross(Vector3.UP).normalized()
	var v := u.cross(axis).normalized()
	var c := pa.lerp(pb, t)
	var r := _fit(c, axis, u, v, 0.02, 0.12, 12)
	for j in r.size():
		r[j] += 0.005
	_tube([_ring(c - axis * 0.014, r, [[a, 1.0]], u, v), _ring(c + axis * 0.014, r, [[a, 1.0]], u, v)], slot)
