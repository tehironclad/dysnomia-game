class_name ChatFeedPanel
extends PanelContainer
## The room's chat, docked bottom-left of the HUD: always there in a territory
## (and the arcade and the pub), the QING's own colours on its header.
##
## - On arrival it greets you with the room's last words (the newest lines
##   read from the chain), so a room you walk into already has a voice.
## - The latest ROWS lines stay: each with its speaker's face (their avatar
##   head) and colour, and how long ago (from the block; hover: the block).
##   Older lines fade back but never vanish; a new line slides in with a soft
##   tick and a flash; a line that names you (your Username) stands out in
##   gold with its own chime.
## - Your own lines show their state (signing…, on chain · block N, or why not).
## - U folds the dock to its header (an unread count shows there); Y opens the
##   scrollable history (hover a line for its block, tx and source).
## Loading, empty, unavailable and quiet are four different states, each said.

const ROWS := 5
const WIDTH := 540.0  # HudLayout.DOCK_W
const GREET_S := 22.0  # how long the arrival greeting heads the dock
const FRESH_S := 45.0  # a new line stays bright this long, then settles
const OWN_TTL := 12.0  # a posted/failed line of yours
const FACE_PX := 34.0
const GOLD := Color("#ffd27a")
const UI_PREFS := "user://ui.cfg"  # this machine's UI choices (the dock folded or not)

var header: Label
var stat: Label
var unread_chip: Label
var sub: Label
var rows: VBoxContainer
var own: VBoxContainer
var foot: HBoxContainer
var history: PanelContainer
var history_text: RichTextLabel
var history_sub: Label
var history_hover: Label
var unread := 0
var mentions := 0
var collapsed := false
var tint := DeepFieldTheme.ICE
var _feed: RoomFeed
var _row_nodes := {}  # line key → row Control
var _fresh := {}  # line key → time it arrived (this session)
var _own_shown := {}  # entry id → seconds left after done
var _t := 0.0
var _greet_until := 0.0
var _pulse := 0.0
var _style: StyleBoxFlat
var _mouse_before := Input.MOUSE_MODE_CAPTURED
var _keys := {}  # meta key → line (history hover)


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	_style = DeepFieldTheme.accent_style(tint, 0.62)
	_style.content_margin_top = 8
	_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", _style)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head_row := HBoxContainer.new()
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_theme_constant_override("separation", 10)
	col.add_child(head_row)
	header = Label.new()
	header.theme_type_variation = "DisplayLabel"
	header.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	head_row.add_child(header)
	stat = Label.new()
	stat.theme_type_variation = "MonoLabel"
	stat.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
	head_row.add_child(stat)
	unread_chip = Label.new()
	unread_chip.theme_type_variation = "MonoLabel"
	unread_chip.add_theme_color_override("font_color", DeepFieldTheme.BLACK)
	var us := StyleBoxFlat.new()
	us.bg_color = GOLD
	us.set_corner_radius_all(9)
	us.content_margin_left = 8
	us.content_margin_right = 8
	unread_chip.add_theme_stylebox_override("normal", us)
	unread_chip.visible = false
	head_row.add_child(unread_chip)
	sub = Label.new()
	sub.theme_type_variation = "MutedLabel"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(WIDTH - 32, 0)
	col.add_child(sub)
	rows = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 4)
	col.add_child(rows)
	own = VBoxContainer.new()
	own.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(own)
	foot = HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", 6)
	col.add_child(foot)
	_build_foot()
	_build_history()


## The keys under the dock: talk, history, the quick lines, fold.
func _build_foot() -> void:
	for c in foot.get_children():
		c.queue_free()
	for kv in [[ControlsHelp.key_of("chat"), "talk"], [ControlsHelp.key_of("chat_history"), "history"],
			["1–4", "quick line"], [ControlsHelp.key_of("chat_dock"), "fold"]]:
		foot.add_child(DeepFieldTheme.key_chip(String(kv[0])))
		var l := Label.new()
		l.theme_type_variation = "MutedLabel"
		l.text = String(kv[1]) + "  "
		foot.add_child(l)


func _build_history() -> void:
	history = PanelContainer.new()
	var sb := DeepFieldTheme.accent_style(tint, 0.94)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	history.add_theme_stylebox_override("panel", sb)
	history.visible = false
	history.mouse_filter = Control.MOUSE_FILTER_STOP
	history.custom_minimum_size = Vector2(900, 700)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	history.add_child(col)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = "DisplayLabel"
	col.add_child(title)
	history_sub = Label.new()
	history_sub.theme_type_variation = "MutedLabel"
	history_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history_sub.custom_minimum_size = Vector2(850, 0)
	col.add_child(history_sub)
	history_text = RichTextLabel.new()
	history_text.bbcode_enabled = true
	history_text.scroll_following = true
	history_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_text.custom_minimum_size = Vector2(850, 460)
	history_text.add_theme_font_override("normal_font", DeepFieldTheme.mono_font())
	history_text.add_theme_font_size_override("normal_font_size", DeepFieldTheme.FS_SMALL)
	history_text.meta_underlined = false
	history_text.meta_hover_started.connect(func(m): _hover(String(m)))
	history_text.meta_hover_ended.connect(func(_m): history_hover.text = "Hover a line for its block, transaction and source.")
	col.add_child(history_text)
	history_hover = Label.new()
	history_hover.theme_type_variation = "MonoLabel"
	history_hover.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	history_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history_hover.custom_minimum_size = Vector2(850, 0)
	history_hover.text = "Hover a line for its block, transaction and source."
	col.add_child(history_hover)
	var f := HBoxContainer.new()
	f.add_theme_constant_override("separation", 6)
	col.add_child(f)
	for kv in [[ControlsHelp.key_of("chat_history"), "close"], [ControlsHelp.key_of("chat"), "talk"], [ControlsHelp.key_of("inspect"), "where these lines come from"]]:
		f.add_child(DeepFieldTheme.key_chip(String(kv[0])))
		var l := Label.new()
		l.theme_type_variation = "MutedLabel"
		l.text = String(kv[1]) + "   "
		f.add_child(l)


func _ready() -> void:
	ChatFeed.current_changed.connect(bind_feed)
	ChatFeed.outbox_changed.connect(_render_own)
	if Session.has_signal("changed"):
		Session.changed.connect(func(): _render_rows())
	if ChatFeed.current:
		bind_feed(ChatFeed.current)
	var cf := ConfigFile.new()
	if cf.load(UI_PREFS) == OK and bool(cf.get_value("chat", "dock_folded", false)):
		set_collapsed(true)


func bind_feed(f: RoomFeed) -> void:
	if _feed and is_instance_valid(_feed):
		if _feed.arrived.is_connected(_on_arrived):
			_feed.arrived.disconnect(_on_arrived)
		if _feed.lines_changed.is_connected(_on_lines):
			_feed.lines_changed.disconnect(_on_lines)
	_feed = f
	unread = 0
	mentions = 0
	_fresh.clear()
	for k in _row_nodes:
		(_row_nodes[k] as Node).queue_free()
	_row_nodes.clear()
	if f == null:
		_refresh_header()
		return
	tint = room_tint(f.territory)
	_restyle()
	f.arrived.connect(_on_arrived)
	f.lines_changed.connect(_on_lines)
	_greet_until = _t + GREET_S
	_on_lines(f.lines)
	_register()


## The QING's own colour (its Deep Field picture's hue), or ice when unknown.
static func room_tint(t: Dictionary) -> Color:
	if t.is_empty() or String(t.get("entropy", "")) == "":
		return DeepFieldTheme.ICE
	var c := DeepField.to_color(DeepField.for_territory(t)["color"])
	return c.lerp(DeepFieldTheme.ICE, 0.25)


func _restyle() -> void:
	_style.border_color = Color(tint, 0.55)
	header.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.35))
	var hs := history.get_theme_stylebox("panel") as StyleBoxFlat
	if hs:
		hs.border_color = Color(tint, 0.6)
	(history.get_child(0).get_node("Title") as Label).add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.35))


func _on_lines(_ls: Array) -> void:
	_refresh_header()
	_render_rows()
	if history.visible:
		_render_history()


func _on_arrived(fresh: Array) -> void:
	var named := false
	for l in fresh:
		_fresh[ChatLines.key(l)] = _t
		if _is_own_shown(l):
			continue
		if collapsed or not is_visible_in_tree():
			unread += 1
		if is_mention(l):
			mentions += 1
			named = true
	_pulse = 1.0
	_render_rows()
	_refresh_header()
	var sc := get_tree().current_scene if is_inside_tree() else null
	if is_visible_in_tree() and not (sc and sc.get("chat_ctl") != null):  # places chime themselves
		Cues.play(self, "mention" if named else "line")


## A line that names you (your LAU's Username), not one of your own.
func is_mention(l: Dictionary) -> bool:
	var ps: PlayerState = Session.player
	if ps == null or ps.username == "":
		return false
	if Session.wallet != "" and String(l.get("wallet", "")) == Session.wallet:
		return false
	if String(l.get("name", "")).to_lower() == ps.username.to_lower():
		return false
	return ChatLines.mentions(String(l.get("text", "")), ps.username)


func _is_own_shown(l: Dictionary) -> bool:
	var tx := String(l.get("tx", "")).to_lower()
	if tx == "":
		return false
	for e in ChatFeed.outbox.entries:
		if String(e.get("tx", "")).to_lower() == tx and _own_shown.has(e["id"]):
			return true
	return false


# --- Rows ------------------------------------------------------------------------------------

## The newest ROWS lines, oldest first; rows are kept per line so a new one can
## slide in while the others stay put.
func _render_rows() -> void:
	if _feed == null or not is_instance_valid(_feed):
		return
	var tail: Array = _feed.lines.slice(maxi(0, _feed.lines.size() - ROWS))
	var keep := {}
	for i in tail.size():
		var l: Dictionary = tail[i]
		var k := ChatLines.key(l)
		keep[k] = true
		var r: Control = _row_nodes.get(k)
		var is_new := r == null
		if is_new:
			r = _make_row(l)
			_row_nodes[k] = r
			rows.add_child(r)
		else:
			_fill_row(r, l)
		rows.move_child(r, i)
		if is_new and _fresh.has(k):
			_slide_in(r)
	for k in _row_nodes.keys():
		if not keep.has(k):
			(_row_nodes[k] as Node).queue_free()
			_row_nodes.erase(k)
	_fade_rows()
	rows.visible = not collapsed and not tail.is_empty()


func _make_row(l: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.name = "Row"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var face := HeadBadge.new("bear", DeepFieldTheme.ICE, FACE_PX)
	face.name = "Face"
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(face)
	var r := RichTextLabel.new()
	r.name = "Text"
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", DeepFieldTheme.FS_BODY)
	r.add_theme_font_size_override("bold_font_size", DeepFieldTheme.FS_BODY)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	r.add_theme_constant_override("outline_size", 3)
	h.add_child(r)
	var age := Label.new()
	age.name = "Age"
	age.theme_type_variation = "MonoLabel"
	age.add_theme_color_override("font_color", DeepFieldTheme.DIM.lerp(DeepFieldTheme.MUTED, 0.5))
	age.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	age.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(age)
	_fill_row(p, l)
	return p


func _fill_row(p: Control, l: Dictionary) -> void:
	var h := p.get_node("Row")
	var col := ChatLines.speaker_color(l)
	(h.get_node("Face") as HeadBadge).set_face(head_of(l), col)
	var mention := is_mention(l)
	(h.get_node("Text") as RichTextLabel).text = row_bbcode(l, col, mention)
	var age := h.get_node("Age") as Label
	var say := String(l.get("source", "chain")) == "say"
	age.text = "say" if say else ChatLines.age_text(int(l.get("block", -1)), _head())
	age.tooltip_text = ChatLines.provenance(l)
	p.set_meta("mention", mention)
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	if mention:
		sb.bg_color = Color(GOLD, 0.12)
		sb.border_width_left = 3
		sb.border_color = GOLD


## Pure: a dock row's BBCode: the speaker in their colour (with ✓/⚠), then the
## line; a line naming you is tagged and gold.
static func row_bbcode(l: Dictionary, col: Color, mention: bool = false) -> String:
	var badge := ""
	match String(l.get("badge", "")):
		"og": badge = " [color=#64e3a8]✓[/color]"
		"imposter": badge = " [color=#ff8fa0]⚠[/color]"
	var text := ChatLines.esc(ChatLines.clean_text(String(l.get("text", "")), 120))
	if mention:
		text = "[color=#ffd27a]%s[/color]  [color=#ffd27a][font_size=%d]· names you[/font_size][/color]" % [text, DeepFieldTheme.FS_CAPTION]
	return "[b][color=#%s]%s[/color][/b]%s  %s" % [col.to_html(false), ChatLines.esc(ChatLines.speaker(l)), badge, text]


## The face a line's speaker wears: yours as your avatar wears it (your pick on
## this machine, else your LAU's), anyone else's from their logged Username
## (the AvatarHeads rules, the same as their echo at the Room).
func head_of(l: Dictionary) -> String:
	var w := String(l.get("wallet", ""))
	var ps: PlayerState = Session.player
	if w != "" and w == Session.wallet and ps != null:
		var pick := AvatarHeads.local_choice(w)
		return pick if pick != "" else ps.head_kind()
	return AvatarHeads.kind_for(String(l.get("name", "")), "", "")


func _head() -> int:
	var h := int(_feed.head_seen) if _feed else -1
	return maxi(h, Chain.head_block)


func _slide_in(r: Control) -> void:
	var sb := r.get_theme_stylebox("panel") as StyleBoxFlat
	var mention: bool = r.get_meta("mention", false)
	var base := Color(GOLD, 0.12) if mention else Color(0, 0, 0, 0)
	sb.bg_color = Color(GOLD if mention else tint, 0.38)
	r.modulate.a = 0.0
	var face := r.get_node("Row/Face") as HeadBadge
	face.pulse()
	r.set_meta("sliding", true)
	var tw := r.create_tween()
	tw.tween_property(r, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(sb, "bg_color", base, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): r.remove_meta("sliding"))


## Older lines settle back, never under 0.55; new ones stay bright for FRESH_S.
func _fade_rows() -> void:
	var n := rows.get_child_count()
	for i in n:
		var r := rows.get_child(i) as Control
		if r.is_queued_for_deletion():
			continue
		var k := ""
		for kk in _row_nodes:
			if _row_nodes[kk] == r:
				k = kk
				break
		var target := row_alpha(n - 1 - i, _fresh.has(k) and _t - float(_fresh[k]) < FRESH_S)
		if r.get_meta("mention", false):
			target = 1.0
		if absf(r.modulate.a - target) > 0.01 and not r.has_meta("sliding"):
			r.modulate.a = target


## Pure: a row's opacity from its place (0 = newest) and freshness.
static func row_alpha(from_newest: int, fresh: bool) -> float:
	if fresh:
		return 1.0
	return clampf(0.92 - 0.09 * float(from_newest), 0.55, 1.0)


# --- Header and states --------------------------------------------------------------------------

func _refresh_header() -> void:
	if _feed == null or not is_instance_valid(_feed):
		header.text = "ROOM"
		stat.text = ""
		sub.text = "No room here: the territory is not known (—)."
		unread_chip.visible = false
		return
	var nm := String(_feed.territory.get("name", _feed.qing)).to_upper()
	header.text = "ROOM · %s" % nm
	var st: Dictionary = ChatFeed.stats()
	stat.text = ("%s today" % ChatLines.count_text(st)) if _feed.is_loaded() else ""  # the state line says it is reading
	stat.tooltip_text = "Lines in the last %s blocks (≈ 24 h), from this room's LogEvent logs" % TokenFormat.group(str(ChatLines.DAY_BLOCKS))
	var n := unread
	unread_chip.text = ("@ %d" % mentions) if mentions > 0 and collapsed else "● %d new" % n
	unread_chip.visible = n > 0 and collapsed and not history.visible
	sub.text = state_line(_feed.is_loaded(), _feed.history_ok, _feed.lines, _head(), _t < _greet_until,
		String(_feed.territory.get("name", "")), Session.wallet != "")
	sub.visible = not collapsed and sub.text != ""


## Pure: the line under the dock's header. Loading, unavailable, empty, quiet
## and talking are different things and say so; `greet` on arrival.
static func state_line(loaded: bool, history_ok: bool, ls: Array, head: int, greet: bool, room: String, has_wallet: bool) -> String:
	if not loaded and ls.is_empty():
		return "Reading the room's lines from the chain…"
	if loaded and ls.is_empty():
		return "History unavailable: — (the log scan stopped)." if not history_ok \
			else "No lines in the scanned range. Every QING is a room: say the first word (%s)." % ControlsHelp.key_of("chat")
	var last := -1
	for l in ls:
		if ChatLines.is_chain_shaped(l):
			last = maxi(last, int(l["block"]))
	var quiet := last > 0 and head > 0 and head - last > ChatLines.DAY_BLOCKS
	if greet:
		var w := "You walk into %s's room. Its last words, from the chain:" % room if room != "" else "Its last words, from the chain:"
		return w + (" (quiet for ≈ %s)" % ChatLines.age_text(last, head) if quiet else "")
	if quiet:
		return "Quiet for ≈ %s (last line at block %s). %s" % [ChatLines.age_text(last, head), TokenFormat.group(str(last)),
			"Wake it: %s" % ControlsHelp.key_of("chat") if has_wallet else "Anyone with a LAU can wake it."]
	return ""


func mark_read() -> void:
	unread = 0
	mentions = 0
	_refresh_header()


## U: fold the dock to its header (the unread count shows there) or unfold it.
func set_collapsed(c: bool) -> void:
	collapsed = c
	rows.visible = not c and rows.get_child_count() > 0
	own.visible = not c
	foot.visible = not c
	if not c:
		mark_read()
	_refresh_header()
	var cf := ConfigFile.new()
	cf.load(UI_PREFS)
	cf.set_value("chat", "dock_folded", c)
	cf.save(UI_PREFS)


func toggle_collapsed() -> void:
	set_collapsed(not collapsed)


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
		r.custom_minimum_size = Vector2(WIDTH - 32, 0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_theme_font_override("normal_font", DeepFieldTheme.mono_font())
		r.add_theme_font_size_override("normal_font_size", DeepFieldTheme.FS_CAPTION)
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
		history.modulate.a = 0.0
		history.create_tween().tween_property(history, "modulate:a", 1.0, 0.18)
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
		var b := ChatLines.bbcode(l, true, true, 400)
		if is_mention(l):
			b = "[bgcolor=#ffd27a22]%s[/bgcolor]" % b
		parts.append(b)
	history_text.text = "\n".join(parts)


func _hover(k: String) -> void:
	var l: Dictionary = _keys.get(k, {})
	history_hover.text = ChatLines.provenance(l) if not l.is_empty() else ""


func _register() -> void:
	if _feed == null:
		return
	Inspector.register(self, "Room chat · %s" % String(_feed.territory.get("name", _feed.qing)),
		"%s\nSpeakers' names are LAU.Username() as logged; ✓ OG / ⚠ imposter compare the speaking LAU's Aura with the name's owner. Faces: your own head as your avatar wears it; others' from their logged Username (the same rules as their echo at the Room). Ages are block counts at ≈ %d blocks a day. Free \"say\" lines (presence server) are tagged say and never on chain." % [_feed.describe(), ChatLines.DAY_BLOCKS])


func _process(delta: float) -> void:
	_t += delta
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 0.6)
		_style.border_color = Color(tint, 0.55 + 0.45 * _pulse)
		_style.shadow_color = Color(tint, 0.35 * _pulse)
		_style.shadow_size = int(10.0 * _pulse)
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
		if int(_t) % 5 == 0:
			_fade_rows()
