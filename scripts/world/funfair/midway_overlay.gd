class_name MidwayOverlay
extends Control
## Plays one midway game (MidwayGame rules) over the world: intro → play → result.
## One button: Use (the "interact" action). Esc forfeits. Emits finished(score)
## once (score -1 when forfeited). Drawn with _draw so it needs no assets.

signal finished(score: int)

var game_id := ""
var seed_v := 0
var paid := false
var ticket_note := ""   # "ticket 0x12ab…cd34 · block N" or "practice · nothing paid"
var board: Array = []   # this stall's local board (ArcadeScores rows)

var _g: Dictionary
var _mech := ""
var _phase := "intro"   # intro, play, show, done
var _t := 0.0           # time in the current round
var _round := 0
var _score := 0
var _last := ""         # last round's line ("+60")
var _show_t := 0.0
var _lock_u := -1.0     # rings: first press
var _target := 0.5      # toss
var _rows: Array = []   # shy
var _seq := PackedInt32Array()  # primes
var _wheel := PackedInt32Array()
var _angle := 0.0
var _braking := false
var _stop_at := 0.0
var _a0 := 0.0
var _rank := 0
var _hits: Array = []   # little flashes [text, color, ttl]
var _done_emitted := false

const W := 760.0
const H := 420.0


func start(id: String, p_seed: int, p_paid: bool, note: String, p_board: Array) -> void:
	game_id = id
	seed_v = p_seed
	paid = p_paid
	ticket_note = note
	board = p_board
	_g = MidwayGame.GAMES[id]
	_mech = String(_g["mech"])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows = MidwayGame.shy_rows(seed_v)
	_seq = MidwayGame.prime_sequence(seed_v)
	_wheel = MidwayGame.wheel_values(seed_v)
	_target = MidwayGame.toss_target(seed_v, 0)
	_phase = "intro"
	_t = 0.0
	queue_redraw()


func score() -> int:
	return _score


func _process(delta: float) -> void:
	_t += delta
	for h in _hits:
		h[2] -= delta
	_hits = _hits.filter(func(h): return h[2] > 0.0)
	if _phase == "play":
		match _mech:
			"wheel":
				if _braking:
					var spd := maxf(0.0, MidwayGame.WHEEL_SPEED - MidwayGame.WHEEL_DECEL * _t)
					_angle = _a0 + MidwayGame.WHEEL_SPEED * _t - 0.5 * MidwayGame.WHEEL_DECEL * _t * _t if spd > 0.0 else _stop_at
					if spd <= 0.0:
						_angle = _stop_at
						var v := int(_wheel[MidwayGame.wheel_segment(_angle)])
						_end_round(v, "+%d" % v)
				else:
					_angle += MidwayGame.WHEEL_SPEED * delta
			"primes":
				# One number crosses the sight every `period` seconds (faster as it goes)
				var period := _prime_period()
				if _t >= period:
					_t -= period
					_round += 1
					if _round >= int(_g["rounds"]) + 4:
						_finish()
	elif _phase == "show":
		_show_t -= delta
		if _show_t <= 0.0:
			if _round >= int(_g["rounds"]):
				_finish()
			else:
				_phase = "play"
				_t = 0.0
				_braking = false
				_lock_u = -1.0
				_target = MidwayGame.toss_target(seed_v, _round)
	queue_redraw()


func _prime_period() -> float:
	return maxf(0.75, 1.5 - 0.05 * _round)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not _done_emitted:
			_done_emitted = true
			finished.emit(-1 if _phase != "done" else _score)
		return
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	match _phase:
		"intro":
			if _mech == "fortune":
				_phase = "done"
				return
			_phase = "play"
			_t = 0.0
		"play":
			_press()
		"done":
			if not _done_emitted:
				_done_emitted = true
				finished.emit(_score)


func _press() -> void:
	match _mech:
		"striker":
			var m := MidwayGame.meter(_t, _round)
			var p := MidwayGame.striker_points(m)
			_end_round(p, "DING! +%d" % p if m >= 0.96 else "+%d" % p)
		"toss":
			var m2 := MidwayGame.meter(_t, _round)
			var p2 := MidwayGame.toss_points(m2, _target)
			_end_round(p2, "+%d" % p2 if p2 > 0 else "miss")
		"rings":
			var m3 := MidwayGame.meter(_t, _round)
			if _lock_u < 0.0:
				_lock_u = m3
				_t = 0.0
			else:
				var p3 := MidwayGame.ring_points(_lock_u, m3)
				_end_round(p3, "RINGER +100" if p3 == 100 else ("+%d" % p3 if p3 > 0 else "bounced off"))
		"shy":
			var row: Dictionary = _rows[_round % 2]
			var hit := MidwayGame.shy_hit(row, _t)
			_round += 1
			if hit:
				_score += 100
			_hits.append(["HIT +100" if hit else "miss", Color("#7dffb0") if hit else Color("#ff8fa0"), 0.8])
			if _round >= int(_g["rounds"]):
				_finish()
		"primes":
			var n := int(_seq[_round % _seq.size()])
			var frac := _t / _prime_period()
			if absf(frac - 0.5) > 0.18:
				_hits.append(["not in the sight", Color("#8e97a9"), 0.6])
				return
			var good := MidwayGame.is_prime(n)
			_score = maxi(0, _score + (100 if good else -50))
			_hits.append(["%d PRIME +100" % n if good else "%d = not prime −50" % n, Color("#7dffb0") if good else Color("#ff8fa0"), 0.9])
			# Each number can be shot once: skip ahead to the next one
			_t = _prime_period() * 0.75
		"wheel":
			if not _braking:
				_braking = true
				_a0 = _angle
				_stop_at = MidwayGame.wheel_stop(_a0)
				_t = 0.0


func _end_round(points: int, line: String) -> void:
	_score += points
	_last = line
	_round += 1
	_phase = "show"
	_show_t = 1.1
	_hits.append([line, Color("#ffd27a") if points > 0 else Color("#ff8fa0"), 1.1])


func _finish() -> void:
	_phase = "done"
	_rank = ArcadeScores.rank_of(board, _score) if paid else 0


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	var vp := get_viewport_rect().size
	var o := (vp - Vector2(W, H)) * 0.5
	var r := Rect2(o, Vector2(W, H))
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35))
	draw_rect(r, Color(0.03, 0.04, 0.08, 0.97))
	draw_rect(r, Color(1.0, 0.75, 0.3, 0.8), false, 2.0)
	var fd := DeepFieldTheme.display_font()
	var fm := DeepFieldTheme.mono_font()
	draw_string(fd, o + Vector2(24, 44), String(_g["title"]), HORIZONTAL_ALIGNMENT_LEFT, W - 48, 30, Color("#ffd27a"))
	draw_string(fm, o + Vector2(24, 68), ticket_note, HORIZONTAL_ALIGNMENT_LEFT, W - 48, 12, DeepFieldTheme.MUTED)
	if _mech != "fortune":
		draw_string(fm, o + Vector2(W - 324, 44), "SCORE %d" % _score, HORIZONTAL_ALIGNMENT_RIGHT, 300, 20, DeepFieldTheme.INK)
		var rounds_txt := "%d / %d" % [mini(_round + (1 if _phase == "play" else 0), int(_g["rounds"])), int(_g["rounds"])]
		if _mech == "primes":
			rounds_txt = "number %d" % (_round + 1)
		draw_string(fm, o + Vector2(W - 324, 68), rounds_txt, HORIZONTAL_ALIGNMENT_RIGHT, 300, 12, DeepFieldTheme.MUTED)
	var key := ControlsHelp.key_of("interact")
	var area := Rect2(o + Vector2(24, 86), Vector2(W - 48, H - 140))
	match _phase:
		"intro":
			_text_block(area, String(_g["how"]))
			draw_string(fd, o + Vector2(0, H - 30), "Press %s to %s   ·   Esc to leave" % [key, "read it" if _mech == "fortune" else "start"],
				HORIZONTAL_ALIGNMENT_CENTER, W, 18, DeepFieldTheme.ICE)
		"play", "show":
			_draw_game(area)
			draw_string(fm, o + Vector2(0, H - 24), "%s: %s" % [key, _hint()], HORIZONTAL_ALIGNMENT_CENTER, W, 14, DeepFieldTheme.ICE)
		"done":
			_draw_done(area)
			draw_string(fd, o + Vector2(0, H - 24), "Press %s to close" % key, HORIZONTAL_ALIGNMENT_CENTER, W, 18, DeepFieldTheme.ICE)
	var y := o.y + 110.0
	for h in _hits:
		draw_string(fd, Vector2(o.x, y), String(h[0]), HORIZONTAL_ALIGNMENT_CENTER, W, 26, Color(h[1], clampf(float(h[2]) * 2.0, 0.0, 1.0)))
		y += 30.0


func _hint() -> String:
	match _mech:
		"rings": return "stop the sweep" if _lock_u < 0.0 else "drop the ring"
		"wheel": return "brake" if not _braking else "…"
		"primes": return "shoot the number in the sight"
		"shy": return "throw"
	return "swing" if _mech == "striker" else "toss"


func _text_block(area: Rect2, text: String) -> void:
	draw_multiline_string(DeepFieldTheme.body_font(), area.position + Vector2(0, 40), text, HORIZONTAL_ALIGNMENT_CENTER,
		area.size.x, 20, -1, DeepFieldTheme.INK)


func _draw_game(a: Rect2) -> void:
	var c := a.get_center()
	match _mech:
		"striker":
			var m := MidwayGame.meter(_t, _round) if _phase == "play" else clampf(_score_last_frac(), 0.0, 1.0)
			var base := Vector2(c.x, a.end.y - 10)
			var top := Vector2(c.x, a.position.y + 30)
			draw_line(base, top, Color(0.7, 0.1, 0.15), 18.0)
			for i in 20:
				var u := float(i) / 19.0
				var col := Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.85, 0.2), minf(u * 2.0, 1.0)).lerp(Color(1.0, 0.15, 0.2), maxf(u * 2.0 - 1.0, 0.0))
				var lit := u <= m
				draw_circle(base.lerp(top, u) + Vector2(-20, 0), 5.0, col if lit else col * Color(1, 1, 1, 0.18))
				draw_circle(base.lerp(top, u) + Vector2(20, 0), 5.0, col if lit else col * Color(1, 1, 1, 0.18))
			draw_circle(top + Vector2(0, -12), 14.0, Color("#ffd27a") if m >= 0.96 else Color(0.5, 0.42, 0.2))
			draw_rect(Rect2(base.lerp(top, m) - Vector2(16, 6), Vector2(32, 12)), Color(0.95, 0.95, 0.9))
		"toss", "rings":
			_draw_meter_game(a)
		"shy":
			for i in 2:
				var row: Dictionary = _rows[i]
				var y := a.position.y + a.size.y * (0.35 + 0.35 * i)
				draw_line(Vector2(a.position.x, y + 18), Vector2(a.end.x, y + 18), Color(0.4, 0.42, 0.5), 2.0)
				var gap := float(row["gap"])
				var k := -1.0
				while k < 1.0 / gap + 1.0:
					var x := fposmod(float(row["offset"]) + float(row["speed"]) * _t + k * gap, 1.0 + gap) - gap * 0.5
					if x >= 0.0 and x <= 1.0:
						_crystal(Vector2(a.position.x + x * a.size.x, y), Color(0.6, 0.8, 1.0) if i == 0 else Color(0.85, 0.6, 1.0))
					k += 1.0
				if i == _round % 2:
					draw_string(DeepFieldTheme.mono_font(), Vector2(a.position.x, y - 26), "throwing at this row", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DeepFieldTheme.ICE)
			draw_line(Vector2(c.x, a.position.y), Vector2(c.x, a.end.y), Color(1.0, 0.85, 0.3, 0.8), 2.0)
		"primes":
			var frac := _t / _prime_period()
			var n := int(_seq[_round % _seq.size()])
			var x := a.end.x - frac * a.size.x
			draw_rect(Rect2(Vector2(c.x - a.size.x * 0.18, a.position.y + 40), Vector2(a.size.x * 0.36, a.size.y - 80)), Color(1.0, 0.85, 0.3, 0.08))
			draw_rect(Rect2(Vector2(c.x - a.size.x * 0.18, a.position.y + 40), Vector2(a.size.x * 0.36, a.size.y - 80)), Color(1.0, 0.85, 0.3, 0.7), false, 2.0)
			draw_string(DeepFieldTheme.display_font(), Vector2(x - 60, c.y + 22), str(n), HORIZONTAL_ALIGNMENT_CENTER, 120, 56, DeepFieldTheme.INK)
		"wheel":
			var rad := minf(a.size.y * 0.5, 150.0)
			var seg := TAU / 12.0
			for k in 12:
				var a0 := _angle + k * seg - PI * 0.5
				var pts := PackedVector2Array([c])
				for j in 9:
					pts.append(c + Vector2.from_angle(a0 + seg * j / 8.0) * rad)
				var col := Color.from_hsv(float(k) / 12.0, 0.55, 0.85 if k % 2 == 0 else 0.65)
				if int(_wheel[k]) == 500:
					col = Color("#ffd27a")
				draw_colored_polygon(pts, col)
				draw_string(DeepFieldTheme.mono_font(), c + Vector2.from_angle(a0 + seg * 0.5) * rad * 0.68 - Vector2(20, -5), str(_wheel[k]),
					HORIZONTAL_ALIGNMENT_CENTER, 40, 14, Color(0.05, 0.05, 0.08))
			draw_circle(c, 14.0, Color(0.1, 0.1, 0.14))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -rad - 14), c + Vector2(12, -rad - 14), c + Vector2(0, -rad + 8)]), Color.WHITE)


func _score_last_frac() -> float:
	return float(_last.trim_prefix("DING! +").trim_prefix("+").to_int()) / 100.0


func _draw_meter_game(a: Rect2) -> void:
	var c := a.get_center()
	if _mech == "toss":
		var bar := Rect2(Vector2(a.position.x + 40, c.y - 16), Vector2(a.size.x - 80, 32))
		draw_rect(bar, Color(0.12, 0.13, 0.18))
		for band in [[0.12, Color(0.4, 0.5, 1.0, 0.35)], [0.07, Color(0.5, 0.9, 1.0, 0.5)], [0.03, Color(1.0, 0.85, 0.3, 0.9)]]:
			var w: float = band[0] * 2.0 * bar.size.x
			draw_rect(Rect2(Vector2(bar.position.x + _target * bar.size.x - w * 0.5, bar.position.y), Vector2(w, bar.size.y)), band[1])
		var m := MidwayGame.meter(_t, _round)
		if _phase == "play":
			draw_rect(Rect2(Vector2(bar.position.x + m * bar.size.x - 3, bar.position.y - 10), Vector2(6, bar.size.y + 20)), Color.WHITE)
		draw_string(DeepFieldTheme.mono_font(), Vector2(bar.position.x, bar.end.y + 30), "target from your ticket: %.0f%% power" % (_target * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DeepFieldTheme.MUTED)
	else:
		var s := minf(a.size.x, a.size.y) - 20.0
		var board_r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
		draw_rect(board_r, Color(0.16, 0.13, 0.1))
		for pu in [0.2, 0.5, 0.8]:
			for pv in [0.2, 0.5, 0.8]:
				draw_circle(board_r.position + Vector2(pu, pv) * s, 0.08 * s, Color(0.4, 0.42, 0.5, 0.4))
				draw_circle(board_r.position + Vector2(pu, pv) * s, 7.0, Color(0.85, 0.8, 0.7))
		var m2 := MidwayGame.meter(_t, _round)
		var u := _lock_u if _lock_u >= 0.0 else m2
		draw_line(board_r.position + Vector2(u * s, 0), board_r.position + Vector2(u * s, s), Color(0.5, 0.9, 1.0, 0.8), 2.0)
		if _lock_u >= 0.0 and _phase == "play":
			draw_line(board_r.position + Vector2(0, m2 * s), board_r.position + Vector2(s, m2 * s), Color(1.0, 0.85, 0.3, 0.8), 2.0)
			draw_arc(board_r.position + Vector2(u, m2) * s, 0.06 * s, 0.0, TAU, 24, Color(1.0, 0.85, 0.3), 3.0)


func _crystal(p: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -22), p + Vector2(13, 0), p + Vector2(0, 18), p + Vector2(-13, 0)]), col)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -22), p + Vector2(5, 0), p + Vector2(0, 18)]), col.lightened(0.4))


func _draw_done(a: Rect2) -> void:
	var fd := DeepFieldTheme.display_font()
	var fm := DeepFieldTheme.mono_font()
	if _mech == "fortune":
		draw_string(fm, a.position + Vector2(0, 30), "The teller turns your ticket over…", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 14, DeepFieldTheme.MUTED)
		draw_multiline_string(fd, a.position + Vector2(0, 100), "“%s”" % MidwayGame.fortune(seed_v), HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 26, -1, Color("#ffd27a"))
		return
	draw_string(fd, a.position + Vector2(0, 40), "SCORE %d" % _score, HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 40, DeepFieldTheme.INK)
	draw_string(fd, a.position + Vector2(0, 80), "You win %s" % MidwayGame.prize(game_id, _score), HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 20, Color("#ffd27a"))
	var y := a.position.y + 116.0
	if paid:
		draw_string(fm, Vector2(a.position.x, y), ("#%d on this stall's board" % _rank) if _rank > 0 else "off this stall's top %d" % ArcadeScores.KEEP,
			HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 13, DeepFieldTheme.ICE)
	else:
		draw_string(fm, Vector2(a.position.x, y), "practice round: not on the board", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 13, DeepFieldTheme.MUTED)
	y += 22.0
	for l in ArcadeScores.lines(board, 4):
		draw_string(fm, Vector2(a.position.x, y), l, HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 12, DeepFieldTheme.MUTED)
		y += 16.0
	draw_string(fm, Vector2(a.position.x, y + 4), ArcadeScores.LABEL, HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 10, DeepFieldTheme.DIM)
