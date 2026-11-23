extends ArcadeGame
## Bar Raiser: build a Hypobar column one segment at a time, with one button.
##
## A gold Epibar mark hangs above the column. Hold fire to pour Fornax into a new segment (it grows
## faster the longer you hold) and let go when its top meets the mark. Within the band the segment
## locks; dead on the mark is PERFECT (gilded, and a streak of perfects scores a growing bonus). Over
## or short trims the column's top segment and costs one of three lives, and so does waiting too long
## to start. Later marks sit higher, drift up and down, and the bands narrow. Height is the score.

enum State { AIM, GROW, RESULT }

const COL_X := 160.0
const COL_W := 60.0
const GROUND_Y := 228.0  # the column base on screen, camera at 0
const SPILL := 22.0  # this far past the band the segment overflows by itself
const RESULT_TIME := 0.65

var segments: Array = []  # {h, perfect}
var height := 0.0
var bonus := 0
var streak := 0
var round_n := 0
var state := State.AIM
var state_t := 0.0
var gap := 30.0
var amp := 0.0
var freq := 1.6
var phase := 0.0
var perfect_tol := 3.0
var good_tol := 8.0
var grow := 0.0
var grow_speed := 30.0
var hold_t := 0.0
var deadline := 4.0
var cam := 0.0
var msg := ""
var msg_c := ICE
var debris: Array = []  # {p, v, w, h, c, life}
var _ai_release := 0.0
var _ai_wait := 0.5


func title() -> String:
	return "Bar Raiser"


func blurb() -> String:
	return "Hold fire to grow the Hypobar; release on the gold Epibar mark."


func _reset() -> void:
	segments.clear()
	debris.clear()
	height = 0.0
	bonus = 0
	streak = 0
	round_n = 0
	cam = 0.0
	msg = ""
	_new_round()


## The mark's height above the column top right now.
func target() -> float:
	return maxf(8.0, gap + amp * sin(state_t * freq + phase))


func _new_round() -> void:
	round_n += 1
	var r := float(mini(round_n, 30))
	gap = rng.randf_range(16.0, 30.0 + r * 1.6)
	amp = 0.0 if round_n < 6 else minf(20.0, (round_n - 5) * 1.6)
	freq = rng.randf_range(1.2, 2.4)
	phase = rng.randf() * TAU
	perfect_tol = maxf(1.0, 3.0 - r * 0.08)
	good_tol = maxf(2.5, 8.0 - r * 0.22)
	grow_speed = minf(26.0 + r * 3.0, 110.0)
	deadline = 4.0 if round_n < 8 else 3.0
	grow = 0.0
	hold_t = 0.0
	state = State.AIM
	state_t = 0.0
	_ai_wait = ai_rng.randf_range(0.3, 1.0)
	_ai_release = ai_rng.randf_range(-1.0, 1.0) * perfect_tol * 1.6


func _tick(dt: float) -> void:
	state_t += dt
	cam = lerpf(cam, maxf(0.0, height - 110.0), minf(1.0, dt * 4.0))
	for i in range(debris.size() - 1, -1, -1):
		var d: Dictionary = debris[i]
		d.v = d.v + Vector2(0.0, 260.0 * dt)
		d.p = d.p + d.v * dt
		d.life -= dt
		if d.life <= 0.0:
			debris.remove_at(i)
	match state:
		State.AIM:
			if pressed & IN_FIRE:
				state = State.GROW
				grow = 0.0
				hold_t = 0.0
			elif state_t > deadline:
				_miss("STALLED")
		State.GROW:
			hold_t += dt
			grow += grow_speed * (1.0 + hold_t * 1.2) * dt
			if not (held & IN_FIRE):
				_judge()
			elif grow > target() + good_tol + SPILL:
				_miss("SPILLED")
		State.RESULT:
			if state_t > RESULT_TIME:
				_new_round()


func _judge() -> void:
	var g := target()
	var err := grow - g
	if absf(err) <= perfect_tol:
		streak += 1
		bonus += 25 * streak
		_lock(g, true)
		msg = "PERFECT" if streak < 2 else "PERFECT x%d" % streak
		msg_c = GOLD
	elif absf(err) <= good_tol:
		streak = 0
		_lock(grow, false)
		msg = "LOCKED"
		msg_c = ICE
	else:
		_miss("OVER" if err > 0.0 else "SHORT")


func _lock(h: float, perfect: bool) -> void:
	segments.append({"h": h, "perfect": perfect})
	height += h
	score = int(height) * 10 + bonus
	state = State.RESULT
	state_t = 0.0


func _miss(why: String) -> void:
	streak = 0
	msg = why
	msg_c = MAGENTA
	# The failed pour spills, and the column loses its top segment.
	if grow > 0.0:
		_debris(height, grow, MAGENTA)
	if not segments.is_empty():
		var top: Dictionary = segments.pop_back()
		height -= top.h
		_debris(height, top.h, GOLD if top.perfect else ICE)
	score = int(height) * 10 + bonus
	grow = 0.0
	state = State.RESULT
	state_t = 0.0
	lose_life()


func _debris(base_h: float, h: float, c: Color) -> void:
	var y := GROUND_Y - base_h - h + cam
	for i in 4:
		if debris.size() >= 24:
			return
		var w := COL_W / 4.0
		debris.append({
			"p": Vector2(COL_X - COL_W * 0.5 + i * w, y), "w": w, "h": h, "c": c, "life": 1.2,
			"v": Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-90.0, -30.0)),
		})


func _demo_input() -> int:
	match state:
		State.AIM:
			return IN_FIRE if state_t > _ai_wait else 0
		State.GROW:
			# Let go a step early, aiming a little off: the demo is good, not perfect.
			var step_grow := grow_speed * (1.0 + hold_t * 1.2) * DT
			return 0 if grow + step_grow >= target() + _ai_release else IN_FIRE
	return 0


# ── drawing ──────────────────────────────────────────────────────────────────


func _y(h: float) -> float:
	return GROUND_Y - h + cam


func _draw_game() -> void:
	var font := ThemeDB.fallback_font
	# The ruler: a tick every 10, a number every 50.
	var h0 := floorf(cam / 10.0) * 10.0 - 10.0
	var h := h0
	while _y(h) > 18.0:
		var y := _y(h)
		if y < SIZE.y:
			var major := int(h) % 50 == 0
			draw_line(Vector2(48, y), Vector2(48 + (10 if major else 5), y), Color(ICE, 0.35 if major else 0.15), 1.0)
			if major and h >= 0.0:
				draw_string(font, Vector2(14, y + 3), str(int(h)), HORIZONTAL_ALIGNMENT_RIGHT, 30, 8, DIM)
		h += 10.0
	draw_line(Vector2(48, 18), Vector2(48, SIZE.y), Color(ICE, 0.12), 1.0)

	# The ground: the QING.
	var gy := _y(0.0)
	if gy < SIZE.y + 2.0:
		glow_line(Vector2(COL_X - 70, gy), Vector2(COL_X + 70, gy), ICE, 1.0)
		text_centered(gy + 10.0, "QING", 7, DIM, COL_X - 30.0, 60.0)

	# The column.
	var base := 0.0
	var x0 := COL_X - COL_W * 0.5
	for s in segments:
		var top := base + float(s.h)
		var r := Rect2(x0, _y(top), COL_W, float(s.h))
		if r.end.y > 16.0 and r.position.y < SIZE.y:
			var c: Color = GOLD if s.perfect else ICE
			draw_rect(r, Color(c, 0.16))
			draw_rect(r, Color(c, 0.75), false, 1.0)
		base = top
	if not segments.is_empty():
		var tr := Rect2(x0, _y(height), COL_W, 1)
		draw_rect(tr, ICE)

	# The pour.
	if state == State.GROW or (state == State.AIM and grow > 0.0):
		var r := Rect2(x0 + 2.0, _y(height + grow), COL_W - 4.0, grow)
		draw_rect(r, Color(MAGENTA, 0.25))
		glow_line(Vector2(x0 + 2.0, r.position.y), Vector2(x0 + COL_W - 2.0, r.position.y), MAGENTA, 1.5)

	# The Epibar mark and its bands.
	if state != State.RESULT:
		var my := _y(height + target())
		draw_rect(Rect2(x0 - 14.0, my - good_tol, COL_W + 28.0, good_tol * 2.0), Color(GOLD, 0.08))
		draw_rect(Rect2(x0 - 14.0, my - perfect_tol, COL_W + 28.0, perfect_tol * 2.0), Color(GOLD, 0.2))
		var x := x0 - 20.0
		while x < x0 + COL_W + 20.0:
			draw_line(Vector2(x, my), Vector2(minf(x + 5.0, x0 + COL_W + 20.0), my), GOLD, 1.0)
			x += 8.0
		text(Vector2(x0 + COL_W + 24.0, my + 3.0), "EPIBAR", 7, GOLD)
		if state == State.AIM:
			var left := clampf(1.0 - state_t / deadline, 0.0, 1.0)
			draw_arc(Vector2(x0 - 30.0, my), 6.0, -PI * 0.5, -PI * 0.5 + TAU * left, 20, Color(MAGENTA if left < 0.35 else ICE, 0.8), 1.5, true)

	for d in debris:
		draw_rect(Rect2(d.p, Vector2(d.w - 1.0, d.h)), Color(d.c, clampf(d.life, 0.0, 1.0) * 0.6), false, 1.0)

	if msg != "" and state == State.RESULT:
		text_centered(56, msg, 16, msg_c)


func _draw_hud() -> void:
	super._draw_hud()
	text(Vector2(250, 30), "H %d" % int(height), 9, ICE)
	text(Vector2(250, 42), "ROUND %d" % round_n, 7, DIM)
	if streak > 1:
		text(Vector2(250, 54), "STREAK %d" % streak, 7, GOLD)
