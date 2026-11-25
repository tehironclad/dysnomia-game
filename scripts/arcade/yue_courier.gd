extends ArcadeGame
## YUE Courier: carry YUE between five QING pads across the Void while its wisps hunt you.
##
## Move in eight directions. A YUE parcel waits on one pad, tagged with the pad it must reach: run
## over it to pick it up, then onto its destination before the clock runs out. A delivery scores
## 100 + the seconds left × 20, times your chain (deliveries in a row, to ×8); a parcel that times out
## breaks the chain. Wisps rise from the rift in the middle and drift after you, faster each level;
## a touch costs a life and the chain. Fire is a Hong pulse: wisps in its ring are stunned and thrown
## back (+15 each); it recharges. Every four deliveries the level rises and another wisp may rise.

const CENTER := Vector2(160, 130)
const PAD_R := 86.0
const PAD_HIT := 13.0
const SPEED := 112.0
const PLAYER_R := 5.0
const WISP_R := 5.0
const PULSE_R := 48.0
const PULSE_RECHARGE := 2.8
const STUN_T := 2.0
const SAFE_T := 1.5
const MAX_WISPS := 7
const ARENA := Rect2(10, 22, 300, 212)

var pads: Array[Vector2] = []
var pos := Vector2(160, 200)
var vel := Vector2.ZERO
var source := -1  ## the pad the parcel waits on (-1: carried)
var dest := 0
var carrying := false
var clock := 0.0  ## seconds left for this parcel
var clock_full := 1.0
var chain := 0
var delivered := 0
var level := 1
var wisps: Array = []  # {p: Vector2, v: Vector2, stun: float}
var wisp_t := 2.0
var charge := 1.0
var pulse_t := -1.0  ## seconds since the last pulse (-1: none showing)
var safe := 0.0
var flash := 0.0
var flash_c := MAGENTA
var popups: Array = []  # {p, s, c, life}
var _ai_wobble := Vector2.ZERO
var _gen := 0


func title() -> String:
	return "YUE Courier"


func blurb() -> String:
	return "Carry YUE pad to pad before time runs out; dodge Void wisps. Fire: Hong pulse."


## Pure: the five pads, a pentagon round the rift.
static func pad_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in 5:
		var a := -PI * 0.5 + TAU * i / 5.0
		out.append(CENTER + Vector2(cos(a), sin(a)) * Vector2(PAD_R * 1.35, PAD_R))
	return out


## Pure: what a delivery scores: (100 + whole seconds left × 20) × the chain (1..8).
static func delivery_score(seconds_left: float, chain_n: int) -> int:
	return (100 + int(seconds_left) * 20) * clampi(chain_n, 1, 8)


func wisp_speed() -> float:
	return minf(34.0 + (level - 1) * 7.0, 96.0)


func wisp_cap() -> int:
	return mini(1 + level, MAX_WISPS)


func _reset() -> void:
	_gen += 1
	pads = pad_positions()
	pos = Vector2(160, 200)
	vel = Vector2.ZERO
	carrying = false
	chain = 0
	delivered = 0
	level = 1
	wisps.clear()
	popups.clear()
	wisp_t = 2.5
	charge = 1.0
	pulse_t = -1.0
	safe = 0.0
	flash = 0.0
	_new_parcel(-1)


## A parcel on a pad you are not standing on, bound for another pad.
func _new_parcel(avoid: int) -> void:
	source = rng.randi_range(0, pads.size() - 1)
	if source == avoid:
		source = (source + 1 + rng.randi_range(0, pads.size() - 2)) % pads.size()
	dest = (source + 1 + rng.randi_range(0, pads.size() - 2)) % pads.size()
	carrying = false
	# Time to walk there and on to the destination, plus some slack (less at higher levels).
	var trip := (pos.distance_to(pads[source]) + pads[source].distance_to(pads[dest])) / SPEED
	clock_full = trip + maxf(2.5, 6.0 - level * 0.4)
	clock = clock_full


func _tick(dt: float) -> void:
	var gen := _gen
	flash = maxf(0.0, flash - dt)
	safe = maxf(0.0, safe - dt)
	var dir := Vector2.ZERO
	if held & IN_LEFT:
		dir.x -= 1.0
	if held & IN_RIGHT:
		dir.x += 1.0
	if held & IN_UP:
		dir.y -= 1.0
	if held & IN_DOWN:
		dir.y += 1.0
	vel = dir.normalized() * SPEED if dir != Vector2.ZERO else Vector2.ZERO
	pos += vel * dt
	pos.x = clampf(pos.x, ARENA.position.x, ARENA.end.x)
	pos.y = clampf(pos.y, ARENA.position.y, ARENA.end.y)
	# The Hong pulse.
	if pulse_t >= 0.0:
		pulse_t += dt
		if pulse_t > 0.45:
			pulse_t = -1.0
	charge = minf(1.0, charge + dt / PULSE_RECHARGE)
	if pressed & IN_FIRE and charge >= 1.0:
		charge = 0.0
		pulse_t = 0.0
		var stunned := 0
		for w in wisps:
			var d: Vector2 = (w["p"] as Vector2) - pos
			if d.length() <= PULSE_R:
				w["stun"] = STUN_T
				w["v"] = d.normalized() * 160.0 if d.length() > 0.01 else Vector2(0, -160)
				stunned += 1
		if stunned > 0:
			score += 15 * stunned
			_popup(pos + Vector2(0, -12), "+%d" % (15 * stunned), ICE)
	# The parcel.
	clock -= dt
	if not carrying and pos.distance_to(pads[source]) <= PAD_HIT:
		carrying = true
		score += 10
		_popup(pads[source] + Vector2(0, -12), "YUE", GOLD)
	elif carrying and pos.distance_to(pads[dest]) <= PAD_HIT:
		chain += 1
		delivered += 1
		var gain := delivery_score(maxf(0.0, clock), chain)
		score += gain
		flash = 0.25
		flash_c = GOLD
		_popup(pads[dest] + Vector2(0, -12), "+%d" % gain, GOLD)
		if delivered % 4 == 0:
			level += 1
		_new_parcel(dest)
	elif clock <= 0.0:
		chain = 0
		_popup(pads[dest if carrying else source] + Vector2(0, -12), "LATE", MAGENTA)
		_new_parcel(-1)
	# Wisps rise from the rift and drift after you.
	wisp_t -= dt
	if wisp_t <= 0.0:
		wisp_t = maxf(1.5, 4.5 - level * 0.35)
		if wisps.size() < wisp_cap():
			var a := rng.randf() * TAU
			wisps.append({"p": CENTER + Vector2(cos(a), sin(a)) * 6.0, "v": Vector2.ZERO, "stun": 0.0})
	var sp := wisp_speed()
	for w in wisps:
		var p: Vector2 = w["p"]
		if float(w["stun"]) > 0.0:
			w["stun"] = float(w["stun"]) - dt
			w["v"] = (w["v"] as Vector2) * maxf(0.0, 1.0 - dt * 3.0)
		else:
			var want := (pos - p).normalized() * sp
			w["v"] = (w["v"] as Vector2).lerp(want, minf(1.0, dt * 1.6))
		p += (w["v"] as Vector2) * dt
		p.x = clampf(p.x, ARENA.position.x, ARENA.end.x)
		p.y = clampf(p.y, ARENA.position.y, ARENA.end.y)
		w["p"] = p
	if safe <= 0.0:
		for w in wisps:
			if float(w["stun"]) <= 0.0 and (w["p"] as Vector2).distance_to(pos) <= PLAYER_R + WISP_R:
				_hit()
				if gen != _gen or not (playing or attract_mode):
					return
				break
	for j in range(popups.size() - 1, -1, -1):
		var pp: Dictionary = popups[j]
		pp["life"] = float(pp["life"]) - dt
		pp["p"] = (pp["p"] as Vector2) + Vector2(0, -16.0 * dt)
		if float(pp["life"]) <= 0.0:
			popups.remove_at(j)


func _hit() -> void:
	chain = 0
	safe = SAFE_T
	flash = 0.45
	flash_c = MAGENTA
	_popup(pos + Vector2(0, -12), "WISPED", MAGENTA)
	# The wisps that got you are thrown back to the rift's edge.
	for w in wisps:
		if (w["p"] as Vector2).distance_to(pos) < 50.0:
			w["stun"] = 1.0
			var d: Vector2 = (w["p"] as Vector2) - pos
			w["v"] = (d.normalized() if d.length() > 0.01 else Vector2(0, -1)) * 140.0
	lose_life()


func _popup(p: Vector2, s: String, c: Color) -> void:
	if popups.size() >= 6:
		popups.pop_front()
	popups.append({"p": p, "s": s, "c": c, "life": 0.8})


## Where the parcel wants you: its pad, or its destination once you carry it.
func goal() -> Vector2:
	return pads[dest] if carrying else pads[source]


## The demo: head for the goal, sidestep the nearest wisp, pulse when one is close.
func _demo_input() -> int:
	var to := goal() - pos
	var near := 1e9
	var away := Vector2.ZERO
	for w in wisps:
		var d: Vector2 = pos - (w["p"] as Vector2)
		if float(w["stun"]) <= 0.0 and d.length() < near:
			near = d.length()
			away = d
	if int(t * 2.0) % 3 == 0:
		_ai_wobble = Vector2(ai_rng.randf_range(-0.4, 0.4), ai_rng.randf_range(-0.4, 0.4))
	var steer := to.normalized() + _ai_wobble
	if near < 40.0:
		steer += away.normalized() * 1.4
	var bits := 0
	if steer.x < -0.3:
		bits |= IN_LEFT
	elif steer.x > 0.3:
		bits |= IN_RIGHT
	if steer.y < -0.3:
		bits |= IN_UP
	elif steer.y > 0.3:
		bits |= IN_DOWN
	if near < 30.0 and charge >= 1.0:
		bits |= IN_FIRE
	return bits


# ── drawing ──────────────────────────────────────────────────────────────────


func _draw_game() -> void:
	draw_rect(ARENA, Color(ICE, 0.08), false, 1.0)
	# The rift.
	for k in 3:
		draw_arc(CENTER, 7.0 + k * 4.0, t * (1.5 + k), t * (1.5 + k) + PI * 1.3, 16, Color(MAGENTA, 0.5 - k * 0.12), 1.0, true)
	var font := ThemeDB.fallback_font
	for i in pads.size():
		var p: Vector2 = pads[i]
		var c := ICE
		if i == dest and carrying:
			c = GOLD
		draw_circle(p, PAD_HIT, Color(c, 0.1))
		draw_arc(p, PAD_HIT, 0.0, TAU, 24, Color(c, 0.7), 1.0, true)
		draw_string(font, p + Vector2(-10, 3), "Q%d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 7, Color(c, 0.6))
	if not carrying:
		_diamond(pads[source] + Vector2(0, -2), 5.0, GOLD)
		draw_line(pads[source], pads[dest], Color(GOLD, 0.12), 1.0)
	# The clock: an arc round the goal.
	var left := clampf(clock / clock_full, 0.0, 1.0)
	draw_arc(goal(), PAD_HIT + 4.0, -PI * 0.5, -PI * 0.5 + TAU * left, 24, Color(MAGENTA if left < 0.3 else GOLD, 0.8), 1.5, true)
	for w in wisps:
		var wp: Vector2 = w["p"]
		var stun := float(w["stun"]) > 0.0
		draw_circle(wp, WISP_R + 2.0, Color(MAGENTA, 0.15))
		draw_circle(wp, WISP_R, Color(DIM if stun else MAGENTA, 0.8))
	if pulse_t >= 0.0:
		draw_arc(pos, PULSE_R * clampf(pulse_t / 0.25, 0.0, 1.0), 0.0, TAU, 32, Color(ICE, 1.0 - pulse_t / 0.45), 2.0, true)
	if safe <= 0.0 or int(t * 12.0) % 2 == 0:
		_diamond(pos, PLAYER_R + 1.0, ICE)
		if carrying:
			_diamond(pos + Vector2(0, -9), 3.5, GOLD)
	for pp in popups:
		var a := clampf(float(pp["life"]) / 0.4, 0.0, 1.0)
		draw_string(font, (pp["p"] as Vector2) - Vector2(30, 0), String(pp["s"]), HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(pp["c"], a))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Color(flash_c, flash * 0.22))


func _draw_hud() -> void:
	super._draw_hud()
	text(Vector2(232, 30), "LEVEL %d" % level, 8, ICE)
	if chain > 1:
		text(Vector2(232, 42), "CHAIN x%d" % mini(chain, 8), 8, GOLD)
	draw_rect(Rect2(6, 18, 40, 3), Color(ICE, 0.15))
	draw_rect(Rect2(6, 18, 40 * charge, 3), GOLD if charge >= 1.0 else ICE)
