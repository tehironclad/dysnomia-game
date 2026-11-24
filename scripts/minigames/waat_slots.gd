extends MinigameBase
## WAAT Slots — three reels of Dysnomia symbols. The QING's Waat sets the house theme
## (which symbol is featured and pays double) and the order of every reel strip, so each
## QING's machine plays a little differently. Stops are drawn fresh every spin.
##
## Payouts are in SAAT, a Cantina-only fun score. You start with 100 SAAT, each spin costs
## 10, and you cash out whenever you like. It is not a token and never leaves the table.

const START_SAAT := 100
const SPIN_COST := 10
const MAX_SPINS := 25

enum Sym { LAU, QING, AFFECTION, CRYSTAL, TEDDY, ROCKET, MOTZKIN }
const SYM_NAMES := ["LAU", "QING", "AFFECTION", "Crystal", "Teddy", "Rocket", "Motzkin"]
const WEIGHTS := [6, 5, 4, 4, 3, 2, 1]
const TRIPLE_PAY := [60, 80, 150, 120, 200, 300, 953]
const PAIR_PAY := 16
const TWO_MOTZKIN_PAY := 60
const ONE_MOTZKIN_PAY := 8
const JACKPOT_TEXT := "MOTZKIN JACKPOT · 953467954114363 is prime"


class ReelView extends Control:
	var strip: Array = []
	var pos: float = 0.0
	var featured: int = -1
	var theme_color: Color = Color.WHITE
	var spinning: bool = false
	var glow: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(118, 240)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func symbol_at(offset: int) -> int:
		var n := strip.size()
		return strip[posmod(int(round(pos)) + offset, n)] if n > 0 else 0

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.05, 0.12)
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = theme_color.lerp(Color(1, 0.9, 0.5), glow)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var cell := size.y / 3.0
		var base := floorf(pos)
		var frac := pos - base
		var n := strip.size()
		if n == 0:
			return
		for k in range(-2, 3):
			var idx := posmod(int(base) + k, n)
			var cy := size.y * 0.5 + (float(k) - frac) * cell
			var dist := absf(cy - size.y * 0.5) / cell
			var a := clampf(1.15 - dist * 0.7, 0.15, 1.0)
			var scale := 1.0 if not spinning else 0.92
			SlotArt.draw_symbol(self, strip[idx], Vector2(size.x * 0.5, cy), cell * 0.74 * scale, a, strip[idx] == featured)
		# Payline shading: dim above/below
		draw_rect(Rect2(0, 0, size.x, cell * 0.92), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(0, size.y - cell * 0.92, size.x, cell * 0.92), Color(0, 0, 0, 0.35))


class SlotArt:
	static func draw_symbol(ci: CanvasItem, id: int, c: Vector2, s: float, a: float, featured: bool) -> void:
		var font := ThemeDB.fallback_font
		if featured:
			ci.draw_circle(c, s * 0.58, Color(1, 0.85, 0.35, 0.12 * a))
		match id:
			Sym.LAU, Sym.QING:
				var col := Color(0.95, 0.62, 0.32, a) if id == Sym.LAU else Color(0.36, 0.72, 0.95, a)
				var pts := PackedVector2Array()
				for i in 6:
					pts.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * s * 0.5)
				ci.draw_colored_polygon(pts, Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, a))
				pts.append(pts[0])
				ci.draw_polyline(pts, col, 3.0, true)
				var label := "LAU" if id == Sym.LAU else "QING"
				var fs := int(s * (0.3 if id == Sym.LAU else 0.25))
				var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				ci.draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			Sym.AFFECTION:
				var col := Color(0.95, 0.42, 0.72, a)
				var r := s * 0.2
				ci.draw_circle(c + Vector2(-r * 0.95, -r * 0.4), r * 1.05, col)
				ci.draw_circle(c + Vector2(r * 0.95, -r * 0.4), r * 1.05, col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 2.0, -r * 0.1), c + Vector2(r * 2.0, -r * 0.1), c + Vector2(0, r * 2.2)]), col)
				ci.draw_circle(c + Vector2(-r * 1.1, -r * 0.7), r * 0.28, Color(1, 1, 1, 0.45 * a))
			Sym.CRYSTAL:
				var col := Color(0.4, 0.88, 1.0, a)
				var top := c + Vector2(0, -s * 0.5)
				var bot := c + Vector2(0, s * 0.5)
				var l := c + Vector2(-s * 0.3, -s * 0.1)
				var rr := c + Vector2(s * 0.3, -s * 0.1)
				ci.draw_colored_polygon(PackedVector2Array([top, rr, bot, l]), Color(col.r * 0.5, col.g * 0.5, col.b * 0.6, a))
				ci.draw_colored_polygon(PackedVector2Array([top, rr, c + Vector2(0, -s * 0.1)]), Color(0.8, 0.97, 1.0, 0.8 * a))
				ci.draw_polyline(PackedVector2Array([top, rr, bot, l, top]), col, 2.5, true)
				ci.draw_line(l, rr, col, 1.5, true)
				ci.draw_line(top, bot, Color(col, 0.5 * a), 1.0, true)
			Sym.TEDDY:
				var fur := Color(0.78, 0.55, 0.33, a)
				var r := s * 0.3
				ci.draw_circle(c + Vector2(-r * 0.85, -r * 0.8), r * 0.42, fur)
				ci.draw_circle(c + Vector2(r * 0.85, -r * 0.8), r * 0.42, fur)
				ci.draw_circle(c + Vector2(-r * 0.85, -r * 0.8), r * 0.2, Color(0.95, 0.75, 0.6, a))
				ci.draw_circle(c + Vector2(r * 0.85, -r * 0.8), r * 0.2, Color(0.95, 0.75, 0.6, a))
				ci.draw_circle(c, r, fur)
				ci.draw_circle(c + Vector2(0, r * 0.35), r * 0.45, Color(0.95, 0.82, 0.68, a))
				ci.draw_circle(c + Vector2(-r * 0.38, -r * 0.15), r * 0.11, Color(0.1, 0.07, 0.1, a))
				ci.draw_circle(c + Vector2(r * 0.38, -r * 0.15), r * 0.11, Color(0.1, 0.07, 0.1, a))
				ci.draw_circle(c + Vector2(0, r * 0.22), r * 0.13, Color(0.2, 0.1, 0.1, a))
				# Astronaut helmet ring
				ci.draw_arc(c, r * 1.32, 0, TAU, 32, Color(0.75, 0.85, 1.0, 0.6 * a), 2.0, true)
			Sym.ROCKET:
				var body := Color(0.92, 0.92, 0.96, a)
				var h := s * 0.5
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.45, h * 0.6), c + Vector2(-h * 0.85, h * 0.95), c + Vector2(-h * 0.45, h * 0.1)]), Color(1, 0.4, 0.3, a))
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.45, h * 0.6), c + Vector2(h * 0.85, h * 0.95), c + Vector2(h * 0.45, h * 0.1)]), Color(1, 0.4, 0.3, a))
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h * 0.45, -h * 0.35), c + Vector2(h * 0.45, h * 0.7), c + Vector2(-h * 0.45, h * 0.7), c + Vector2(-h * 0.45, -h * 0.35)]), body)
				ci.draw_circle(c + Vector2(0, -h * 0.15), h * 0.2, Color(0.35, 0.7, 1.0, a))
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.3, h * 0.72), c + Vector2(h * 0.3, h * 0.72), c + Vector2(0, h * 1.15)]), Color(1, 0.75, 0.2, a))
			Sym.MOTZKIN:
				var gold := Color(1.0, 0.84, 0.32, a)
				var pts := PackedVector2Array()
				for i in 16:
					var rad := s * (0.52 if i % 2 == 0 else 0.3)
					pts.append(c + Vector2.from_angle(TAU * i / 16.0 - PI / 2.0) * rad)
				ci.draw_colored_polygon(pts, Color(gold.r * 0.55, gold.g * 0.4, 0.1, a))
				pts.append(pts[0])
				ci.draw_polyline(pts, gold, 2.5, true)
				var fs := int(s * 0.42)
				var w := font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				ci.draw_string(font, c + Vector2(-w * 0.5, fs * 0.36), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.85, a))


# ─── Pure logic (tested) ────────────────────────────────────────────────

static func build_strip(waat_hex: String, reel: int, featured: int) -> Array:
	## The reel strip for this QING's machine: weighted symbols (featured +2), shuffled by Waat.
	var out: Array = []
	for sym in WEIGHTS.size():
		var w: int = WEIGHTS[sym] + (2 if sym == featured and sym != Sym.MOTZKIN else 0)
		for _i in w:
			out.append(sym)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|reel%d" % [waat_hex.to_lower(), reel]).sha256_buffer().decode_s64(0)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


static func payout(line: Array, featured: int) -> Dictionary:
	## {amount, label, jackpot, kind}. line = the three payline symbols.
	var a: int = line[0]
	var b: int = line[1]
	var c: int = line[2]
	if a == b and b == c:
		var amt: int = TRIPLE_PAY[a]
		var label := "TRIPLE %s" % SYM_NAMES[a].to_upper()
		if a == Sym.MOTZKIN:
			return {"amount": amt, "label": JACKPOT_TEXT, "jackpot": true, "kind": "jackpot"}
		if a == featured:
			amt *= 2
			label += " — HOUSE DOUBLE"
		return {"amount": amt, "label": label, "jackpot": false, "kind": "triple"}
	var m := line.count(Sym.MOTZKIN)
	if m == 2:
		return {"amount": TWO_MOTZKIN_PAY, "label": "Two Motzkins!", "jackpot": false, "kind": "motzkin"}
	if a == b:
		var amt := PAIR_PAY * 2 if a == featured else PAIR_PAY
		return {"amount": amt, "label": "Pair of %s" % SYM_NAMES[a], "jackpot": false, "kind": "pair"}
	if m == 1:
		return {"amount": ONE_MOTZKIN_PAY, "label": "A Motzkin glints", "jackpot": false, "kind": "motzkin"}
	return {"amount": 0, "label": "", "jackpot": false, "kind": "none"}


static func expected_return(strips: Array, featured: int) -> float:
	## Exact average payout per spin over every stop combination (for tests / tuning).
	var total := 0.0
	var n := 0
	for x in strips[0]:
		for y in strips[1]:
			for z in strips[2]:
				total += payout([x, y, z], featured)["amount"]
				n += 1
	return total / float(n)


# ─── Game ───────────────────────────────────────────────────────────────

var _reels: Array = []
var _spin_btn: Button
var _cash_btn: Button
var _nudge_btn: Button
var _result_label: Label
var _tease_label: Label
var _theme: Dictionary
var _waat: String = ""
var _rng := RandomNumberGenerator.new()
var _spins: int = 0
var _stops: Array = [0, 0, 0]
var _spin_t: float = 0.0
var _landed: Array = [true, true, true]
var _spinning: bool = false
var _nudge_used: bool = false
var _jackpot: bool = false
var _best_win: int = 0
var _last_amt: int = 0
var _nudging: bool = false


func _ready() -> void:
	_score_unit = "SAAT"
	_waat = GameManager.territory_waat_hex
	if DysnomiaLore.hex_bytes(_waat).is_empty():
		_waat = "%016x" % absi(GameManager.terrain_seed * 40503 + 953)
	_theme = DysnomiaLore.house_theme(_waat)
	_rng.randomize()
	_init_ui("WAAT Slots", "%s · house theme: %s" % [DysnomiaLore.qing_label(), _theme["name"]])
	_build_game_ui()
	start_game()
	_set_score(START_SAAT)


func _build_game_ui() -> void:
	var feat: int = _theme["featured"]
	var banner := _center_label("%s pays double tonight  ·  Waat %s" % [SYM_NAMES[feat], DysnomiaLore.short_hex(_waat, 4)], 13, _theme["color"])
	_content_vbox.add_child(banner)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_content_vbox.add_child(row)
	for i in 3:
		var r := ReelView.new()
		r.strip = build_strip(_waat, i, feat)
		r.featured = feat
		r.theme_color = Color(_theme["color"], 0.7)
		r.pos = float(_rng.randi() % r.strip.size())
		row.add_child(r)
		_reels.append(r)

	_result_label = _center_label("Pull the lever — %d SAAT a spin" % SPIN_COST, 18, Color(0.8, 0.85, 1.0))
	_content_vbox.add_child(_result_label)
	_tease_label = _center_label(" ", 12, PINK)
	_content_vbox.add_child(_tease_label)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 10)
	_content_vbox.add_child(btns)
	_spin_btn = _button("SPIN  -%d" % SPIN_COST, PULSE, Vector2(150, 46))
	_spin_btn.pressed.connect(_on_spin)
	btns.add_child(_spin_btn)
	_nudge_btn = _button("NUDGE", PINK, Vector2(100, 46))
	_nudge_btn.pressed.connect(_on_nudge)
	_nudge_btn.disabled = true
	btns.add_child(_nudge_btn)
	_cash_btn = _button("CASH OUT", Color(0.35, 0.85, 0.55), Vector2(130, 46))
	_cash_btn.pressed.connect(_on_cash_out)
	btns.add_child(_cash_btn)

	var pay := _center_label(
		"3× Motzkin 953 (jackpot) · Rocket 300 · Teddy 200 · AFFECTION 150 · Crystal 120 · QING 80 · LAU 60\nFirst two match %d · two Motzkins %d · one Motzkin %d · %s triples and pairs pay double" % [PAIR_PAY, TWO_MOTZKIN_PAY, ONE_MOTZKIN_PAY, SYM_NAMES[feat]],
		10, Color(0.55, 0.55, 0.65))
	_content_vbox.add_child(pay)
	var note := _center_label("SAAT is a Cantina fun score: no tokens in, no tokens out.", 10, Color(0.45, 0.45, 0.55))
	_content_vbox.add_child(note)


func _process(delta: float) -> void:
	_base_process(delta)
	if not _spinning:
		return
	_spin_t += delta
	for i in 3:
		var r: ReelView = _reels[i]
		if _landed[i]:
			continue
		var stop_at := 0.7 + i * 0.45
		if _spin_t < stop_at:
			r.pos += delta * (18.0 + i * 3.0)
			r.queue_redraw()
		elif r.spinning:
			r.spinning = false
			var n := r.strip.size()
			var target := floorf(r.pos) + 2.0
			while posmod(int(target), n) != _stops[i]:
				target += 1.0
			var tw := r.create_tween()
			tw.tween_property(r, "pos", target, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_callback(_on_reel_landed.bind(i))
		else:
			r.queue_redraw()


func _on_spin() -> void:
	if _spinning or _finished:
		return
	if _score < SPIN_COST:
		_on_cash_out()
		return
	_update_score(-SPIN_COST)
	_spins += 1
	_spinning = true
	_spin_t = 0.0
	_nudge_btn.disabled = true
	_tease_label.text = " "
	for i in 3:
		var r: ReelView = _reels[i]
		_stops[i] = _rng.randi() % r.strip.size()
		r.spinning = true
		r.glow = 0.0
		_landed[i] = false
	_spin_btn.disabled = true
	_cash_btn.disabled = true
	_result_label.text = "Spinning…"
	_result_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	_sfx("roll")


func _on_reel_landed(i: int) -> void:
	_landed[i] = true
	var r: ReelView = _reels[i]
	r.pos = roundf(r.pos)
	r.queue_redraw()
	_sfx("land", 1.0 + i * 0.12)
	_punch(r, 0.04)
	# Tension: first two match → the last reel slows to a crawl in the player's head
	if i == 1 and _line()[0] == _line()[1]:
		_tease_label.text = "Two %s… come on…" % SYM_NAMES[_line()[0]]
		_sfx("alarm", 1.3)
	if not _landed.has(false):
		_spinning = false
		_evaluate()


func _line() -> Array:
	return [_reels[0].symbol_at(0), _reels[1].symbol_at(0), _reels[2].symbol_at(0)]


func _evaluate() -> void:
	var line := _line()
	var p := payout(line, _theme["featured"])
	var amt: int = p["amount"]
	if _nudging:
		amt = maxi(0, amt - _last_amt)   # the pre-nudge line was already paid
		_nudging = false
	_last_amt = p["amount"]
	if amt > 0:
		_update_score(amt)
		_best_win = maxi(_best_win, amt)
		_result_label.text = "%s  +%d SAAT" % [p["label"], amt]
		var col := GOLD if p["kind"] in ["jackpot", "triple"] else DysnomiaLore.OK
		_result_label.add_theme_color_override("font_color", col)
		_float_text("+%d" % amt, col, _result_label, 30 if amt >= 90 else 24)
		_punch(_result_label, 0.4 if amt >= 90 else 0.15)
		for r in _reels:
			r.glow = 1.0 if p["kind"] in ["jackpot", "triple"] else 0.4
			r.queue_redraw()
		if p["jackpot"]:
			_jackpot = true
			_shake(9.0, 0.6)
			_sfx("jackpot")
		else:
			_sfx("big" if amt >= 90 else "coin")
	else:
		_result_label.text = "No line."
		_result_label.add_theme_color_override("font_color", Color(0.65, 0.5, 0.55))
		_tease_label.text = _near_miss_text(line)
	# Nudge: once a game, when reel 3 is one step from completing a match
	if not _nudge_used and line[0] == line[1] and line[2] != line[0]:
		var r3: ReelView = _reels[2]
		if r3.symbol_at(-1) == line[0] or r3.symbol_at(1) == line[0]:
			_nudge_btn.disabled = false
			_tease_label.text = "%s right next to the line. One NUDGE per game…" % SYM_NAMES[line[0]]
			_sfx("nudge")
	_spin_btn.disabled = false
	_cash_btn.disabled = false
	if _spins >= MAX_SPINS or (_score < SPIN_COST and _nudge_btn.disabled):
		_on_cash_out()


func _near_miss_text(line: Array) -> String:
	for i in 3:
		var r: ReelView = _reels[i]
		if r.symbol_at(-1) == Sym.MOTZKIN or r.symbol_at(1) == Sym.MOTZKIN:
			return "A Motzkin just off the line on reel %d…" % (i + 1)
	if line[0] == line[2]:
		return "So close: %s on both ends." % SYM_NAMES[line[0]]
	return "%d spins left" % (MAX_SPINS - _spins)


func _on_nudge() -> void:
	if _nudge_used or _spinning:
		return
	_nudge_used = true
	_nudge_btn.disabled = true
	var r3: ReelView = _reels[2]
	var want: int = _line()[0]
	var step := -1.0 if r3.symbol_at(-1) == want else 1.0
	_sfx("nudge")
	var tw := r3.create_tween()
	tw.tween_property(r3, "pos", r3.pos + step, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		r3.pos = roundf(r3.pos)
		r3.queue_redraw()
		_spin_btn.disabled = true
		_cash_btn.disabled = true
		_nudging = true
		_evaluate())


func _on_cash_out() -> void:
	if _finished or _spinning:
		return
	_spin_btn.disabled = true
	_cash_btn.disabled = true
	_nudge_btn.disabled = true
	var won := _score > START_SAAT
	var lines: Array = ["%d spins · best hit %d SAAT · %s" % [_spins, _best_win, _theme["name"]]]
	if _jackpot:
		lines.append("You hit the Motzkin. 953467954114363 thanks you.")
	finish(won, {"headline": "UP ON THE HOUSE" if won else "CASHED OUT", "lines": lines, "jackpot": _jackpot})
