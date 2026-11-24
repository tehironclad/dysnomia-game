class_name ActTracker
extends PanelContainer
## The compact act tracker on the HUD: the top acts here (as PlayLoop ranks
## them, the same ones the beacons mark) and the personal goals, each goal
## from chain reads and saying so on hover. Unread values show "—".

const SHOW_ACTS := 3

var _acts: VBoxContainer
var _goals: VBoxContainer
var _foot: Label


func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var head := Label.new()
	head.theme_type_variation = "MutedLabel"
	head.add_theme_font_size_override("font_size", 11)
	head.text = "TO DO HERE"
	v.add_child(head)
	_acts = VBoxContainer.new()
	_acts.add_theme_constant_override("separation", 3)
	v.add_child(_acts)
	var sep := HSeparator.new()
	v.add_child(sep)
	_goals = VBoxContainer.new()
	_goals.add_theme_constant_override("separation", 1)
	v.add_child(_goals)
	_foot = Label.new()
	_foot.theme_type_variation = "MutedLabel"
	_foot.add_theme_font_size_override("font_size", 10)
	v.add_child(_foot)


static func _clear(box: Container) -> void:
	for c in box.get_children():
		c.queue_free()


func show_loop(acts: Array, goals: Array, block: int) -> void:
	_clear(_acts)
	_clear(_goals)
	var n := 0
	for a in acts:
		if n >= SHOW_ACTS or a["kind"] == "well":
			continue
		n += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var dot := Label.new()
		dot.text = "◆"
		dot.add_theme_color_override("font_color", ActBeacon.color_of(a["kind"]) if a["doable"] else DeepFieldTheme.DIM)
		dot.add_theme_font_size_override("font_size", 11)
		row.add_child(dot)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := Label.new()
		t.text = String(a["title"])
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_color_override("font_color", DeepFieldTheme.INK if a["doable"] else DeepFieldTheme.MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(t)
		var d := Label.new()
		d.theme_type_variation = "MutedLabel"
		d.add_theme_font_size_override("font_size", 11)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.text = String(a.get("detail", "")) if a["doable"] or String(a.get("blocker", "")) == "" else String(a["blocker"])
		d.tooltip_text = String(a.get("call", ""))
		col.add_child(d)
		row.add_child(col)
		_acts.add_child(row)
	if n == 0:
		var l := Label.new()
		l.theme_type_variation = "MutedLabel"
		l.text = "reading this territory…"
		_acts.add_child(l)
	for g in goals:
		var l := Label.new()
		l.theme_type_variation = "MonoLabel"
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = String(g["text"])
		l.tooltip_text = String(g["source"])
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_goals.add_child(l)
	_foot.text = ("block %d" % block if block > 0 else "block —") + " · markers show where · ask the steward at the Core"
