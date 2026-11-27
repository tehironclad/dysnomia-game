class_name ActTracker
extends PanelContainer
## The compact act tracker on the HUD: the top acts here (as PlayLoop ranks
## them, the same ones the beacons mark) and the personal goals, each goal
## from chain reads and saying so on hover. Unread values show "—".
## The last line is today's challenge (DailyRun: the day's game, your tries, time left; local facts).

const SHOW_ACTS := 3
const SHOW_GOALS := 2  # the rest: the Steward at the Core, and the guide

var _acts: VBoxContainer
var _goals: VBoxContainer
var _foot: Label
var _daily: Label
var _daily_t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(HudLayout.COL_W, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var head := Label.new()
	head.theme_type_variation = "DisplayLabel"
	head.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	head.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
	head.text = "WHAT TO DO HERE"
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
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_foot)
	_daily = Label.new()
	_daily.theme_type_variation = "MonoLabel"
	_daily.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	_daily.add_theme_color_override("font_color", Color("#ffd36b"))
	_daily.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_daily.mouse_filter = Control.MOUSE_FILTER_PASS
	_daily.tooltip_text = "Today's challenge: one arcade game a UTC day, free, the same seed for everyone (the first block after 00:00 UTC). In the arcade's ★ TODAY cabinet, or from the front door."
	v.add_child(_daily)
	_show_daily()


func _process(delta: float) -> void:
	_daily_t += delta
	if _daily_t >= 30.0:
		_daily_t = 0.0
		_show_daily()


## "★ TODAY · Void Lanes · 3/3 tries · 5 h 12 min left · arcade ★ cabinet"
func _show_daily() -> void:
	var st := DailyRun.status()
	var seed: Dictionary = st["seed"]
	var tries := "%d/%d tries" % [int(st["left"]), DailyChallenge.ATTEMPTS] if seed["state"] != "failed" else "seed —, practice"
	_daily.text = "★ TODAY · %s · %s · %s · the arcade's ★ cabinet" % [st["title"], tries, st["left_text"]]


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
		dot.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
		row.add_child(dot)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := Label.new()
		t.text = String(a["title"])
		t.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
		t.add_theme_color_override("font_color", DeepFieldTheme.INK if a["doable"] else DeepFieldTheme.MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(t)
		var d := Label.new()
		d.theme_type_variation = "MutedLabel"
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
	for g in goals.slice(0, SHOW_GOALS):
		var l := Label.new()
		l.theme_type_variation = "MonoLabel"
		l.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = String(g["text"])
		l.tooltip_text = String(g["source"])
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_goals.add_child(l)
	_goals.get_parent().get_child(_goals.get_index() - 1).visible = not goals.is_empty()  # the rule above the goals
	var more := goals.size() - SHOW_GOALS
	_foot.text = ("block %s" % TokenFormat.group(str(block)) if block > 0 else "block —") + " · ◆ marks the spot · " + \
		("%d more goal%s with the Steward at the Core" % [more, "" if more == 1 else "s"] if more > 0 else "the Steward at the Core knows more")
