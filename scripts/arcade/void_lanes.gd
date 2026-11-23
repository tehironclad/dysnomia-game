extends ArcadeGame
## Void Lanes: lines of chat fall through the Void down four lanes. Catch the true ones.
##
## Left/right switch lanes. Catching a true line scores and builds the combo (the multiplier rises
## every six in a row); gold OG lines are worth triple. Imposters look true until they fall far enough
## to be checked, then show ⚠; catching one costs a life. Sharp eyes can spot an imposter early by its
## lookalike name (s0ul, 3ris…). Fire flags the nearest line in your lane: flag an imposter for a
## bonus (double before it is revealed), but a false flag breaks the combo. Five missed true lines
## cost a life. Lines fall faster and imposters reveal later as the epochs pass.

const LANES := 4
const LANE_X: Array[float] = [52.0, 124.0, 196.0, 268.0]
const TOP := 22.0
const CATCH_Y := 214.0
const LINE_W := 64.0
const LINE_H := 15.0
const MISSES_PER_LIFE := 5
const FLAG_COOLDOWN := 0.45
const NAMES := ["soul", "aura", "pole", "yue", "iota", "eris", "fornax", "zuo", "qing", "cheon", "lau", "shio", "sei", "cho", "yang", "zhou", "void", "atropa"]
const MSGS := ["gm", "su", "join", "gn", "lfg", "beat", "hi", "wen", "ok", "yes"]
const LOOKALIKE := {"o": "0", "l": "1", "i": "1", "e": "3", "a": "4", "s": "5", "u": "v"}

enum Kind { TRUE, IMPOSTER, OG }

var lane := 1
var lane_x := 124.0
var lines: Array = []  # {lane, y, kind, who, msg, reveal}
var combo := 0
var misses := 0
var cooldown := 0.0
var beam_t := -1.0
var beam_x := 0.0
var beam_top := 0.0
var spawn := 0.6
var fall := 46.0
var epoch := 1
var popups: Array = []  # {p, s, c, life}
var flash := 0.0
var flash_c := MAGENTA
var _ai_t := 0.0
var _ai_lane := 1


func title() -> String:
	return "Void Lanes"


func blurb() -> String:
	return "Catch true chat lines; dodge or flag the imposters. Fire: flag."


func multiplier() -> int:
	return mini(8, 1 + int(combo / 6.0))


func _reset() -> void:
	lane = 1
	lane_x = LANE_X[1]
	lines.clear()
	popups.clear()
	combo = 0
	misses = 0
	cooldown = 0.0
	beam_t = -1.0
	spawn = 0.6
	fall = 46.0
	epoch = 1
	flash = 0.0
	_ai_t = 0.0
	_ai_lane = 1


func _tick(dt: float) -> void:
	epoch = 1 + int(t / 18.0)
	fall = minf(46.0 + (epoch - 1) * 10.0 + t * 0.15, 175.0)
	cooldown = maxf(0.0, cooldown - dt)
	flash = maxf(0.0, flash - dt)
	if beam_t >= 0.0:
		beam_t += dt
		if beam_t > 0.18:
			beam_t = -1.0

	if pressed & IN_LEFT:
		lane = maxi(0, lane - 1)
	if pressed & IN_RIGHT:
		lane = mini(LANES - 1, lane + 1)
	lane_x = lerpf(lane_x, LANE_X[lane], minf(1.0, dt * 22.0))

	if pressed & IN_FIRE and cooldown <= 0.0:
		_flag()
		if not (playing or attract_mode):
			return

	spawn -= dt
	if spawn <= 0.0:
		spawn = maxf(0.3, 1.05 - (epoch - 1) * 0.08) * rng.randf_range(0.75, 1.25)
		_spawn_line()

	for i in range(popups.size() - 1, -1, -1):
		var pu: Dictionary = popups[i]
		pu.life -= dt
		pu.p = pu.p + Vector2(0.0, -18.0 * dt)
		if pu.life <= 0.0:
			popups.remove_at(i)

	for i in range(lines.size() - 1, -1, -1):
		var l: Dictionary = lines[i]
		l.y += fall * dt
		var bottom: float = l.y + LINE_H
		if l.lane == lane and bottom >= CATCH_Y - 6.0 and l.y <= CATCH_Y + 2.0:
			lines.remove_at(i)
			if _catch(l):
				return  # the run ended
			continue
		if l.y > SIZE.y:
			lines.remove_at(i)
			if l.kind == Kind.IMPOSTER:
				score += 5  # dodged
			else:
				combo = 0
				misses += 1
				_popup(Vector2(LANE_X[l.lane], SIZE.y - 30.0), "MISSED", DIM)
				if misses >= MISSES_PER_LIFE:
					misses = 0
					flash = 0.3
					flash_c = DIM
					if lose_life():
						return


func revealed(l: Dictionary) -> bool:
	return l.kind == Kind.IMPOSTER and l.y >= l.reveal


func _spawn_line() -> void:
	var tries := 0
	var ln := rng.randi_range(0, LANES - 1)
	while tries < LANES:
		var clear := true
		for l in lines:
			if l.lane == ln and l.y < TOP + LINE_H * 2.2:
				clear = false
		if clear:
			break
		ln = (ln + 1) % LANES
		tries += 1
	if tries >= LANES:
		return
	var roll := rng.randf()
	var p_imp := minf(0.22 + (epoch - 1) * 0.03, 0.45)
	var kind := Kind.TRUE
	if roll < p_imp:
		kind = Kind.IMPOSTER
	elif roll < p_imp + 0.08:
		kind = Kind.OG
	var who: String = NAMES[rng.randi_range(0, NAMES.size() - 1)]
	if kind == Kind.IMPOSTER:
		who = _lookalike(who)
	var late := clampf((epoch - 1) / 8.0, 0.0, 1.0)
	var reveal := lerpf(TOP + 6.0, 150.0, late) + rng.randf_range(-8.0, 16.0)
	lines.append({"lane": ln, "y": TOP - LINE_H, "kind": kind, "who": who, "msg": MSGS[rng.randi_range(0, MSGS.size() - 1)], "reveal": reveal})


func _lookalike(who: String) -> String:
	var spots: Array[int] = []
	for i in who.length():
		if LOOKALIKE.has(who[i]):
			spots.append(i)
	if spots.is_empty():
		return who + "_"
	var i := spots[rng.randi_range(0, spots.size() - 1)]
	return who.substr(0, i) + LOOKALIKE[who[i]] + who.substr(i + 1)


## Returns true when this catch ended the run.
func _catch(l: Dictionary) -> bool:
	var at := Vector2(LANE_X[l.lane], CATCH_Y - 18.0)
	if l.kind == Kind.IMPOSTER:
		combo = 0
		flash = 0.35
		flash_c = MAGENTA
		_popup(at, "IMPOSTER", MAGENTA)
		return lose_life()
	combo += 2 if l.kind == Kind.OG else 1
	var pts := (30 if l.kind == Kind.OG else 10) * multiplier()
	score += pts
	_popup(at, "+%d" % pts, GOLD if l.kind == Kind.OG else ICE)
	return false


func _flag() -> void:
	cooldown = FLAG_COOLDOWN
	beam_t = 0.0
	beam_x = LANE_X[lane]
	beam_top = TOP
	var best := -1
	for i in lines.size():
		var l: Dictionary = lines[i]
		if l.lane == lane and l.y < CATCH_Y and (best < 0 or l.y > lines[best].y):
			best = i
	if best < 0:
		return
	var l: Dictionary = lines[best]
	lines.remove_at(best)
	beam_top = l.y + LINE_H
	var at := Vector2(LANE_X[l.lane], l.y)
	if l.kind == Kind.IMPOSTER:
		var pts := (20 if revealed(l) else 40) * multiplier()
		score += pts
		combo += 1
		_popup(at, "FLAGGED +%d" % pts, MAGENTA)
	else:
		combo = 0
		misses += 1
		_popup(at, "FALSE FLAG", DIM)
		if misses >= MISSES_PER_LIFE:
			misses = 0
			lose_life()


func _popup(p: Vector2, s: String, c: Color) -> void:
	if popups.size() < 8:
		popups.append({"p": p, "s": s, "c": c, "life": 0.7})


func _demo_input() -> int:
	_ai_t -= DT
	if _ai_t <= 0.0:
		_ai_t = ai_rng.randf_range(0.08, 0.2)
		# Go for the most urgent catchable true line; keep out of a revealed imposter's lane.
		var best_y := -1e9
		_ai_lane = lane
		for l in lines:
			if l.kind != Kind.IMPOSTER and l.y < CATCH_Y - 8.0 and l.y > best_y:
				var reach := absf(l.lane - lane) * 0.12
				if (CATCH_Y - l.y - LINE_H) / fall > reach:
					best_y = l.y
					_ai_lane = l.lane
	var bits := 0
	if _ai_lane < lane and (held & IN_LEFT) == 0:
		bits |= IN_LEFT
	elif _ai_lane > lane and (held & IN_RIGHT) == 0:
		bits |= IN_RIGHT
	for l in lines:
		if l.lane == lane and revealed(l) and l.y > 120.0 and cooldown <= 0.0 and (held & IN_FIRE) == 0:
			bits |= IN_FIRE
	return bits


# ── drawing ──────────────────────────────────────────────────────────────────


func _draw_game() -> void:
	# The Void: lane rails and a slow falling dot lattice.
	for i in range(1, LANES):
		var x := (LANE_X[i - 1] + LANE_X[i]) * 0.5
		draw_line(Vector2(x, TOP), Vector2(x, CATCH_Y + 10.0), Color(ICE, 0.07), 1.0)
	var off := fmod(t * fall * 0.35, 24.0)
	for row in 10:
		var y := TOP + row * 24.0 + off
		for i in LANES:
			draw_rect(Rect2(LANE_X[i] - 0.5, y, 1, 1), Color(ICE, 0.18))
	draw_line(Vector2(16, TOP), Vector2(304, TOP), Color(ICE, 0.25), 1.0)

	var font := ThemeDB.fallback_font
	for l in lines:
		var c := ICE
		if l.kind == Kind.OG:
			c = GOLD
		elif revealed(l):
			c = MAGENTA
		var r := Rect2(LANE_X[l.lane] - LINE_W * 0.5, l.y, LINE_W, LINE_H)
		draw_rect(r, Color(c, 0.1))
		draw_rect(r, Color(c, 0.8), false, 1.0)
		var label: String = "%s: %s" % [l.who, l.msg]
		var tx := r.position.x + 4.0
		if revealed(l):
			_warning(Vector2(r.position.x + 7.0, l.y + 8.0), MAGENTA)
			tx += 10.0
		elif l.kind == Kind.OG:
			_diamond(Vector2(r.position.x + 6.0, l.y + 7.5), 2.5, GOLD)
			tx += 8.0
		draw_string(font, Vector2(tx, l.y + 11.0), label, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 2.0, 8, c)

	if beam_t >= 0.0:
		var a := 1.0 - beam_t / 0.18
		glow_line(Vector2(beam_x, CATCH_Y - 2.0), Vector2(beam_x, beam_top), Color(MAGENTA, a), 1.5)

	# The catcher (your LAU).
	var y := CATCH_Y
	var hw := LINE_W * 0.5 + 2.0
	glow_line(Vector2(lane_x - hw, y), Vector2(lane_x + hw, y), ICE, 1.5)
	glow_line(Vector2(lane_x - hw, y), Vector2(lane_x - hw, y - 7.0), ICE, 1.5)
	glow_line(Vector2(lane_x + hw, y), Vector2(lane_x + hw, y - 7.0), ICE, 1.5)
	text_centered(y + 12.0, "LAU", 7, DIM, lane_x - 20.0, 40.0)

	for pu in popups:
		text_centered(pu.p.y, pu.s, 8, Color(pu.c, clampf(pu.life * 2.0, 0.0, 1.0)), pu.p.x - 40.0, 80.0)
	if flash > 0.0 and not over:
		draw_rect(Rect2(0, TOP, SIZE.x, SIZE.y - TOP), Color(flash_c, flash * 0.3))


func _draw_hud() -> void:
	super._draw_hud()
	var m := multiplier()
	text_centered(12, "x%d  COMBO %d" % [m, combo], 9, GOLD if m > 1 else MUTED)
	for i in MISSES_PER_LIFE:
		var r := Rect2(SIZE.x - 50 + i * 6, 15, 4, 3)
		draw_rect(r, MAGENTA if i < misses else Color(DIM, 0.5))
	text(Vector2(64, 12), "E%d" % epoch, 8, DIM)


func _warning(c: Vector2, color: Color) -> void:
	var tri := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 4), c + Vector2(-5, 4)])
	glow_poly(tri, color, 1.0)
	draw_line(c + Vector2(0, -2), c + Vector2(0, 1), color, 1.0)
	draw_rect(Rect2(c + Vector2(-0.5, 2), Vector2(1, 1)), color)
