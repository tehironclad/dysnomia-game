extends MinigameBase
## Contract Match — memory pairs with Dysnomia contract cards (LAU, QING, AFFECTION, YUE,
## XIE, HECKE…). Each match reads out that contract's one-line flavour, so a few rounds
## teach you the whole stack. Three timed rounds that grow 6 → 8 → 10 pairs; consecutive
## matches build a combo, time left is banked as a bonus. Clear two rounds to win.

const ROUNDS := [
	{"pairs": 6, "cols": 4, "time": 45.0},
	{"pairs": 8, "cols": 4, "time": 60.0},
	{"pairs": 10, "cols": 5, "time": 75.0},
]
const WIN_ROUNDS := 2


class Card extends Button:
	var contract: String = ""
	var face_up: bool = false
	var matched: bool = false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(84, 66)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(7)
		var font := ThemeDB.fallback_font
		if not face_up:
			sb.bg_color = Color(0.13, 0.09, 0.24) if not is_hovered() else Color(0.18, 0.13, 0.32)
			sb.set_border_width_all(2)
			sb.border_color = Color(0.62, 0.42, 1.0, 0.55)
			draw_style_box(sb, r)
			var c := size * 0.5
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * minf(size.x, size.y) * 0.26)
			draw_polyline(pts, Color(0.62, 0.42, 1.0, 0.6), 2.0, true)
			draw_circle(c, 4.0, Color(0.95, 0.42, 0.72, 0.8))
			return
		var info: Dictionary = DysnomiaLore.CONTRACTS.get(contract, {})
		var col: Color = info.get("color", Color.WHITE)
		sb.bg_color = Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.97)
		sb.set_border_width_all(3 if matched else 2)
		sb.border_color = col if not matched else Color(1, 0.9, 0.5)
		draw_style_box(sb, r)
		var fs := 17 if contract.length() <= 4 else 12
		var w := font.get_string_size(contract, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5 + 2), contract, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.25))
		var role: String = info.get("role", "")
		var rfs := 9
		var rw := font.get_string_size(role, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x
		if rw > size.x - 8:
			role = role.split(" ")[0]
			rw = font.get_string_size(role, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x
		draw_string(font, Vector2((size.x - rw) * 0.5, size.y * 0.5 + 18), role, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, Color(0.85, 0.85, 0.92, 0.85))


var _grid: GridContainer
var _cards: Array = []
var _round_label: Label
var _timer_label: Label
var _combo_label: Label
var _flavour_label: Label
var _rng := RandomNumberGenerator.new()
var _round: int = 0
var _time_left: float = 0.0
var _running: bool = false
var _first: Card = null
var _checking: bool = false
var _combo: int = 0
var _matches: int = 0
var _moves: int = 0
var _rounds_cleared: int = 0
var _best_combo: int = 0


static func match_points(combo: int) -> int:
	return 50 * clampi(combo, 1, 5)


static func round_bonus(round_idx: int, time_left: float) -> int:
	return 200 * (round_idx + 1) + int(time_left) * 10


func _ready() -> void:
	_rng.randomize()
	_init_ui("Contract Match", "%s · match the contracts that run Dysnomia" % DysnomiaLore.qing_label(), Vector2(520, 640))
	_build_game_ui()
	start_game()
	_start_round(0)


func _build_game_ui() -> void:
	var top := HBoxContainer.new()
	_content_vbox.add_child(top)
	_round_label = _label("", 14, DysnomiaLore.DIM)
	_round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_round_label)
	_combo_label = _label("", 14, PINK)
	top.add_child(_combo_label)
	_timer_label = _label("", 20, GOLD)
	_timer_label.custom_minimum_size = Vector2(70, 0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_timer_label)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_vbox.add_child(_grid)

	_flavour_label = _center_label("Flip two cards. Matching pairs read out what that contract does.", 13, Color(0.8, 0.8, 0.92))
	_flavour_label.custom_minimum_size = Vector2(0, 40)
	_content_vbox.add_child(_flavour_label)


func _start_round(idx: int) -> void:
	_round = idx
	var cfg: Dictionary = ROUNDS[idx]
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_grid.columns = cfg["cols"]
	var pool: Array = DysnomiaLore.CONTRACTS.keys()
	var chosen: Array = []
	while chosen.size() < cfg["pairs"]:
		var c: String = pool.pop_at(_rng.randi() % pool.size())
		chosen.append(c)
	var deck: Array = chosen + chosen
	for i in range(deck.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	var rows := ceili(float(cfg["pairs"] * 2) / float(cfg["cols"]))
	var h := minf(118.0, (390.0 - 6.0 * (rows - 1)) / float(rows))
	for name in deck:
		var card := Card.new()
		card.contract = name
		card.custom_minimum_size.y = h
		card.pressed.connect(_on_card.bind(card))
		_grid.add_child(card)
		_cards.append(card)
	_matches = 0
	_first = null
	_checking = false
	_time_left = cfg["time"]
	_running = true
	_round_label.text = "Round %d / %d  ·  %d pairs" % [idx + 1, ROUNDS.size(), cfg["pairs"]]
	_combo_label.text = ""
	# Deal-in animation
	for i in _cards.size():
		var c: Card = _cards[i]
		c.modulate.a = 0.0
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.2).set_delay(i * 0.02)


func _process(delta: float) -> void:
	_base_process(delta)
	if not _running:
		return
	var before := ceili(_time_left)
	_time_left -= delta
	_timer_label.text = "%ds" % maxi(0, ceili(_time_left))
	_timer_label.add_theme_color_override("font_color", DysnomiaLore.BAD if _time_left < 10.0 else GOLD)
	if _time_left < 10.0 and ceili(_time_left) != before:
		_sfx("tick", 1.3)
		_punch(_timer_label, 0.15)
	if _time_left <= 0.0:
		_running = false
		_out_of_time()


func _on_card(card: Card) -> void:
	if not _running or _checking or card.face_up or card.matched:
		return
	_flip(card, true)
	if _first == null:
		_first = card
		return
	_moves += 1
	_checking = true
	var a := _first
	_first = null
	if a.contract == card.contract:
		get_tree().create_timer(0.3).timeout.connect(_on_match.bind(a, card))
	else:
		get_tree().create_timer(0.75).timeout.connect(_on_miss.bind(a, card))


func _flip(card: Card, up: bool) -> void:
	_sfx("flip", 1.0 if up else 0.85)
	card.pivot_offset = card.size * 0.5
	var tw := card.create_tween()
	tw.tween_property(card, "scale:x", 0.0, 0.08)
	tw.tween_callback(func():
		card.face_up = up
		card.queue_redraw())
	tw.tween_property(card, "scale:x", 1.0, 0.1)


func _on_match(a: Card, b: Card) -> void:
	if not is_inside_tree():
		return
	_checking = false
	a.matched = true
	b.matched = true
	a.queue_redraw()
	b.queue_redraw()
	_combo += 1
	_best_combo = maxi(_best_combo, _combo)
	var pts := match_points(_combo)
	_update_score(pts)
	_float_text("+%d" % pts, GOLD if _combo > 1 else DysnomiaLore.OK, b)
	_punch(a, 0.12)
	_punch(b, 0.12)
	_sfx("match", 1.0 + 0.08 * mini(_combo, 5))
	_combo_label.text = "Combo ×%d" % mini(_combo, 5) if _combo > 1 else ""
	var info: Dictionary = DysnomiaLore.CONTRACTS[a.contract]
	_flavour_label.add_theme_color_override("font_color", (info["color"] as Color).lightened(0.3))
	_flavour_label.text = "%s — %s" % [a.contract, info["flavour"]]
	_matches += 1
	if _matches >= int(ROUNDS[_round]["pairs"]):
		_round_clear()


func _on_miss(a: Card, b: Card) -> void:
	if not is_inside_tree():
		return
	_combo = 0
	_combo_label.text = ""
	_flip(a, false)
	_flip(b, false)
	_checking = false


func _round_clear() -> void:
	_running = false
	_rounds_cleared += 1
	var bonus := round_bonus(_round, _time_left)
	_update_score(bonus)
	_float_text("ROUND CLEAR +%d" % bonus, GOLD, _timer_label, 24)
	_sfx("big")
	if _round + 1 >= ROUNDS.size():
		_finish_cards("FULL STACK DEPLOYED")
		return
	_round_label.text = "Round %d cleared! Next: %d pairs" % [_round + 1, ROUNDS[_round + 1]["pairs"]]
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_inside_tree():
			_start_round(_round + 1))


func _out_of_time() -> void:
	_sfx("bust")
	_shake(6.0, 0.3)
	for c in _cards:
		if not c.matched:
			c.face_up = true
			c.modulate = Color(1, 1, 1, 0.5)
			c.queue_redraw()
	_finish_cards("OUT OF BLOCKS" if _rounds_cleared < WIN_ROUNDS else "STACK HOLDS")


func _finish_cards(headline: String) -> void:
	var won := _rounds_cleared >= WIN_ROUNDS
	var lines: Array = ["%d round%s cleared · %d moves · best combo ×%d" % [
		_rounds_cleared, "" if _rounds_cleared == 1 else "s", _moves, mini(_best_combo, 5)]]
	finish(won, {"headline": headline, "lines": lines, "rounds": _rounds_cleared})
