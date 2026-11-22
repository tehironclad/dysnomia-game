class_name JuliaHeightfield
extends RefCounted
## A territory's ground, computed from its Deep Field parameters: the filled
## Julia set of z ↦ z^D + c, framed exactly like the territory's emblem (so the
## ground *is* the card). Deterministic: 64-bit doubles on the CPU, same input →
## same heights on every machine; GPU shaders only add visual detail.
##
## Mapping (all distances in metres, see docs/REWORK_PLAN.md §3.4):
## - inside the filled set → a raised plateau with gentle orbit-trap relief;
## - at the boundary        → a crest (the filaments become ridges);
## - outside                → the land falls away with the distance estimate,
##                            lightly terraced;
## - the centre             → a flat disc for the Core.
##
## World ↔ complex plane: z = R(rotation) · (x, z_world) / half_size · extent.

const SIZE_M := 512.0  ## territory edge length (metres)
const MAX_ITER := 140
const PLATEAU_M := 22.0
const RELIEF_M := 3.0  ## interior undulation from the orbit trap
const CREST_M := 4.0  ## ridge along the boundary
const CREST_W_M := 3.0
const FALLOFF_W_M := 38.0  ## how fast land drops outside the set
const TERRACE_M := 2.0
const CORE_RADIUS_M := 24.0
const CORE_BLEND_M := 14.0
const CACHE_DIR := "user://cache/terrain"
const VERSION := 1  ## bump when the mapping changes (invalidates caches)

var n := 257  ## samples per side
var heights := PackedFloat32Array()  ## row-major, n*n, metres
var inside := PackedByteArray()  ## 1 where the sample is in the filled set
var core_height := 0.0
var params: Dictionary = {}
var address := ""


static func sample_spacing(samples: int) -> float:
	return SIZE_M / float(samples - 1)


## World position (metres, centred on the territory) → complex plane.
static func world_to_z(p: Dictionary, x: float, zw: float) -> Array:
	var half := SIZE_M * 0.5
	var ux := x / half * float(p["extent"])
	var uy := zw / half * float(p["extent"])
	var ca := cos(float(p["rotation"]))
	var sa := sin(float(p["rotation"]))
	return [ux * ca - uy * sa, ux * sa + uy * ca]


## Escape data at one complex point: [inside(bool), trap, de(complex units), nu].
static func probe(p: Dictionary, zx: float, zy: float, max_iter: int = MAX_ITER) -> Array:
	var c: Array = p["c"]
	var c0: float = c[0]
	var c1: float = c[1]
	var d: int = p["power"]
	var dx := 1.0
	var dy := 0.0
	var m := 0.0
	var trap := 1e9
	var i := 0
	while i < max_iter:
		var px1 := 1.0
		var py1 := 0.0
		for e in range(1, d):
			var t1 := px1 * zx - py1 * zy
			py1 = px1 * zy + py1 * zx
			px1 = t1
		var ndx := d * (px1 * dx - py1 * dy)
		dy = d * (px1 * dy + py1 * dx)
		dx = ndx
		var nzx := px1 * zx - py1 * zy + c0
		zy = px1 * zy + py1 * zx + c1
		zx = nzx
		m = zx * zx + zy * zy
		trap = minf(trap, m)
		if m > 1e4:
			break
		i += 1
	if i >= max_iter:
		return [true, trap, 0.0, float(max_iter)]
	var rr := sqrt(m)
	var de := 0.5 * rr * log(rr) / maxf(1e-300, sqrt(dx * dx + dy * dy))
	var nu := i + 1 - log(log(rr)) / log(float(d))
	return [false, trap, de, nu]


## Raw (unsmoothed) height in metres for one probe result.
static func height_of(pr: Array, metres_per_unit: float) -> float:
	if pr[0]:
		return PLATEAU_M + RELIEF_M * (1.0 - exp(-3.0 * float(pr[1])))
	var de_m: float = float(pr[2]) * metres_per_unit
	var h := PLATEAU_M * exp(-de_m / FALLOFF_W_M) + CREST_M * exp(-de_m / CREST_W_M)
	# Light terracing of the slopes (the site's "bands" made of land).
	var tq := roundf(h / TERRACE_M) * TERRACE_M
	return lerpf(h, tq, 0.35)


## Computes the heightfield (blocking; uses worker threads). `samples` should be 2^k + 1.
static func compute(p: Dictionary, addr: String, samples: int = 257) -> JuliaHeightfield:
	var hf := JuliaHeightfield.new()
	hf.n = samples
	hf.params = p
	hf.address = addr.to_lower()
	hf.heights.resize(samples * samples)
	hf.inside.resize(samples * samples)
	var spacing := sample_spacing(samples)
	var half := SIZE_M * 0.5
	var mpu := half / float(p["extent"])  # metres per complex unit
	# Each worker fills its own row buffers; writing `hf.heights[k]` from a
	# lambda would copy the whole packed array on every write (and race).
	var row_h: Array = []
	var row_in: Array = []
	row_h.resize(samples)
	row_in.resize(samples)
	var lock := Mutex.new()
	var task := func(row: int) -> void:
		var zw := -half + row * spacing
		var hs := PackedFloat32Array()
		var ins := PackedByteArray()
		hs.resize(samples)
		ins.resize(samples)
		for col in samples:
			var x := -half + col * spacing
			var z := world_to_z(p, x, zw)
			var pr := probe(p, z[0], z[1])
			hs[col] = height_of(pr, mpu)
			ins[col] = 1 if pr[0] else 0
		lock.lock()
		row_h[row] = hs
		row_in[row] = ins
		lock.unlock()
	# Single-threaded: deterministic and simple. (A WorkerThreadPool version
	# stalled in headless runs; revisit with a C#/GDExtension path if needed.)
	for row in samples:
		task.call(row)
	var all_h := PackedFloat32Array()
	var all_in := PackedByteArray()
	for r in samples:
		all_h.append_array(row_h[r])
		all_in.append_array(row_in[r])
	hf.heights = all_h
	hf.inside = all_in
	hf._smooth(2)
	hf._flatten_core()
	return hf


## Box blur passes: tames the fractal's aliasing into walkable land.
func _smooth(passes: int) -> void:
	var src := heights
	for pass_i in passes:
		var out := src.duplicate()
		for r in range(1, n - 1):
			for c in range(1, n - 1):
				var s := 0.0
				for dr in range(-1, 2):
					for dc in range(-1, 2):
						s += src[(r + dr) * n + c + dc]
				out[r * n + c] = s / 9.0
		src = out
	heights = src


func _flatten_core() -> void:
	var hs := heights  # work on a local (packed arrays are copy-on-write)
	var spacing := sample_spacing(n)
	var half := SIZE_M * 0.5
	var ci := (n - 1) / 2
	core_height = hs[ci * n + ci]
	var reach := CORE_RADIUS_M + CORE_BLEND_M
	var rad := ceili(reach / spacing)
	for r in range(maxi(0, ci - rad), mini(n, ci + rad + 1)):
		for c in range(maxi(0, ci - rad), mini(n, ci + rad + 1)):
			var d := Vector2((c - ci) * spacing, (r - ci) * spacing).length()
			if d <= CORE_RADIUS_M:
				hs[r * n + c] = core_height
			elif d < reach:
				var t := smoothstep(0.0, 1.0, (d - CORE_RADIUS_M) / CORE_BLEND_M)
				hs[r * n + c] = lerpf(core_height, hs[r * n + c], t)
	heights = hs


## Bilinear height at a world position (metres, centred on the territory).
func height_at(x: float, zw: float) -> float:
	var half := SIZE_M * 0.5
	var fx := clampf((x + half) / sample_spacing(n), 0.0, n - 1.001)
	var fz := clampf((zw + half) / sample_spacing(n), 0.0, n - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var h00 := heights[z0 * n + x0]
	var h10 := heights[z0 * n + x0 + 1]
	var h01 := heights[(z0 + 1) * n + x0]
	var h11 := heights[(z0 + 1) * n + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Integer fingerprint of the heights (millimetres) for determinism tests.
func fingerprint() -> int:
	var h := 1469598103934665603
	for v in heights:
		h = (h ^ int(roundf(v * 1000.0))) * 1099511628211
	return h


# --- Cache -------------------------------------------------------------------------

static func cache_path(addr: String, samples: int) -> String:
	return "%s/v%d_%s_%d.bin" % [CACHE_DIR, VERSION, addr.to_lower(), samples]


## Loads from the on-disk cache or computes (and caches) the heightfield.
static func for_territory(q: Dictionary, samples: int = 257) -> JuliaHeightfield:
	var addr := String(q["address"]).to_lower()
	var p := DeepField.for_territory(q)
	var path := cache_path(addr, samples)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var data: Dictionary = f.get_var()
		if data.get("n", 0) == samples and (data.get("heights") as PackedFloat32Array).size() == samples * samples:
			var hf := JuliaHeightfield.new()
			hf.n = samples
			hf.params = p
			hf.address = addr
			hf.heights = data["heights"]
			hf.inside = data["inside"]
			hf.core_height = data["core_height"]
			return hf
	var fresh := compute(p, addr, samples)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w:
		w.store_var({"n": samples, "heights": fresh.heights, "inside": fresh.inside, "core_height": fresh.core_height})
	return fresh


# --- Previews ----------------------------------------------------------------------

## Slope statistics in degrees: {p50, p95, max, steep_pct (> 40°)}.
func slope_stats() -> Dictionary:
	var sp := sample_spacing(n)
	var angles := PackedFloat32Array()
	for r in range(1, n - 1):
		for c in range(1, n - 1):
			var gx := (heights[r * n + c + 1] - heights[r * n + c - 1]) / (2.0 * sp)
			var gz := (heights[(r + 1) * n + c] - heights[(r - 1) * n + c]) / (2.0 * sp)
			angles.append(rad_to_deg(atan(sqrt(gx * gx + gz * gz))))
	angles.sort()
	var steep := 0
	for a in angles:
		if a > 40.0:
			steep += 1
	return {"p50": angles[angles.size() / 2], "p95": angles[int(angles.size() * 0.95)],
		"max": angles[angles.size() - 1], "steep_pct": 100.0 * steep / angles.size()}


## Preview in the Deep Field look: dark hillshaded ground, the boundary crest
## lit in the territory's colour (a stand-in for the GPU filament shader).
func preview_image() -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var col := DeepField.to_color(params["color"])
	var col2 := DeepField.to_color(params["color2"])
	var ground := Color("#0b0e16")
	var light := Vector3(-0.6, 0.7, -0.4).normalized()
	var sp := sample_spacing(n)
	var crest_top := PLATEAU_M * 0.85
	for r in n:
		for c in n:
			var hl := heights[r * n + maxi(c - 1, 0)]
			var hr := heights[r * n + mini(c + 1, n - 1)]
			var hu := heights[maxi(r - 1, 0) * n + c]
			var hd := heights[mini(r + 1, n - 1) * n + c]
			var nrm := Vector3(hl - hr, 2.0 * sp, hu - hd).normalized()
			var shade := clampf(nrm.dot(light), 0.0, 1.0)
			var h := heights[r * n + c]
			var base := ground.lerp(Color("#1a2030"), clampf(h / PLATEAU_M, 0.0, 1.0)) * (0.35 + 0.65 * shade)
			var on_set := inside[r * n + c] == 1
			# glow where the land rises toward the boundary from outside
			var glow := 0.0 if on_set else clampf((h - crest_top * 0.35) / (crest_top * 0.65), 0.0, 1.0)
			var tint := col2 if on_set else col
			base = base.lerp(tint, glow * glow * 0.85)
			if on_set:
				base = base.lerp(col2 * 0.25, 0.25)
			img.set_pixel(c, r, Color(minf(base.r, 1.0), minf(base.g, 1.0), minf(base.b, 1.0)))
	return img
