class_name ChatFeedPanel
extends VBoxContainer
## The room's live tail in the HUD: new lines (chain, and free "say" lines when
## the presence server is there) appear compact under the room's name and fade;
## your own lines show their state (signing…, on chain · block N, or why not);
## an unread marker counts lines you have not looked at. Y expands the
## scrollable history (hover a line for its block, tx and source; H lists
## where the feed reads from).

const ROWS := 6
const TTL := 28.0  # seconds a new line stays
const HISTORY_TTL := 14.0  # the last few lines shown on arrival
const OWN_TTL := 12.0  # a posted/failed line of yours
const WIDTH := 640.0

var header: Label
var rows: VBoxContainer
var own: VBoxContainer
var unread_chip: Label
var history: PanelContainer
var history_text: RichTextLabel
var history_sub: Label
var history_hover: Label
var unread := 0
var _feed: RoomFeed
var _row_nodes: Array = []  # [{node, line, until}]
var _own_shown := {}  # entry id → seconds left after done
var _t := 0.0
var _mouse_before := Input.MOUSE_MODE_CAPTURED
var _keys := {}  # meta key → line (history hover)


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 2)
	var head_row := HBoxContainer.new()
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head_row)
	header = Label.new()
	header.theme_type_variation = "MonoLabel"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", DeepFieldTheme.MUTED)  # DIM vanished over bright regolith
	header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	header.add_theme_constant_override("outline_size", 6)
	head_row.add_child(header)
	unread_chip = Label.new()
	unread_chip.theme_type_variation = "MonoLabel"
	unread_chip.add_theme_font_size_override("font_size", 11)
	unread_chip.add_theme_color_override("font_color", Color("#ffd27a"))
	unread_chip.visible = false
	head_row.add_child(unread_chip)
	rows = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 1)
	add_child(rows)
	own = VBoxContainer.new()
	own.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(own)
	_build_history()


func _build_history() -> void:
	history = PanelContainer.new()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.93
	history.add_theme_stylebox_override("panel", sb)
	history.visible = false
	history.mouse_filter = Control.MOUSE_FILTER_STOP
	history.custom_minimum_size = Vector2(720, 560)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	history.add_child(col)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 18)
	col.add_child(title)
	history_sub = Label.new()
	history_sub.theme_type_variation = "MutedLabel"
	history_sub.add_theme_font_size_override("font_size", 11)
	history_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history_sub.custom_minimum_size = Vector2(690, 0)
	col.add_child(history_sub)
	history_text = RichTextLabel.new()
	history_text.bbcode_enabled = true
	history_text.scroll_following = true
	history_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_text.custom_minimum_size = Vector2(690, 400)
	history_text.add_theme_font_override("normal_font", DeepFieldTheme.mono_font())
	history_text.add_theme_font_size_override("normal_font_size", 13)
	history_text.meta_underlined = false
	history_text.meta_hover_started.connect(func(m): _hover(String(m)))
	history_text.meta_hover_ended.connect(func(_m): history_hover.text = "Hover a line for its block, transaction and source.")
	col.add_child(history_text)
	history_hover = Label.new()
	history_hover.theme_type_variation = "MonoLabel"
	history_hover.add_theme_font_size_override("font_size", 11)
	history_hover.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	history_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history_hover.custom_minimum_size = Vector2(690, 0)
	history_hover.text = "Hover a line for its block, transaction and source."
	col.add_child(history_hover)
	var foot := Label.new()
	foot.theme_type_variation = "MutedLabel"
	foot.add_theme_font_size_override("font_size", 11)
	foot.text = "%s close · %s chat · %s where these lines come from" % [ControlsHelp.key_of("chat_history"), ControlsHelp.key_of("chat"), ControlsHelp.key_of("inspect")]
	col.add_child(foot)


func _ready() -> void:
	ChatFeed.current_changed.connect(bind_feed)
	ChatFeed.outbox_changed.connect(_render_own)
	if ChatFeed.current:
		bind_feed(ChatFeed.current)


func bind_feed(f: RoomFeed) -> void:
	if _feed and is_instance_valid(_feed):
		if _feed.arrived.is_connected(_on_arrived):
			_feed.arrived.disconnect(_on_arrived)
		if _feed.lines_changed.is_connected(_on_lines):
			_feed.lines_changed.disconnect(_on_lines)
	_feed = f
	unread = 0
	for r in _row_nodes:
		(r["node"] as Node).queue_free()
	_row_nodes.clear()
	if f == null:
		return
	f.arrived.connect(_on_arrived)
	f.lines_changed.connect(_on_lines)
	_shown_history = false
	_on_lines(f.lines)


var _shown_history := false


## History landed: on arrival, the last few lines show briefly (they are
## history, so they don't count as unread).
func _on_lines(ls: Array) -> void:
	_refresh_header()
	if history.visible:
		_render_history()
	if _shown_history or ls.is_empty() or not _feed.is_loaded():
		return
	_shown_history = true
	for l in ls.slice(maxi(0, ls.size() - 3)):
		_add_row(l, HISTORY_TTL, true)
	_register()


func _on_arrived(fresh: Array) -> void:
	for l in fresh:
		if _is_own_shown(l):
			continue
		_add_row(l, TTL, false)
		unread += 1
	_refresh_header()
	var sc := get_tree().current_scene
	if is_visible_in_tree() and not (sc and sc.get("chat_ctl") != null):  # places chime themselves
		Cues.play(self, "line")


func _is_own_shown(l: Dictionary) -> bool:
	var tx := String(l.get("tx", "")).to_lower()
	if tx == "":
		return false
	for e in ChatFeed.outbox.entries:
		if String(e.get("tx", "")).to_lower() == tx and _own_shown.has(e["id"]):
			return true
	return false


func _add_row(l: Dictionary, ttl: float, dim: bool) -> void:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(WIDTH, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", DeepFieldTheme.mono_font())
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	r.add_theme_constant_override("outline_size", 5)
	r.text = ChatLines.bbcode(l, false, false, 110)
	r.modulate.a = 0.62 if dim else 1.0
	rows.add_child(r)
	_row_nodes.append({"node": r, "line": l, "until": _t + ttl})
	while _row_nodes.size() > ROWS:
		(_row_nodes.pop_front()["node"] as Node).queue_free()


func _refresh_header() -> void:
	if _feed == null:
		header.text = ""
		return
	var st: Dictionary = ChatFeed.stats()
	var nm := String(_feed.territory.get("name", _feed.qing)).to_upper()
	var today := "lines today: %s" % ChatLines.count_text(st) if _feed.is_loaded() else "reading the room…"
	header.text = "ROOM · %s · %s · %s chat · %s history" % [nm, today, ControlsHelp.key_of("chat"), ControlsHelp.key_of("chat_history")]
	unread_chip.text = "  ● %d new" % unread
	unread_chip.visible = unread > 0 and not history.visible


func mark_read() -> void:
	unread = 0
	_refresh_header()


# --- Your lines in flight ---------------------------------------------------------------

func _render_own() -> void:
	for c in own.get_children():
		c.queue_free()
	for e in ChatFeed.outbox.entries:
		var done: bool = e["state"] == "posted" or e["state"] == "failed"
		if done and not _own_shown.has(e["id"]):
			_own_shown[e["id"]] = OWN_TTL if e["state"] == "posted" else OWN_TTL * 2.0
		if done and float(_own_shown[e["id"]]) <= 0.0:
			continue
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.scroll_active = false
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.custom_minimum_size = Vector2(WIDTH, 0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_theme_font_override("normal_font", DeepFieldTheme.mono_font())
		r.add_theme_font_size_override("normal_font_size", 13)
		r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		r.add_theme_constant_override("outline_size", 5)
		r.text = own_bbcode(e)
		own.add_child(r)


static func own_bbcode(e: Dictionary) -> String:
	var col := "#8e97a9"
	match String(e["state"]):
		"posted": col = "#64e3a8"
		"failed": col = "#ff8fa0"
		"signing": col = "#ffd27a"
	var extra := ""
	if e["state"] == "failed":
		extra = " · T: the line is back in the bar" + (" (Join there)" if e.get("kind", "") == "join" else "")
	return "[color=#a8e6ff]you[/color]  %s  [color=%s]%s%s[/color]" % [
		ChatLines.esc(ChatLines.clean_text(String(e["text"]), 90)), col, ChatLines.esc(ChatOutbox.status_text(e)), extra]


# --- History ------------------------------------------------------------------------------

func is_history_open() -> bool:
	return history.visible


func toggle_history() -> void:
	history.visible = not history.visible
	if history.visible:
		_mouse_before = Input.get_mouse_mode()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mark_read()
		_render_history()
	else:
		Input.set_mouse_mode(_mouse_before if _mouse_before != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED)
	_refresh_header()


func _render_history() -> void:
	if _feed == null:
		return
	(history.get_child(0).get_node("Title") as Label).text = "ROOM · %s" % String(_feed.territory.get("name", _feed.qing)).to_upper()
	var st: Dictionary = ChatFeed.stats()
	# Loading is not zero: no count until the history has been read.
	history_sub.text = "%s\nLines today (last %s blocks): %s" % [_feed.describe(), TokenFormat.group(str(ChatLines.DAY_BLOCKS)),
		("%s · speakers today: %d" % [ChatLines.count_text(st), st["speakers"].size()]) if _feed.is_loaded() else "— (reading the history…)"]
	_keys.clear()
	var parts: PackedStringArray = []
	if not _feed.is_loaded() and _feed.lines.is_empty():
		parts.append("[color=#5d6578]Reading the room's lines from the chain…[/color]")
	elif _feed.lines.is_empty():
		parts.append("[color=#5d6578]%s[/color]" % ("No lines in the scanned range." if _feed.history_ok else "History unavailable: —"))
	for l in _feed.lines:
		_keys[ChatLines.key(l)] = l
		parts.append(ChatLines.bbcode(l, true, true, 400))
	history_text.text = "\n".join(parts)


func _hover(k: String) -> void:
	var l: Dictionary = _keys.get(k, {})
	history_hover.text = ChatLines.provenance(l) if not l.is_empty() else ""


func _register() -> void:
	if _feed == null:
		return
	Inspector.register(self, "Room chat feed · %s" % String(_feed.territory.get("name", _feed.qing)),
		"%s\nSpeakers' names are LAU.Username() as logged; ✓ OG / ⚠ imposter compare the speaking LAU's Aura with the name's owner. Free \"say\" lines (presence server) are tagged say and never on chain." % _feed.describe())


func _process(delta: float) -> void:
	_t += delta
	for i in range(_row_nodes.size() - 1, -1, -1):
		var r: Dictionary = _row_nodes[i]
		var left: float = r["until"] - _t
		var n: CanvasItem = r["node"]
		if left <= 0.0:
			n.queue_free()
			_row_nodes.remove_at(i)
		elif left < 3.0:
			n.modulate.a = minf(n.modulate.a, left / 3.0)
	var changed := false
	for id in _own_shown.keys():
		var e: Dictionary = ChatFeed.outbox.get_entry(id)
		if e.is_empty():
			_own_shown.erase(id)
			continue
		if float(_own_shown[id]) > 0.0:
			_own_shown[id] = float(_own_shown[id]) - delta
			if float(_own_shown[id]) <= 0.0:
				changed = true
	if changed:
		_render_own()
	if int(_t) != int(_t - delta):
		_refresh_header()  # once a second: today's count moves with the head
