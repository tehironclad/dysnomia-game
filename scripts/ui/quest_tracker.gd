class_name QuestTracker
extends Control
## Small always-on HUD pill ("Y  Things to do · 2/4 quests · streak 3") plus the
## celebration banner when a quest completes, a title unlocks or the streak grows.
## Listens to QuestBoard.bus; no other wiring needed.

const PULSE := DysnomiaLore.PULSE
const PINK := DysnomiaLore.AFFECTION_PINK

var _pill: PanelContainer
var _pill_label: Label
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _queue: Array = []
var _banner_t: float = 0.0
var _refresh_t: float = 0.0
var key_hint: String = "Y"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_pill = PanelContainer.new()
	var sb := DysnomiaLore.styled_panel(Color(PULSE, 0.6), 14, 0.8)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.shadow_size = 0
	_pill.add_theme_stylebox_override("panel", sb)
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_pill.position = Vector2(14, 60)
	add_child(_pill)
	_pill_label = Label.new()
	_pill_label.add_theme_font_size_override("font_size", 13)
	_pill_label.add_theme_color_override("font_color", Color(0.9, 0.88, 1.0))
	_pill.add_child(_pill_label)

	_banner = PanelContainer.new()
	var bsb := DysnomiaLore.styled_panel(PINK, 12, 0.92)
	bsb.content_margin_left = 26
	bsb.content_margin_right = 26
	_banner.add_theme_stylebox_override("panel", bsb)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = 96
	_banner.visible = false
	add_child(_banner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_banner.add_child(v)
	_banner_title = Label.new()
	_banner_title.add_theme_font_size_override("font_size", 20)
	_banner_title.add_theme_color_override("font_color", DysnomiaLore.GOLD)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.add_theme_font_size_override("font_size", 14)
	_banner_sub.add_theme_color_override("font_color", Color(0.92, 0.9, 1.0))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_sub)

	QuestBoard.bus.changed.connect(refresh)
	QuestBoard.bus.quest_completed.connect(func(q: Dictionary) -> void:
		celebrate("QUEST COMPLETE", q.get("text", "")))
	QuestBoard.bus.title_unlocked.connect(func(t: Dictionary) -> void:
		celebrate("TITLE UNLOCKED: %s" % t["name"], t.get("desc", "")))
	QuestBoard.bus.streak_changed.connect(func(n: int) -> void:
		if n >= 2:
			celebrate("%d-DAY STREAK" % n, "Come back tomorrow (UTC) to keep it going."))
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	var b := QuestBoard.board()
	var done := 0
	for q in b["quests"]:
		if q["done"]:
			done += 1
	var s := QuestBoard.streak()
	var t := "%s   Things to do · %d/%d quests" % [key_hint, done, b["quests"].size()]
	if s["current"] > 0:
		t += " · streak %d%s" % [s["current"], "" if s["done_today"] else " (at risk)"]
	_pill_label.text = t
	_pill.reset_size()


func celebrate(title: String, sub: String) -> void:
	_queue.append([title, sub])
	if not _banner.visible:
		_next_banner()


func _next_banner() -> void:
	if _queue.is_empty():
		_banner.visible = false
		return
	var e: Array = _queue.pop_front()
	_banner_title.text = e[0]
	_banner_sub.text = e[1]
	_banner.visible = true
	_banner.reset_size()
	_banner.position.x = -_banner.size.x * 0.5
	_banner.modulate.a = 0.0
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(0.8, 0.8)
	var tw := _banner.create_tween().set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.2)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_t = 3.2
	MinigameSfx.play(self, "win", -12.0)


func _process(delta: float) -> void:
	if _banner.visible and _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			var tw := _banner.create_tween()
			tw.tween_property(_banner, "modulate:a", 0.0, 0.3)
			tw.tween_callback(_next_banner)
	# Countdown in the pill ticks over at UTC midnight
	_refresh_t += delta
	if _refresh_t > 30.0:
		_refresh_t = 0.0
		refresh()
