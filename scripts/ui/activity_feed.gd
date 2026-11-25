class_name ActivityFeed
extends VBoxContainer
## The activity feed on the HUD (HudLayout "activity": top-left, under the
## territory card): what online players just did, newest on top, each line with
## the player's face in their head's colour. Lines come from Net.activity (the
## game server's events and this machine's own chain reads; never made up), fade
## after NetEvents.FEED_TTL_S, at most NetEvents.FEED_MAX at once. A one-line
## header says who is online to invite (the bell, N) or offers the sign-in.
## The `activity_feed` key folds it (folded: a count of new lines). Every line
## stays in the notification panel's history for this session.
##   var f := ActivityFeed.new(); hud_root.add_child(f); f.follow(where_panel)

const FACE_PX := 30.0
const FADE_S := 1.2

var header: Label
## Under the header: the online notices and status (NetChatFeed, NetPresence puts it here).
var slot: VBoxContainer
var _box: PanelContainer
var _lines: VBoxContainer
var _folded := false
var _unseen := 0
var _follow: Control
var _tick := 0.0


func _init() -> void:
	name = "ActivityFeed"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(HudLayout.COL_W, 0)
	add_theme_constant_override("separation", 4)
	theme = DeepFieldTheme.get_theme()
	header = Label.new()
	header.theme_type_variation = "MonoLabel"
	header.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	header.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
	header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	header.add_theme_constant_override("outline_size", 5)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.custom_minimum_size = Vector2(HudLayout.COL_W, 0)
	add_child(header)
	slot = VBoxContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)
	_box = PanelContainer.new()  # a soft glass behind the lines: readable over bright ground
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := DeepFieldTheme.panel_style(Color(DeepFieldTheme.ICE, 0.16))
	sb.bg_color = Color(sb.bg_color, 0.5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_box.add_theme_stylebox_override("panel", sb)
	_box.custom_minimum_size = Vector2(HudLayout.COL_W, 0)
	_box.visible = false
	add_child(_box)
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 3)
	_box.add_child(_lines)


func _ready() -> void:
	position = Vector2(HudLayout.MARGIN, HudLayout.slots()["activity"].position.y)
	var net := get_node_or_null("/root/Net")
	if net and net.activity:
		net.activity.added.connect(_on_added)
		net.activity.updated.connect(_on_updated)
		# The last few lines from before this scene (a door, a warp) come back, if still fresh.
		var now := Time.get_ticks_msec()
		for it in net.activity.items.slice(maxi(0, net.activity.items.size() - NetEvents.FEED_MAX)):
			var left := NetEvents.FEED_TTL_S - (now - int(it["ms"])) / 1000.0
			if left > 1.0:
				_show(it, left)
	var inv := get_node_or_null("/root/Invites")
	if inv:
		inv.online_changed.connect(_refresh_header)
	_refresh_header()


## Sit right under `c` (the territory card), never lower than the activity slot allows.
func follow(c: Control) -> void:
	_follow = c
	if c:
		c.resized.connect(_place)
		_place.call_deferred()


func _place() -> void:
	if _follow == null or not is_instance_valid(_follow):
		return
	var y := _follow.position.y + _follow.size.y + HudLayout.GAP
	position = Vector2(HudLayout.MARGIN, minf(y, HudLayout.slots()["room"].position.y - HudLayout.ACTIVITY_MAX_H))


## Shows the last `n` lines again, fresh (screenshots: lines from a minute apart on one frame).
func replay_recent(n: int = NetEvents.FEED_MAX) -> void:
	for row in _lines.get_children():
		row.free()
	var net := get_node_or_null("/root/Net")
	if net == null or net.activity == null:
		return
	for it in net.activity.items.slice(maxi(0, net.activity.items.size() - n)):
		_show(it, NetEvents.FEED_TTL_S)


func is_folded() -> bool:
	return _folded


func set_folded(on: bool) -> void:
	_folded = on
	_lines.visible = not on
	_box.visible = not on and _lines.get_child_count() > 0
	if not on:
		_unseen = 0
	_refresh_header()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("activity_feed") and not event.is_echo():
		get_viewport().set_input_as_handled()
		set_folded(not _folded)


func _on_added(it: Dictionary) -> void:
	if _folded:
		_unseen += 1
		_refresh_header()
		return
	_show(it, NetEvents.FEED_TTL_S)


func _on_updated(it: Dictionary) -> void:
	for row in _lines.get_children():
		if int(row.get_meta("n", -1)) == int(it["n"]):
			(row.get_node("Text") as Label).text = String(it["text"])
			(row.get_node("Face") as HeadBadge).set_face(String(it["head"]), _face_color(it))


func _face_color(it: Dictionary) -> Color:
	return HeadIcons.color_of(String(it["head"])) if String(it.get("wallet", "")) != "" else Color(0.55, 0.6, 0.68)


func _show(it: Dictionary, ttl: float) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.set_meta("n", int(it["n"]))
	row.set_meta("t", ttl)
	var face := HeadBadge.new(String(it["head"]), _face_color(it), FACE_PX)
	face.name = "Face"
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(face)
	var l := Label.new()
	l.name = "Text"
	l.theme_type_variation = "MonoLabel"
	l.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
	l.add_theme_color_override("font_color", it["color"])
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	l.add_theme_constant_override("outline_size", 6)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(HudLayout.COL_W - FACE_PX - 8 - 16, 0)
	l.text = String(it["text"])
	row.add_child(l)
	_lines.add_child(row)
	_lines.move_child(row, 0)  # newest on top
	while _lines.get_child_count() > NetEvents.FEED_MAX:
		_lines.get_child(_lines.get_child_count() - 1).free()
	_box.visible = not _folded
	face.pulse()


func _process(delta: float) -> void:
	for row in _lines.get_children():
		var t: float = float(row.get_meta("t")) - delta
		row.set_meta("t", t)
		row.modulate.a = clampf(t / FADE_S, 0.0, 1.0)
		if t <= 0.0:
			_lines.remove_child(row)
			row.queue_free()
	if _box.visible and _lines.get_child_count() == 0:
		_box.visible = false
	# Never down into the chat dock: long (wrapped) lines push the oldest out early.
	while _lines.get_child_count() > 1 and get_combined_minimum_size().y > HudLayout.ACTIVITY_MAX_H + 20:
		var old := _lines.get_child(_lines.get_child_count() - 1)
		_lines.remove_child(old)
		old.queue_free()
	_tick += delta
	if _tick > 2.0:
		_tick = 0.0
		_refresh_header()


func _refresh_header() -> void:
	var net := get_node_or_null("/root/Net")
	var inv := get_node_or_null("/root/Invites")
	var t := header_text(net != null and net.is_online(), net.sign_in_state() if net else "", net != null and net.can_sign_in(),
		inv.online if inv else [], ControlsHelp.key_of("notifications"), ControlsHelp.key_of("activity_feed"), _folded, _unseen)
	header.text = t
	header.visible = t != ""
	visible = t != "" or _lines.get_child_count() > 0


## Pure: the header line. "" when offline (single-player: nothing to say).
static func header_text(online: bool, sign_state: String, can_sign: bool, others: Array, bell_key: String, fold_key: String,
		folded: bool, unseen: int) -> String:
	if not online:
		return ""
	var head := ""
	match sign_state:
		"prompt", "signing":
			head = "Signing in: approve the free signature in your wallet (not a transaction)"
		"signed":
			var free := others.filter(func(r): return not r.get("busy", false)).size()
			if others.is_empty():
				head = "Online · nobody else signed in right now"
			else:
				head = "%d other%s online · %d to invite (%s)" % [others.size(), "" if others.size() == 1 else "s", free, bell_key]
		_:
			head = ("Online as a guest · others see \"guest\": sign in with the bell (%s)" % bell_key) if can_sign else "Online as a guest"
	if folded:
		return "▸ activity%s · %s · %s" % [(" (%d new)" % unseen) if unseen > 0 else "", fold_key, head]
	return head
