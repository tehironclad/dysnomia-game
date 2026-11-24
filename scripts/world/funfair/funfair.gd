class_name Funfair
extends Node3D
## The Affection Fair — a lived-in night carnival that sits inside every QING.
##
##   var fair := Funfair.new(); parent.add_child(fair); fair.initialize(seed)
##
## Built around the local origin on a flat 80 × 80 m site (y = 0 is the ground; all
## geometry stays inside x, z ∈ [-38, 38]). The entrance arch sits on the +X/−Z corner,
## facing the player spawn; a boardwalk midway of game stalls runs from it to a central
## plaza with the Orbital Carousel. Around the plaza: the Rho Wheel (face-on to the
## entrance), the Pi Drop Tower, the Upsilon Rocket at the far end of the midway as the
## vista, a bandstand and a food court. Everything random is seeded from `seed_value`.
##
## Tiers (QingStanding decides; the fair is earned, not given):
##   0 Surveyed Lot  — roped-off plot, work light, holo "SITE RESERVED" sign + unlock hint
##   1 Night Market  — arch, two stalls by the plaza, string lights, Orbital Carousel, 4 locals
##   2 Fairground    — full midway, games corner, bandstand, Rho Wheel, Pi Drop, ~8 locals
##   3 Grand Fair    — plus the Upsilon Rocket, launch bleachers, fireworks + searchlights, full crowd
##
## Layout is written in midway coordinates (s, w): s runs along the midway from the
## entrance (s ≈ −34.5) through the plaza centre (s = 0) toward the rocket, w across it.

const U := Vector3(-0.78086, 0.0, 0.62469)   # entrance → centre (spawn lies along −U)
const V := Vector3(0.62469, 0.0, 0.78086)    # across the midway
const ARCH_S := -34.0
const MIDWAY_HALF := 3.6
const PLAZA_R := 13.5
const PATH_Y := 0.04
const ROCKET_POS := U * 27.0 + V * 12.0     # off the midway axis (clear of the arch's heart from spawn)

var _rides: Array = []
var _rng := RandomNumberGenerator.new()
var _batch := FairKit.Batch.new()
var _lights: Array = []
var _last_night := -1.0
var _npc_count := 0
var _spare_kinds: Array = []
var _tier := 3
var _npc_cap := 12
var _hint_text := ""
var _hint_label: Label3D
var _beams: Array = []          # [pivot Node3D, phase, outward yaw]
var _vendor_spots: Array = []   # [pos, facing] behind each counter
var _seat_spots: Array = []     # [pos, facing] chairs / bleacher seats
var _bench_spots: Array = []


func initialize(seed_value: int, tier: int = 3) -> void:
	_rng.seed = seed_value
	_tier = clampi(tier, 0, 3)
	_npc_cap = [0, 6, 12, 24][_tier]   # visitors; vendors and the band come on top
	if _tier == 0:
		_build_survey_lot()
	else:
		_build_ground()
		_build_rides(seed_value)
		_build_arch()
		_build_midway_stalls()
		_build_plaza_dressing()
		_build_food_court()
		if _tier >= 2:
			_build_bandstand()
			_build_side_lanes()
			_build_reactor_yard()
			_build_service_area()
			_build_paths_and_garden()
		if _tier >= 3:
			_build_bleachers()
			_build_launch_support()
			_build_headliner()
		_build_perimeter()
	_batch.flush(self)
	_spawn_visitors(seed_value)
	for n in find_children("*", "Light3D", true, false):
		if n.has_meta("base_energy"):
			_lights.append(n)
	_apply_time(true)


func get_rides() -> Array:
	## Only the rides this tier has built.
	return _rides


func get_tier() -> int:
	return _tier


func set_unlock_hint(text: String) -> void:
	## Second line on the tier-0 "SITE RESERVED" sign, e.g. "Unlocks at Standing 250 · this QING: 180".
	## No-op (but remembered) above tier 0.
	_hint_text = text
	if _hint_label:
		_hint_label.text = text
		_fit_label(_hint_label, 9.0)


func _process(_delta: float) -> void:
	_apply_time(false)
	if _beams.size() > 0:
		var t := Time.get_ticks_msec() * 0.001
		for e in _beams:
			var pv: Node3D = e[0]
			var ph: float = e[1]
			var yaw: float = e[2] + 0.75 * sin(t * 0.27 + ph)
			pv.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.32 + 0.14 * sin(t * 0.19 + ph * 1.7))


func _apply_time(force: bool) -> void:
	## Lights come up at dusk: bulbs/signs/pools and real lights follow the sun height.
	# v2: Dysnomia is ~96 AU from the Sun and the Deep Field sky is always dark,
	# so the fair runs its night lighting all the time (bulbs, neon, searchlights).
	var n := 1.0
	if not force and absf(n - _last_night) < 0.004:
		return
	_last_night = n
	FairKit.apply_night(n)
	for l in _lights:
		if is_instance_valid(l):
			var base: float = l.get_meta("base_energy")
			var ds: float = l.get_meta("day_scale")
			(l as Light3D).light_energy = base * lerpf(ds, 1.0, n)


# ─── Helpers ────────────────────────────────────────────────────────────

func _p(s: float, w: float, y: float = 0.0) -> Vector3:
	return U * s + V * w + Vector3(0, y, 0)


func _yaw_to(dir: Vector3) -> float:
	## Yaw that turns a node's local +Z toward `dir`.
	return atan2(dir.x, dir.z)


func _territory_display_name() -> String:
	var gm := get_node_or_null("/root/GameManager")
	var nm: String = String(gm.territory_name).strip_edges() if gm else ""
	if nm.to_upper().ends_with(" QING"):
		nm = nm.substr(0, nm.length() - 5).strip_edges()
	elif nm.to_upper() == "QING":
		nm = ""
	return nm.to_upper()


# ─── Ground ─────────────────────────────────────────────────────────────

func _build_ground() -> void:
	var planks := FairKit.pbr("metal_plate_02", Color(0.55, 0.57, 0.62), 0.5)   # metal deck midway (low albedo: no blow-out under the lamps)
	var pavers := FairKit.pbr("asphalt_02", Color(0.72, 0.72, 0.76), 0.3)
	var kerb := FairKit.pbr("asphalt_02", Color(0.38, 0.38, 0.41), 0.3)
	# Dark regolith apron under the stall fronts on both sides of the deck
	var apron_len := absf(ARCH_S) - PLAZA_R + 1.0
	var apron := FairKit.box(self, Vector3((MIDWAY_HALF + 3.2) * 2.0, PATH_Y * 0.5, apron_len), _p(ARCH_S + apron_len * 0.5, 0, PATH_Y * 0.25), FairKit.pbr("asphalt_02", Color(0.3, 0.3, 0.33), 0.3))
	apron.rotation.y = _yaw_to(U)
	# Boardwalk midway from the arch to the plaza
	var mlen := absf(ARCH_S) - PLAZA_R + 3.0
	var mid := _p(ARCH_S + mlen * 0.5 - 1.0, 0, PATH_Y * 0.5)
	var bw := FairKit.box(self, Vector3(MIDWAY_HALF * 2.0, PATH_Y, mlen), mid, planks)
	bw.rotation.y = _yaw_to(U)
	for side in [-1.0, 1.0]:
		var k := FairKit.box(self, Vector3(0.25, 0.12, mlen), mid + V * side * (MIDWAY_HALF + 0.12) + Vector3(0, 0.04, 0), kerb)
		k.rotation.y = _yaw_to(U)
	# Plaza: paver disc with a darker ring
	FairKit.mesh(self, FairKit.cyl_mesh(PLAZA_R, PLAZA_R, PATH_Y, 64), Vector3(0, PATH_Y * 0.5, 0), pavers)
	FairKit.mesh(self, FairKit.torus_mesh(PLAZA_R - 0.05, PLAZA_R + 0.25, 72, 4), Vector3(0, 0.02, 0), kerb).scale = Vector3(1, 0.4, 1)
	# Spur paths: plaza → each ride / area
	var spurs := [[_p(12.5, 11.5), 6.0]]
	if _tier >= 2:
		spurs += [[_p(-2.0, -14.5), 6.0], [_p(-2.0, 13.5), 5.0], [_p(13.0, -11.5), 6.0]]
	if _tier >= 3:
		spurs.append([_p(16.5, 4.5), 8.0])
	for e in spurs:
		var c: Vector3 = e[0]
		var d: Vector3 = c.normalized()
		var p := FairKit.box(self, Vector3(4.2, PATH_Y, e[1]), Vector3(c.x, PATH_Y * 0.5 - 0.005, c.z), pavers)
		p.rotation.y = _yaw_to(d)


# ─── Rides ──────────────────────────────────────────────────────────────

func _place_ride(r: RideBase, pos: Vector3, facing: Vector3, seed_value: int, mirror: bool = false) -> void:
	if mirror:
		r.booth_local_position.x *= -1.0
		r.exit_local_position.x *= -1.0
	add_child(r)
	r.position = pos
	r.rotation.y = _yaw_to(facing)
	r.setup(seed_value)
	_rides.append(r)


func _build_rides(seed_value: int) -> void:
	_place_ride(OrbitalCarousel.new(), Vector3.ZERO, -U, seed_value + 1)
	if _tier >= 3:
		# Off the midway axis so the arch's heart never sits on the rocket base from spawn
		_place_ride(RocketRide.new(), ROCKET_POS, -U, seed_value + 2)
	if _tier >= 2:
		_place_ride(FerrisWheel.new(), _p(-3.0, -24.0), -U, seed_value + 3, true)
		var dt := _p(-1.0, 22.5)
		_place_ride(DropTower.new(), dt, -dt.normalized(), seed_value + 4)


# ─── Entrance arch ──────────────────────────────────────────────────────

func _build_arch() -> void:
	var root := Node3D.new()
	root.name = "EntranceArch"
	root.position = _p(ARCH_S, 0)
	root.rotation.y = _yaw_to(-U)          # local +Z faces the spawn
	add_child(root)
	var b := FairKit.Batch.new()
	var steel := FairKit.paint(Color(0.92, 0.9, 0.86), 0.3, 0.6, 0.4)
	var red := FairKit.paint(Color(0.62, 0.06, 0.14), 0.35, 0.35, 0.6)
	var gold := FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	var half := 5.4
	var pylon_h := 8.0
	for sx in [-1.0, 1.0]:
		var base := Vector3(sx * half, 0, 0)
		FairKit.box(root, Vector3(1.5, 0.6, 1.5), base + Vector3(0, 0.3, 0), FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3))
		FairKit.mesh(root, FairKit.cyl_mesh(0.42, 0.55, pylon_h, 16), base + Vector3(0, pylon_h * 0.5 + 0.6, 0), red)
		FairKit.mesh(root, FairKit.cyl_mesh(0.62, 0.62, 0.3, 16), base + Vector3(0, pylon_h + 0.75, 0), gold)
		FairKit.crystal_cluster(root, base + Vector3(0, pylon_h + 0.9, 0), _rng, FairKit.NEON_CYAN, 6, 0.9)
		FairKit.crystal_cluster(root, base + Vector3(sx * 0.9, 0.0, 0.9), _rng, FairKit.CRYSTAL_COLORS[1], 4, 0.6)
		FairKit.solid_box(root, Vector3(1.5, 3.0, 1.5), base + Vector3(0, 1.5, 0))
		# Spiral of bulbs round each pylon
		var sp := PackedVector3Array()
		for i in 64:
			var a := i * 0.55
			sp.append(base + Vector3(cos(a) * 0.62, 0.8 + i * 0.115, sin(a) * 0.62))
		b.bulb_line(sp, [FairKit.BULB_WARM, Color(1.0, 0.35, 0.6)], 0.06, 0.06)
		# Balloon bunches tied to the pylons
		for k in 7:
			var off := Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(0.3, 0.9))
			b.balloon(base + Vector3(sx * 0.7, 1.8, 0) + off * 0.5, FairKit.PALETTE[_rng.randi() % 6], _rng.randf())
	# Arched truss between the pylons: two chords + zig-zag web, bulbs along the top
	var top_pts := PackedVector3Array()
	var bot_pts := PackedVector3Array()
	var n := 24
	for i in n + 1:
		var t := float(i) / n
		var x := lerpf(-half, half, t)
		var rise := sin(t * PI) * 2.2
		top_pts.append(Vector3(x, pylon_h + 0.9 + rise + 0.6, 0))
		bot_pts.append(Vector3(x, pylon_h + 0.9 + rise - 0.25, 0))
	for i in n:
		b.strut(top_pts[i], top_pts[i + 1], 0.09, steel)
		b.strut(bot_pts[i], bot_pts[i + 1], 0.09, steel)
		b.strut(bot_pts[i], top_pts[i + 1], 0.04, steel)
		b.strut(bot_pts[i] + Vector3(0, -0.14, 0.1), bot_pts[i + 1] + Vector3(0, -0.14, 0.1), 0.03, FairKit.glow(FairKit.NEON_CYAN, 4.0, 1.0))
	b.bulb_line(top_pts, [FairKit.BULB_WARM, Color(1.0, 0.85, 0.5)], 0.08, 0.085)
	# Neon heart crowning the arch (AFFECTION)
	var heart := PackedVector3Array()
	var hc := Vector3(0, pylon_h + 4.6, 0.12)
	for i in 44:
		var t2 := TAU * i / 44.0
		var hx := 16.0 * pow(sin(t2), 3.0)
		var hy := 13.0 * cos(t2) - 5.0 * cos(2.0 * t2) - 2.0 * cos(3.0 * t2) - cos(4.0 * t2)
		heart.append(hc + Vector3(hx, hy, 0) * 0.075)
	b.bulb_line(heart, [Color(1.0, 0.18, 0.4)], 0.025, 0.09)
	b.strut(Vector3(0, pylon_h + 3.1, 0), hc + Vector3(0, -0.85, -0.1), 0.05, steel)
	# Sign board hung under the arch
	var nm := _territory_display_name()
	var owner_line := ""
	if nm != "":
		owner_line = nm + ("'" if nm.ends_with("S") else "'S")
	var board_y := pylon_h - 0.2
	FairKit.box(root, Vector3(9.2, 2.3, 0.22), Vector3(0, board_y, 0), FairKit.paint(Color(0.05, 0.04, 0.07), 0.5, 0.3))
	FairKit.box(root, Vector3(9.5, 0.1, 0.3), Vector3(0, board_y + 1.2, 0), gold)
	FairKit.box(root, Vector3(9.5, 0.1, 0.3), Vector3(0, board_y - 1.2, 0), gold)
	for sx in [-1.0, 1.0]:
		b.strut(Vector3(sx * 4.0, board_y + 1.15, 0), Vector3(sx * 4.2, pylon_h + 1.0, 0), 0.04, steel)
	var title_px := 118
	if owner_line != "":
		var l1 := FairKit.label(root, owner_line, Vector3(0, board_y + 0.55, 0.13), 74, Color(2.6, 2.2, 1.4))
		l1.outline_size = 10
		_fit_label(l1, 8.6)
	var l2 := FairKit.label(root, "AFFECTION FAIR", Vector3(0, board_y - 0.3 if owner_line != "" else board_y, 0.13), title_px, Color(2.8, 0.9, 1.5))
	l2.outline_size = 14
	_fit_label(l2, 8.8)
	var l3 := FairKit.label(root, "THANKS FOR VISITING", Vector3(0, board_y, -0.13), 72, Color(2.0, 1.7, 1.2), PI)
	_fit_label(l3, 8.6)
	var border := PackedVector3Array()
	for i in 31:
		var x := -4.5 + i * 0.3
		border.append(Vector3(x, board_y + 1.05, 0.14))
		border.append(Vector3(x, board_y - 1.05, 0.14))
	b.bulb_line(border, [FairKit.BULB_WARM], 0.09, 0.05)
	b.pool(Vector3(0, 0.08, 0), 8.0, Color(1.0, 0.55, 0.65) * 0.6)
	b.flush(root)
	FairKit.omni(root, Vector3(0, 6.0, 3.0), Color(1.0, 0.7, 0.7), 3.0, 18.0, 0.0)
	# Turnstile rails and a pay-what-you-love welcome post
	var chrome := FairKit.paint(Color(0.82, 0.82, 0.85), 0.15, 0.95)
	for x in [-3.0, -1.1, 1.1, 3.0]:
		FairKit.beam(root, Vector3(x, 0, -0.6), Vector3(x, 1.0, -0.6), 0.05, chrome)
		FairKit.beam(root, Vector3(x, 1.0, -0.6), Vector3(x, 1.0, 0.8), 0.04, chrome)
		FairKit.beam(root, Vector3(x, 0, 0.8), Vector3(x, 1.0, 0.8), 0.05, chrome)
	FairKit.model(root, "Megaphone_01", Vector3(-4.2, 1.4, 1.2), 0.6, 1.4)
	FairKit.model(root, "wooden_crate_01", Vector3(-4.2, 0.0, 1.2), 0.2, 2.6)


func _fit_label(l: Label3D, max_w: float) -> void:
	## Shrink a Label3D's pixel size so its text fits max_w metres.
	var f := l.font if l.font else ThemeDB.fallback_font
	var w := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size
	if w > max_w:
		l.pixel_size *= max_w / w


# ─── Midway stalls ──────────────────────────────────────────────────────

func _build_midway_stalls() -> void:
	## Moon-native games and food: every stall is themed on Dysnomia lore.
	var kinds := ["entropy", "waat", "regolith", "crystal", "saat", "motzkin", "pulse", "eris"]
	# Deterministic shuffle per QING
	for i in range(kinds.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = kinds[i]; kinds[i] = kinds[j]; kinds[j] = tmp
	var slots := [[-29.0, -1.0], [-29.0, 1.0], [-23.6, -1.0], [-23.6, 1.0], [-18.2, -1.0], [-18.2, 1.0]]
	var first := 4 if _tier == 1 else 0        # Night Market: just the two stalls by the plaza
	for i in range(first, slots.size()):
		var s: float = slots[i][0]
		var side: float = slots[i][1]
		var pos := _p(s, side * (MIDWAY_HALF + 2.0))
		_stall(pos, -V * side, kinds[i], FairKit.AWNING_PAIRS[i % FairKit.AWNING_PAIRS.size()])
	_spare_kinds = [kinds[6], kinds[7]]
	# One shared light per facing pair of stalls, on the centreline (lights both interiors)
	for i in range(first, slots.size(), 2):
		FairKit.omni(self, _p(slots[i][0], 0, 3.0), Color(1.0, 0.76, 0.5), 2.0, 9.5)
	# Lamp posts stand in the GAPS between stalls (never in front of a sign), with a crystal
	# outcrop behind each; string lights zig-zag between them
	var gaps := [-31.65, -26.3, -20.9, -15.55]
	var posts: Array = []
	for s3 in gaps:
		for side in [-1.0, 1.0]:
			var pp := _p(s3, side * (MIDWAY_HALF + 0.45))
			_lamp_post(pp)
			posts.append(pp)
			if _tier >= 2 or s3 > -21.0:
				var cp := _p(s3, side * (MIDWAY_HALF + 1.7))
				FairKit.crystal_cluster(self, cp, _rng, FairKit.CRYSTAL_COLORS[_rng.randi() % 4], 5, 0.5)
				_batch.pool(cp + Vector3(0, 0.08, 0), 1.4, FairKit.NEON_CYAN * 0.25)
	var pal := [FairKit.BULB_WARM, FairKit.NEON_CYAN, Color(1.0, 0.8, 0.35), FairKit.NEON_VIOLET]
	for i in range(0, posts.size() - 2, 2):
		var top := Vector3(0, 3.75, 0)
		_batch.string_lights(posts[i] + top, posts[i + 1] + top, 0.5, 0.42, pal)      # across
		_batch.string_lights(posts[i] + top, posts[i + 3] + top, 0.7, 0.42, pal)      # diagonal
		_batch.string_lights(posts[i + 1] + top, posts[i + 2] + top, 0.7, 0.42, pal)  # diagonal
	_batch.string_lights(posts[posts.size() - 2] + Vector3(0, 3.75, 0), posts[posts.size() - 1] + Vector3(0, 3.75, 0), 0.5, 0.42, pal)
	# Chain conduits: cyan and violet data lines along the kerbs, pulses racing to the plaza
	for side in [-1.0, 1.0]:
		var a := _p(ARCH_S + 1.5, side * (MIDWAY_HALF + 0.28), 0.14)
		var b := _p(-PLAZA_R + 0.5, side * (MIDWAY_HALF + 0.28), 0.14)
		_conduit(a, b, FairKit.NEON_CYAN if side < 0.0 else FairKit.NEON_VIOLET)


func _lamp_post(p: Vector3) -> void:
	## Street lamp with a Dysnomia crystal finial; warm pool on the ground.
	_batch.prop("street_lamp_01", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	FairKit.mesh(self, FairKit.sphere_mesh(0.16, 10), p + Vector3(0, 3.55, 0), FairKit.glow(Color(1.0, 0.82, 0.55), 4.0, 0.4), Vector3.ZERO, false)
	FairKit.crystal_cluster(self, p + Vector3(0, 3.86, 0), _rng, FairKit.CRYSTAL_COLORS[_rng.randi() % 2], 3, 0.32)
	_batch.pool(p + Vector3(0, 0.07, 0), 3.2, Color(1.0, 0.72, 0.42) * 0.3)
	FairKit.solid_cyl(self, 0.18, 3.0, p + Vector3(0, 1.5, 0))


const STALL_TITLES := {
	"entropy": "ENTROPY TOSS", "waat": "WAAT WHEEL OF FORTUNE", "regolith": "REGOLITH RING TOSS",
	"crystal": "CRYSTAL SHY", "saat": "SAAT FORTUNE TELLER", "motzkin": "MOTZKIN PRIME SHOOTER",
	"pulse": "PULSE POPS", "eris": "ERIS ICE",
}


func _stall(pos: Vector3, facing: Vector3, kind: String, pair: Array) -> void:
	## A game/food stall: corrugated walls, metal deck, painted-wood counter, striped awning,
	## an angled lit sign, prize rack, interior light and a vendor behind the counter.
	var root := Node3D.new()
	root.name = "Stall_" + kind
	root.position = pos
	root.rotation.y = _yaw_to(facing)   # local +Z = counter side
	add_child(root)
	var b := FairKit.Batch.new()
	var wall := FairKit.pbr("corrugated_iron", (pair[0] as Color).lerp(Color(0.62, 0.64, 0.7), 0.5), 0.8, 1.0)
	var roof := FairKit.pbr("corrugated_iron", Color(0.32, 0.33, 0.36), 0.8, 1.0)
	var deck := FairKit.pbr("metal_plate_02", Color(0.5, 0.52, 0.56), 0.8)
	var paint_wood := FairKit.pbr("brown_planks_05", (pair[1] as Color).darkened(0.45), 1.2)
	var top_wood := FairKit.pbr("brown_planks_05", Color(0.5, 0.42, 0.36), 1.2)
	var trim := FairKit.paint(Color(0.55, 0.56, 0.6), 0.4, 0.7)
	var dark := FairKit.paint(Color(0.06, 0.05, 0.07), 0.6, 0.2)
	var cool := kind in ["crystal", "saat", "eris", "motzkin"]
	var w := 4.0
	var d := 2.6
	var h := 2.9
	FairKit.box(root, Vector3(w, 0.12, d), Vector3(0, 0.06, 0), deck)
	FairKit.box(root, Vector3(w, h, 0.08), Vector3(0, h * 0.5, -d * 0.5), wall)
	for sx in [-1.0, 1.0]:
		FairKit.box(root, Vector3(0.08, h, d), Vector3(sx * w * 0.5, h * 0.5, 0), wall)
		FairKit.box(root, Vector3(0.14, h + 0.25, 0.14), Vector3(sx * (w * 0.5 - 0.02), (h + 0.25) * 0.5, d * 0.5), trim)
		# Cool neon tube up each front post — the Dysnomia accent
		FairKit.box(root, Vector3(0.04, h - 0.3, 0.04), Vector3(sx * (w * 0.5 - 0.02), h * 0.5, d * 0.5 + 0.09),
			FairKit.glow(FairKit.NEON_VIOLET if cool else FairKit.NEON_CYAN, 2.2, 0.8))
	FairKit.box(root, Vector3(w + 0.1, 0.1, d + 0.1), Vector3(0, h + 0.05, 0), roof)
	# Striped canvas roof so the stall reads as a stall (not a container) from above
	FairKit.awning(root, w + 0.3, d + 0.3, Vector3(0, h + 0.16, -0.05), Vector3(0.06, 0, 0), pair, roundf(w / 0.5))
	# Back of house: service panel, conduit and a cool strip so the backs aren't black boxes
	FairKit.box(root, Vector3(w - 0.6, 1.2, 0.03), Vector3(0, 1.0, -d * 0.5 - 0.055), FairKit.pbr("metal_plate_02", Color(0.6, 0.62, 0.66), 0.8))
	FairKit.box(root, Vector3(w, 0.04, 0.04), Vector3(0, h - 0.1, -d * 0.5 - 0.06), FairKit.glow(FairKit.NEON_CYAN, 2.5, 0.6))
	b.strut(Vector3(-w * 0.5 + 0.2, 0.15, -d * 0.5 - 0.1), Vector3(-w * 0.5 + 0.2, h - 0.2, -d * 0.5 - 0.1), 0.04, trim)
	# Counter: painted planks front, oiled plank top, neon lip
	FairKit.box(root, Vector3(w - 0.2, 1.0, 0.5), Vector3(0, 0.5, d * 0.5 - 0.2), paint_wood)
	FairKit.box(root, Vector3(w - 0.05, 0.07, 0.7), Vector3(0, 1.04, d * 0.5 - 0.15), top_wood)
	FairKit.box(root, Vector3(w - 0.2, 0.03, 0.03), Vector3(0, 0.98, d * 0.5 + 0.06), FairKit.glow(FairKit.NEON_CYAN, 1.6, 0.5))
	# Awning sloping out over the counter
	var tilt := 0.36
	FairKit.awning(root, w + 0.3, 1.9, Vector3(0, h - 0.1 - 0.95 * sin(tilt), d * 0.5 - 0.05 + 0.95 * cos(tilt)), Vector3(tilt, 0, 0), pair)
	# Sign above the awning, turned ~12° toward the entrance so it reads walking in
	var to_arch := root.transform.basis.inverse() * (-U)
	var sign_xf := Transform3D(Basis(Vector3.UP, deg_to_rad(12.0) * signf(to_arch.x)), Vector3(0, h + 0.62, d * 0.5 - 0.1))
	var sign_node := Node3D.new()
	sign_node.transform = sign_xf
	root.add_child(sign_node)
	FairKit.box(sign_node, Vector3(w - 0.4, 0.8, 0.12), Vector3.ZERO, dark)
	var tl := FairKit.label(sign_node, STALL_TITLES.get(kind, "GAMES"), Vector3(0, 0.02, 0.07), 52, (pair[0] as Color).lightened(0.35) * 2.2)
	tl.outline_size = 8
	_fit_label(tl, w - 0.75)
	var border := PackedVector3Array()
	for i in 13:
		var x := -(w - 0.5) * 0.5 + i * (w - 0.5) / 12.0
		border.append(root.transform * sign_xf * Vector3(x, 0.38, 0.08))
		border.append(root.transform * sign_xf * Vector3(x, -0.38, 0.08))
	_batch.bulb_line(border, [FairKit.BULB_WARM], 0.1, 0.04)
	# Bulbs along the awning's front edge
	var edge := PackedVector3Array()
	for i in 11:
		edge.append(root.transform * Vector3(-w * 0.5 + i * w / 10.0, h - 0.1 - 1.9 * sin(tilt) - 0.12, d * 0.5 - 0.05 + 1.9 * cos(tilt)))
	_batch.bulb_line(edge, [pair[1], FairKit.BULB_WARM], 0.15, 0.06)
	# Interior light strips (ceiling + back wall) and a soft pool in front of the counter
	var inner := Color(0.7, 0.6, 1.0) if cool else Color(1.0, 0.85, 0.62)
	FairKit.box(root, Vector3(w - 0.4, 0.05, 0.05), Vector3(0, h - 0.12, d * 0.5 - 0.35), FairKit.glow(inner, 5.0, 1.5))
	FairKit.box(root, Vector3(w - 0.4, 0.04, 0.04), Vector3(0, h - 0.2, -d * 0.5 + 0.1), FairKit.glow(inner, 4.0, 1.2))
	_batch.pool(root.transform * Vector3(0, 0.08, d * 0.5 + 1.0), 2.6, (Color(0.6, 0.6, 1.0) if cool else Color(1.0, 0.7, 0.45)) * 0.2)
	_batch.pool(root.transform * Vector3(0, 0.14, 0.0), 1.8, inner * 0.35)
	_stall_goods(root, b, kind, w, d)
	b.flush(root)
	FairKit.solid_box(root, Vector3(w, h, d - 0.2), Vector3(0, h * 0.5, -0.1))
	# Vendor behind the counter (spawned with the crowd)
	_vendor_spots.append([root.transform * Vector3(-0.7, 0.12, d * 0.5 - 0.95), root.transform.basis * Vector3.BACK])
	# Back-of-house clutter
	for i in 2:
		_batch.prop("Barrel_02" if i == 0 else "Barrel_01", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), root.transform * Vector3(-1.2 + i * 0.7, 0.006, -d * 0.5 - 0.55)))
	FairKit.model(self, "wooden_crate_01", root.transform * Vector3(1.0, 0.0, -d * 0.5 - 0.55), root.rotation.y + _rng.randf_range(-0.3, 0.3))


func _stall_goods(root: Node3D, b: FairKit.Batch, kind: String, w: float, d: float) -> void:
	var cy := 1.075                       # counter top
	var front := d * 0.5 - 0.15
	var back := -d * 0.5
	match kind:
		"entropy":
			# Dice of fate on a violet felt table; every third die is a Dysnomia crystal die
			FairKit.box(root, Vector3(w - 0.4, 0.02, 0.5), Vector3(0, cy + 0.01, front), FairKit.paint(Color(0.22, 0.1, 0.38), 0.95, 0.0))
			var ivory := FairKit.paint(Color(0.95, 0.94, 0.9), 0.25, 0.0, 0.8)
			for i in 9:
				var mat: Material = ivory if i % 3 != 0 else FairKit.crystal_mat(FairKit.CRYSTAL_COLORS[i % 4])
				var dm := FairKit.box(root, Vector3(0.13, 0.13, 0.13), Vector3(-1.6 + i * 0.4, cy + 0.085, front + sin(i * 1.7) * 0.12), mat)
				dm.rotation.y = i * 0.9
			for i in 2:
				FairKit.cyl(root, 0.11, 0.09, 0.22, Vector3(-1.2 + i * 2.4, cy + 0.11, front - 0.15), FairKit.paint(Color(0.35, 0.12, 0.08), 0.6, 0.1), 14)
			_prize_rack(root, w, d)
		"waat":
			# The Waat wheel: striped disc on the back wall, bulbs round the rim, gold pointer
			var disc_mesh := FairKit.cached_mesh("waat_disc", func() -> Mesh:
				return FairKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.05, 0.0)]), 48))
			var disc := FairKit.mesh(root, disc_mesh, Vector3(0, 1.75, back + 0.12), FairKit.shader_mat("fair_awning"))
			disc.rotation.x = PI * 0.5
			disc.set_instance_shader_parameter("color_a", Color(0.1, 0.55, 0.75))
			disc.set_instance_shader_parameter("color_b", Color(0.95, 0.75, 0.2))
			disc.set_instance_shader_parameter("stripes", 12.0)
			FairKit.cyl(root, 0.12, 0.12, 0.1, Vector3(0, 1.75, back + 0.16), FairKit.glow(FairKit.NEON_CYAN, 4.0, 1.5), 16).rotation.x = PI * 0.5
			FairKit.box(root, Vector3(0.12, 0.3, 0.06), Vector3(0, 2.9, back + 0.16), FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95))
			var rim := PackedVector3Array()
			for i in 24:
				var a := TAU * i / 24.0
				rim.append(Vector3(cos(a) * 1.12, 1.75 + sin(a) * 1.12, back + 0.16))
			b.bulb_line(rim, [FairKit.BULB_WARM, FairKit.NEON_CYAN], 0.04, 0.045)
			_mini_rockets(root, Vector3(0, cy, front), 7)
		"regolith":
			# Regolith pegs on a sloped board with glowing tips; rings stacked on the counter
			var board := FairKit.box(root, Vector3(w - 0.4, 0.06, 1.2), Vector3(0, 1.1, -0.45), FairKit.pbr("asphalt_02", Color(0.8, 0.8, 0.85), 1.5))
			board.rotation.x = -0.35
			var rock := FairKit.pbr("asphalt_02", Color(0.85, 0.85, 0.9), 2.0)
			for i in 18:
				var x := -1.5 + (i % 6) * 0.6
				var z := -0.85 + int(i / 6) * 0.4
				var y := 1.1 - (z + 0.45) * tan(0.35) + 0.13
				FairKit.cyl(root, 0.05, 0.08, 0.26, Vector3(x, y, z), rock, 8)
				FairKit.mesh(root, FairKit.sphere_mesh(0.04, 8), Vector3(x, y + 0.15, z), FairKit.glow(FairKit.CRYSTAL_COLORS[i % 4], 4.0, 1.5), Vector3.ZERO, false)
			for i in 6:
				FairKit.mesh(root, FairKit.torus_mesh(0.07, 0.1, 16, 6), Vector3(1.3, cy + 0.02 + i * 0.03, front), FairKit.glow(FairKit.NEON_CYAN if i % 2 == 0 else FairKit.NEON_VIOLET, 2.5, 0.8))
			_prize_rack(root, w, d)
		"crystal":
			# Crystal Shy: crystals perched on posts — knock one off, win it
			var steel := FairKit.paint(Color(0.3, 0.32, 0.36), 0.4, 0.8)
			for i in 6:
				var x2 := -1.5 + i * 0.6
				var top := 1.3 + float(i % 2) * 0.35
				b.strut(Vector3(x2, 0.12, -0.75), Vector3(x2, top, -0.75), 0.03, steel)
				FairKit.crystal_cluster(root, Vector3(x2, top, -0.75), _rng, FairKit.CRYSTAL_COLORS[i % 4], 3, 0.32)
			for i in 7:
				FairKit.mesh(root, FairKit.sphere_mesh(0.07, 10), Vector3(1.2 + (i % 3) * 0.15, cy + 0.07 + int(i / 3) * 0.1, front - 0.1), FairKit.paint(Color(0.85, 0.85, 0.8), 0.6, 0.0))
			_shelves(root, d)
			_crystal_prizes(root, d)
		"saat":
			# Saat Fortune Teller: drapes, a glowing scrying orb, cards laid out on the counter
			var drape := FairKit.paint(Color(0.24, 0.07, 0.34), 0.92, 0.0)
			var drape2 := FairKit.paint(Color(0.17, 0.05, 0.25), 0.92, 0.0)
			# Pleated back curtain (alternating folds) + tied-back front curtains
			for i in 16:
				var px := -(w - 0.4) * 0.5 + (i + 0.5) * (w - 0.4) / 16.0
				FairKit.box(root, Vector3((w - 0.4) / 16.0 + 0.01, 2.6, 0.05), Vector3(px, 1.42, back + 0.1 + 0.05 * float(i % 2)), drape if i % 2 == 0 else drape2)
			FairKit.box(root, Vector3(w - 0.3, 0.08, 0.1), Vector3(0, 2.72, back + 0.12), FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95))
			for sx in [-1.0, 1.0]:
				var cur := FairKit.cyl(root, 0.08, 0.28, 2.2, Vector3(sx * (w * 0.5 - 0.3), 1.6, d * 0.5 - 0.42), drape, 10)
				cur.scale = Vector3(1, 1, 0.5)
				FairKit.mesh(root, FairKit.torus_mesh(0.1, 0.14, 12, 4), Vector3(sx * (w * 0.5 - 0.3), 1.5, d * 0.5 - 0.42), FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95))
			# Moon phases across the back curtain
			for i in 5:
				var mp := Vector3(-1.2 + i * 0.6, 2.35, back + 0.2)
				FairKit.mesh(root, FairKit.sphere_mesh(0.09, 12), mp, FairKit.glow(Color(0.85, 0.8, 1.0), 1.6, 0.8), Vector3.ZERO, false)
				FairKit.mesh(root, FairKit.sphere_mesh(0.092, 12), mp + Vector3(-0.09 + i * 0.045, 0, 0.03), drape2, Vector3.ZERO, false)
			# Table cloth with gold fringe, candles, the reader's stool
			FairKit.cyl(root, 0.45, 0.4, 0.85, Vector3(0, 0.55, -0.3), FairKit.paint(Color(0.1, 0.05, 0.12), 0.6, 0.2), 16)
			FairKit.cyl(root, 0.14, 0.18, 0.12, Vector3(0, 1.03, -0.3), FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95), 16)
			FairKit.mesh(root, FairKit.torus_mesh(0.42, 0.47, 32, 4), Vector3(0, 0.98, -0.3), FairKit.paint(Color(0.95, 0.74, 0.32), 0.3, 0.9))
			FairKit.mesh(root, FairKit.sphere_mesh(0.26, 24), Vector3(0, 1.35, -0.3), FairKit.glass(Color(0.75, 0.7, 1.0, 0.22)), Vector3.ZERO, false)
			FairKit.mesh(root, FairKit.sphere_mesh(0.13, 16), Vector3(0, 1.35, -0.3), FairKit.glow(Color(0.7, 0.5, 1.0), 4.0, 1.6), Vector3.ZERO, false)
			FairKit.crystal_cluster(root, Vector3(0, 1.2, -0.3), _rng, FairKit.NEON_VIOLET, 3, 0.18)
			for sx in [-0.32, 0.32]:
				FairKit.cyl(root, 0.03, 0.03, 0.16, Vector3(sx, 1.08, -0.12), FairKit.paint(Color(0.92, 0.9, 0.82), 0.6, 0.0), 8)
				FairKit.mesh(root, FairKit.sphere_mesh(0.022, 6), Vector3(sx, 1.18, -0.12), FairKit.glow(Color(1.0, 0.7, 0.35), 5.0, 1.5), Vector3.ZERO, false)
			b.pool(Vector3(0, 1.0, -0.3), 0.9, Color(0.7, 0.5, 1.0) * 0.5)
			for i in 5:
				var cd := FairKit.box(root, Vector3(0.14, 0.01, 0.22), Vector3(-0.9 + i * 0.45, cy + 0.01, front), FairKit.paint(Color(0.12, 0.08, 0.2), 0.5, 0.2))
				cd.rotation.y = (i - 2) * 0.12
				FairKit.box(root, Vector3(0.08, 0.012, 0.12), Vector3(-0.9 + i * 0.45, cy + 0.012, front), FairKit.glow(FairKit.CRYSTAL_COLORS[i % 4], 3.0, 1.0)).rotation.y = (i - 2) * 0.12
			var stars := PackedVector3Array()
			for i in 22:
				stars.append(Vector3(_rng.randf_range(-1.7, 1.7), _rng.randf_range(1.3, 2.6), back + 0.14))
			b.bulb_line(stars, [Color(0.85, 0.8, 1.0)], 0.13, 0.025)
		"motzkin":
			# Motzkin Prime Shooter: only the prime targets score
			var primes := ["2", "3", "5", "7", "11", "13", "17", "19"]
			for i in primes.size():
				var tp := Vector3(-1.5 + (i % 4) * 1.0, 1.45 + int(i / 4) * 0.75, back + 0.12)
				FairKit.cyl(root, 0.26, 0.26, 0.04, tp, FairKit.paint(Color(0.92, 0.92, 0.9), 0.4, 0.1), 24).rotation.x = PI * 0.5
				FairKit.mesh(root, FairKit.torus_mesh(0.17, 0.21, 24, 4), tp + Vector3(0, 0, 0.03), FairKit.glow(FairKit.CRYSTAL_COLORS[i % 4], 3.5, 1.2), Vector3(PI * 0.5, 0, 0), false)
				var lb := FairKit.label(root, primes[i], tp + Vector3(0, 0, 0.04), 36, Color(0.1, 0.08, 0.12), 0.0, Color(0, 0, 0, 0))
				lb.shaded = true
			var gun := FairKit.paint(Color(0.18, 0.19, 0.22), 0.35, 0.8)
			for i in 3:
				var gp := Vector3(-1.2 + i * 1.2, cy + 0.08, front)
				FairKit.box(root, Vector3(0.1, 0.12, 0.42), gp, gun)
				FairKit.cyl(root, 0.025, 0.025, 0.3, gp + Vector3(0, 0.03, -0.3), gun, 8).rotation.x = PI * 0.5
				FairKit.box(root, Vector3(0.03, 0.03, 0.2), gp + Vector3(0, 0.08, -0.05), FairKit.glow(Color(1.0, 0.25, 0.3), 4.0, 1.5))
		"pulse":
			# Pulse Pops: neon candy that beats with the chain
			var stick := FairKit.paint(Color(0.9, 0.9, 0.88), 0.5, 0.0)
			for i in 14:
				var p := Vector3(-1.6 + (i % 7) * 0.53, cy + 0.32 + int(i / 7) * 0.18, front - 0.1 - int(i / 7) * 0.18)
				b.strut(p - Vector3(0, 0.3, 0), p, 0.008, stick)
				FairKit.mesh(root, FairKit.sphere_mesh(0.07, 10), p + Vector3(0, 0.05, 0), FairKit.glow(FairKit.PALETTE[i % 6], 3.5, 1.5), Vector3.ZERO, false)
			FairKit.box(root, Vector3(1.4, 0.95, 0.7), Vector3(-0.9, 0.6, -0.6), FairKit.paint(Color(0.85, 0.88, 0.92), 0.25, 0.6))
			_prize_rack(root, w, d, 1.7)
		"eris":
			# Eris Ice: frozen-volatile sorbets in a frosted freezer, cones on the counter
			FairKit.box(root, Vector3(2.4, 0.9, 0.8), Vector3(0, 0.57, -0.5), FairKit.paint(Color(0.82, 0.86, 0.92), 0.3, 0.6))
			FairKit.box(root, Vector3(2.3, 0.04, 0.72), Vector3(0, 1.04, -0.5), FairKit.glass(Color(0.75, 0.9, 1.0, 0.3)))
			var flav := [Color(0.7, 0.92, 1.0), Color(0.92, 0.75, 1.0), Color(0.75, 1.0, 0.88), Color(1.0, 0.8, 0.9)]
			for i in 6:
				FairKit.cyl(root, 0.15, 0.15, 0.1, Vector3(-0.9 + (i % 3) * 0.9, 1.0, -0.65 + int(i / 3) * 0.3), FairKit.paint(flav[i % 4], 0.85, 0.0), 16)
			var cone := FairKit.paint(Color(0.8, 0.6, 0.35), 0.8, 0.0)
			for i in 5:
				var p2 := Vector3(-1.4 + i * 0.7, cy + 0.12, front)
				FairKit.cyl(root, 0.05, 0.0, 0.2, p2, cone, 10)
				FairKit.mesh(root, FairKit.sphere_mesh(0.065, 10), p2 + Vector3(0, 0.13, 0), FairKit.paint(flav[i % 4], 0.85, 0.0))
			_prize_rack(root, w, d, 1.75)


func _shelves(root: Node3D, d: float) -> void:
	for i in 2:
		FairKit.model(root, "wooden_display_shelves_01", Vector3(-0.95 + i * 1.9, 0.12, -d * 0.5 + 0.3), PI * 0.5)


func _crystal_prizes(root: Node3D, d: float) -> void:
	## Crystal shards lined up on the prize shelves.
	for i in 2:
		var x := -0.95 + i * 1.9
		for lvl in 3:
			for j in 4:
				var p := Vector3(x - 0.38 + j * 0.25, 0.12 + 0.42 + lvl * 0.42, -d * 0.5 + 0.32)
				var mi := FairKit.mesh(root, FairKit.crystal_mesh(), p, FairKit.crystal_mat(FairKit.CRYSTAL_COLORS[(j + lvl) % 4]), Vector3.ZERO, false)
				mi.scale = Vector3.ONE * 0.35


func _mini_rockets(root: Node3D, at: Vector3, n: int) -> void:
	## Toy Upsilon rockets — the souvenir everyone wants.
	var hull := FairKit.cached_mesh("mini_rocket", func() -> Mesh:
		return FairKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.01), Vector2(0.06, 0.05),
			Vector2(0.06, 0.22), Vector2(0.035, 0.3), Vector2(0.0, 0.34)]), 12))
	var cols := [Color(0.9, 0.9, 0.88), Color(0.85, 0.12, 0.18), Color(0.2, 0.55, 0.9)]
	for i in n:
		FairKit.mesh(root, hull, at + Vector3(-1.6 + i * 0.53, 0.0, sin(i * 2.1) * 0.08), FairKit.paint(cols[i % 3], 0.3, 0.3, 0.8))


func _teddies(root: Node3D, count: int, w: float, y0: float) -> void:
	## Plush teddy-astronaut prizes (the players' own mascot) hung along the back wall.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _teddy_mesh()
	mm.instance_count = count
	var cols := [Color(0.85, 0.85, 0.9), Color(0.55, 0.75, 0.95), Color(0.95, 0.85, 0.5), Color(0.75, 0.6, 0.95), Color(0.6, 0.9, 0.85)]
	for i in count:
		var row := i / 8
		var x := -w * 0.5 + 0.45 + (i % 8) * (w - 0.9) / 7.0
		var y := y0 + row * 0.55
		var sc := 0.9 + 0.5 * float(i % 3 == 0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3(x, y, -1.1)))
		mm.set_instance_color(i, cols[i % cols.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.rim_enabled = true
	m.rim = 0.7
	m.rim_tint = 0.8
	mmi.material_override = m
	root.add_child(mmi)


func _teddy_mesh() -> Mesh:
	## Teddy astronaut: plush body and head with a backpack, suit collar and helmet ring.
	return FairKit.cached_mesh("teddy", func() -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var parts := [[0.13, Vector3(0, 0.13, 0), Vector3(1, 1.05, 0.85)], [0.1, Vector3(0, 0.31, 0.01), Vector3.ONE],
			[0.04, Vector3(-0.08, 0.39, 0), Vector3.ONE], [0.04, Vector3(0.08, 0.39, 0), Vector3.ONE],
			[0.045, Vector3(0, 0.29, 0.09), Vector3(1, 0.8, 0.8)], [0.05, Vector3(-0.11, 0.17, 0.04), Vector3(1, 1.4, 1)],
			[0.05, Vector3(0.11, 0.17, 0.04), Vector3(1, 1.4, 1)], [0.055, Vector3(-0.07, 0.02, 0.07), Vector3.ONE],
			[0.055, Vector3(0.07, 0.02, 0.07), Vector3.ONE], [0.045, Vector3(0, 0.15, -0.12), Vector3(1.6, 1.8, 0.8)]]
		for p in parts:
			st.append_from(FairKit.sphere_mesh(p[0], 10), 0, Transform3D(Basis.from_scale(p[2]), p[1]))
		st.append_from(FairKit.torus_mesh(0.1, 0.13, 16, 6), 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.235, 0)))
		st.append_from(FairKit.torus_mesh(0.135, 0.16, 16, 6), 0, Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 0.32, 0.0)))
		return st.commit())


# ─── Plaza ──────────────────────────────────────────────────────────────

func _build_plaza_dressing() -> void:
	## Lamp posts sit between the spur paths (never in front of the carousel or a booth),
	## swagged with string lights; benches, bins and crystal planters beside them.
	var angles := [-153.0, -106.0, -61.0, -16.0, 29.0, 75.0, 113.0, 162.0]
	var posts: Array = []
	var sightlines := _booth_sightlines()
	for deg in angles:
		var a := deg_to_rad(deg)
		var p := Vector3(cos(a), 0, sin(a)) * (PLAZA_R - 0.4)
		for tries in 8:   # slide along the ring until no booth sign is blocked
			if not _blocks_sign(p, sightlines):
				break
			a += deg_to_rad(5.0)
			p = Vector3(cos(a), 0, sin(a)) * (PLAZA_R - 0.4)
		posts.append(p)
		_lamp_post(p)
	for i in posts.size():
		var a3: Vector3 = posts[i] + Vector3(0, 3.75, 0)
		var b3: Vector3 = posts[(i + 1) % posts.size()] + Vector3(0, 3.75, 0)
		_batch.string_lights(a3, b3, 0.8, 0.45, [FairKit.BULB_WARM, FairKit.NEON_VIOLET, FairKit.NEON_CYAN], 0.06)
	for i in angles.size():
		var a2 := deg_to_rad(angles[i] + 8.0)
		var d := Vector3(cos(a2), 0, sin(a2))
		var p2 := d * (PLAZA_R - 1.2)
		if i % 2 == 0:
			var bench := FairKit.model(self, "painted_wooden_bench", p2 + Vector3(0, PATH_Y, 0), _yaw_to(-d))
			bench.name = "Bench"
			FairKit.solid_box(self, Vector3(1.2, 0.9, 0.5), p2 + Vector3(0, 0.45, 0), _yaw_to(-d))
			_bench_spots.append([p2 + Vector3(0, PATH_Y, 0), -d])
			var bin := p2 + d.cross(Vector3.UP) * 1.0
			FairKit.model(self, "metal_trash_can", bin + Vector3(0, PATH_Y + 0.072, 0), _rng.randf() * TAU)
			FairKit.solid_cyl(self, 0.3, 1.0, bin + Vector3(0, 0.5, 0))
		else:
			# Crystal planter: a regolith boulder bed with a glowing outcrop
			var bed := FairKit.model(self, "moon_rock_03", p2, _rng.randf() * TAU, 12.0)
			bed.scale.y *= 1.4
			FairKit.crystal_cluster(self, p2 + Vector3(0, 0.3, 0), _rng, FairKit.CRYSTAL_COLORS[i % 4], 6, 0.7)
			_batch.pool(p2 + Vector3(0, 0.08, 0), 2.0, FairKit.CRYSTAL_COLORS[i % 4] * 0.3)
	FairKit.omni(self, _p(-PLAZA_R + 2.0, 6.0, 4.0), Color(1.0, 0.75, 0.5), 2.0, 14.0)
	FairKit.omni(self, _p(PLAZA_R - 3.0, -6.0, 4.0), Color(1.0, 0.75, 0.5), 2.0, 14.0)
	# Balloon seller by the midway mouth
	var seller := _p(-PLAZA_R - 2.5, -2.4)
	_batch.strut(seller, seller + Vector3(0, 1.3, 0), 0.025, FairKit.paint(Color(0.85, 0.85, 0.85), 0.3, 0.8))
	for k in 16:
		var off := Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.0, 0.7), _rng.randf_range(-0.6, 0.6))
		_batch.balloon(seller + Vector3(0, 1.3, 0) + off * 0.3, FairKit.PALETTE[_rng.randi() % 6], _rng.randf())


func _booth_sightlines() -> Array:
	## [kiosk position, facing] for every ride ticket booth (its sign faces `facing`).
	var out: Array = []
	for r in _rides:
		var ride: RideBase = r
		var bp: Vector3 = ride.transform * ride.booth_local_position
		var f: Vector3 = ride.transform.basis * Vector3(signf(ride.booth_local_position.x) * 0.15, 0, 1)
		f = Vector3(f.x, 0, f.z).normalized()
		out.append([bp - f * 1.7, f])
	return out


func _blocks_sign(p: Vector3, sightlines: Array) -> bool:
	## True when p stands within 2 m of a booth or in the 14 m view corridor in front of its sign.
	for e in sightlines:
		var k: Vector3 = e[0]
		var f: Vector3 = e[1]
		var d := Vector3(p.x - k.x, 0, p.z - k.z)
		var along := d.dot(f)
		var side := (d - f * along).length()
		if d.length() < 2.5 or (along > 0.0 and along < 14.0 and side < 1.8 + along * 0.12):
			return true
	return false


# ─── Bandstand ──────────────────────────────────────────────────────────

func _build_bandstand() -> void:
	var c := _p(13.0, -17.5)
	var root := Node3D.new()
	root.name = "Bandstand"
	root.position = c
	root.rotation.y = _yaw_to(-c.normalized())
	add_child(root)
	var b := FairKit.Batch.new()
	var white := FairKit.paint(Color(0.93, 0.92, 0.88), 0.35, 0.3)
	var gold := FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	var r := 4.6
	FairKit.mesh(root, FairKit.cyl_mesh(r, r + 0.2, 0.9, 8), Vector3(0, 0.45, 0), FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3)).rotation.y = PI / 8.0
	FairKit.mesh(root, FairKit.cyl_mesh(r - 0.15, r - 0.15, 0.06, 8), Vector3(0, 0.93, 0), FairKit.pbr("brown_planks_05", Color(0.75, 0.55, 0.38), 0.8)).rotation.y = PI / 8.0
	FairKit.solid_cyl(self, r, 1.0, c + Vector3(0, 0.5, 0))
	for s in 4:
		FairKit.box(root, Vector3(2.4, 0.225 * (s + 1), 0.4), Vector3(0, 0.1125 * (s + 1), r + 0.2 + (3 - s) * 0.4), white)
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector3(cos(a), 0, sin(a)) * (r - 0.35)
		b.strut(p + Vector3(0, 0.95, 0), p + Vector3(0, 4.4, 0), 0.1, white)
	var dome := PackedVector2Array()
	for i in 10:
		var u := float(i) / 9.0
		dome.append(Vector2(lerpf(r + 0.5, 0.0, u), 4.4 + sin(u * PI * 0.5) * 2.0 + (0.0 if i < 9 else 0.0)))
	var roof := FairKit.mesh(root, _dome_mesh(dome), Vector3.ZERO, FairKit.shader_mat("fair_awning"))
	roof.set_instance_shader_parameter("color_a", Color(0.1, 0.32, 0.6))
	roof.set_instance_shader_parameter("color_b", Color(0.95, 0.92, 0.85))
	roof.set_instance_shader_parameter("stripes", 16.0)
	FairKit.mesh(root, FairKit.torus_mesh(r + 0.35, r + 0.55, 48, 6), Vector3(0, 4.4, 0), gold)
	b.strut(Vector3(0, 6.3, 0), Vector3(0, 7.6, 0), 0.05, gold)
	FairKit.mesh(root, FairKit.sphere_mesh(0.22, 12), Vector3(0, 7.7, 0), FairKit.glow(Color(1.0, 0.75, 0.4), 6.0, 1.0), Vector3.ZERO, false)
	b.bulb_line(FairKit.ring_points(Vector3(0, 4.25, 0), r + 0.48, 56), [FairKit.BULB_WARM, Color(0.45, 0.8, 1.0)], 0.05, 0.07)
	# Speaker stacks, a boom stand with the megaphone, bunting from the roof to poles
	var spk := FairKit.paint(Color(0.07, 0.07, 0.08), 0.7, 0.1)
	for sx in [-1.0, 1.0]:
		FairKit.box(root, Vector3(0.8, 1.6, 0.6), Vector3(sx * 3.0, 1.75, -1.6), spk)
		FairKit.box(root, Vector3(0.6, 0.6, 0.02), Vector3(sx * 3.0, 2.0, -1.29), FairKit.paint(Color(0.2, 0.2, 0.22), 0.9, 0.0))
		FairKit.box(root, Vector3(0.62, 0.05, 0.02), Vector3(sx * 3.0, 1.15, -1.29), FairKit.glow(Color(0.4, 1.0, 0.6), 3.0, 1.0))
	FairKit.model(root, "Megaphone_01", Vector3(0.0, 2.25, 1.2), PI * 0.5, 1.2)
	b.strut(Vector3(0, 0.95, 1.25), Vector3(0, 2.1, 1.25), 0.02, FairKit.paint(Color(0.6, 0.6, 0.62), 0.3, 0.9))
	var lab := FairKit.label(root, "LIVE ON THE MOON", Vector3(0, 3.9, r * 0.92), 44, Color(2.2, 1.8, 1.2))
	lab.outline_size = 6
	b.flush(root)
	FairKit.spot(root, Vector3(0, 6.0, 0.5), Vector3(0, 0.9, 0.6), Color(1.0, 0.6, 0.85), 6.0, 10.0, 40.0, 0.0)
	_batch.pool(c + Vector3(0, 0.08, 0) + (-c.normalized()) * 5.5, 5.0, Color(1.0, 0.55, 0.75) * 0.45)


func _dome_mesh(prof: PackedVector2Array) -> Mesh:
	# Reverse so UV.y runs apex(0) → rim(1) for the scalloped awning edge
	var rev := PackedVector2Array()
	for i in range(prof.size() - 1, -1, -1):
		rev.append(prof[i])
	return FairKit.lathe(rev, 32)


# ─── Food court ─────────────────────────────────────────────────────────

func _build_food_court() -> void:
	var c := _p(12.5, 17.5)
	var face := -c.normalized()
	var yaw := _yaw_to(face)
	var basis := Basis(Vector3.UP, yaw)
	FairKit.box(self, Vector3(12.0, PATH_Y, 9.0), c + Vector3(0, PATH_Y * 0.5 + 0.005, 0), FairKit.pbr("metal_plate_02", Color(0.55, 0.57, 0.62), 0.5)).rotation.y = yaw
	var cart := FairKit.model(self, "CoffeeCart_01", c + basis * Vector3(0.0, PATH_Y, -3.2), yaw)
	cart.name = "CocoaCart"
	FairKit.solid_box(self, Vector3(2.2, 1.7, 1.1), c + basis * Vector3(-0.3, 0.85, -3.2), yaw)
	var cart_sign := FairKit.label(self, "HECKE HOTDOGS  ·  LUNAR COCOA", c + basis * Vector3(-0.3, 2.35, -2.75), 40, Color(2.0, 1.5, 0.9), yaw)
	cart_sign.outline_size = 6
	_vendor_spots.append([c + basis * Vector3(-0.3, PATH_Y, -4.1), basis * Vector3.BACK])
	# Queue rails in front of the cart
	_queue_rails(c + basis * Vector3(-0.3, 0, -2.2), basis * Vector3.BACK, 3.0, Color(0.9, 0.55, 0.2))
	_batch.pool(c + basis * Vector3(0, 0.08, -2.0), 3.5, Color(1.0, 0.7, 0.4) * 0.45)
	var tables := [Vector3(-3.8, 0, 0.2), Vector3(0.0, 0, 1.0), Vector3(3.8, 0, 0.2), Vector3(-2.0, 0, 3.3), Vector3(2.0, 0, 3.3)]
	for t in tables:
		var tp: Vector3 = c + basis * t
		var ty := yaw + _rng.randf_range(-0.4, 0.4)
		_table(tp, ty)
	# Four poles with a canopy of string lights
	var poles := [Vector3(-5.6, 0, -4.3), Vector3(5.6, 0, -4.3), Vector3(5.6, 0, 4.3), Vector3(-5.6, 0, 4.3)]
	var wp: Array = []
	var pole_m := FairKit.paint(Color(0.2, 0.18, 0.16), 0.6, 0.4)
	for p in poles:
		var q: Vector3 = c + basis * p
		_batch.strut(q, q + Vector3(0, 4.6, 0), 0.07, pole_m)
		wp.append(q + Vector3(0, 4.5, 0))
	var pal := [FairKit.BULB_WARM, Color(1.0, 0.85, 0.55), FairKit.NEON_CYAN]
	for i in 4:
		_batch.string_lights(wp[i], wp[(i + 1) % 4], 0.5, 0.4, pal, 0.0)
	_batch.string_lights(wp[0], wp[2], 1.2, 0.4, pal, 0.0)
	_batch.string_lights(wp[1], wp[3], 1.2, 0.4, pal, 0.0)
	FairKit.omni(self, c + Vector3(0, 3.6, 0), Color(1.0, 0.75, 0.48), 2.2, 13.0)
	_batch.pool(c + Vector3(0, 0.08, 0), 6.5, Color(1.0, 0.72, 0.45) * 0.3)
	for i in 3:
		_batch.prop("Barrel_01", Transform3D(Basis(Vector3.UP, i * 1.1), c + basis * Vector3(-5.6 + i * 0.6, 0.006, -3.6)))


# ─── Side lanes: games corner and crew yard ───────────────────────────

func _build_side_lanes() -> void:
	var pavers := FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3)
	for side in [-1.0, 1.0]:
		var a := _p(-14.0, side * (MIDWAY_HALF + 0.3))
		var b := _p(-14.0, side * 31.0)
		var pth := FairKit.box(self, Vector3(3.6, PATH_Y, a.distance_to(b)), (a + b) * 0.5 + Vector3(0, PATH_Y * 0.5 - 0.004, 0), pavers)
		pth.rotation.y = _yaw_to(V)
	# Games corner (+w): two more stalls and the high striker
	if _spare_kinds.size() >= 2:
		_stall(_p(-18.5, 27.0), U, _spare_kinds[0], FairKit.AWNING_PAIRS[4])
		_stall(_p(-9.5, 27.5), -U, _spare_kinds[1], FairKit.AWNING_PAIRS[5])
	_high_striker(_p(-14.0, 33.0), -V)
	for i in 4:
		_lamp_post(_p(-14.0 + (2.3 if i % 2 == 0 else -2.3), 9.0 + i * 6.0))
	# Crew yard (−w): container, generators, cable drums, crates — the fair's backstage
	var yard := _p(-15.0, -30.0)
	var yaw := _yaw_to(V)
	var basis := Basis(Vector3.UP, yaw)
	var cont := FairKit.box(self, Vector3(2.44, 2.6, 6.1), yard + basis * Vector3(-1.8, 1.3, 0), FairKit.pbr("corrugated_iron", Color(0.25, 0.45, 0.6), 0.6, 1.0))
	cont.rotation.y = yaw + PI * 0.5
	FairKit.solid_box(self, Vector3(2.44, 2.6, 6.1), yard + basis * Vector3(-1.8, 1.3, 0), yaw + PI * 0.5)
	var stencil := FairKit.label(self, "AFFECTION FAIR  ·  CREW", yard + basis * Vector3(-1.8, 1.7, 1.24), 40, Color(0.9, 0.9, 0.85), yaw)
	stencil.shaded = true
	FairKit.model(self, "portable_generator", yard + basis * Vector3(2.0, 0, -1.0), yaw + 0.3)
	FairKit.model(self, "portable_generator", yard + basis * Vector3(3.2, 0, 0.2), yaw - 0.5)
	for i in 6:
		_batch.prop("Barrel_01" if i % 2 == 0 else "Barrel_02", Transform3D(Basis(Vector3.UP, i * 0.9), yard + basis * Vector3(1.0 + (i % 3) * 0.65, 0.006, 2.2 + int(i / 3) * 0.65)))
	for i in 3:
		FairKit.model(self, "wooden_crate_01", yard + basis * Vector3(-1.2 + i * 0.9, 0.0, 3.6), yaw + i * 0.2)
	FairKit.model(self, "wooden_crate_01", yard + basis * Vector3(-0.75, 0.35, 3.6), yaw + 0.5)
	var cable := FairKit.paint(Color(0.04, 0.04, 0.04), 0.7, 0.0)
	var wheel := _p(-3.0, -23.5)
	_batch.strut(yard + basis * Vector3(2.0, 0.05, -1.0), wheel + Vector3(0, 0.05, 0), 0.035, cable)
	_batch.strut(yard + basis * Vector3(3.2, 0.05, 0.2), _p(-14.0, -4.0, 0.05), 0.035, cable)
	FairKit.omni(self, yard + Vector3(0, 4.0, 0), Color(0.85, 0.9, 1.0), 1.5, 12.0)
	_batch.pool(yard + Vector3(0, 0.08, 0), 5.0, Color(0.7, 0.8, 1.0) * 0.35)


func _high_striker(pos: Vector3, facing: Vector3) -> void:
	## "TEST YOUR AFFECTION" strength tester: a 7 m scale of bulbs and a bell on top.
	var root := Node3D.new()
	root.name = "HighStriker"
	root.position = pos
	root.rotation.y = _yaw_to(facing)
	add_child(root)
	var b := FairKit.Batch.new()
	var red := FairKit.paint(Color(0.7, 0.08, 0.12), 0.35, 0.3, 0.6)
	var gold := FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	FairKit.box(root, Vector3(1.6, 0.25, 1.2), Vector3(0, 0.125, 0), FairKit.pbr("brown_planks_05", Color(0.9, 0.75, 0.6), 1.0))
	FairKit.box(root, Vector3(0.5, 7.2, 0.3), Vector3(0, 3.85, -0.3), red)
	FairKit.box(root, Vector3(0.08, 6.8, 0.08), Vector3(0, 3.8, -0.11), gold)
	FairKit.mesh(root, FairKit.sphere_mesh(0.3, 16), Vector3(0, 7.65, -0.2), gold)
	FairKit.box(root, Vector3(0.6, 0.15, 0.5), Vector3(0, 0.33, 0.3), FairKit.paint(Color(0.2, 0.2, 0.22), 0.4, 0.8))
	FairKit.box(root, Vector3(0.22, 0.16, 0.12), Vector3(0, 4.9, -0.08), FairKit.paint(Color(0.95, 0.95, 0.9), 0.3, 0.6))
	var pts := PackedVector3Array()
	var cols: Array = []
	for i in 22:
		var u := float(i) / 21.0
		pts.append(Vector3(0, 0.8 + u * 6.4, -0.12))
		cols.append(Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.85, 0.2), minf(u * 2.0, 1.0)).lerp(Color(1.0, 0.15, 0.2), maxf(u * 2.0 - 1.0, 0.0)))
	for i in pts.size():
		b.bulb(pts[i] + Vector3(0.2, 0, 0), cols[i], 1.0 - float(i) * 0.03, 0.07)
		b.bulb(pts[i] - Vector3(0.2, 0, 0), cols[i], 1.0 - float(i) * 0.03, 0.07)
	var l := FairKit.label(root, "TEST YOUR AFFECTION", Vector3(0, 2.2, -0.14), 30, Color(2.2, 1.9, 1.3))
	l.rotation.z = PI * 0.5
	b.flush(root)
	FairKit.solid_box(root, Vector3(1.6, 2.0, 1.2), Vector3(0, 1.0, 0))
	_batch.pool(pos + Vector3(0, 0.08, 0), 3.0, Color(1.0, 0.6, 0.4) * 0.5)


# ─── Launch bleachers ──────────────────────────────────────────────────

func _build_bleachers() -> void:
	## Three-tier viewing stand beside the rocket pad (people come to watch launches).
	var c := ROCKET_POS - V * 13.0
	var root := Node3D.new()
	root.name = "LaunchBleachers"
	root.position = c
	root.rotation.y = _yaw_to(V)   # seats face the pad
	add_child(root)
	var wood := FairKit.pbr("brown_planks_05", Color(0.6, 0.52, 0.44), 1.0)
	var steel := FairKit.paint(Color(0.55, 0.57, 0.6), 0.4, 0.8)
	var b := FairKit.Batch.new()
	for tier in 3:
		var z := 1.0 - tier * 0.9
		var y := 0.45 + tier * 0.45
		FairKit.box(root, Vector3(8.0, 0.08, 0.5), Vector3(0, y, z), wood)
		FairKit.box(root, Vector3(8.0, 0.06, 0.4), Vector3(0, y - 0.42, z + 0.45), wood)
		for x in [-3.8, -1.3, 1.3, 3.8]:
			b.strut(Vector3(x, 0, z), Vector3(x, y, z), 0.04, steel)
		for x in [-2.6, 0.6, 2.9]:
			if (tier + int(x)) % 2 == 0:
				_seat_spots.append([root.transform * Vector3(x, y - 0.45, z), root.transform.basis * Vector3.BACK])
	for x in [-4.0, 4.0]:
		b.strut(Vector3(x, 0, -1.0), Vector3(x, 2.4, -1.0), 0.04, steel)
		b.strut(Vector3(x, 2.4, -1.0), Vector3(x, 1.0, 1.4), 0.03, steel)
	b.strut(Vector3(-4.0, 2.4, -1.0), Vector3(4.0, 2.4, -1.0), 0.03, steel)
	b.flush(root)
	var l := FairKit.label(root, "LAUNCH VIEWING", Vector3(0, 2.75, -1.0), 40, Color(2.0, 1.7, 1.2))
	l.outline_size = 6
	FairKit.solid_box(root, Vector3(8.2, 1.5, 3.0), Vector3(0, 0.75, 0.1))


# ─── Perimeter ──────────────────────────────────────────────────────────

func _build_perimeter() -> void:
	## Bunting fence round the site (open at the entrance), lit by crystal-topped lamp posts,
	## with a few distinct boulder groups outside it.
	var lim := 36.5
	var corners := [Vector3(-lim, 0, -lim), Vector3(lim, 0, -lim), Vector3(lim, 0, lim), Vector3(-lim, 0, lim)]
	var pole_m := FairKit.paint(Color(0.85, 0.82, 0.75), 0.5, 0.3)
	var entrance := _p(ARCH_S, 0)
	var pal := [Color(0.85, 0.1, 0.2), Color(0.98, 0.78, 0.15), Color(0.1, 0.45, 0.8), Color(0.95, 0.95, 0.92), Color(0.2, 0.65, 0.4)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var n := int(a.distance_to(b) / 4.6)
		var prev := Vector3.INF
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			if Vector2(p.x - entrance.x, p.z - entrance.z).length() < 9.0:
				prev = Vector3.INF
				continue
			_batch.strut(p, p + Vector3(0, 2.6, 0), 0.05, pole_m)
			if prev != Vector3.INF:
				_batch.bunting(prev + Vector3(0, 2.5, 0), p + Vector3(0, 2.5, 0), 0.45, pal)
				_batch.strut(prev + Vector3(0, 0.9, 0), p + Vector3(0, 0.9, 0), 0.02, pole_m)
			prev = p
		# Lamp posts just inside the fence so the edge of the lot isn't black at night
		var inward := -(a + b).normalized() * 1.3
		for j in 4:
			var lp: Vector3 = a.lerp(b, (j + 0.5) / 4.0) + Vector3(inward.x, 0, inward.z)
			if Vector2(lp.x - entrance.x, lp.z - entrance.z).length() < 11.0:
				continue
			if _clear_of_structures(lp, 2.5):
				_lamp_post(lp)
	# Boulder groups: a few big distinct outcrops rather than a dotted line of pebbles
	var groups := [[corners[1] * 0.98, 3], [corners[2] * 0.98, 4], [corners[3] * 0.98, 3],
		[Vector3(lim + 0.8, 0, -8.0), 2], [Vector3(-8.0, 0, lim + 0.8), 2], [Vector3(-lim - 0.8, 0, 6.0), 2]]
	for g in groups:
		var gc: Vector3 = g[0]
		if Vector2(gc.x - entrance.x, gc.z - entrance.z).length() < 12.0:
			continue
		for i in int(g[1]):
			var off := Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5)) * (0.4 + i * 0.4)
			var pr := gc + off
			pr.x = clampf(pr.x, -37.7, 37.7)
			pr.z = clampf(pr.z, -37.7, 37.7)
			var big := i == 0
			var id := "moon_rock_01" if (i % 2 == 0) else "moon_rock_03"
			var sc := (_rng.randf_range(14.0, 18.0) if big else _rng.randf_range(5.0, 9.0)) * (1.0 if id == "moon_rock_01" else 1.6)
			var rock := FairKit.model(self, id, pr + Vector3(0, -0.004 * sc, 0), _rng.randf() * TAU, sc)
			rock.scale.y *= _rng.randf_range(1.5, 2.6)
			rock.rotation.x = _rng.randf_range(-0.15, 0.15)
			rock.name = "MoonRock"


func _conduit(a: Vector3, b: Vector3, c: Color, r: float = 0.05) -> void:
	## A glowing chain conduit: armoured pipe with light pulses chasing along it.
	_batch.strut(a, b, r, FairKit.paint(Color(0.12, 0.13, 0.16), 0.35, 0.85))
	_batch.strut(a + Vector3(0, r * 0.9, 0), b + Vector3(0, r * 0.9, 0), r * 0.3, FairKit.glow(c, 1.4, 0.6))
	var n := int(a.distance_to(b) / 0.7)
	var pts := PackedVector3Array()
	for i in n:
		pts.append(a.lerp(b, (i + 0.5) / n) + Vector3(0, r * 1.2, 0))
	_batch.bulb_line(pts, [c * 0.7], -0.045, r * 1.1)


func _prize_rack(root: Node3D, w: float, d: float, y0: float = 1.5) -> void:
	## Back-wall pegboard rack with two rows of prizes: teddy astronauts and toy rockets.
	var back := -d * 0.5
	FairKit.box(root, Vector3(w - 0.4, 1.25, 0.04), Vector3(0, y0 + 0.5, back + 0.07), FairKit.pbr("metal_plate_02", Color(0.42, 0.44, 0.5), 1.2))
	FairKit.box(root, Vector3(w - 0.5, 0.04, 0.22), Vector3(0, y0 - 0.1, back + 0.17), FairKit.pbr("brown_planks_05", Color(0.5, 0.42, 0.36), 1.5))
	_teddies(root, 7, w, y0 + 0.55)
	_mini_rockets(root, Vector3(0.0, y0 - 0.08, back + 0.17), 7)


func _table(tp: Vector3, ty: float) -> void:
	## Outdoor table + two chairs (Poly Haven set, chairs along local ±Z); records seats.
	FairKit.model(self, "outdoor_table_chair_set_01", tp + Vector3(0, PATH_Y, 0), ty)
	FairKit.solid_cyl(self, 0.45, 0.8, tp + Vector3(0, 0.4, 0))
	var tb := Basis(Vector3.UP, ty)
	for sz in [-1.0, 1.0]:
		var seat := tp + tb * Vector3(-0.03, PATH_Y, sz * 0.58)
		_seat_spots.append([seat, (tp - seat).normalized()])


func _queue_rails(front: Vector3, out: Vector3, length: float, c: Color) -> void:
	## Two chrome stanchion rails forming a short queue lane leading away along `out`.
	var o := Vector3(out.x, 0, out.z).normalized()
	var side := o.cross(Vector3.UP)
	var chrome := FairKit.paint(Color(0.8, 0.8, 0.82), 0.18, 0.95)
	var rope := FairKit.paint(c.darkened(0.2), 0.6, 0.0)
	var n := int(length / 1.1)
	for sd in [-0.7, 0.7]:
		var prev := Vector3.INF
		for i in n + 1:
			var p: Vector3 = front + o * (i * 1.1) + side * sd
			_batch.strut(p, p + Vector3.UP * 0.95, 0.025, chrome)
			if prev != Vector3.INF:
				_batch.strut(prev + Vector3.UP * 0.9, p + Vector3.UP * 0.9, 0.018, rope)
			prev = p


# ─── Reactor yard, food row, service truck, launch support ───────────────


func _build_reactor_yard() -> void:
	## The fair runs on a chain reactor: a truck-mounted crystal core in the far corner,
	## glowing conduits snaking out to the rides. A food row and tables fill the lane to it.
	var c := _p(19.0, -28.0)
	var yaw := _yaw_to(V)            # truck runs across the lot
	var tb := Basis(Vector3.UP, yaw)
	var steel := FairKit.paint(Color(0.24, 0.25, 0.28), 0.45, 0.8)
	var cab_m := FairKit.paint(Color(0.85, 0.45, 0.1), 0.4, 0.4, 0.5)
	# Flatbed + cab + wheels
	FairKit.box(self, Vector3(2.5, 0.35, 7.4), c + tb * Vector3(0, 1.05, 0), FairKit.pbr("metal_plate_02", Color(0.55, 0.57, 0.6), 0.6, 1.0)).rotation.y = yaw
	FairKit.box(self, Vector3(2.5, 2.1, 2.0), c + tb * Vector3(0, 1.95, 4.4), cab_m).rotation.y = yaw
	FairKit.box(self, Vector3(2.3, 0.8, 0.04), c + tb * Vector3(0, 2.4, 5.42), FairKit.glass(Color(0.4, 0.6, 0.8, 0.5))).rotation.y = yaw
	for zz in [-2.6, 0.0, 3.9]:
		for sx in [-1.15, 1.15]:
			var wm := FairKit.cyl(self, 0.55, 0.55, 0.4, c + tb * Vector3(sx, 0.55, zz), FairKit.paint(Color(0.06, 0.06, 0.07), 0.9, 0.0), 16)
			wm.basis = tb * Basis(Vector3.BACK, PI * 0.5)
	# Reactor: armoured drum, crystal core in a glass column, coolant rings
	var core := c + tb * Vector3(0, 1.25, -1.2)
	FairKit.cyl(self, 1.0, 1.1, 0.5, core + Vector3(0, 0.25, 0), steel, 24)
	FairKit.cyl(self, 0.62, 0.62, 2.6, core + Vector3(0, 1.8, 0), FairKit.glass(Color(0.6, 0.9, 1.0, 0.18)), 24)
	FairKit.crystal_cluster(self, core + Vector3(0, 0.5, 0), _rng, FairKit.NEON_CYAN, 7, 1.15)
	for k in 3:
		FairKit.mesh(self, FairKit.torus_mesh(0.62, 0.78, 32, 6), core + Vector3(0, 0.9 + k * 0.8, 0), FairKit.glow(FairKit.NEON_VIOLET if k == 1 else FairKit.NEON_CYAN, 4.0, 1.5), Vector3.ZERO, false)
	FairKit.cyl(self, 1.0, 0.8, 0.4, core + Vector3(0, 3.3, 0), steel, 24)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		_batch.strut(core + Vector3(cos(a) * 0.95, 0.5, sin(a) * 0.95), core + Vector3(cos(a) * 0.85, 3.2, sin(a) * 0.85), 0.06, steel)
	var lbl := FairKit.label(self, "CHAIN REACTOR · FAIR POWER", c + tb * Vector3(1.27, 1.95, 4.4), 30, Color(0.1, 0.1, 0.12), yaw + PI * 0.5, Color(0, 0, 0, 0))
	lbl.shaded = true
	FairKit.model(self, "portable_generator", c + tb * Vector3(2.4, 0, -3.0), yaw + 0.5)
	FairKit.solid_box(self, Vector3(2.6, 3.0, 9.6), c + tb * Vector3(0, 1.5, 0.6), yaw)
	FairKit.omni(self, core + Vector3(0, 2.0, 0), Color(0.45, 0.85, 1.0), 2.4, 14.0, 0.2)
	_batch.pool(c + Vector3(0, 0.08, 0), 6.0, FairKit.NEON_CYAN * 0.35)
	# Conduits out to the rides (ground-level, pulses running away from the core)
	var feed := core + Vector3(0, -1.15, 0)
	var targets := [_p(-3.0, -24.0), _p(6.0, -12.0), _p(13.0, -17.5)]
	if _tier >= 3:
		targets.append(ROCKET_POS + Vector3(0, 0, 0))
	for t in targets:
		var tt: Vector3 = t
		var mid := Vector3(feed.x, 0.1, tt.z).lerp(Vector3(tt.x, 0.1, feed.z), 0.5)
		_conduit(Vector3(feed.x, 0.1, feed.z), mid, FairKit.NEON_CYAN, 0.06)
		_conduit(mid, Vector3(tt.x, 0.1, tt.z) + (Vector3(feed.x, 0, feed.z) - Vector3(tt.x, 0, tt.z)).normalized() * 5.0, FairKit.NEON_VIOLET, 0.06)
	# Food row: three kiosks facing the lane, tables in front
	var lane_c := _p(9.0, -25.5)
	FairKit.box(self, Vector3(14.0, PATH_Y, 7.0), lane_c + Vector3(0, PATH_Y * 0.5 + 0.004, 0), FairKit.pbr("metal_plate_02", Color(0.55, 0.57, 0.62), 0.5)).rotation.y = _yaw_to(U)
	var foods := [["HECKE HOTDOGS", 0], ["NEBULA NOODLES", 2], ["ERIS ICE", 1]]
	for i in foods.size():
		_kiosk(_p(4.0 + i * 5.0, -30.2), V, foods[i][0], FairKit.AWNING_PAIRS[foods[i][1]])
	for i in 4:
		_table(_p(3.5 + i * 3.6, -23.8 + float(i % 2) * 1.2), _yaw_to(U) + _rng.randf_range(-0.4, 0.4))
	_lamp_post(_p(1.5, -26.5))
	_lamp_post(_p(17.0, -26.0))
	_batch.string_lights(_p(1.5, -26.5, 3.75), _p(17.0, -26.0, 3.75), 1.0, 0.45, [FairKit.BULB_WARM, FairKit.NEON_CYAN])


func _kiosk(pos: Vector3, facing: Vector3, title: String, pair: Array) -> void:
	## Compact food kiosk: corrugated box, serving hatch with awning, lit sign, vendor.
	var root := Node3D.new()
	root.name = "Kiosk"
	root.position = pos
	root.rotation.y = _yaw_to(facing)
	add_child(root)
	var wall := FairKit.pbr("corrugated_iron", (pair[0] as Color).lerp(Color(0.62, 0.64, 0.7), 0.45), 0.8, 1.0)
	FairKit.box(root, Vector3(3.0, 2.6, 2.2), Vector3(0, 1.3, -0.2), wall)
	FairKit.box(root, Vector3(2.4, 0.9, 0.05), Vector3(0, 1.6, 0.92), FairKit.glow(Color(1.0, 0.82, 0.55), 2.2, 0.8))
	FairKit.box(root, Vector3(3.1, 0.08, 0.5), Vector3(0, 1.08, 1.05), FairKit.pbr("brown_planks_05", Color(0.5, 0.42, 0.36), 1.2))
	FairKit.awning(root, 3.2, 1.3, Vector3(0, 2.35, 1.45), Vector3(0.4, 0, 0), pair)
	FairKit.awning(root, 3.3, 2.5, Vector3(0, 2.66, -0.25), Vector3(0.05, 0, 0), pair, 7.0)
	FairKit.box(root, Vector3(2.8, 0.6, 0.1), Vector3(0, 3.0, 0.75), FairKit.paint(Color(0.06, 0.05, 0.07), 0.6, 0.2))
	var l := FairKit.label(root, title, Vector3(0, 3.0, 0.81), 44, (pair[0] as Color).lightened(0.4) * 2.0)
	_fit_label(l, 2.6)
	FairKit.solid_box(root, Vector3(3.0, 2.6, 2.4), Vector3(0, 1.3, -0.1))
	_batch.pool(root.transform * Vector3(0, 0.08, 2.0), 2.6, Color(1.0, 0.72, 0.45) * 0.4)
	_vendor_spots.append([root.transform * Vector3(0.4, 0.0, 0.3), root.transform.basis * Vector3.BACK])


func _build_service_area() -> void:
	## Eris Ice food truck in the +w corner with a queue lane and a few tables.
	var c := _p(12.0, 32.0)
	var face := -V
	var yaw := _yaw_to(face)
	var tb := Basis(Vector3.UP, yaw)
	var body := FairKit.pbr("metal_plate_02", Color(0.82, 0.88, 0.95), 0.7, 1.0)
	# Box truck side-on to the lane; serving hatch on its +Z side
	var tr := Node3D.new()
	tr.name = "ErisIceTruck"
	tr.position = c
	tr.rotation.y = yaw
	add_child(tr)
	FairKit.box(tr, Vector3(6.6, 2.6, 2.4), Vector3(0, 1.75, 0), body)
	FairKit.box(tr, Vector3(1.8, 2.0, 2.3), Vector3(4.2, 1.45, 0), FairKit.paint(Color(0.2, 0.5, 0.75), 0.35, 0.4, 0.5))
	FairKit.box(tr, Vector3(0.04, 0.8, 2.0), Vector3(5.11, 2.0, 0), FairKit.glass(Color(0.4, 0.6, 0.8, 0.5)))
	for xx in [-2.2, 2.0, 4.2]:
		for sz in [-1.15, 1.15]:
			FairKit.cyl(tr, 0.5, 0.5, 0.35, Vector3(xx, 0.5, sz), FairKit.paint(Color(0.06, 0.06, 0.07), 0.9, 0.0), 16).rotation.x = PI * 0.5
	# Livery: Eris-blue lower band, violet pinstripe, frost-crystal decals, roof sign box
	var livery := FairKit.paint(Color(0.12, 0.38, 0.7), 0.35, 0.4, 0.7)
	for sz in [-1.0, 1.0]:
		FairKit.box(tr, Vector3(6.62, 0.7, 0.03), Vector3(0, 0.85, sz * 1.21), livery)
		FairKit.box(tr, Vector3(6.62, 0.05, 0.03), Vector3(0, 1.26, sz * 1.215), FairKit.glow(FairKit.NEON_VIOLET, 2.0, 0.6))
		for xx in [-2.2, 2.0]:
			FairKit.box(tr, Vector3(1.3, 0.55, 0.04), Vector3(xx, 0.75, sz * 1.22), FairKit.paint(Color(0.05, 0.05, 0.06), 0.8, 0.1))
	for i in 4:
		var dc := FairKit.mesh(tr, FairKit.crystal_mesh(), Vector3(1.6 + i * 0.32, 2.6, 1.22), FairKit.crystal_mat(FairKit.CRYSTAL_COLORS[i % 4]), Vector3(0, 0, -0.3 + i * 0.2), false)
		dc.scale = Vector3(0.8, 1.2, 0.15)
	FairKit.box(tr, Vector3(4.2, 0.7, 0.5), Vector3(-0.6, 3.4, 0.6), FairKit.paint(Color(0.06, 0.08, 0.12), 0.5, 0.3))
	var rl := FairKit.label(tr, "ERIS ICE", Vector3(-0.6, 3.42, 0.86), 64, Color(1.0, 1.7, 2.4))
	rl.outline_size = 8
	_fit_label(rl, 3.9)
	# Serving hatch: steel frame, lit interior, prop-up shutter
	var steel := FairKit.paint(Color(0.7, 0.72, 0.76), 0.3, 0.9)
	FairKit.box(tr, Vector3(3.6, 0.08, 0.1), Vector3(-0.4, 2.62, 1.24), steel)
	FairKit.box(tr, Vector3(3.6, 0.08, 0.1), Vector3(-0.4, 1.56, 1.24), steel)
	for xx in [-2.2, 1.4]:
		FairKit.box(tr, Vector3(0.08, 1.1, 0.1), Vector3(xx, 2.09, 1.24), steel)
	FairKit.box(tr, Vector3(3.4, 1.0, 0.04), Vector3(-0.4, 2.1, 1.18), FairKit.glow(Color(0.7, 0.9, 1.0), 1.8, 0.6))
	for i in 5:
		FairKit.cyl(tr, 0.1, 0.1, 0.12, Vector3(-1.6 + i * 0.55, 1.62, 1.0), FairKit.paint([Color(0.7, 0.92, 1.0), Color(0.92, 0.75, 1.0), Color(0.75, 1.0, 0.88)][i % 3], 0.85, 0.0), 12)
	FairKit.box(tr, Vector3(1.2, 0.8, 0.04), Vector3(2.0, 2.1, 1.23), FairKit.paint(Color(0.05, 0.05, 0.07), 0.6, 0.1))
	FairKit.label(tr, "COMET CONE\nNITROGEN SWIRL\nPLUTO PARFAIT", Vector3(2.0, 2.1, 1.255), 16, Color(1.6, 1.6, 1.8))
	for xx in [-2.2, 2.0, 4.2]:
		FairKit.box(tr, Vector3(1.25, 0.12, 2.5), Vector3(xx, 1.07, 0), FairKit.paint(Color(0.1, 0.1, 0.11), 0.7, 0.3))
	for sz in [-0.8, 0.8]:
		FairKit.mesh(tr, FairKit.sphere_mesh(0.1, 8), Vector3(5.12, 1.0, sz), FairKit.glow(Color(1.0, 0.95, 0.85), 4.0, 0.6), Vector3.ZERO, false)
	FairKit.box(tr, Vector3(3.6, 0.08, 0.45), Vector3(-0.4, 1.5, 1.4), FairKit.pbr("brown_planks_05", Color(0.5, 0.42, 0.36), 1.2))
	FairKit.awning(tr, 3.8, 1.2, Vector3(-0.4, 2.85, 1.75), Vector3(0.45, 0, 0), [Color(0.2, 0.55, 0.85), Color(0.95, 0.95, 0.98)])
	var l := FairKit.label(tr, "FROZEN VOLATILES", Vector3(-0.4, 2.92, 1.36), 30, Color(1.2, 1.8, 2.4))
	_fit_label(l, 3.4)
	FairKit.solid_box(self, Vector3(6.8, 3.0, 2.6), c + Vector3(0, 1.5, 0), yaw)
	_vendor_spots.append([tr.transform * Vector3(-0.4, 0.75, 0.4), tb * Vector3.BACK])
	_queue_rails(tr.transform * Vector3(-0.4, 0, 2.0), tb * Vector3.BACK, 3.3, Color(0.3, 0.7, 1.0))
	_batch.pool(tr.transform * Vector3(-0.4, 0.08, 2.6), 3.5, Color(0.6, 0.85, 1.0) * 0.4)
	FairKit.box(self, Vector3(10.0, PATH_Y, 5.0), _p(12.0, 27.0, PATH_Y * 0.5 + 0.004), FairKit.pbr("metal_plate_02", Color(0.55, 0.57, 0.62), 0.5)).rotation.y = _yaw_to(V)
	for i in 3:
		_table(_p(8.5 + i * 3.4, 26.0 + float(i % 2) * 0.8), _rng.randf() * TAU)
	_lamp_post(_p(6.5, 28.5))
	_lamp_post(_p(17.5, 28.5))


func _build_launch_support() -> void:
	## Beyond the pad: a launch-control bunker and frosted propellant tanks.
	var bc := ROCKET_POS + U * 12.0 - V * 14.0
	var yaw := _yaw_to(-U)
	var concrete := FairKit.pbr("asphalt_02", Color(0.92, 0.92, 0.96), 0.3)
	FairKit.box(self, Vector3(6.0, 2.6, 3.6), bc + Vector3(0, 1.3, 0), concrete).rotation.y = yaw
	FairKit.box(self, Vector3(4.6, 0.5, 0.04), bc + Basis(Vector3.UP, yaw) * Vector3(0, 1.8, 1.81), FairKit.glow(Color(0.5, 0.9, 1.0), 2.5, 0.6)).rotation.y = yaw
	FairKit.solid_box(self, Vector3(6.0, 2.6, 3.6), bc + Vector3(0, 1.3, 0), yaw)
	var lc := FairKit.label(self, "LAUNCH CONTROL", bc + Basis(Vector3.UP, yaw) * Vector3(0, 2.35, 1.82), 40, Color(1.8, 1.7, 1.4), yaw)
	lc.outline_size = 6
	_batch.strut(bc + Vector3(0, 2.6, 0), bc + Vector3(0, 7.0, 0), 0.05, FairKit.paint(Color(0.6, 0.6, 0.62), 0.4, 0.8))
	FairKit.mesh(self, FairKit.sphere_mesh(0.1, 8), bc + Vector3(0, 7.05, 0), FairKit.glow(Color(1.0, 0.1, 0.05), 6.0, 2.0), Vector3.ZERO, false)
	var frost := FairKit.paint(Color(0.88, 0.9, 0.94), 0.55, 0.3)
	for k in 2:
		var tp := ROCKET_POS + U * 9.0 - V * (4.0 + k * 3.2)
		FairKit.cyl(self, 1.2, 1.2, 5.5, tp + Vector3(0, 2.75, 0), frost, 24)
		FairKit.mesh(self, FairKit.sphere_mesh(1.2, 20), tp + Vector3(0, 5.5, 0), frost)
		FairKit.mesh(self, FairKit.torus_mesh(1.2, 1.28, 32, 4), tp + Vector3(0, 1.0 + k * 0.4, 0), FairKit.glow(FairKit.NEON_CYAN, 2.5, 0.5), Vector3.ZERO, false)
		FairKit.solid_cyl(self, 1.25, 5.0, tp + Vector3(0, 2.5, 0))
		var tl := FairKit.label(self, "LOX" if k == 0 else "RP-1", tp + Vector3(0, 3.2, 0) - U * 1.22, 48, Color(0.15, 0.15, 0.18), _yaw_to(-U), Color(0, 0, 0, 0))
		tl.shaded = true


func _clear_of_structures(p: Vector3, r: float) -> bool:
	## Rough keep-out test against the big footprints so perimeter posts don't land in them.
	var keep := [[_p(-3.0, -24.0), 12.0], [_p(19.0, -28.0), 6.0], [_p(12.0, 32.0), 5.0], [_p(-14.0, 33.0), 3.0]]
	if _tier >= 3:
		keep += [[ROCKET_POS + U * 12.0 - V * 14.0, 5.0], [ROCKET_POS + U * 9.0 - V * 5.6, 4.5]]
	for k in keep:
		if Vector2(p.x - k[0].x, p.z - k[0].z).length() < float(k[1]) + r:
			return false
	return true


func _path(a: Vector3, b: Vector3, width: float = 3.0) -> void:
	## Paved link path a→b (laid just under the plaza/deck surfaces so joins never z-fight).
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var mid := (a + b) * 0.5
	var pv := FairKit.box(self, Vector3(width, PATH_Y * 0.6, d.length()), Vector3(mid.x, PATH_Y * 0.3 - 0.004, mid.z), FairKit.pbr("asphalt_02", Color(0.6, 0.6, 0.64), 0.3))
	pv.rotation.y = _yaw_to(d.normalized())


func _path_dressing(a: Vector3, b: Vector3, side: float) -> void:
	## A bench + bin on one side of a path's midpoint and a crystal planter on the other.
	var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var n := d.cross(Vector3.UP) * side
	var m := (a + b) * 0.5
	var bp := m + n * 2.3
	FairKit.model(self, "painted_wooden_bench", Vector3(bp.x, PATH_Y, bp.z), _yaw_to(-n))
	FairKit.solid_box(self, Vector3(1.2, 0.9, 0.5), Vector3(bp.x, 0.45, bp.z), _yaw_to(-n))
	var bin := bp + d * 1.1
	FairKit.model(self, "metal_trash_can", Vector3(bin.x, PATH_Y + 0.072, bin.z), _rng.randf() * TAU)
	_seat_spots.append([Vector3(bp.x, PATH_Y, bp.z), -n])
	var cp := m - n * 2.6
	FairKit.model(self, "moon_rock_03", Vector3(cp.x, 0, cp.z), _rng.randf() * TAU, 10.0).scale.y *= 1.5
	FairKit.crystal_cluster(self, Vector3(cp.x, 0.25, cp.z), _rng, FairKit.CRYSTAL_COLORS[_rng.randi() % 4], 5, 0.6)


func _build_paths_and_garden() -> void:
	## Paved paths tie every area to the plaza, and a Crystal Garden fills the open quarter
	## between the bandstand, the reactor yard and the launch pad.
	var g := _p(26.0, -13.5)
	var dg := Vector3(g.x, 0, g.z).normalized()
	_path(dg * (PLAZA_R - 0.5), g - dg * 5.0)
	_path_dressing(dg * PLAZA_R, g - dg * 5.0, 1.0)
	_path(g + (_p(9.0, -25.5) - g).normalized() * 5.0, _p(10.0, -23.5))          # garden → food row
	_path(_p(4.0, -12.0), _p(8.0, -22.5))                                        # plaza → food row
	_path(_p(12.5, 22.0), _p(12.0, 25.0), 4.0)                                    # food court → truck
	_path(_p(-9.0, 11.0), _p(-12.0, 22.0))                                       # plaza → games corner lane
	_path_dressing(_p(-9.0, 11.0), _p(-12.0, 22.0), -1.0)
	if _tier >= 3:
		var rb: Vector3 = _booth_sightlines()[1][0] if _rides.size() > 1 else ROCKET_POS
		for e in _booth_sightlines():
			if Vector3(e[0]).distance_to(ROCKET_POS) < 16.0:
				rb = e[0]
		_path(g + (rb - g).normalized() * 5.0, rb + (g - rb).normalized() * 2.5)   # garden → rocket booth
	# The garden: paved disc, raised crystal bed with a glow ring, benches facing it
	FairKit.mesh(self, FairKit.cyl_mesh(5.2, 5.2, PATH_Y, 40), Vector3(g.x, PATH_Y * 0.5, g.z), FairKit.pbr("asphalt_02", Color(0.6, 0.6, 0.64), 0.3))
	FairKit.mesh(self, FairKit.torus_mesh(5.15, 5.4, 48, 4), Vector3(g.x, 0.02, g.z), FairKit.pbr("asphalt_02", Color(0.38, 0.38, 0.41), 0.3)).scale = Vector3(1, 0.4, 1)
	FairKit.mesh(self, FairKit.cyl_mesh(1.7, 1.9, 0.55, 24), Vector3(g.x, 0.275, g.z), FairKit.pbr("asphalt_02", Color(0.5, 0.5, 0.54), 0.5))
	FairKit.solid_cyl(self, 1.9, 1.2, Vector3(g.x, 0.6, g.z))
	FairKit.crystal_cluster(self, Vector3(g.x, 0.55, g.z), _rng, FairKit.NEON_CYAN, 8, 1.7)
	FairKit.crystal_cluster(self, Vector3(g.x + 0.8, 0.55, g.z - 0.5), _rng, FairKit.NEON_VIOLET, 5, 1.0)
	FairKit.mesh(self, FairKit.torus_mesh(1.82, 1.9, 48, 4), Vector3(g.x, 0.57, g.z), FairKit.glow(FairKit.NEON_CYAN, 2.0, 0.5), Vector3.ZERO, false)
	FairKit.omni(self, Vector3(g.x, 3.0, g.z), Color(0.5, 0.85, 1.0), 1.6, 11.0, 0.0)
	_batch.pool(Vector3(g.x, 0.08, g.z), 5.5, FairKit.NEON_CYAN * 0.3)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		var bp := g + d * 3.6
		FairKit.model(self, "painted_wooden_bench", Vector3(bp.x, PATH_Y, bp.z), _yaw_to(-d))
		FairKit.solid_box(self, Vector3(1.2, 0.9, 0.5), Vector3(bp.x, 0.45, bp.z), _yaw_to(-d))
		_seat_spots.append([Vector3(bp.x, PATH_Y, bp.z), -d])
		if i % 2 == 0:
			_lamp_post(g + Vector3(cos(a + PI / 4.0), 0, sin(a + PI / 4.0)) * 4.6)
	var plaque := FairKit.label(self, "CRYSTAL GARDEN", Vector3(g.x, 1.0, g.z) - dg * 1.95, 30, FairKit.NEON_CYAN * 1.6, _yaw_to(-dg))
	plaque.outline_size = 5
	# Souvenir kiosk on the garden's edge
	var kp := g + Vector3(-dg.z, 0, dg.x) * -7.2
	_kiosk(kp, (g - kp).normalized(), "UPSILON SOUVENIRS", FairKit.AWNING_PAIRS[0])


func get_board_anchor() -> Transform3D:
	## LOCAL transform reserved for a 3.2 m × 1.8 m media billboard by the entrance, at every
	## tier. Origin = centre of the board face (bottom edge 1.2 m above ground, so y = 2.1);
	## the board's front is local −Z, turned toward visitors arriving from the spawn side.
	## The spot (beside the arch, opposite the tier-0 sign, outside every path/ride/sign) is
	## kept clear by the fair.
	var front := (-U + V * 0.25).normalized()      # faces arriving visitors, a little toward the gate
	var basis := Basis.looking_at(front, Vector3.UP)   # looking_at → −Z points along `front`
	var pos := _p(ARCH_S - 1.0, -9.0, 2.1)
	return Transform3D(basis, pos)


# ─── Tier 0: Surveyed Lot ──────────────────────────────────────────────

func _build_survey_lot() -> void:
	## A promise, not an empty field: the plot is staked and roped, crew gear waits by a work
	## light, faint holograms trace where each ride will stand, and a big holo sign says so.
	var lim := 31.0
	var stake_m := FairKit.paint(Color(0.95, 0.45, 0.08), 0.5, 0.1)
	var rope := FairKit.paint(Color(0.95, 0.85, 0.75), 0.7, 0.0)
	var corners := [Vector3(-lim, 0, -lim), Vector3(lim, 0, -lim), Vector3(lim, 0, lim), Vector3(-lim, 0, lim)]
	var pal := [Color(0.98, 0.5, 0.08), Color(0.95, 0.85, 0.15)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var n := int(a.distance_to(b) / 4.0)
		var prev := Vector3.INF
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			_batch.strut(p, p + Vector3(0, 1.1, 0), 0.035, stake_m)
			if prev != Vector3.INF:
				_batch.strut(prev + Vector3(0, 0.95, 0), p + Vector3(0, 0.95, 0), 0.012, rope)
				if i % 2 == 0:
					_batch.bunting(prev + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0), 0.25, pal, 0.8)
			prev = p
		# Corner survey beacons
		FairKit.mesh(self, FairKit.sphere_mesh(0.09, 8), a + Vector3(0, 1.2, 0), FairKit.glow(Color(1.0, 0.45, 0.1), 5.0, 1.5), Vector3.ZERO, false)
	# Chalked layout lines: the planned plaza ring and midway
	var chalk := FairKit.paint(Color(0.85, 0.88, 0.9), 0.9, 0.0)
	var ring := FairKit.mesh(self, FairKit.torus_mesh(PLAZA_R - 0.08, PLAZA_R + 0.08, 72, 4), Vector3(0, 0.01, 0), chalk)
	ring.scale = Vector3(1, 0.1, 1)
	for side in [-1.0, 1.0]:
		var l0 := _p(ARCH_S + 3.0, side * MIDWAY_HALF, 0.012)
		var l1 := _p(-PLAZA_R, side * MIDWAY_HALF, 0.012)
		var ln := FairKit.box(self, Vector3(0.14, 0.02, l0.distance_to(l1)), (l0 + l1) * 0.5, chalk)
		ln.rotation.y = _yaw_to(U)
	# Holographic ghosts of what's coming
	var holo := FairKit.holo_mat(FairKit.NEON_CYAN, 1.4)
	var wheel_c := _p(-3.0, -24.0, 18.5)
	var wheel := FairKit.mesh(self, FairKit.torus_mesh(14.9, 15.1, 96, 4), wheel_c, holo, Vector3.ZERO, false)
	wheel.rotation = Vector3(PI * 0.5, _yaw_to(-U), 0)
	wheel.basis = Basis(Vector3.UP, _yaw_to(-U)) * Basis(Vector3.RIGHT, PI * 0.5)
	FairKit.mesh(self, FairKit.torus_mesh(7.1, 7.3, 64, 4), Vector3(0, 0.15, 0), holo, Vector3.ZERO, false)
	var rocket_c := ROCKET_POS
	for i in 9:
		var r := 2.1 if i < 8 else 1.2
		FairKit.mesh(self, FairKit.torus_mesh(r - 0.06, r + 0.06, 32, 4), rocket_c + Vector3(0, 3.0 + i * 3.6, 0), holo, Vector3.ZERO, false)
	_batch.strut(rocket_c + Vector3(0, 12.0, 0), rocket_c + Vector3(0, 41.0, 0), 0.05, holo)
	var drop_c := _p(-1.0, 22.5)
	for i in 5:   # ring stack (a full-height line would cut through the sign from spawn)
		FairKit.mesh(self, FairKit.torus_mesh(1.3, 1.42, 32, 4), drop_c + Vector3(0, 18.0 + i * 8.0, 0), holo, Vector3.ZERO, false)
	FairKit.mesh(self, FairKit.torus_mesh(3.4, 3.6, 40, 4), drop_c + Vector3(0, 55.0, 0), holo, Vector3.ZERO, false)
	# Plot markers where each ride goes
	for e in [[_p(-9.0, -5.0), "ORBITAL CAROUSEL"], [_p(-3.0, -14.0), "RHO WHEEL"], [_p(-1.0, 14.5), "PI DROP"],
			[_p(17.5, 0.5), "UPSILON ROCKET"]]:
		var mp: Vector3 = e[0]
		_batch.strut(mp, mp + Vector3(0, 1.5, 0), 0.04, stake_m)
		FairKit.box(self, Vector3(1.6, 0.5, 0.05), mp + Vector3(0, 1.6, 0), FairKit.paint(Color(0.06, 0.06, 0.08), 0.5, 0.3)).rotation.y = _yaw_to(-U)
		var lb := FairKit.label(self, e[1], mp + Vector3(0, 1.6, 0) - U * 0.03, 26, FairKit.NEON_CYAN * 2.0, _yaw_to(-U))
		_fit_label(lb, 1.5)
	# The sign: big holo panel by the future entrance, facing the spawn
	var sign_root := Node3D.new()
	sign_root.name = "SiteReservedSign"
	sign_root.position = _p(ARCH_S + 2.0, 7.5)   # off the midway axis: no ghosts behind the text
	sign_root.rotation.y = _yaw_to(-U)
	add_child(sign_root)
	var post := FairKit.paint(Color(0.25, 0.27, 0.3), 0.4, 0.8)
	for sx in [-5.2, 5.2]:
		FairKit.box(sign_root, Vector3(0.25, 6.2, 0.25), Vector3(sx, 3.1, 0), post)
		FairKit.box(sign_root, Vector3(0.06, 4.0, 0.06), Vector3(sx, 4.0, 0.16), FairKit.glow(FairKit.NEON_CYAN, 4.0, 1.0))
		FairKit.solid_box(sign_root, Vector3(0.5, 3.0, 0.5), Vector3(sx, 1.5, 0))
	FairKit.box(sign_root, Vector3(10.2, 3.6, 0.04), Vector3(0, 4.2, -0.08), FairKit.paint(Color(0.02, 0.04, 0.06), 0.4, 0.3))   # opaque backer: nothing shows through the text
	FairKit.box(sign_root, Vector3(10.2, 3.6, 0.04), Vector3(0, 4.2, 0), FairKit.holo_mat(FairKit.NEON_CYAN, 0.35))
	FairKit.box(sign_root, Vector3(10.4, 0.06, 0.08), Vector3(0, 6.05, 0), FairKit.glow(FairKit.NEON_CYAN, 4.0, 1.0))
	FairKit.box(sign_root, Vector3(10.4, 0.06, 0.08), Vector3(0, 2.35, 0), FairKit.glow(FairKit.NEON_CYAN, 4.0, 1.0))
	var nm := _territory_display_name()
	if nm != "":
		var l0 := FairKit.label(sign_root, nm + ("'" if nm.ends_with("S") else "'S"), Vector3(0, 5.55, 0.05), 48, FairKit.NEON_CYAN * 2.2)
		_fit_label(l0, 9.0)
	var l1 := FairKit.label(sign_root, "AFFECTION FAIR — SITE RESERVED", Vector3(0, 4.6, 0.05), 96, Color(2.4, 2.2, 1.6))
	l1.outline_size = 12
	_fit_label(l1, 9.6)
	_hint_label = FairKit.label(sign_root, _hint_text, Vector3(0, 3.35, 0.05), 54, FairKit.NEON_CYAN * 2.4)
	_fit_label(_hint_label, 9.0)
	FairKit.label(sign_root, "SURVEYED LOT · GROW THIS QING'S STANDING TO OPEN THE FAIR", Vector3(0, 2.7, 0.05), 28, Color(1.4, 1.4, 1.5))
	FairKit.label(sign_root, "AFFECTION FAIR — SITE RESERVED", Vector3(0, 4.4, -0.13), 80, Color(1.8, 1.7, 1.4), PI)
	# Site office trailer and two floodlight masts so the lot reads at night
	_site_trailer(_p(ARCH_S + 9.0, 13.0), -V)
	for e in [_p(-14.0, 14.0), _p(6.0, -12.0), _p(-24.0, -9.0)]:
		_floodlight_mast(e)
	# Work light, generator, crates — the crew has been here
	var wl := _p(ARCH_S + 8.0, -7.0)
	_batch.strut(wl, wl + Vector3(0, 6.0, 0), 0.07, post)
	for k in 3:
		var a2 := TAU * k / 3.0
		_batch.strut(wl + Vector3(cos(a2), 0, sin(a2)) * 1.1, wl + Vector3(0, 1.6, 0), 0.04, post)
	FairKit.box(self, Vector3(0.9, 0.5, 0.25), wl + Vector3(0, 6.1, 0), post).rotation.y = _yaw_to(V)
	FairKit.box(self, Vector3(0.8, 0.4, 0.02), wl + Vector3(0, 6.05, 0) + V * 0.14, FairKit.glow(Color(1.0, 0.9, 0.75), 6.0, 0.5)).rotation.y = _yaw_to(V)
	FairKit.omni(self, wl + Vector3(0, 5.6, 0) + V * 1.0, Color(1.0, 0.85, 0.65), 1.3, 20.0, 0.0)
	_batch.pool(wl + V * 4.0 + Vector3(0, 0.08, 0), 7.0, Color(1.0, 0.82, 0.6) * 0.35)
	FairKit.model(self, "portable_generator", wl + Vector3(-1.5, 0, 0.8), 0.7)
	_batch.strut(wl + Vector3(-1.2, 0.05, 0.8), wl + Vector3(0, 0.05, 0), 0.03, FairKit.paint(Color(0.04, 0.04, 0.04), 0.7, 0.0))
	var yard := wl + V * 5.0 + U * 2.0
	for i in 5:
		FairKit.model(self, "wooden_crate_01", yard + Vector3((i % 3) * 0.9, 0.0, int(i / 3) * 0.6), _rng.randf() * TAU)
	FairKit.model(self, "wooden_crate_01", yard + Vector3(0.45, 0.35, 0.0), _rng.randf() * TAU)
	for i in 4:
		_batch.prop("Barrel_01", Transform3D(Basis(Vector3.UP, i * 1.3), yard + Vector3(3.0 + (i % 2) * 0.62, 0.006, int(i / 2) * 0.62)))
	var cont := FairKit.box(self, Vector3(2.44, 2.6, 6.1), yard + U * 6.0 + Vector3(0, 1.3, 0), FairKit.pbr("corrugated_iron", Color(0.25, 0.45, 0.6), 0.6, 1.0))
	cont.rotation.y = _yaw_to(V)
	FairKit.solid_box(self, Vector3(2.44, 2.6, 6.1), yard + U * 6.0 + Vector3(0, 1.3, 0), _yaw_to(V))
	# Survey tripod beside the sign
	var tri := _p(ARCH_S + 4.5, 6.5)
	for k in 3:
		var a3 := TAU * k / 3.0
		_batch.strut(tri + Vector3(cos(a3), 0, sin(a3)) * 0.5, tri + Vector3(0, 1.4, 0), 0.02, FairKit.paint(Color(0.9, 0.75, 0.2), 0.5, 0.3))
	FairKit.box(self, Vector3(0.2, 0.22, 0.32), tri + Vector3(0, 1.55, 0), FairKit.paint(Color(0.85, 0.85, 0.8), 0.4, 0.4))
	FairKit.mesh(self, FairKit.sphere_mesh(0.03, 6), tri + Vector3(0, 1.6, -0.17), FairKit.glow(Color(1.0, 0.15, 0.1), 6.0, 2.0), Vector3.ZERO, false)
	# The territory's crystals poke through the graded regolith
	for e2 in [_p(-12.0, 9.0), _p(6.0, -10.0), _p(14.0, 12.0)]:
		FairKit.crystal_cluster(self, e2, _rng, FairKit.CRYSTAL_COLORS[_rng.randi() % 4], 6, 0.9)
		_batch.pool(e2 + Vector3(0, 0.08, 0), 2.2, FairKit.NEON_CYAN * 0.3)


func _site_trailer(pos: Vector3, facing: Vector3) -> void:
	## Portable site office: lit windows, steps, AC unit, a "SITE OFFICE" plate.
	var root := Node3D.new()
	root.name = "SiteTrailer"
	root.position = pos
	root.rotation.y = _yaw_to(facing)
	add_child(root)
	var shell := FairKit.pbr("corrugated_iron", Color(0.78, 0.8, 0.84), 0.6, 1.0)
	FairKit.box(root, Vector3(7.0, 2.7, 2.6), Vector3(0, 1.75, 0), shell)
	FairKit.box(root, Vector3(7.1, 0.12, 2.7), Vector3(0, 3.16, 0), FairKit.paint(Color(0.3, 0.31, 0.34), 0.5, 0.6))
	for x in [-2.4, -0.6, 2.2]:
		FairKit.box(root, Vector3(1.2, 0.7, 0.04), Vector3(x, 2.0, 1.31), FairKit.glow(Color(1.0, 0.85, 0.6), 2.5, 0.4))
	FairKit.box(root, Vector3(0.9, 2.0, 0.04), Vector3(1.0, 1.4, 1.31), FairKit.paint(Color(0.25, 0.35, 0.5), 0.5, 0.4))
	for s2 in 3:
		FairKit.box(root, Vector3(1.2, 0.13 * (s2 + 1), 0.3), Vector3(1.0, 0.065 * (s2 + 1), 1.45 + (2 - s2) * 0.3), FairKit.pbr("metal_plate", Color.WHITE, 0.6, 1.0))
	FairKit.box(root, Vector3(0.9, 0.7, 0.6), Vector3(-3.0, 0.75, 1.5), FairKit.paint(Color(0.82, 0.83, 0.85), 0.4, 0.5))
	var l := FairKit.label(root, "SITE OFFICE · AFFECTION FAIR CREW", Vector3(-0.8, 2.75, 1.33), 28, FairKit.NEON_CYAN * 1.8)
	_fit_label(l, 4.0)
	for x in [-3.0, 3.0]:
		for z in [-1.0, 1.0]:
			FairKit.box(root, Vector3(0.3, 0.4, 0.3), Vector3(x, 0.2, z), FairKit.paint(Color(0.2, 0.2, 0.22), 0.6, 0.6))
	FairKit.solid_box(root, Vector3(7.0, 3.2, 2.6), Vector3(0, 1.6, 0))
	_batch.pool(root.transform * Vector3(0, 0.08, 2.2), 4.0, Color(1.0, 0.85, 0.6) * 0.4)


func _floodlight_mast(p: Vector3) -> void:
	## 8 m mast with a four-lamp head aimed down; one shadowless light, a broad pool.
	var steel := FairKit.paint(Color(0.3, 0.32, 0.36), 0.45, 0.8)
	_batch.strut(p, p + Vector3(0, 8.0, 0), 0.09, steel)
	for k in 3:
		var a := TAU * k / 3.0
		_batch.strut(p + Vector3(cos(a), 0, sin(a)) * 1.0, p + Vector3(0, 2.2, 0), 0.04, steel)
	FairKit.box(self, Vector3(1.8, 0.12, 0.12), p + Vector3(0, 8.0, 0), steel)
	for x in [-0.7, -0.23, 0.23, 0.7]:
		var lamp := FairKit.box(self, Vector3(0.4, 0.3, 0.12), p + Vector3(x, 8.25, 0.0), steel)
		lamp.rotation.x = -0.5
		FairKit.box(self, Vector3(0.34, 0.24, 0.02), p + Vector3(x, 8.2, 0.08), FairKit.glow(Color(1.0, 0.95, 0.85), 6.0, 0.3)).rotation.x = -0.5
	FairKit.omni(self, p + Vector3(0, 7.0, 0), Color(1.0, 0.92, 0.8), 3.6, 30.0, 0.0)
	_batch.pool(p + Vector3(0, 0.08, 0), 14.0, Color(1.0, 0.9, 0.75) * 0.45)


# ─── Tier 3 headliner: fireworks + searchlights ───────────────────────────

func _build_headliner() -> void:
	## Shells burst over the fair in a slow lunar arc (GPU-only, no particles nodes), and three
	## searchlights sweep the sky so the Grand Fair is visible from across the territory.
	var bursts := 7
	var sparks := 64
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = bursts * sparks
	var cols := [FairKit.NEON_CYAN, Color(1.0, 0.75, 0.3), FairKit.NEON_VIOLET, Color(1.0, 0.35, 0.6), Color(0.4, 1.0, 0.7)]
	for k in bursts:
		var c := _p(_rng.randf_range(-18.0, 22.0), _rng.randf_range(-22.0, 22.0), _rng.randf_range(58.0, 82.0))
		var col: Color = cols[k % cols.size()]
		var phase := float(k) / bursts + _rng.randf_range(0.0, 0.06)
		for i in sparks:
			# Fibonacci sphere directions, jittered
			var y := 1.0 - 2.0 * (float(i) + 0.5) / sparks
			var r := sqrt(maxf(1.0 - y * y, 0.0))
			var th := float(i) * 2.39996 + k
			# Filled shell (speeds 0.35–1.0), not a crisp ring of dots
			var dir := Vector3(cos(th) * r, y, sin(th) * r) * sqrt(_rng.randf_range(0.12, 1.0))
			var idx := k * sparks + i
			mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY, c))
			mm.set_instance_color(idx, col.lerp(Color.WHITE, 0.15 if i % 5 == 0 else 0.0))
			mm.set_instance_custom_data(idx, Color(dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, dir.z * 0.5 + 0.5, phase))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Fireworks"
	mmi.multimesh = mm
	mmi.material_override = FairKit.shader_mat("fair_firework")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60, -100, -60), Vector3(120, 180, 120))
	add_child(mmi)
	# Searchlights
	var beam_mesh := FairKit.cached_mesh("beam", func() -> Mesh:
		return FairKit.lathe(PackedVector2Array([Vector2(0.35, 0.0), Vector2(5.5, 150.0)]), 20))
	var housing := FairKit.paint(Color(0.2, 0.21, 0.24), 0.4, 0.8)
	# Away from the rocket: two by the entrance corners, one by the reactor yard; each sweeps
	# an arc that leans OUT of the fair so the shafts never wash over the rides
	for e in [[_p(-30.0, -12.0), 0.0], [_p(-30.0, 12.0), 2.1], [_p(9.5, -34.5), 4.2]]:
		var sp: Vector3 = e[0]
		FairKit.cyl(self, 0.55, 0.7, 0.9, sp + Vector3(0, 0.45, 0), housing, 16)
		var pivot := Node3D.new()
		pivot.position = sp + Vector3(0, 1.3, 0)
		add_child(pivot)
		FairKit.cyl(pivot, 0.5, 0.42, 0.7, Vector3(0, 0.1, 0), housing, 20)
		FairKit.cyl(pivot, 0.4, 0.4, 0.03, Vector3(0, 0.46, 0), FairKit.glow(Color(0.85, 0.92, 1.0), 8.0, 0.5), 20)
		var bm := FairKit.mesh(pivot, beam_mesh, Vector3(0, 0.45, 0), FairKit.shader_mat("fair_beam"), Vector3.ZERO, false)
		bm.custom_aabb = AABB(Vector3(-8, 0, -8), Vector3(16, 160, 16))
		var outv := Vector3(sp.x, 0, sp.z).normalized()
		_beams.append([pivot, float(e[1]), atan2(outv.x, outv.z)])
		_batch.pool(sp + Vector3(0, 0.08, 0), 3.0, Color(0.7, 0.85, 1.0) * 0.4)


# ─── Visitors ───────────────────────────────────────────────────────────

func _npc(seed_v: int, pts: Array, facing: Vector3 = Vector3.FORWARD, pos: Vector3 = Vector3.ZERO,
		staff: bool = false) -> AmbientNPC:
	## Visitors share the player's teddy-astronaut model (seeded suits, culled past 70 m).
	## Staff (vendors, band) don't count toward the tier's visitor cap.
	if not staff:
		if _npc_count >= _npc_cap:
			return null
		_npc_count += 1
	var n := AmbientNPC.new()
	n.name = ("Staff%d" if staff else "Visitor%d") % get_child_count()
	n.position = pos
	add_child(n)
	n.setup(seed_v, pts, facing)
	return n


func _seat(n: AmbientNPC) -> void:
	if n:
		n.set_pose("sit")


func _give_food(n: AmbientNPC, kind: int) -> void:
	## Put a snack in the local's right glove: an Eris Ice cone or a glowing Pulse Pop.
	if n == null:
		return
	var model: Node3D = n.get("_model")
	var glove: Node3D = model.get("_glove_right") if model else null
	if glove == null:
		return
	var holder := Node3D.new()
	glove.add_child(holder)
	holder.scale = Vector3(1.0 / 0.85, 1.0 / 0.65, 1.0)   # undo the glove's squash
	if kind == 0:
		FairKit.cyl(holder, 0.035, 0.0, 0.13, Vector3(0, 0.06, 0.02), FairKit.paint(Color(0.8, 0.6, 0.35), 0.8, 0.0), 8)
		FairKit.mesh(holder, FairKit.sphere_mesh(0.045, 8), Vector3(0, 0.14, 0.02), FairKit.paint(Color(0.7, 0.92, 1.0), 0.85, 0.0))
	else:
		_batch_local_stick(holder)
		FairKit.mesh(holder, FairKit.sphere_mesh(0.05, 8), Vector3(0, 0.2, 0.02), FairKit.glow(FairKit.PALETTE[n.get_index() % 6], 3.0, 1.2), Vector3.ZERO, false)


func _batch_local_stick(holder: Node3D) -> void:
	FairKit.beam(holder, Vector3(0, 0.0, 0.02), Vector3(0, 0.17, 0.02), 0.006, FairKit.paint(Color(0.9, 0.9, 0.88), 0.5, 0.0), 6)


func _spawn_visitors(seed_value: int) -> void:
	## Staff first (one vendor per stall/kiosk/truck, a bandleader), then visitors in priority
	## order — queues at every booth, clumps on the midway, ride riders, customers, diners,
	## strollers — until the tier's cap (6 / 12 / 24). Locals cull past 70 m, so this is cheap.
	if _tier == 0:
		return
	var y := PATH_Y
	var sv := seed_value + 500
	for v in _vendor_spots:
		_npc(sv, [], v[1], v[0], true)
		sv += 1
	var band := get_node_or_null("Bandstand") as Node3D
	if band:
		_npc(seed_value + 32, [], band.transform.basis * Vector3.BACK, band.transform * Vector3(0.0, 0.96, 0.3), true)
	# Queues at every ride booth (the rocket draws the longest line)
	for r in _rides:
		var ride: RideBase = r
		var booth := ride.to_global(ride.booth_local_position)
		var lane := ride.global_transform.basis * Vector3(signf(ride.booth_local_position.x) * 0.15, 0, 1).normalized()
		var n: int = {"rocket": 3, "wheel": 2, "drop": 2, "carousel": 2}.get(ride.ride_id, 1)
		for q in n:
			var p := to_local(booth + lane * (1.2 + q * 1.0))
			p.y = 0.0
			_npc(seed_value + 60 + _npc_count, [], -lane, p)
	# Clumps on the midway: friends stopped to chat, one with a snack
	var clumps := [_p(-24.5, -1.9, y), _p(-19.0, 1.9, y)]
	if _tier >= 2:
		clumps.append(_p(-13.5, -2.0, y))
	for ci in clumps.size():
		var cc: Vector3 = clumps[ci]
		for i in 3:
			var a := TAU * i / 3.0 + ci
			var off := Vector3(cos(a), 0, sin(a)) * 0.75
			var cn := _npc(seed_value + 100 + ci * 3 + i, [], -off, cc + off)
			if i == 0:
				_give_food(cn, (ci + 1) % 2)
	# Riders: a few locals already seated on the carousel and up in the wheel
	for r in _rides:
		if not r.has_method("get_rider_mounts"):
			continue
		var mounts: Array = r.get_rider_mounts()
		var picks: Array = [0, 2, 4] if r.ride_id == "carousel" else [3, 7, 11]
		for i in picks:
			if i >= mounts.size() or _npc_count >= _npc_cap:
				continue
			_npc_count += 1
			var rider := AmbientNPC.new()
			var m: Node3D = mounts[i]
			m.add_child(rider)
			rider.setup(seed_value + 90 + i + (0 if r.ride_id == "carousel" else 20), [], Vector3.FORWARD)
			if r.ride_id == "carousel":
				rider.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0.12))
			else:
				# Gondola bench (back at -Z), sitting facing the middle of the cabin
				rider.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-0.32, -2.63, -0.55))
			rider.set_pose("sit")
	# Customers at the stall counters
	var k := 0
	for v in _vendor_spots:
		if k >= 2:
			break
		var at: Vector3 = v[0] + (v[1] as Vector3) * 1.9
		at.y = 0.0
		var c := _npc(seed_value + 40 + k, [], -(v[1] as Vector3), at)
		if k == 1:
			_give_food(c, 1)
		k += 1
	# Diners at tables / launch fans on the bleachers
	var seated := 0
	for st in _seat_spots:
		if seated >= (2 if _tier == 1 else 4):
			break
		_seat(_npc(seed_value + 80 + seated, [], st[1], st[0]))
		seated += 1
	# Strollers: midway, plaza ring, out to the garden and the food court
	var ring: Array = []
	for i in 9:
		var a2 := TAU * i / 9.0
		ring.append(Vector3(cos(a2), 0, sin(a2)) * 9.4 + Vector3(0, y, 0))
	var ring2: Array = ring.duplicate()
	ring2.reverse()
	_npc(seed_value + 11, [_p(-29.0, -1.2, y), _p(-16.0, -1.6, y), _p(-11.5, -2.5, y), _p(-16.0, 1.0, y), _p(-28.5, 1.4, y)])
	_npc(seed_value + 14, ring)
	_npc(seed_value + 17, [_p(9.0, -9.0, y), _p(19.0, -12.5, y), _p(24.0, -10.0, y), _p(12.0, -6.0, y)])
	_npc(seed_value + 16, [_p(9.0, 4.0, y), _p(12.0, 14.0, y), _p(14.5, 18.0, y), _p(9.0, 13.0, y)])
	_npc(seed_value + 12, [_p(-14.0, 1.5, y), _p(-27.0, 0.8, y), _p(-29.5, -0.5, y), _p(-22.0, -1.8, y)])
	_npc(seed_value + 15, ring2.slice(4) + ring2.slice(0, 4))
	_npc(seed_value + 13, [_p(-20.0, 0.0, y), _p(-12.5, 4.0, y), _p(-3.0, 10.5, y), _p(6.0, 10.0, y), _p(-8.0, 9.0, y)])
	_npc(seed_value + 18, [_p(-14.0, 6.0, y), _p(-14.0, 22.0, y), _p(-13.0, 30.0, y), _p(-14.5, 12.0, y)])
