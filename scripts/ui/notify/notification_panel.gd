class_name NotificationPanel
extends CanvasLayer
## The notification panel (N, or click the bell): game invites, stakes and wagers,
## and who is online to invite. Its own layer, above a seated table, so an invite
## reaches you while you play. What it shows comes from the Invites autoload (this
## session's notifications; the server's invites and games; the chain's Transfer
## logs for wagers). Added as one node by the HUD and by places:
##   add_child(NotificationPanel.new())
## With no game server it says so: invites need the server; the game is single-player.

const W := 500.0
const TOAST_S := 7.0
const GAMES := ["pool", "cards"]

var _bell: Bell
var _toast: PanelContainer
var _toast_label: Label
var _toast_t := 0.0
var _panel: PanelContainer
var _status: Label
var _sign_in: Button
var _game_buttons := {}
var _stake: LineEdit
var _online_box: VBoxContainer
var _online_note: Label
var _notes_box: VBoxContainer
var _msg: Label
var _game := "pool"
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _guarded := false
var _tick := 0.0
var _dirty := true


func _init() -> void:
	name = "NotificationPanel"


func _ready() -> void:
	layer = 27
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DeepFieldTheme.get_theme()
	add_child(root)
	_bell = Bell.new()
	_bell.set_anchors_preset(Control.PRESET_CENTER_TOP)  # beside the wallet chip: clear of the HUD's corners and a table's numbers
	_bell.offset_left = 250  # clear of the wallet chip at the theme's type scale
	_bell.offset_right = 292
	_bell.offset_top = 4
	_bell.offset_bottom = 46
	_bell.tooltip_text = "Notifications (%s): invites, stakes, wagers, who is online" % ControlsHelp.key_of("notifications")
	_bell.pressed.connect(toggle)
	root.add_child(_bell)
	if _dock_slot != null and is_instance_valid(_dock_slot):
		dock_bell(_dock_slot)
	_build_toast(root)
	_build_panel(root)
	Invites.notes_changed.connect(_mark_dirty)
	Invites.match_changed.connect(func(_id): _mark_dirty())
	Invites.online_changed.connect(_mark_dirty)
	Invites.note_added.connect(_on_note)
	_refresh_bell()


func _exit_tree() -> void:
	_unguard()


var _dock_slot: Control = null

## Put the bell in a HUD slot (HudV2.notify_slot, the top-right corner) instead of
## its fallback spot beside the wallet chip. Safe to call before or after _ready.
func dock_bell(slot: Control) -> void:
	_dock_slot = slot
	if _bell == null or slot == null:
		return
	if _bell.get_parent() != null:
		_bell.get_parent().remove_child(_bell)
	_bell.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_bell.offset_left = 0
	_bell.offset_top = 0
	_bell.offset_right = 42
	_bell.offset_bottom = 42
	_bell.custom_minimum_size = Vector2(42, 42)
	_bell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(_bell)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if _panel.visible:
		close()
	else:
		open()


## Opens the panel; `game` preselects the game to invite to ("" = keep / the table you sit at).
func open(game: String = "") -> void:
	if game == "":
		game = _table_game()
	if game in GAMES:
		_set_game(game)
	_was_mouse = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_panel.visible = true
	_toast.visible = false
	_msg.text = ""
	Invites.refresh_online()
	_rebuild()
	Invites.mark_all_read()


func close() -> void:
	if not _panel.visible:
		return
	_unguard()
	_panel.visible = false
	Input.set_mouse_mode(_was_mouse)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("notifications") and not event.is_echo():
		get_viewport().set_input_as_handled()
		toggle()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		if _panel.visible and _has_countdown():
			_dirty = true
	if _dirty:
		_dirty = false
		_refresh_bell()
		if _panel.visible:
			_rebuild()


func _mark_dirty() -> void:
	_dirty = true


func _refresh_bell() -> void:
	_bell.count = Invites.unread()
	_bell.online = Invites.blocker() == ""
	_bell.queue_redraw()


func _on_note(x: Dictionary) -> void:
	if _panel.visible:
		Invites.mark_all_read()
		return
	_toast_label.text = "%s\n%s opens the notifications" % [x["text"], ControlsHelp.key_of("notifications")]
	_toast_t = TOAST_S
	_toast.modulate.a = 1.0
	_toast.visible = true


## The game of the table you are sitting at, if any.
func _table_game() -> String:
	var cs := get_tree().current_scene
	if cs is GamesPlace:
		if cs.pool_seat and cs.pool_seat.is_active():
			return "pool"
		if cs.card_seat and cs.card_seat.is_active():
			return "cards"
	return ""


func _has_countdown() -> bool:
	for inv in Invites.invites.values():
		if inv.get("state") == "pending":
			return true
	return false


# --- Building -----------------------------------------------------------------------

func _label(parent: Control, text: String, variation: String = "MutedLabel", size: int = 13, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(W - 40, 0)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _build_toast(root: Control) -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", DeepFieldTheme.panel_style(Color(DeepFieldTheme.ICE, 0.45)))
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)  # clear of the HUD and the table's numbers
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_left = -470
	_toast.offset_right = -22
	_toast.offset_top = -150
	_toast.offset_bottom = -110
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	root.add_child(_toast)
	_toast_label = Label.new()
	_toast_label.theme_type_variation = "MonoLabel"
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(430, 0)
	_toast.add_child(_toast_label)


func _build_panel(root: Control) -> void:
	_panel = PanelContainer.new()
	var sb := DeepFieldTheme.panel_style(Color(DeepFieldTheme.ICE, 0.35))
	sb.bg_color = Color(DeepFieldTheme.BLACK, 0.93)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -W - 20
	_panel.offset_right = -20
	_panel.offset_top = 110
	_panel.offset_bottom = -70
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	root.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var t := Label.new()
	t.theme_type_variation = "DisplayLabel"
	t.add_theme_font_size_override("font_size", 18)
	t.text = "NOTIFICATIONS"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_button(head, "Close · %s" % ControlsHelp.key_of("notifications"), close)
	_status = _label(col, "", "MutedLabel", 12)
	_sign_in = _button(col, "Sign in to the game server (a free signature)", func():
		get_node("/root/Net").sign_in()
		_msg.text = "Approve the free signature in your wallet window (not a transaction).")
	_msg = _label(col, "", "MonoLabel", 12, DeepFieldTheme.ICE)
	col.add_child(HSeparator.new())
	_label(col, "INVITE A PLAYER ONLINE", "DisplayLabel", 13, DeepFieldTheme.ICE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var group := ButtonGroup.new()
	for g in GAMES:
		var b := Button.new()
		b.text = InviteBook.title_of(g)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): _set_game(g))
		row.add_child(b)
		_game_buttons[g] = b
	_stake = LineEdit.new()
	_stake.placeholder_text = "stake Ⓐ (optional)"
	_stake.custom_minimum_size = Vector2(150, 0)
	_stake.add_theme_font_size_override("font_size", 13)
	_stake.focus_entered.connect(_guard)
	_stake.focus_exited.connect(_unguard)
	_stake.text_submitted.connect(func(_t): _stake.release_focus())
	row.add_child(_stake)
	_button(row, "Refresh", func(): Invites.refresh_online())
	_label(col, "At the arcade of the territory you are in. A stake is honour-bound: both of you confirm it at the table; the loser pays the winner in Ⓐ and the chain's Transfer log shows it paid.", "MutedLabel", 11)
	_online_note = _label(col, "", "MutedLabel", 12)
	_online_box = VBoxContainer.new()
	_online_box.add_theme_constant_override("separation", 3)
	col.add_child(_online_box)
	col.add_child(HSeparator.new())
	_label(col, "THIS SESSION", "DisplayLabel", 13, DeepFieldTheme.ICE)
	_notes_box = VBoxContainer.new()
	_notes_box.add_theme_constant_override("separation", 8)
	col.add_child(_notes_box)
	_set_game(_game)


func _set_game(g: String) -> void:
	_game = g
	for k in _game_buttons:
		(_game_buttons[k] as Button).set_pressed_no_signal(k == g)


## Typing a stake must not walk the player (ChatInputGuard lifts gameplay keys meanwhile).
func _guard() -> void:
	if not ChatInputGuard.is_suspended():
		ChatInputGuard.suspend()
		_guarded = true


func _unguard() -> void:
	if _guarded:
		_guarded = false
		ChatInputGuard.restore()


# --- Contents --------------------------------------------------------------------------

func _rebuild() -> void:
	var b := Invites.blocker()
	var net := get_node("/root/Net")
	_status.text = b if b != "" else "Online · %s · signed in as %s" % [String(net.client.server_name), NetMatch.short(Invites.me())]
	_status.add_theme_color_override("font_color", Color("#ffd27a") if b != "" else DeepFieldTheme.MUTED)
	_sign_in.visible = net.client != null and net.client.is_online() and net.client.wallet == "" and net.client.features.has("invites")
	_build_online(b)
	_build_notes()


func _build_online(b: String) -> void:
	for c in _online_box.get_children():
		c.queue_free()
	if b != "":
		_online_note.text = "Invites need the game server: %s" % b if not b.begins_with("Invites") else b
		return
	match Invites.online_state:
		"loading":
			_online_note.text = "Asking the server who is online…"
		"ok":
			_online_note.text = "Nobody else is signed in right now." if Invites.online.is_empty() else "%d signed in (guests are not listed):" % Invites.online.size()
		_:
			_online_note.text = "Who is online: %s" % Invites.online_state
	for r in Invites.online:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_online_box.add_child(row)
		var l := Label.new()
		l.theme_type_variation = "MonoLabel"
		l.add_theme_font_size_override("font_size", 12)
		var where := Invites.place_name(String(r.get("room", ""))) if String(r.get("room", "")) != "" else "between places"
		l.text = "%s · %s%s" % [Invites._who(String(r["wallet"]), String(r.get("name", ""))), where, " · in a game" if r.get("busy", false) else ""]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var w := String(r["wallet"])
		_button(row, "Invite: %s" % ("pool" if _game == "pool" else "21"), func(): _invite(w))


func _invite(wallet: String) -> void:
	var err := Invites.invite(wallet, _game, _stake.text)
	_msg.text = err if err != "" else "Invite sent: it expires in %d s if they don't answer." % InviteBook.TTL_S


## Newest first; a game's buttons only on its newest notification.
func _build_notes() -> void:
	for c in _notes_box.get_children():
		c.queue_free()
	if Invites.notes.is_empty():
		_label(_notes_box, "Nothing yet. Invites you send or get, games, stakes and wagers show here (this session).", "MutedLabel", 12)
		return
	var shown_refs := {}
	var now := int(Time.get_unix_time_from_system())
	for i in range(Invites.notes.size() - 1, -1, -1):
		var x: Dictionary = Invites.notes[i]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		_notes_box.add_child(box)
		var top := Label.new()
		top.theme_type_variation = "MutedLabel"
		top.add_theme_font_size_override("font_size", 11)
		top.text = "%s · %s" % [_ago(now - int(x["at"])), String(x["kind"]).to_upper()]
		box.add_child(top)
		_label(box, String(x["text"]), "MonoLabel", 12, DeepFieldTheme.INK if not x["read"] else Color(0, 0, 0, 0))
		var key := _match_of(x)
		if key == "" or shown_refs.has(key):
			continue
		shown_refs[key] = true
		_actions(box, x, now)


func _ago(s: int) -> String:
	if s < 60:
		return "%d s ago" % s
	if s < 3600:
		return "%d min ago" % (s / 60)
	return "%d h ago" % (s / 3600)


## The invite or game a notification is about (for its buttons).
func _match_of(x: Dictionary) -> String:
	var ref := String(x.get("ref", ""))
	if ref == "":
		return ""
	if Invites.invites.has(ref):
		var inv: Dictionary = Invites.invites[ref]
		return ("m:" + String(inv["match"])) if String(inv.get("match", "")) != "" else ("i:" + ref)
	return ("m:" + ref) if Invites.matches.has(ref) else ""


func _actions(box: VBoxContainer, x: Dictionary, now: int) -> void:
	var key := _match_of(x)
	var me := Invites.me()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if key.begins_with("i:"):
		var inv: Dictionary = Invites.invites[key.substr(2)]
		if inv["state"] == "pending":
			var left := InviteBook.seconds_left(inv, now)
			if inv["to"] == me:
				var id := String(inv["id"])
				_button(row, "Accept%s" % ((" · stake %s Ⓐ" % inv["stake"]) if inv["stake"] != "" else ""), func():
					Invites.answer(id, "accept")
					_msg.text = "Accepted: to the table…")
				_button(row, "Decline", func(): Invites.answer(id, "decline"))
			elif inv["from"] == me:
				var id := String(inv["id"])
				_button(row, "Cancel", func(): Invites.answer(id, "cancel"))
			_label(box, "expires in %d s" % left, "MutedLabel", 11)
	elif key.begins_with("m:"):
		var mid := key.substr(2)
		var m := Invites.match_dict(mid)
		if m.is_empty():
			return
		var mine := (m["players"] as Array).find(me)
		var line := "#%s · %s · %s vs %s · %s" % [mid, InviteBook.title_of(m["kind"]), Invites.display(m["players"][0]), Invites.display(m["players"][1]), _state_text(m, mine)]
		_label(box, line, "MonoLabel", 11, DeepFieldTheme.ICE)
		var wager := Wager.code(m)
		if wager != "none":
			var wl := _label(box, "Wager: " + Wager.text(m, me, Invites.display) + (" (%s)" % m["check_note"] if String(m.get("check_note", "")) != "" else ""), "MonoLabel", 11,
				Color("#7dffa8") if wager == "paid" else (Color("#ff8a8a") if wager == "unpaid" else Color("#ffd27a")))
			wl.name = "Wager"
		if mine >= 0 and m["status"] == "confirm" and not m["stake_ok"][mine]:
			_button(row, "Confirm the %s stake" % NetMatch.fmt(m["stake"]), func(): Invites.confirm_stake(mid, true))
			_button(row, "Play without a stake", func(): Invites.confirm_stake(mid, false))
		if mine >= 0 and m["status"] in ["confirm", "playing"] and not m.get("abandoned", false):
			_button(row, "Go to the table", func():
				close()
				Invites.go_to_table(mid))
			_button(row, "Concede", func(): Invites.send_move(mid, "concede"))
			var nmo: NetMatch = Invites.matches.get(mid)
			if nmo and nmo.claimable_by(mine, int(Time.get_unix_time_from_system() * 1000.0)):
				_button(row, "Claim (idle %d min)" % (NetMatch.IDLE_CLAIM_MS / 60000), func(): Invites.send_move(mid, "claim"))
		if mine >= 0 and String(m["loser"]) == me and wager in ["owed", "unpaid"]:
			_button(row, "Pay %s to %s" % [NetMatch.fmt(m["stake"]), Invites.display(m["winner"])], func(): _pay(mid))
		if wager in ["owed", "unpaid"]:
			_button(row, "Check the chain again", func(): Invites.check_wager(mid))
	if row.get_child_count() > 0:
		box.add_child(row)


func _state_text(m: Dictionary, mine: int) -> String:
	if m.get("abandoned", false):
		return "abandoned"
	match String(m["status"]):
		"confirm":
			return "confirming the stake"
		"playing":
			if String(m.get("waiting", "")) != "":
				return "waiting for " + String(m["waiting"]).split(":")[0]
			var t := NetMatch.turn_of(m)
			return ("your move" if t == mine else "%s to move" % Invites.display(m["players"][t])) if t >= 0 else "playing"
		"over":
			if m["push"]:
				return "push"
			var who := "you" if mine >= 0 and m["winner"] == m["players"][mine] else Invites.display(m["winner"])
			return "%s won%s" % [who, " · both tables agree" if m.get("agreed", false) else ""]
	return String(m["status"])


func _pay(mid: String) -> void:
	_msg.text = "Paying through your wallet: simulate, sign, then the receipt is checked…"
	var r: Dictionary = await Invites.pay(mid)
	_msg.text = ("Paid in block %d: the Transfer log is re-read from the chain." % int(r["block"])) if r.get("ok", false) \
		else "Not paid (%s): %s" % [String(r.get("stage", "?")), String(r.get("message", ""))]


## The bell: a small drawn bell, gold with a count when something is unread.
class Bell extends Button:
	var count := 0
	var online := false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(42, 42)

	func _draw() -> void:
		var base := Color("#ffd36b") if count > 0 else (DeepFieldTheme.ICE if online else DeepFieldTheme.MUTED)
		draw_circle(Vector2(21, 21), 20, Color(DeepFieldTheme.BLACK, 0.72))
		draw_arc(Vector2(21, 21), 20, 0, TAU, 32, Color(base, 0.55), 1.5, true)
		draw_circle(Vector2(21, 15), 6.5, base)
		draw_colored_polygon(PackedVector2Array([Vector2(14.5, 15), Vector2(27.5, 15), Vector2(30, 27), Vector2(12, 27)]), base)
		draw_rect(Rect2(10, 26, 22, 3), base)
		draw_circle(Vector2(21, 31.5), 2.6, base)
		draw_circle(Vector2(21, 8), 1.6, base)
		if count > 0:
			var txt := str(count) if count < 100 else "99+"
			draw_circle(Vector2(34, 9), 9, Color("#ff4fd8"))
			var f := DeepFieldTheme.mono_font()
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(f, Vector2(34 - w / 2.0, 13), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
