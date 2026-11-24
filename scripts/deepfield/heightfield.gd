class_name JuliaHeightfield
extends RefCounted
## A territory's ground, computed from its Deep Field parameters: the filled
## Julia set of z ↦ z^D + c, framed exactly like the territory's emblem (so the
## ground *is* the card). Deterministic: 64-bit doubles on the CPU, same input →
## same heights on every machine; GPU shaders only add visual detail.
##
## Mapping v2 (all distances in metres; docs/LEARNINGS.md §11 "Relief"):
## - inside the filled set → the plateau. Each Fatou component rises into a
##   stepped highland: its height follows the orbit trap s (how close the orbit
##   comes to the critical point 0), so every hill is one component of the set
##   and its terraces are contour lines of s. Where the orbit passes through 0
##   (s → 0) the summit holds a crater. Highlands grow with the distance to the
##   coast, so the coast stays a walkable shelf and tiny beads stay low;
## - at the boundary        → a crest (the filaments become ridges);
## - outside                → the land falls away with the distance estimate in
##                            terraces, cut by canyons along the external rays
##                            (the arg of the escaping orbit);
## - the centre             → the Core's plain: a flat disc, relief fades in
##                            between PLAIN_IN_M and PLAIN_OUT_M from the Core;
## - the border             → the land eases down to 0 m over the outer 40 m,
##                            so neighbours meet level at the force-field wall.
## What sets each landform: relief_params().
##
## World ↔ complex plane: z = R(rotation) · (x, z_world) / half_size · extent.

## Territory edge length (metres). 724 m since 2026-11-24 (was 512 m): √2 × the
## edge, twice the area. The Julia frame scales with it (the same set, drawn
## larger); every landform width below stays in metres, so terraces, crests,
## coasts and canyons keep their human scale and the larger set gets more of them.
const SIZE_M := 724.0
const MAX_ITER := 140
const PLATEAU_M := 22.0
const CREST_W_M := 3.0
const FALLOFF_W_M := 46.0  ## how fast land drops outside the set
const COAST_W_M := 34.0  ## highlands reach full height this far inside the coast
const CORE_RADIUS_M := 24.0
const CORE_BLEND_M := 14.0
const PLAIN_IN_M := 120.0  ## relief starts this far from the Core… (90 on the 512 m map)
const PLAIN_OUT_M := 190.0  ## …and is full from here (160 on the 512 m map): room for the fair and the landmark
const EDGE_BLEND_M := 40.0  ## land eases to 0 m over the border's outer metres
const CACHE_DIR := "user://cache/terrain"
const VERSION := 4  ## bump when the mapping changes (invalidates caches). 3: SIZE_M 512 → 724; 4: the Core plain 120/190 m

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


## Escape data at one complex point: [inside(bool), trap, de(complex units), nu,
## iterations to escape, log|z| at escape (both 0 inside)].
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
		return [true, trap, 0.0, float(max_iter), 0, 0.0]
	var rr := sqrt(m)
	var de := 0.5 * rr * log(rr) / maxf(1e-300, sqrt(dx * dx + dy * dy))
	var nu := i + 1 - log(log(rr)) / log(float(d))
	return [false, trap, de, nu, i + 1, log(rr)]


## The territory's landforms, each from its Deep Field numbers (so from
## QING.Entropy() and the address). Pure; the same for every viewer.
## - relief:  highland height above the plateau (m), 10–22 from `depth`, +5 for
##            Legendary and Mythic;
## - mesa_w:  how far inland (m) the highlands take to rise, 18–42 from `frame`;
## - mesa, dome, sharp: the mix of landforms by family. Spirals build terraced
##            mesas that follow the coast; period bulbs add trap domes with deep
##            craters; star sets (D > 2) rise into sharp peaks;
## - terrace: step height (m), 2–3.5 from (arms + turn) mod 4;
## - crater:  the summit crater's reach in normalised trap units (0.08–0.20,
##            from `hue`) and its depth (m);
## - crest:   the boundary ridge (m), 3–6, +2 for star sets;
## - rays:    canyons run along the external rays at angles j/rays turns
##            (rays = the spiral's arms, else 2·D + 1), from the border in
##            toward the points where those rays land on the set;
## - canyon:  their depth (m), 5–10 from `depth`.
static func relief_params(p: Dictionary) -> Dictionary:
	var depth: float = float(p.get("depth", 0.5))
	var family := String(p.get("family", "spiral"))
	var tier := String(p.get("tier", ""))
	var arms: int = int(p.get("arms", 0))
	var turn: int = int(p.get("turn", 0))
	var power: int = int(p.get("power", 2))
	var frame: float = float(p.get("frame", 1.0))
	var hue: float = float(p.get("hue", 0.5))
	var rp := {
		"relief": 10.0 + 12.0 * depth + (5.0 if tier == "Legendary" or tier == "Mythic" else 0.0),
		"mesa_w": 18.0 + 60.0 * clampf(frame - 0.8, 0.0, 0.4),
		"mesa": 1.0, "dome": 0.35, "sharp": 1.0,
		"terrace": 2.0 + 0.5 * float((arms + turn) % 4),
		"crater": 0.08 + 0.12 * hue,
		"crater_depth": 0.4,
		"crest": 3.0 + 3.0 * (1.0 - depth),
		"canyon": 5.0 + 5.0 * depth,
	}
	if family.begins_with("period"):
		rp["mesa"] = 0.7
		rp["dome"] = 0.7
		rp["sharp"] = 1.4
		rp["crater_depth"] = 0.7
	elif family == "star":
		rp["mesa"] = 0.55
		rp["dome"] = 1.0
		rp["sharp"] = 1.8
		rp["crest"] = float(rp["crest"]) + 2.0
	rp["crater_depth"] = float(rp["relief"]) * float(rp["crater_depth"])
	rp["rays"] = arms if arms >= 3 else 2 * power + 1
	return rp


## Soft terraces: flat treads, the rise over the top `riser` fraction of each step.
static func terrace(h: float, step: float, riser: float = 0.35) -> float:
	if step <= 0.0:
		return h
	var k := floorf(h / step)
	var f := h / step - k
	return step * (k + smoothstep(1.0 - riser, 1.0, f))


## Height inside the set (metres above the plateau, before the Core's plain):
## a terraced highland rising with the distance from the coast (`coast_m`),
## plus a dome over the orbit trap, with a crater where s → 0. `t` is s
## normalised by the territory's own interior s (0..1).
static func interior_relief(t: float, coast_m: float, rp: Dictionary) -> float:
	var relief: float = rp["relief"]
	var inland := smoothstep(0.0, COAST_W_M, coast_m)
	var mesa := float(rp["mesa"]) * relief * (1.0 - exp(-coast_m / float(rp["mesa_w"])))
	var dome := float(rp["dome"]) * relief * pow(clampf(1.0 - t, 0.0, 1.0), float(rp["sharp"])) * inland
	var h := terrace(mesa + dome, float(rp["terrace"]))
	var tc: float = rp["crater"]
	if t < tc:
		var u := t / tc
		h -= float(rp["crater_depth"]) * (1.0 - u * u) * (1.0 - u * u) * inland
	var rim := (t - tc) / (0.45 * tc)  # the crater's raised rim
	return h + relief * 0.15 * exp(-rim * rim) * inland


## The plain flank outside the set (metres): falls with the distance estimate,
## with the crest on the boundary.
static func flank(de_m: float, rp: Dictionary) -> float:
	return PLATEAU_M * exp(-de_m / FALLOFF_W_M) + float(rp["crest"]) * exp(-de_m / CREST_W_M)


## The external angle (turns × 2π) of a point outside the set, from n
## iterations: Θ ← D·Θ + arg(1 + c / z^D), angle = Θ / D^n (Böttcher's
## coordinate, branch-tracked). Continuous wherever |z_k^D| > |c| along the
## orbit, i.e. away from the set (canyons fade out near it).
static func external_angle(p: Dictionary, zx: float, zy: float, n: int) -> float:
	var c: Array = p["c"]
	var c0: float = c[0]
	var c1: float = c[1]
	var d: int = p["power"]
	var th := atan2(zy, zx)
	var scale := 1.0
	for k in n:
		var wx := 1.0
		var wy := 0.0
		for e in d:
			var t1 := wx * zx - wy * zy
			wy = wx * zy + wy * zx
			wx = t1
		var nx := wx + c0
		var ny := wy + c1
		th = d * th + atan2(wx * ny - wy * nx, wx * nx + wy * ny)
		scale *= d
		zx = nx
		zy = ny
	return th / scale


## How far (metres) a point outside the set is from the nearest canyon ray
## (external angle j/rays turns): the angle offset scaled to the ground by
## |φ| / |φ'| ≈ D^n · |z_n| / |z_n'| = D^n · 2·de / log|z_n|.
static func ray_offset_m(angle: float, n: int, d: int, log_r: float, de_m: float, rays: int) -> float:
	var a := fposmod(angle * rays + PI, TAU) - PI  # offset from the nearest ray, × rays
	return absf(a) / rays * pow(float(d), n) * 2.0 * de_m / maxf(1e-6, log_r)


## Height outside the set (metres, before the Core's plain): the flank in
## terraces, cut by canyons along the external rays, widening downstream.
## `ray_m`: ray_offset_m() for this point.
static func exterior_height(de_m: float, ray_m: float, rp: Dictionary) -> float:
	var h := flank(de_m, rp)
	h = lerpf(h, terrace(h, float(rp["terrace"]), 0.3), 0.75)
	var off := ray_m
	var w := 4.0 + 0.07 * de_m
	return h - float(rp["canyon"]) * exp(-off * off / (w * w)) * smoothstep(4.0, 22.0, de_m)


## Computes the heightfield (blocking). `samples` − 1 should be even (the ground
## mesh takes every 2nd sample); SIZE_M + 1 gives 1 m spacing.
static func compute(p: Dictionary, addr: String, samples: int = 257) -> JuliaHeightfield:
	var hf := JuliaHeightfield.new()
	hf.n = samples
	hf.params = p
	hf.address = addr.to_lower()
	var spacing := sample_spacing(samples)
	var half := SIZE_M * 0.5
	var rp := relief_params(p)
	var count := samples * samples
	# Pass 1: escape data per sample, rows split over a few threads (each sample is
	# independent, so the result is the same however it is split; 64-bit doubles,
	# no shared state). Plain Threads: a WorkerThreadPool version stalled in headless runs.
	var ins := PackedByteArray()
	var sv := PackedFloat32Array()  # inside: sqrt(trap); outside: de in metres
	var av := PackedFloat32Array()  # outside: metres to the nearest canyon ray
	var interior_s := PackedFloat32Array()
	var parts := clampi(OS.get_processor_count() - 1, 1, 6) if count >= 65536 else 1
	var bounds: Array = []
	for t in parts:
		bounds.append([samples * t / parts, samples * (t + 1) / parts])
	var results: Array = []
	if parts == 1:
		results.append(_escape_rows(p, rp, samples, 0, samples))
	else:
		var threads: Array = []
		for b in bounds:
			var th := Thread.new()
			# Own copies: shared Dictionaries/Arrays make every read an atomic
			# refcount on the same cache line, and the threads run in lockstep.
			th.start(_escape_rows.bind(p.duplicate(true), rp.duplicate(true), samples, b[0], b[1]))
			threads.append(th)
		for th in threads:
			results.append(th.wait_to_finish())
	for r in results:
		ins.append_array(r[0])
		sv.append_array(r[1])
		av.append_array(r[2])
		interior_s.append_array(r[3])
	# The territory's own scale for s: its 98th percentile inside.
	var s_max := 1.0
	if interior_s.size() > 8:
		interior_s.sort()
		s_max = maxf(1e-6, interior_s[int((interior_s.size() - 1) * 0.98)])
	var coast := inland_distance(ins, samples, spacing)
	# Pass 2: heights.
	var hs := PackedFloat32Array()
	hs.resize(count)
	var crest: float = rp["crest"]
	for row in samples:
		var zw := -half + row * spacing
		for col in samples:
			var x := -half + col * spacing
			var k := row * samples + col
			var plain := smoothstep(PLAIN_IN_M, PLAIN_OUT_M, sqrt(x * x + zw * zw))
			if ins[k] == 1:
				var t := clampf(sv[k] / s_max, 0.0, 1.0)
				hs[k] = PLATEAU_M + crest * exp(-coast[k] / CREST_W_M) + interior_relief(t, coast[k], rp) * plain
			else:
				hs[k] = lerpf(flank(sv[k], rp), exterior_height(sv[k], av[k], rp), plain)
	hf.heights = hs
	hf.inside = ins
	hf._smooth(2)
	hf._flatten_core()
	hf._ease_border()
	return hf


## Pass 1 of compute() for rows [r0, r1): [inside, s or de (m), ray offset (m), interior s].
static func _escape_rows(p: Dictionary, rp: Dictionary, samples: int, r0: int, r1: int) -> Array:
	var spacing := sample_spacing(samples)
	var half := SIZE_M * 0.5
	var mpu := half / float(p["extent"])  # metres per complex unit
	var rays: int = rp["rays"]
	var power: int = p["power"]
	var cnt := (r1 - r0) * samples
	var ins := PackedByteArray()
	var sv := PackedFloat32Array()
	var av := PackedFloat32Array()
	var interior_s := PackedFloat32Array()
	ins.resize(cnt)
	sv.resize(cnt)
	av.resize(cnt)
	for row in range(r0, r1):
		var zw := -half + row * spacing
		for col in samples:
			var z := world_to_z(p, -half + col * spacing, zw)
			var pr := probe(p, z[0], z[1])
			var k := (row - r0) * samples + col
			if pr[0]:
				ins[k] = 1
				sv[k] = sqrt(float(pr[1]))
				interior_s.append(sv[k])
			else:
				sv[k] = float(pr[2]) * mpu
				av[k] = 1e6
				if sv[k] > 4.0:  # canyons fade in from 4 m off the set
					var ang := external_angle(p, z[0], z[1], int(pr[4]))
					av[k] = ray_offset_m(ang, int(pr[4]), power, float(pr[5]), sv[k], rays)
	return [ins, sv, av, interior_s]


## Distance (metres) from each inside sample to the nearest outside one, by a
## two-pass chamfer transform; outside samples read 0. Land running off the
## frame counts as inland (capped at 10 km).
static func inland_distance(ins: PackedByteArray, n: int, spacing: float) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(n * n)
	for k in n * n:
		d[k] = 1e4 if ins[k] == 1 else 0.0
	var a := spacing
	var b := spacing * 1.41421356
	for r in n:
		for c in n:
			var k := r * n + c
			var v := d[k]
			if v == 0.0:
				continue
			if c > 0:
				v = minf(v, d[k - 1] + a)
			if r > 0:
				v = minf(v, d[k - n] + a)
				if c > 0:
					v = minf(v, d[k - n - 1] + b)
				if c < n - 1:
					v = minf(v, d[k - n + 1] + b)
			d[k] = v
	for r in range(n - 1, -1, -1):
		for c in range(n - 1, -1, -1):
			var k := r * n + c
			var v := d[k]
			if v == 0.0:
				continue
			if c < n - 1:
				v = minf(v, d[k + 1] + a)
			if r < n - 1:
				v = minf(v, d[k + n] + a)
				if c < n - 1:
					v = minf(v, d[k + n + 1] + b)
				if c > 0:
					v = minf(v, d[k + n - 1] + b)
			d[k] = v
	return d


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


## Every territory's land eases down to 0 m along its border, so a neighbour's
## ground meets this one level at the force-field wall.
func _ease_border() -> void:
	var hs := heights
	var spacing := sample_spacing(n)
	var half := SIZE_M * 0.5
	var reach := ceili(EDGE_BLEND_M / spacing)
	for r in n:
		var dz := half - absf(-half + r * spacing)
		for c in n:
			if r > reach and r < n - 1 - reach and c > reach and c < n - 1 - reach:
				continue
			var dx := half - absf(-half + c * spacing)
			hs[r * n + c] *= smoothstep(0.0, EDGE_BLEND_M, minf(dx, dz))
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


## Relief preview for reviewing landforms: height tinted (0 m dark blue,
## the plateau slate, highlands pale), hillshaded, a contour every 2 m.
func relief_image() -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.75, -0.3).normalized()
	var sp := sample_spacing(n)
	var low := Color("#0a1430")
	var mid := Color("#46506a")
	var top := Color("#e8e2d0")
	for r in n:
		for c in n:
			var hl := heights[r * n + maxi(c - 1, 0)]
			var hr := heights[r * n + mini(c + 1, n - 1)]
			var hu := heights[maxi(r - 1, 0) * n + c]
			var hd := heights[mini(r + 1, n - 1) * n + c]
			var nrm := Vector3(hl - hr, 2.0 * sp, hu - hd).normalized()
			var shade := 0.3 + 0.7 * clampf(nrm.dot(light), 0.0, 1.0)
			var h := heights[r * n + c]
			var base := low.lerp(mid, clampf(h / PLATEAU_M, 0.0, 1.0)) if h < PLATEAU_M \
				else mid.lerp(top, clampf((h - PLATEAU_M) / 20.0, 0.0, 1.0))
			if h < 0.0:
				base = Color("#200a10").lerp(low, clampf(1.0 + h / 8.0, 0.0, 1.0))
			var f := absf(fposmod(h, 2.0) - 1.0)
			if f > 0.93:
				base = base * 0.8
			img.set_pixel(c, r, base * shade)
	return img


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
