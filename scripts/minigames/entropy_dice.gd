extends MinigameBase
## Entropy Dice — push-your-luck dice rolled from this QING's real on-chain entropy.
##
## Every roll is sha256(QING entropy | unix second | roll #). Bytes are read in order and
## any byte >= 252 is skipped, so each die is an unbiased byte % 6 + 1. The feed under the
## dice shows exactly which bytes made the roll: anyone holding the entropy and the second
## can recompute it. Fair, but flavoured by the territory.
##
## Five turns. Each roll adds to the pot at a rising multiplier; BANK to keep it, or push.
## A roll with no combo and no lucky face is an Entropy Collapse and the pot is lost.
## Beat the QING's house line (from its entropy) to win.

const TURNS := 5
const MULTS: Array[float] = [1.0, 1.5, 2.0, 3.0, 4.0, 5.0]


class DieFace extends Control:
	var value: int = 1
	var spin: float = 0.0
	var lucky: bool = false
	var settled: bool = true
	var tint: Color = Color(0.95, 0.94, 0.9)

	func _init() -> void:
		custom_minimum_size = Vector2(112, 112)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.78
		draw_set_transform(c, spin, Vector2.ONE)
		var r := Rect2(-s * 0.5, -s * 0.5, s, s)
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint if settled else tint.darkened(0.12)
		sb.set_corner_radius_all(int(s * 0.18))
		sb.set_border_width_all(4 if lucky and settled else 2)
		sb.border_color = DysnomiaLore.AFFECTION_PINK if lucky and settled else Color(0.25, 0.2, 0.4)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 6
		draw_style_box(sb, r)
		var pip := DysnomiaLore.AFFECTION_PINK if lucky and settled else Color(0.18, 0.12, 0.32)
		var q := s * 0.26
		var spots := {
			1: [Vector2.ZERO],
			2: [Vector2(-q, -q), Vector2(q, q)],
			3: [Vector2(-q, -q), Vector2.ZERO, Vector2(q, q)],
			4: [Vector2(-q, -q), Vector2(q, -q), Vector2(-q, q), Vector2(q, q)],
			5: [Vector2(-q, -q), Vector2(q, -q), Vector2.ZERO, Vector2(-q, q), Vector2(q, q)],
			6: [Vector2(-q, -q), Vector2(q, -q), Vector2(-q, 0), Vector2(q, 0), Vector2(-q, q), Vector2(q, q)],
		}
		for p in spots.get(clampi(value, 1, 6), []):
			draw_circle(p, s * 0.085, pip)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var _dice: Array = []
var _roll_btn: Button
var _bank_btn: Button
var _combo_label: Label
var _pot_label: Label
var _turn_label: Label
var _mult_row: HBoxContainer
var _feed: RichTextLabel
var _help: Label

var _entropy_hex: String = ""
var _entropy_source: String = ""
var _lucky: int = 3
var _house_line: int = 400
var _turn: int = 1
var _roll_in_turn: int = 0
var _roll_index: int = 0
var _pot: int = 0
var _rolling: bool = false
var _roll_t: float = 0.0
var _final: Array = [1, 1, 1]
var _last_feed: Dictionary = {}
var _best_pot: int = 0
var _collapses: int = 0


# ─── Pure logic (tested in tools/test_minigames.gd) ────────────────────

static func roll_bytes(entropy_hex: String, unix_second: int, roll_index: int) -> PackedByteArray:
	return ("%s|%d|%d" % [entropy_hex.to_lower(), unix_second, roll_index]).sha256_buffer()


static func dice_from_bytes(b: PackedByteArray, n: int = 3) -> Dictionary:
	## Unbiased dice: skip bytes >= 252 (252 = 42 × 6). Returns {dice, used: [byte idx]}.
	var dice: Array = []
	var used: Array = []
	for i in b.size():
		if dice.size() >= n:
			break
		if b[i] < 252:
			dice.append(int(b[i]) % 6 + 1)
			used.append(i)
	while dice.size() < n:  # 32 bytes all >= 252 never happens in practice
		dice.append(1)
	return {"dice": dice, "used": used}


static func lucky_face(entropy_hex: String) -> int:
	var b := DysnomiaLore.hex_bytes(entropy_hex)
	return (int(b[b.size() - 1]) % 6 + 1) if b.size() > 0 else 3


static func house_line(entropy_hex: String) -> int:
	var b := DysnomiaLore.hex_bytes(entropy_hex)
	return 300 + (int(b[b.size() - 2]) % 5) * 50 if b.size() > 1 else 400


static func score_roll(dice: Array, lucky: int) -> Dictionary:
	## {points, kind, label}. kind: triple / straight / pair / lucky / bust
	var d := dice.duplicate()
	d.sort()
	var lucky_n := dice.count(lucky)
	var bonus := lucky_n * 25
	if d[0] == d[2]:
		var name := "MOTZKIN TRIPLE" if d[0] == 6 else ("VOID TRIPLE" if d[0] == 1 else "TRIPLE %d" % d[0])
		return {"points": 100 * d[0] + bonus, "kind": "triple", "label": name}
	if d[0] + 1 == d[1] and d[1] + 1 == d[2]:
		return {"points": 150 + bonus, "kind": "straight", "label": "QING STRAIGHT %d-%d-%d" % [d[0], d[1], d[2]]}
	if d[0] == d[1] or d[1] == d[2]:
		return {"points": 50 + bonus, "kind": "pair", "label": "PAIR OF %dS" % d[1]}
	if lucky_n > 0:
		return {"points": bonus, "kind": "lucky", "label": "LUCKY %d" % lucky}
	return {"points": 0, "kind": "bust", "label": "ENTROPY COLLAPSE"}


static func near_miss(dice: Array) -> String:
	var d := dice.duplicate()
	d.sort()
	if d[2] - d[0] == 3 and d[0] != d[1] and d[1] != d[2]:
		return "One pip off a QING straight."
	if d[2] - d[0] == 2 and d[0] != d[1]:
		return "So close to a straight."
	return "Entropy giveth, entropy taketh."


static func multiplier(roll_in_turn: int) -> float:
	return MULTS[clampi(roll_in_turn - 1, 0, MULTS.size() - 1)]


# ─── UI ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_entropy_hex = GameManager.territory_entropy_hex
	_entropy_source = "QING entropy"
	if DysnomiaLore.hex_bytes(_entropy_hex).is_empty():
		_entropy_hex = "%016x" % absi(GameManager.terrain_seed * 2654435761 + 369)
		_entropy_source = "offline seed"
	_lucky = lucky_face(_entropy_hex)
	_house_line = house_line(_entropy_hex)
	_init_ui("Entropy Dice", "%s · dice rolled from the QING's own entropy" % DysnomiaLore.qing_label(), Vector2(500, 560))
	_build_game_ui()
	start_game()
	_update_turn_ui()


func _build_game_ui() -> void:
	_turn_label = _center_label("", 14, DysnomiaLore.DIM)
	_content_vbox.add_child(_turn_label)

	_mult_row = HBoxContainer.new()
	_mult_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mult_row.add_theme_constant_override("separation", 6)
	_content_vbox.add_child(_mult_row)
	for m in MULTS:
		var chip := _label("×%s" % _fmt_mult(m), 13, Color(0.45, 0.45, 0.55))
		_mult_row.add_child(chip)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_content_vbox.add_child(row)
	for i in 3:
		var d := DieFace.new()
		d.value = [_lucky, 3, 6][i]
		row.add_child(d)
		_dice.append(d)

	_combo_label = _center_label("Roll to start the pot", 22, Color(0.8, 0.85, 1.0))
	_content_vbox.add_child(_combo_label)
	_pot_label = _center_label("POT 0", 18, GOLD)
	_content_vbox.add_child(_pot_label)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	_content_vbox.add_child(btns)
	_roll_btn = _button("ROLL", PULSE, Vector2(170, 48))
	_roll_btn.pressed.connect(_on_roll)
	btns.add_child(_roll_btn)
	_bank_btn = _button("BANK", Color(0.35, 0.85, 0.55), Vector2(170, 48))
	_bank_btn.pressed.connect(_on_bank)
	btns.add_child(_bank_btn)

	var feed_panel := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	fsb.set_corner_radius_all(6)
	fsb.content_margin_left = 10
	fsb.content_margin_right = 10
	fsb.content_margin_top = 6
	fsb.content_margin_bottom = 6
	feed_panel.add_theme_stylebox_override("panel", fsb)
	_content_vbox.add_child(feed_panel)
	_feed = RichTextLabel.new()
	_feed.bbcode_enabled = true
	_feed.fit_content = true
	_feed.scroll_active = false
	_feed.add_theme_font_size_override("normal_font_size", 11)
	_feed.add_theme_font_size_override("bold_font_size", 12)
	feed_panel.add_child(_feed)
	_render_feed()

	_help = _center_label(
		"Triple: 100 × face (6-6-6 is the MOTZKIN)  ·  QING straight 150  ·  Pair 50\nLucky %d: +25 per die  ·  No combo and no %d = collapse, pot lost" % [_lucky, _lucky],
		11, Color(0.55, 0.55, 0.65))
	_content_vbox.add_child(_help)


func _fmt_mult(m: float) -> String:
	return str(int(m)) if is_equal_approx(m, roundf(m)) else "%.1f" % m


func _update_turn_ui() -> void:
	_turn_label.text = "Turn %d / %d   ·   House line %d   ·   Lucky face %d" % [mini(_turn, TURNS), TURNS, _house_line, _lucky]
	for i in _mult_row.get_child_count():
		var chip: Label = _mult_row.get_child(i)
		var active := i == _roll_in_turn - 1
		var next := i == _roll_in_turn
		chip.add_theme_color_override("font_color", GOLD if active else (PINK if next else Color(0.4, 0.4, 0.5)))
		chip.add_theme_font_size_override("font_size", 17 if active else 13)
	_pot_label.text = "POT %d" % _pot if _pot > 0 else "POT —"
	_roll_btn.text = "ROLL" if _roll_in_turn == 0 else "PUSH ×%s" % _fmt_mult(multiplier(_roll_in_turn + 1))
	_bank_btn.disabled = _pot <= 0 or _rolling
	_roll_btn.disabled = _rolling or _finished


func _process(delta: float) -> void:
	_base_process(delta)
	if not _rolling:
		return
	_roll_t += delta
	var all_settled := true
	for i in 3:
		var d: DieFace = _dice[i]
		var stop := 0.55 + i * 0.22
		if _roll_t < stop:
			all_settled = false
			if int(_roll_t * 30.0) != int((_roll_t - delta) * 30.0):
				d.value = randi_range(1, 6)
			d.spin += delta * (14.0 - i * 2.0)
			d.settled = false
			d.queue_redraw()
		elif not d.settled:
			d.value = _final[i]
			d.spin = 0.0
			d.settled = true
			d.lucky = _final[i] == _lucky
			d.queue_redraw()
			_punch(d, 0.18)
			_sfx("land", 0.9 + i * 0.1)
	if all_settled:
		_rolling = false
		_resolve()


func _on_roll() -> void:
	if _rolling or _finished:
		return
	_rolling = true
	_roll_t = 0.0
	_roll_index += 1
	_roll_in_turn += 1
	var t := int(Time.get_unix_time_from_system())
	var b := roll_bytes(_entropy_hex, t, _roll_index)
	var r := dice_from_bytes(b)
	_final = r["dice"]
	_last_feed = {"t": t, "bytes": b, "used": r["used"]}
	for d in _dice:
		d.lucky = false
	_combo_label.text = "Rolling…"
	_combo_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	_sfx("roll")
	_render_feed()
	_update_turn_ui()


func _resolve() -> void:
	var s := score_roll(_final, _lucky)
	if s["kind"] == "bust":
		var lost := _pot
		_pot = 0
		_collapses += 1
		_combo_label.text = "ENTROPY COLLAPSE"
		_combo_label.add_theme_color_override("font_color", DysnomiaLore.BAD)
		if lost > 0:
			_float_text("-%d" % lost, DysnomiaLore.BAD, _pot_label)
		_shake(7.0, 0.35)
		_sfx("bust")
		_end_turn()
		if not _finished:
			_pot_label.text = near_miss(_final) + ("  Pot of %d lost." % lost if lost > 0 else "")
		return
	var m := multiplier(_roll_in_turn)
	var gain := int(round(s["points"] * m))
	_pot += gain
	_best_pot = maxi(_best_pot, _pot)
	_combo_label.text = "%s  +%d%s" % [s["label"], gain, ("  (×%s)" % _fmt_mult(m)) if m > 1.0 else ""]
	var col: Color = {"triple": GOLD, "straight": Color(0.4, 0.95, 1.0), "pair": DysnomiaLore.OK, "lucky": PINK}[s["kind"]]
	_combo_label.add_theme_color_override("font_color", col)
	_punch(_combo_label, 0.2 if s["kind"] != "triple" else 0.5)
	_float_text("+%d" % gain, col, _pot_label)
	_sfx("jackpot" if s["kind"] == "triple" else ("win" if s["kind"] == "straight" else "coin"))
	if s["kind"] == "triple":
		_shake(5.0, 0.4)
	_update_turn_ui()
	# Tension: tell them what the bank would do right now
	var banked_total := _score + _pot
	if banked_total >= _house_line and _score < _house_line:
		_pot_label.text = "POT %d — bank now to clear the house line!" % _pot
	elif _roll_in_turn >= MULTS.size():
		_pot_label.text = "POT %d — max multiplier, bank it!" % _pot


func _on_bank() -> void:
	if _rolling or _pot <= 0 or _finished:
		return
	var banked := _pot
	_pot = 0
	_update_score(banked)
	_float_text("BANKED %d" % banked, DysnomiaLore.OK, _score_label, 22)
	_sfx("coin", 1.2)
	_combo_label.text = "Banked %d" % banked
	_combo_label.add_theme_color_override("font_color", DysnomiaLore.OK)
	_end_turn()


func _end_turn() -> void:
	_turn += 1
	_roll_in_turn = 0
	if _turn > TURNS:
		_finish_dice()
		return
	_update_turn_ui()


func _finish_dice() -> void:
	_roll_btn.disabled = true
	_bank_btn.disabled = true
	var won := _score >= _house_line
	var lines: Array = ["House line %d · biggest pot %d · %d collapse%s" % [_house_line, _best_pot, _collapses, "" if _collapses == 1 else "s"]]
	if not won and _house_line - _score <= 60:
		lines.append("Missed the line by %d. Agonising." % (_house_line - _score))
	finish(won, {"headline": "YOU BEAT THE HOUSE" if won else "THE HOUSE HOLDS", "lines": lines})


func _render_feed() -> void:
	var h := DysnomiaLore.short_hex(_entropy_hex, 6)
	var t := "[color=#9e6bff]%s[/color] [color=#e0e0ff]%s[/color]" % [_entropy_source, h]
	if _last_feed.is_empty():
		t += "\n[color=#8888a0]Each roll = sha256(entropy | unix second | roll #). Bytes ≥ 252 are skipped so every face is equally likely.[/color]"
	else:
		t += "  [color=#8888a0]|[/color] t=[color=#e0e0ff]%d[/color]  [color=#8888a0]|[/color] roll #%d\n" % [_last_feed["t"], _roll_index]
		var b: PackedByteArray = _last_feed["bytes"]
		var parts: Array = []
		for i in mini(8, b.size()):
			var used: bool = _last_feed["used"].has(i)
			parts.append(("[color=#f26bb8][b]%02x[/b][/color]" if used else "[color=#666677]%02x[/color]") % b[i])
		t += "sha256 → %s…   " % " ".join(parts)
		var faces: Array = []
		for k in _last_feed["used"].size():
			var bi: int = _last_feed["used"][k]
			faces.append("%d%%6+1=%d" % [b[bi], _final[k]])
		t += "[color=#c8c8d8]%s[/color]" % "  ".join(faces)
	_feed.text = t
