class_name TerritoryRoads
extends Node3D
## Roads between a territory's places (2026-11-24, when territories grew to 724 m).
##
## A ring road circles the Core's plaza; from it, roads run to each place's door
## (the vehicle pad, the Affection Fair, the skyline landmark and its landing ring,
## anything else passed in) and to the middle of every border that has a QING
## beyond it. Each road is routed over the territory's own ground (AStarGrid2D on
## an ≈8 m grid, cost rising with the slope, so roads follow the terraces and
## canyons instead of climbing them) and later roads reuse earlier ones, so they
## join into a network. Pure and deterministic: the same terrain, places and
## neighbours give the same roads for every viewer.
##
## Drawing: the terrain shader reads a distance-to-road texture (road_field), so
## the roads lie on the ground at no extra draw calls; the ground is never
## flattened. Lamp posts (one MultiMesh) stand along them: low marker posts on a
## Wild or Outpost territory, lit lamps from Settlement up (Development tier).

const CELLS := 91                                     ## routing grid points per side
const CELL_M := JuliaHeightfield.SIZE_M / (CELLS - 1)  ## ≈ 8.04 m
const HALF_W := 4.5          ## road half-width: 9 m, room for two vehicles
const FIELD_M := 12.0        ## road_field stores the distance to a road up to this
const TEX := 512             ## road_field texels per side (≈ 1.4 m)
const RING_R := 60.0         ## the Core's ring road (the Core's plain is flat to 90 m)
const CORE_KEEP := 50.0      ## no routing inside this (the Core, arcade, monolith, skyline)
const AVENUE_FROM := Vector2(0.0, 24.0)  ## the avenue from the Room's door to the ring
const LAMP_EVERY := 34.0     ## metres between lamps along a road
const REUSE := 0.35          ## weight of a cell an earlier road already uses
const SLOPE_REF := 0.15      ## grade where a cell costs 3× a flat one

var roads: Array = []        ## [PackedVector2Array] polylines (world x, z)
var places: Array = []       ## [{name, at: Vector2, r}] as last built
var field := PackedByteArray()
var tier := -1
var _key := ""
var _material: ShaderMaterial
var _height: Callable        ## world (x, z) → world height
var _tint := Color("#7fd3ff")
var _lamps: Node3D


## Builds (or rebuilds, when the places changed) the roads. `places`:
## [{name, at: Vector2 (world x, z), r: footprint radius}]; `gates`: [Vector2]
## border points (world x, z). `terrain_mat` gets the road_field texture.
func build(height_fn: Callable, terrain_mat: ShaderMaterial, p_places: Array, gates: Array, p_tier: int, tint: Color) -> void:
	_height = height_fn
	_material = terrain_mat
	_tint = tint
	var key := str(p_places) + str(gates)
	if key != _key:
		_key = key
		places = p_places
		var t0 := Time.get_ticks_msec()
		roads = plan(height_fn, p_places, gates)
		field = rasterize(roads, p_places)
		_apply_field()
		print("[Roads] %d roads, %d m, to %s · %d ms" % [roads.size(), int(total_length(roads)),
			", ".join(p_places.map(func(p): return String(p["name"]))) + (" + %d border gates" % gates.size()), Time.get_ticks_msec() - t0])
		tier = -1
	set_tier(p_tier)


## Development tier → the lamps (and how brightly the road edges glow).
func set_tier(t: int) -> void:
	if t == tier:
		return
	tier = t
	if _material:
		_material.set_shader_parameter("road_lit", 0.25 if t < 2 else 0.5 + 0.1 * t)
	_build_lamps()
	var lit := t >= 2
	Inspector.register(self, "Roads",
		"%d roads, %d m: a ring road around the Core and a road from it to each place (%s) and to every border with a QING beyond it. Routed over this territory's own ground (cost grows with the slope), so they follow its terraces; the same for every viewer.\n%s (Development tier %d)." % [
			roads.size(), int(total_length(roads)), ", ".join(places.map(func(p): return String(p["name"]))),
			"Lit lamps" if lit else "Marker posts; the lamps light from Settlement up", tier])


# --- Routing (pure) -------------------------------------------------------------------

## The roads, in order: the Core's ring, the avenue to it, then one road per
## place (from the ring to its door) and per border gate.
static func plan(height_fn: Callable, p_places: Array, gates: Array) -> Array:
	var half := JuliaHeightfield.SIZE_M * 0.5
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, CELLS, CELLS)
	astar.cell_size = Vector2(CELL_M, CELL_M)
	astar.offset = Vector2(-half, -half)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	var h := PackedFloat32Array()
	h.resize(CELLS * CELLS)
	for j in CELLS:
		for i in CELLS:
			h[j * CELLS + i] = height_fn.call(-half + i * CELL_M, -half + j * CELL_M)
	for j in CELLS:
		for i in CELLS:
			var h0 := h[j * CELLS + i]
			var g := 0.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				if ni >= 0 and nj >= 0 and ni < CELLS and nj < CELLS:
					g = maxf(g, absf(h[nj * CELLS + ni] - h0) / CELL_M)
			var w := 1.0 + 2.0 * pow(g / SLOPE_REF, 2.0)
			var p := Vector2(-half + i * CELL_M, -half + j * CELL_M)
			var solid := p.length() < CORE_KEEP or maxf(absf(p.x), absf(p.y)) > half - 4.0
			for pl in p_places:
				if p.distance_to(pl["at"]) < float(pl["r"]) + 2.0:
					solid = true
			astar.set_point_solid(Vector2i(i, j), solid)
			astar.set_point_weight_scale(Vector2i(i, j), w)
	var out: Array = []
	# The ring road around the Core's plaza, and the avenue from the Room's door.
	var ring := PackedVector2Array()
	for k in 49:
		var a := TAU * k / 48.0
		ring.append(Vector2(cos(a), sin(a)) * RING_R)
	out.append(ring)
	for k in 48:
		var c := _cell(ring[k])
		if astar.is_in_boundsv(c):
			astar.set_point_weight_scale(c, REUSE)
	out.append(PackedVector2Array([AVENUE_FROM, Vector2(0.0, RING_R)]))
	# Roads to each place's door and each border gate.
	var targets: Array = []
	for pl in p_places:
		var at: Vector2 = pl["at"]
		var dir := -at.normalized() if at.length() > 1.0 else Vector2(0, -1)
		var t := {}
		if pl.has("from"):  # a road from another place (e.g. the tower to its landing ring)
			var from: Vector2 = pl["from"]
			dir = (from - at).normalized()
			t["start"] = from
		t["door"] = at + dir * (float(pl["r"]) + 6.0)
		t["end"] = at + dir * (float(pl["r"]) - 1.0)
		targets.append(t)
	for g in gates:
		targets.append({"door": g, "end": g})
	for t in targets:
		var door: Vector2 = t["door"]
		var start: Vector2 = t.get("start", door.normalized() * RING_R)
		var line := _route(astar, start, door)
		if line.size() < 2:
			continue
		line.append(t["end"])
		line = _smooth(line)
		for p in line:
			var c := _cell(p)
			if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
				astar.set_point_weight_scale(c, REUSE)
		out.append(line)
	return out


static func _cell(p: Vector2) -> Vector2i:
	var half := JuliaHeightfield.SIZE_M * 0.5
	return Vector2i(roundi((p.x + half) / CELL_M), roundi((p.y + half) / CELL_M))


## The nearest free grid point to `p` (rings outward), or (-1, -1).
static func _free(astar: AStarGrid2D, p: Vector2) -> Vector2i:
	var c0 := _cell(p)
	for r in 6:
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var c := c0 + Vector2i(di, dj)
				if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
					return c
	return Vector2i(-1, -1)


static func _route(astar: AStarGrid2D, a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca := _free(astar, a)
	var cb := _free(astar, b)
	var line := PackedVector2Array()
	if ca.x < 0 or cb.x < 0:
		return line
	line.append(a)
	for p in astar.get_point_path(ca, cb, true):
		line.append(p)
	line.append(b)
	return line


## Chaikin corner cutting (2 passes), endpoints kept: grid steps → curves.
static func _smooth(line: PackedVector2Array) -> PackedVector2Array:
	var cur := line
	for pass_i in 2:
		if cur.size() < 3:
			return cur
		var nxt := PackedVector2Array([cur[0]])
		for i in cur.size() - 1:
			nxt.append(cur[i].lerp(cur[i + 1], 0.25))
			nxt.append(cur[i].lerp(cur[i + 1], 0.75))
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return cur


static func total_length(lines: Array) -> float:
	var s := 0.0
	for l in lines:
		for i in l.size() - 1:
			s += l[i].distance_to(l[i + 1])
	return s


## Distance from (x, z) to the nearest road (metres; FIELD_M or more → FIELD_M).
static func distance_to_roads(lines: Array, p: Vector2) -> float:
	var best := FIELD_M
	for l in lines:
		for i in l.size() - 1:
			best = minf(best, _seg_dist(p, l[i], l[i + 1]))
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(1e-9, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## The road_field texture (TEX², row-major, 0 = on a road's centre line, 255 = FIELD_M
## or more away). The places' own terraces are left clear (roads end at their rims).
static func rasterize(lines: Array, p_places: Array) -> PackedByteArray:
	var half := JuliaHeightfield.SIZE_M * 0.5
	var tx := JuliaHeightfield.SIZE_M / TEX
	var d := PackedFloat32Array()
	d.resize(TEX * TEX)
	d.fill(FIELD_M)
	for l in lines:
		for i in l.size() - 1:
			var a: Vector2 = l[i]
			var b: Vector2 = l[i + 1]
			var i0 := clampi(int((minf(a.x, b.x) - FIELD_M + half) / tx), 0, TEX - 1)
			var i1 := clampi(int((maxf(a.x, b.x) + FIELD_M + half) / tx) + 1, 0, TEX - 1)
			var j0 := clampi(int((minf(a.y, b.y) - FIELD_M + half) / tx), 0, TEX - 1)
			var j1 := clampi(int((maxf(a.y, b.y) + FIELD_M + half) / tx) + 1, 0, TEX - 1)
			var ab := b - a
			var inv := 1.0 / maxf(1e-9, ab.length_squared())
			for j in range(j0, j1 + 1):
				var pz := -half + (j + 0.5) * tx
				for k in range(i0, i1 + 1):
					var p := Vector2(-half + (k + 0.5) * tx, pz)
					var t := clampf((p - a).dot(ab) * inv, 0.0, 1.0)
					var dist := p.distance_to(a + ab * t)
					var idx := j * TEX + k
					if dist < d[idx]:
						d[idx] = dist
	var out := PackedByteArray()
	out.resize(TEX * TEX)
	for j in TEX:
		var pz := -half + (j + 0.5) * tx
		for k in TEX:
			var p := Vector2(-half + (k + 0.5) * tx, pz)
			var v := d[j * TEX + k]
			if v < FIELD_M:
				if p.length() < 22.0:
					v = FIELD_M  # the Core's plaza
				for pl in p_places:
					if p.distance_to(pl["at"]) < float(pl["r"]) - 1.0:
						v = FIELD_M
						break
			out[j * TEX + k] = int(roundf(clampf(v / FIELD_M, 0.0, 1.0) * 255.0))
	return out


## Lamp spots along the roads: every LAMP_EVERY m, alternating sides, off the
## places' terraces and the Core's plaza. [[Vector2 at, Vector2 road direction]].
static func lamp_spots(lines: Array, p_places: Array) -> Array:
	var out: Array = []
	var side := 1.0
	for l in lines:
		var carry := LAMP_EVERY * 0.5
		for i in l.size() - 1:
			var a: Vector2 = l[i]
			var b: Vector2 = l[i + 1]
			var len := a.distance_to(b)
			if len < 1e-4:
				continue
			var dir := (b - a) / len
			var s := carry
			while s < len:
				var p := a + dir * s + Vector2(-dir.y, dir.x) * side * (HALF_W + 1.2)
				side = -side
				var ok := p.length() > 30.0 and maxf(absf(p.x), absf(p.y)) < JuliaHeightfield.SIZE_M * 0.5 - 3.0
				for pl in p_places:
					if p.distance_to(pl["at"]) < float(pl["r"]) + 12.0:
						ok = false
				if ok:
					out.append([p, dir])
				s += LAMP_EVERY
			carry = s - len
	return out


# --- Drawing -----------------------------------------------------------------------

func _apply_field() -> void:
	if _material == null:
		return
	var img := Image.create_from_data(TEX, TEX, false, Image.FORMAT_L8, field)
	_material.set_shader_parameter("road_field", ImageTexture.create_from_image(img))
	_material.set_shader_parameter("road_half_w", HALF_W)
	_material.set_shader_parameter("road_field_m", FIELD_M)
	_material.set_shader_parameter("has_roads", true)


func _build_lamps() -> void:
	if _lamps:
		_lamps.queue_free()
	_lamps = Node3D.new()
	_lamps.name = "Lamps"
	add_child(_lamps)
	var spots := lamp_spots(roads, places)
	if spots.is_empty():
		return
	var lit := tier >= 2
	var pole_h := 5.5 if lit else 1.1
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06 if lit else 0.07
	pole.bottom_radius = 0.1
	pole.height = pole_h
	pole.radial_segments = 6
	pole.rings = 1
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.16, 0.17, 0.2)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.5
	pole.material = pole_mat
	var head := BoxMesh.new()
	head.size = Vector3(0.9, 0.14, 0.32) if lit else Vector3(0.16, 0.16, 0.16)
	var head_mat := StandardMaterial3D.new()
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow := _tint.lerp(Color("#a8e6ff"), 0.5) if not lit else Color(1.0, 0.92, 0.78)
	head_mat.albedo_color = glow
	head_mat.emission_enabled = true
	head_mat.emission = glow
	head_mat.emission_energy_multiplier = 2.4 if lit else 1.2
	head.material = head_mat
	var mm_pole := MultiMesh.new()
	mm_pole.transform_format = MultiMesh.TRANSFORM_3D
	mm_pole.mesh = pole
	mm_pole.instance_count = spots.size()
	var mm_head := MultiMesh.new()
	mm_head.transform_format = MultiMesh.TRANSFORM_3D
	mm_head.mesh = head
	mm_head.instance_count = spots.size()
	for i in spots.size():
		var p: Vector2 = spots[i][0]
		var dir: Vector2 = spots[i][1]
		var y: float = _height.call(p.x, p.y) if _height.is_valid() else 0.0
		mm_pole.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, y + pole_h * 0.5 - 0.05, p.y)))
		# the lamp head leans over the road (toward its centre line)
		var basis := Basis(Vector3.UP, atan2(dir.x, dir.y))
		mm_head.set_instance_transform(i, Transform3D(basis, Vector3(p.x, y + pole_h, p.y)))
	for mm in [mm_pole, mm_head]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lamps.add_child(mi)
