class_name LandmarkPlan
extends RefCounted
## The landmark supertall of a developed QING, as numbers. Pure: no scene, no
## network, so every client builds the same tower from the same chain state.
##
## - Its class comes from the Development tier (the Hypobar total at the QING):
##   Wild and Outpost build nothing (they stay moonscape); Settlement a sky inn;
##   Town a grand hotel; City a twisted supertall; Capital a Burj-class tower
##   with a spire.
## - Its height is the Hypobar total's log10, placed within the tier's band in
##   whole 4 m floors. Bars only grow, so the tower only grows.
## - Its site is found on the territory's own land like the Affection Fair's
##   (FairSite.find_site): flat, fully on the plateau, clear of the Core, the
##   arcade, the monolith, the plinth, the skyline and the fair.
## - The base-jump landing ring is found the same way, downrange of the tower.

const FLOOR_M := 4.0
const PLAZA_R := 30.0          ## round terrace that carries the tower (fixed for every tier, so the site never moves)
const RING_R := 14.0           ## the landing zone's terrace
const LIFT_HALF := 2.0         ## the glass lift shaft is 4 × 4 m
const LIFT_GAP := 1.5          ## clearance between the shaft and the tower's face
const PREFER := Vector2(0.0, -150.0 * TerritoryLayout.SCALE)  ## north (≈212 m), beyond the skyline: seen ahead on arrival
const KEEP_CLEAR := [Vector2(0, 0), Vector2(26, 18), Vector2(-26, 18), Vector2(0, -11.5), Vector2(0, 16)]
const CORE_CLEAR := 84.0       ## skyline ring (≤ 46 m) + plaza + margin
const JUMP_MIN_M := 24.0       ## the least drop that is a base jump
const BORDER_KEEP := TerritoryLayout.BORDER_KEEP_M  ## footprints stay inside |x|, |z| ≤ this (338 m; the force fields stand at 362 m)

## Development tier → landmark. Heights are roof metres at the bottom and top of
## the tier's log10 band (the top tier's band is open; it is capped).
const CLASSES := [
	{},  # Wild
	{},  # Outpost
	{"kind": "inn", "title": "Sky Inn", "lo": 64.0, "hi": 112.0, "log_lo": 4.0, "log_hi": 6.0},
	{"kind": "hotel", "title": "Grand Hotel", "lo": 128.0, "hi": 232.0, "log_lo": 6.0, "log_hi": 8.0},
	{"kind": "supertall", "title": "Supertall", "lo": 260.0, "hi": 400.0, "log_lo": 8.0, "log_hi": 9.0},
	{"kind": "burj", "title": "Burj", "lo": 440.0, "hi": 600.0, "log_lo": 9.0, "log_hi": 11.0},
]


## Pure: the landmark for a tier and the Hypobar total's log10. {} below Settlement.
## {kind, title, roof, floors, top (spire tip or roof), deck}
static func spec(tier: int, hypobar_log10: float) -> Dictionary:
	if tier < 2 or tier >= CLASSES.size():
		return {}
	var c: Dictionary = CLASSES[tier]
	var f := clampf((hypobar_log10 - float(c["log_lo"])) / (float(c["log_hi"]) - float(c["log_lo"])), 0.0, 1.0)
	var roof := lerpf(float(c["lo"]), float(c["hi"]), f)
	var floors := int(round(roof / FLOOR_M))
	roof = floors * FLOOR_M
	var top := roof
	if c["kind"] == "burj":
		top = roof + floors_spire(roof)
	elif c["kind"] == "supertall":
		top = roof + 24.0  # the open crown
	return {"kind": c["kind"], "title": c["title"], "roof": roof, "floors": floors, "top": top, "deck": roof}


static func floors_spire(roof: float) -> float:
	return roof * 0.32


## The sign: from the QING's name (the registry snapshot of QING.name()).
static func sign_name(kind: String, qing_name: String) -> String:
	var n := qing_name.strip_edges().to_upper()
	if n.ends_with(" QING"):
		n = n.left(n.length() - 5)
	if n == "":
		n = "QING"
	match kind:
		"burj": return "BURJ " + n
		"supertall": return n + " TOWER"
		"hotel": return "HOTEL " + n
		_: return n + " SKY INN"


# --- Masses ------------------------------------------------------------------
# Each mass is a box {size: Vector3, pos: Vector3 (its centre), yaw} or a
# prism {cyl: radius, h, pos}. Local frame: +Z faces the Core (the front, the
# lobby and the lift), y = 0 on the plaza.

static func masses(s: Dictionary) -> Array:
	var out: Array = []
	if s.is_empty():
		return out
	var roof: float = s["roof"]
	match s["kind"]:
		"inn":
			out.append({"size": Vector3(20, roof, 20), "pos": Vector3(0, roof * 0.5, 0), "yaw": 0.0})
			out.append({"size": Vector3(26, 12, 24), "pos": Vector3(0, 6, -2), "yaw": 0.0})  # podium
		"hotel":
			# A slab with stepped wings: the main block and two lower wings either side
			out.append({"size": Vector3(30, roof, 14), "pos": Vector3(0, roof * 0.5, 0), "yaw": 0.0})
			for side in [-1.0, 1.0]:
				var h1 := roof * 0.72
				out.append({"size": Vector3(12, h1, 12), "pos": Vector3(side * 19.0, h1 * 0.5, -3), "yaw": 0.0})
				var h2 := roof * 0.45
				out.append({"size": Vector3(10, h2, 10), "pos": Vector3(side * 25.0, h2 * 0.5, -6), "yaw": 0.0})
		"supertall":
			# Square, tapering and twisting 45° up its height (24 segments)
			var n := 24
			var seg := roof / n
			for i in n:
				var f := (i + 0.5) / n
				var w := 26.0 * (1.0 - 0.35 * f)
				out.append({"size": Vector3(w, seg + 0.02, w), "pos": Vector3(0, seg * (i + 0.5), 0), "yaw": deg_to_rad(45.0) * f})
		"burj":
			# Y plan: a central core and three wings (at 30°, 150°, 270°) stepping back
			# in a spiral, the way the Burj Khalifa does.
			out.append({"cyl": 9.0, "h": roof, "pos": Vector3(0, roof * 0.5, 0)})
			for wi in 3:
				var a := deg_to_rad(30.0 + 120.0 * wi)
				var dir := Vector2(cos(a), sin(a))
				var y0 := 0.0
				for j in 6:
					var y1 := roof * (0.22 + 0.12 * j + 0.035 * wi)
					var length := 22.0 - j * 2.4
					var width := 10.0 - j * 0.6
					var c := dir * length * 0.5
					out.append({"size": Vector3(length, y1 - y0, width), "pos": Vector3(c.x, (y0 + y1) * 0.5, c.y), "yaw": -a})
					y0 = y1
	return out


## Pure: is (x, z) inside a mass's footprint (any height)?
static func in_footprint(p: Vector2, m: Dictionary) -> bool:
	var c := Vector2(m["pos"].x, m["pos"].z)
	if m.has("cyl"):
		return p.distance_to(c) <= float(m["cyl"])
	var d := (p - c).rotated(float(m["yaw"]))  # into the box's own frame (Godot yaw turns +X toward -Z)
	var sz: Vector3 = m["size"]
	return absf(d.x) <= sz.x * 0.5 and absf(d.y) <= sz.z * 0.5


## How far the masses reach from the axis along a bearing (radians, 0 = +X, π/2 = +Z).
static func reach(ms: Array, bearing: float) -> float:
	var dir := Vector2(cos(bearing), sin(bearing))
	var r := 0.0
	var d := 0.0
	while d < 80.0:
		for m in ms:
			if in_footprint(dir * d, m):
				r = d
				break
		d += 0.5
	return r


## How far the masses at height y reach toward the front (+Z) along x = 0.
static func front_at(ms: Array, y: float) -> float:
	var f := 0.0
	for m in ms:
		var hh: float = (float(m["h"]) if m.has("cyl") else m["size"].y) * 0.5
		if absf(y - m["pos"].y) > hh:
			continue
		var d := 0.0
		while d < 60.0:
			if in_footprint(Vector2(0.0, d), m):
				f = maxf(f, d)
			d += 0.25
	return f


## The glass lift: a shaft on the front (+Z) face. {x, z, half} (its centre).
static func lift(s: Dictionary) -> Dictionary:
	var ms := masses(s)
	var front := 0.0
	for x in [-LIFT_HALF, 0.0, LIFT_HALF]:
		var d := 0.0
		while d < 60.0:
			var inside := false
			for m in ms:
				if in_footprint(Vector2(x, d), m):
					inside = true
					break
			if inside:
				front = maxf(front, d)
			d += 0.25
	return {"x": 0.0, "z": front + LIFT_GAP + LIFT_HALF, "half": LIFT_HALF}


## The sky deck at the roof: a round slab around the axis that also covers the lift's top.
static func deck_radius(s: Dictionary) -> float:
	var ms := masses(s)
	var top := 0.0
	var roof: float = s["roof"]
	for m in ms:
		var y1: float = m["pos"].y + (float(m["h"]) if m.has("cyl") else m["size"].y) * 0.5
		if y1 >= roof - 0.5:
			var reach_xz: float = float(m["cyl"]) if m.has("cyl") else Vector2(m["size"].x, m["size"].z).length() * 0.5
			top = maxf(top, reach_xz)
	var lz: float = lift(s)["z"]
	return maxf(top + 3.0, lz + LIFT_HALF + 2.5)


## The jump plank: the bearing (local) it points along and where it starts and ends.
## It points toward the landing ring, but never over the lift (the front) and, on
## the Burj, out through a gap between the wings. Its tip clears every mass below.
static func plank(s: Dictionary, target_bearing: float) -> Dictionary:
	var ms := masses(s)
	var b := target_bearing
	if s["kind"] == "burj":
		var gaps := [deg_to_rad(210.0), deg_to_rad(330.0)]
		b = gaps[0] if absf(angle_difference(b, gaps[0])) < absf(angle_difference(b, gaps[1])) else gaps[1]
	else:
		var front := PI * 0.5
		var off := angle_difference(front, b)
		if absf(off) < deg_to_rad(55.0):
			b = front + (deg_to_rad(55.0) if off >= 0.0 else -deg_to_rad(55.0))
	var r0 := deck_radius(s) - 1.0
	var r1 := maxf(r0 + 6.0, reach(ms, b) + 4.0)
	return {"bearing": wrapf(b, -PI, PI), "from": r0, "to": r1}


## The tower's yaw (radians, Godot's: local +Z → world angle π/2 − yaw, angles
## measured atan2(z, x)) so the plank points at the ring (world angle `ring_a`)
## and the front faces the Core (world angle `core_a`) as nearly as that allows.
static func orient(s: Dictionary, ring_a: float, core_a: float) -> float:
	var face_core := PI * 0.5 - core_a
	var cands: Array = []
	if s.get("kind", "") == "burj":
		cands = [deg_to_rad(210.0) - ring_a, deg_to_rad(330.0) - ring_a]
	else:
		# The plank may leave anywhere 55°+ from the front: keep facing the Core if the
		# ring already lies there, else turn just enough.
		var b := ring_a + face_core
		if absf(angle_difference(PI * 0.5, b)) >= deg_to_rad(55.0):
			return wrapf(face_core, -PI, PI)
		cands = [deg_to_rad(145.0) - ring_a, deg_to_rad(35.0) - ring_a]
	var best: float = cands[0]
	for y in cands:
		if absf(angle_difference(PI * 0.5 - y, core_a)) < absf(angle_difference(PI * 0.5 - best, core_a)):
			best = y
	return wrapf(best, -PI, PI)


# --- Sites -------------------------------------------------------------------

## Finds a round footprint of `radius` fully on the plateau (heights ≥ land_floor,
## relative to the Core), flattest first, preferring `prefer`, clear of `avoid`
## ([[Vector2 centre, float min distance]…]). The same search as the fair's.
## Pure and deterministic. {ok, at, top, low, land}.
static func find_site(height_fn: Callable, radius: float, avoid: Array, prefer: Vector2, land_floor: float = -2.5, prefer_w: float = 0.05, ideal_dist: float = -1.0, from: Vector2 = Vector2.ZERO) -> Dictionary:
	var best := {"ok": false, "score": INF}
	var fallback := {"ok": false, "land": -1.0}
	var g := TerritoryLayout.grid_steps()
	for gx in range(-g, g + 1):
		for gz in range(-g, g + 1):
			var c := Vector2(gx * 16.0, gz * 16.0)
			if maxf(absf(c.x), absf(c.y)) + radius > BORDER_KEEP:
				continue  # clear of the border fields
			var clear := true
			for a in avoid:
				if c.distance_to(a[0]) < float(a[1]):
					clear = false
					break
			if not clear:
				continue
			var top := -INF
			var low := INF
			var on_land := 0
			var n := 0
			for ring in [0.0, 0.5, 1.0]:
				var steps := 1 if ring == 0.0 else 12
				for i in steps:
					var a := TAU * i / steps
					var p: Vector2 = c + Vector2(cos(a), sin(a)) * radius * ring
					var h: float = height_fn.call(p.x, p.y)
					top = maxf(top, h)
					low = minf(low, h)
					n += 1
					if h >= land_floor:
						on_land += 1
			var land := float(on_land) / n
			if land > fallback["land"]:
				fallback = {"ok": false, "at": c, "top": top, "low": low, "land": land}
			if on_land < n:
				continue
			var score := (top - low) * 4.0
			if ideal_dist > 0.0:
				score += absf(c.distance_to(from) - ideal_dist) * prefer_w
			else:
				score += c.distance_to(prefer) * prefer_w
			if score < best["score"]:
				best = {"ok": true, "at": c, "top": top, "low": low, "land": 1.0, "score": score}
	return best if best["ok"] else fallback


## The tower's site: clear of the Core's landmarks and the skyline, and of the
## other sites already placed (`others`: [[centre, footprint radius], …] — the
## fair, the vehicle pad).
static func tower_site(height_fn: Callable, others: Array = []) -> Dictionary:
	var avoid: Array = [[Vector2.ZERO, CORE_CLEAR]]
	for k in KEEP_CLEAR:
		avoid.append([k, PLAZA_R + 20.0])
	for o in others:
		avoid.append([o[0], float(o[1]) + PLAZA_R + 10.0])
	return find_site(height_fn, PLAZA_R, avoid, PREFER)


## The landing ring: on flat land ~150 m from the tower, clear of everything.
static func ring_site(height_fn: Callable, tower_at: Vector2, others: Array = []) -> Dictionary:
	var avoid: Array = [[Vector2.ZERO, 74.0], [tower_at, PLAZA_R + RING_R + 46.0]]  # 74: clear of the skyline ring too
	for k in KEEP_CLEAR:
		avoid.append([k, RING_R + 30.0])
	for o in others:
		avoid.append([o[0], float(o[1]) + RING_R + 8.0])
	return find_site(height_fn, RING_R, avoid, Vector2.ZERO, -2.5, 0.05, 150.0, tower_at)


# --- The lift ----------------------------------------------------------------

const LIFT_V := 42.0   ## m/s top speed (fast: it is a glass car on the outside)
const LIFT_A := 7.0    ## m/s²


## Seconds for a ride of `h` metres (trapezoid profile: accelerate, cruise, brake).
static func lift_duration(h: float) -> float:
	h = absf(h)
	var d_acc := LIFT_V * LIFT_V / (2.0 * LIFT_A)
	if h <= 2.0 * d_acc:
		return 2.0 * sqrt(h / LIFT_A)
	return 2.0 * LIFT_V / LIFT_A + (h - 2.0 * d_acc) / LIFT_V


## Metres travelled after t seconds of a ride of `h` (0 → h, monotonic).
static func lift_travel(t: float, h: float) -> float:
	h = absf(h)
	var T := lift_duration(h)
	t = clampf(t, 0.0, T)
	var v := minf(LIFT_V, sqrt(h * LIFT_A))  # the peak speed reached
	var ta := v / LIFT_A
	if t < ta:
		return 0.5 * LIFT_A * t * t
	if t > T - ta:
		var r := T - t
		return h - 0.5 * LIFT_A * r * r
	return 0.5 * LIFT_A * ta * ta + v * (t - ta)
