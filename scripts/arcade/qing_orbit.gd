extends ArcadeGame
## Qing Orbit: ride the four orbits of a QING, sweep up Ⓐ, stay out of the Void's rifts.
##
## Your LAU circles the QING on one of four rings, always moving (counter-clockwise). Left drops a
## ring inward, right climbs a ring outward; up throttles, down brakes. Fire is a Hong dash: a burst
## along the ring, untouchable while it lasts (it recharges). Gold Ⓐ on the rings score 10 × the
## multiplier, which rises with every Ⓐ in a row (to ×9) and falls back to ×1 when a rift hits you.
## A rare magenta LAU sigil is +100 and ×3 at once. Rifts drift against your direction; one touch
## costs a life (then a moment untouchable). Every 20 s the orbit speeds up and the rifts multiply.

const CENTER := Vector2(160, 128)
const RINGS: Array[float] = [34.0, 56.0, 78.0, 100.0]
const HIT_PX := 8.0
const BASE_SPEED := 70.0  ## px/s along the ring at level 1
const DASH_T := 0.32
const DASH_RECHARGE := 2.4
const SAFE_T := 1.4
const RING_T := 0.18  ## seconds to change ring
const MAX_THINGS := 28
const LEVEL_S := 20.0

enum Kind { COIN, RIFT, LAU }

var ring := 1
var ring_from := 1
var ring_t := 1.0  ## 0..1 through a ring change
var angle := 0.0  ## radians, counter-clockwise from +x
var throttle := 1.0
var dash := 0.0  ## seconds of dash left
var charge := 1.0  ## 0..1 until the next dash
var safe := 0.0
var mult := 1
var streak := 0
var level := 1
var things: Array = []  # {ring, a, kind, w (rad/s, its own drift)}
var spawn_t := 0.5
var flash := 0.0
var flash_c := MAGENTA
var popups: Array = []  # {p, s, c, life}
var trail: Array = []  # Vector2, newest last
var _ai_t := 0.0
var _gen := 0


func title() -> String:
	return "Qing Orbit"


func blurb() -> String:
	return "Ride the QING's rings for Ⓐ; dodge Void rifts. Fire: Hong dash."


## Pure: where a ring-and-angle sits on screen.
static func at(ring_r: float, a: float) -> Vector2:
	return CENTER + Vector2(cos(a), -sin(a)) * ring_r


## Pure: the shortest signed angle from a to b (−π..π).
static func angle_to(a: float, b: float) -> float:
	return wrapf(b - a, -PI, PI)


## The radius you're at right now (eased through a ring change).
func radius() -> float:
	var e := ring_t * ring_t * (3.0 - 2.0 * ring_t)
	return lerpf(RINGS[ring_from], RINGS[ring], e)


## The ring that counts for hits (the new one past halfway through a change).
func hit_ring() -> int:
	return ring if ring_t >= 0.5 else ring_from


func speed() -> float:
	return BASE_SPEED * (1.0 + (level - 1) * 0.14) * throttle * (3.2 if dash > 0.0 else 1.0)


func _reset() -> void:
	_gen += 1
	ring = 1
	ring_from = 1
	ring_t = 1.0
	angle = PI * 0.5
	throttle = 1.0
	dash = 0.0
	charge = 1.0
	safe = 0.0
	mult = 1
	streak = 0
	level = 1
	things.clear()
	popups.clear()
	trail.clear()
	spawn_t = 0.5
	flash = 0.0
	_ai_t = 0.0
	for i in 8:
		_spawn(true)


func _spawn(opening: bool = false) -> void:
	if things.size() >= MAX_THINGS:
		return
	var roll := rng.randi_range(0, 99)
	var rift_share := mini(30 + level * 6, 62)
	var kind := Kind.COIN
	if roll < 3:
		kind = Kind.LAU
	elif roll < 3 + rift_share:
		kind = Kind.RIFT
	var r := rng.randi_range(0, RINGS.size() - 1)
	# Spawn ahead of you, out of reach: a quarter to half a turn on.
	var a := angle + rng.randf_range(PI * 0.5, PI * 0.95)
	if opening and kind == Kind.RIFT:
		kind = Kind.COIN
	var w := 0.0
	if kind == Kind.RIFT:
		w = -rng.randf_range(0.15, 0.35 + level * 0.05)
	elif kind == Kind.COIN:
		w = rng.randf_range(-0.1, 0.1)
	things.append({"ring": r, "a": a, "kind": kind, "w": w})
	# Coins come in arcs of three.
	if kind == Kind.COIN and not opening and things.size() < MAX_THINGS - 2:
		for k in 2:
			things.append({"ring": r, "a": a + (k + 1) * 0.16, "kind": Kind.COIN, "w": w})


func _tick(dt: float) -> void:
	var gen := _gen
	level = 1 + int(t / LEVEL_S)
	flash = maxf(0.0, flash - dt)
	safe = maxf(0.0, safe - dt)
	if pressed & IN_LEFT and ring > 0:
		_change_ring(ring - 1)
	elif pressed & IN_RIGHT and ring < RINGS.size() - 1:
		_change_ring(ring + 1)
	ring_t = minf(1.0, ring_t + dt / RING_T)
	var want := 1.0
	if held & IN_UP:
		want = 1.45
	elif held & IN_DOWN:
		want = 0.6
	throttle = move_toward(throttle, want, dt * 2.5)
	if dash > 0.0:
		dash = maxf(0.0, dash - dt)
	else:
		charge = minf(1.0, charge + dt / DASH_RECHARGE)
		if pressed & IN_FIRE and charge >= 1.0:
			dash = DASH_T
			charge = 0.0
	angle = wrapf(angle + speed() / radius() * dt, -PI, PI)
	trail.append(at(radius(), angle))
	if trail.size() > 10:
		trail.pop_front()
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = maxf(0.28, 0.9 - level * 0.07)
		_spawn()
	var me := hit_ring()
	for i in range(things.size() - 1, -1, -1):
		var th: Dictionary = things[i]
		th["a"] = wrapf(float(th["a"]) + float(th["w"]) * dt, -PI, PI)
		# Long behind you: gone.
		var rel := angle_to(angle, float(th["a"]))
		if rel < -PI * 0.75:
			things.remove_at(i)
			continue
		if int(th["ring"]) != me:
			continue
		if absf(rel) * RINGS[me] > HIT_PX:
			continue
		match int(th["kind"]):
			Kind.COIN:
				things.remove_at(i)
				streak += 1
				mult = mini(9, 1 + streak / 5)
				score += 10 * mult
				_popup(at(RINGS[me], angle), "+%d" % (10 * mult), GOLD)
			Kind.LAU:
				things.remove_at(i)
				streak += 15
				mult = mini(9, mult + 3)
				score += 100
				flash = 0.35
				flash_c = GOLD
				_popup(at(RINGS[me], angle), "LAU +100", MAGENTA)
			Kind.RIFT:
				if dash > 0.0 or safe > 0.0:
					continue
				things.remove_at(i)
				streak = 0
				mult = 1
				safe = SAFE_T
				flash = 0.45
				flash_c = MAGENTA
				_popup(at(RINGS[me], angle), "RIFT", MAGENTA)
				lose_life()
				if gen != _gen or not (playing or attract_mode):
					return
	for j in range(popups.size() - 1, -1, -1):
		var p: Dictionary = popups[j]
		p["life"] = float(p["life"]) - dt
		p["p"] = (p["p"] as Vector2) + Vector2(0, -16.0 * dt)
		if float(p["life"]) <= 0.0:
			popups.remove_at(j)


func _change_ring(to: int) -> void:
	ring_from = hit_ring()
	ring = to
	ring_t = 0.0


func _popup(p: Vector2, s: String, c: Color) -> void:
	if popups.size() >= 6:
		popups.pop_front()
	popups.append({"p": p, "s": s, "c": c, "life": 0.8})


## The demo: hop off a ring with a rift coming, hop onto a ring with Ⓐ ahead; dash now and then.
func _demo_input() -> int:
	var bits := 0
	var danger := false
	var best_ring := ring
	var best := -1.0
	for th in things:
		var rel := angle_to(angle, float(th["a"]))
		if rel < 0.0 or rel > 0.9:
			continue
		if int(th["kind"]) == Kind.RIFT and int(th["ring"]) == ring and rel < 0.45:
			danger = true
		elif int(th["kind"]) != Kind.RIFT and 1.0 - rel > best:
			best = 1.0 - rel
			best_ring = int(th["ring"])
	_ai_t -= DT
	if ring_t >= 1.0 and _ai_t <= 0.0:
		if danger:
			bits |= IN_LEFT if ring > 0 and ai_rng.randf() < 0.5 or ring == RINGS.size() - 1 else IN_RIGHT
			_ai_t = 0.2
		elif best_ring < ring:
			bits |= IN_LEFT
			_ai_t = 0.25
		elif best_ring > ring:
			bits |= IN_RIGHT
			_ai_t = 0.25
	if danger and charge >= 1.0 and ai_rng.randf() < 0.05:
		bits |= IN_FIRE
	return bits


# ── drawing ──────────────────────────────────────────────────────────────────


func _draw_game() -> void:
	draw_circle(CENTER, 14.0, Color(ICE, 0.12))
	draw_arc(CENTER, 14.0, 0.0, TAU, 32, ICE, 1.5, true)
	text_centered(CENTER.y + 3.0, "QING", 7, ICE, CENTER.x - 20.0, 40.0)
	for i in RINGS.size():
		draw_arc(CENTER, RINGS[i], 0.0, TAU, 64, Color(ICE, 0.25 if i == hit_ring() else 0.1), 1.0, true)
	for th in things:
		var p := at(RINGS[int(th["ring"])], float(th["a"]))
		match int(th["kind"]):
			Kind.COIN:
				draw_circle(p, 3.0, GOLD)
			Kind.LAU:
				_diamond(p, 5.0, MAGENTA)
			Kind.RIFT:
				draw_circle(p, 5.0, Color(MAGENTA, 0.25))
				draw_arc(p, 5.0, 0.0, TAU, 12, MAGENTA, 1.0, true)
				draw_line(p + Vector2(-3, -3), p + Vector2(3, 3), MAGENTA, 1.0)
				draw_line(p + Vector2(-3, 3), p + Vector2(3, -3), MAGENTA, 1.0)
	for k in trail.size():
		draw_circle(trail[k], 1.0 + k * 0.15, Color(ICE if dash <= 0.0 else GOLD, 0.06 * k))
	var me := at(radius(), angle)
	if safe <= 0.0 or int(t * 12.0) % 2 == 0:
		_diamond(me, 5.0, GOLD if dash > 0.0 else ICE)
	var font := ThemeDB.fallback_font
	for p in popups:
		var a := clampf(float(p["life"]) / 0.4, 0.0, 1.0)
		draw_string(font, (p["p"] as Vector2) - Vector2(30, 0), String(p["s"]), HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(p["c"], a))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Color(flash_c, flash * 0.22))


func _draw_hud() -> void:
	super._draw_hud()
	text(Vector2(250, 30), "ORBIT %d" % level, 8, ICE)
	if mult > 1:
		text(Vector2(250, 42), "x%d" % mult, 9, GOLD)
	draw_rect(Rect2(6, 18, 40, 3), Color(ICE, 0.15))
	draw_rect(Rect2(6, 18, 40 * charge, 3), GOLD if charge >= 1.0 else ICE)
