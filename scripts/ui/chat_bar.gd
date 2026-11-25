class_name ChatBar
extends PanelContainer
## The one-line chat bar over gameplay (T). Enter sends, Esc closes (the text
## stays for next time), Up/Down recall sent lines, Tab switches say/post
## when the presence server is there, 1–4 (bar closed) open it with a quick
## line. While it is open no gameplay action fires (ChatInputGuard).
##
## Posting goes through ChatFeed (simulate → sign → receipt → read back), so
## the bar closes at once and you keep playing; the line shows in the feed as
## "signing…" and then "on chain · block N", or why it was not posted, and a
## failed line comes back into the bar.

signal opened
signal closed

const WIDTH := 640.0

var edit: LineEdit
var mode_btn: Button
var note: Label
var status: Label
var join_btn: Button
var hint: Label
var _count: Label
var _kept := ""  # text left in the bar when it was closed
var _seen_failed := {}
var _mouse_before := Input.MOUSE_MODE_CAPTURED


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style(DeepFieldTheme.ICE * Color(1, 1, 1, 0.35))
	sb.bg_color.a = 0.86
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	mode_btn = Button.new()
	mode_btn.focus_mode = Control.FOCUS_NONE
	mode_btn.custom_minimum_size = Vector2(74, 0)
	mode_btn.add_theme_font_override("font", DeepFieldTheme.mono_font())
	mode_btn.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	mode_btn.pressed.connect(func(): ChatFeed.toggle_mode())
	row.add_child(mode_btn)
	edit = LineEdit.new()
	edit.max_length = ChatDraft.MAX_LEN
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_override("font", DeepFieldTheme.mono_font())
	edit.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
	edit.text_submitted.connect(func(_t): send())
	edit.text_changed.connect(func(_t): _update_count())
	edit.gui_input.connect(_on_edit_input)
	edit.context_menu_enabled = false
	row.add_child(edit)
	_count = Label.new()
	_count.theme_type_variation = "MonoLabel"
	_count.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	_count.add_theme_color_override("font_color", DeepFieldTheme.DIM)
	_count.custom_minimum_size = Vector2(52, 0)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_count)
	note = Label.new()
	note.theme_type_variation = "MonoLabel"
	note.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	note.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(WIDTH - 24, 0)
	col.add_child(note)
	status = Label.new()
	status.theme_type_variation = "MonoLabel"
	status.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	status.add_theme_color_override("font_color", Color("#ffd27a"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(WIDTH - 24, 0)
	status.visible = false
	col.add_child(status)
	join_btn = Button.new()
	join_btn.visible = false
	join_btn.focus_mode = Control.FOCUS_NONE
	join_btn.pressed.connect(_join)
	col.add_child(join_btn)
	hint = Label.new()
	hint.theme_type_variation = "MutedLabel"
	hint.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	hint.add_theme_color_override("font_color", DeepFieldTheme.DIM)
	col.add_child(hint)


func _ready() -> void:
	ChatFeed.outbox_changed.connect(_on_outbox)
	ChatFeed.mode_changed.connect(func(_m): _refresh_mode())
	ChatFeed.note_changed.connect(_refresh_mode)
	hint.text = hint_text()


static func hint_text() -> String:
	return "Enter send · Esc close (text kept) · %s/%s recall · %s say/post · %s… quick lines · %s history" % [
		ControlsHelp.key_of("chat_recall_prev"), ControlsHelp.key_of("chat_recall_next"), ControlsHelp.key_of("chat_mode"),
		ControlsHelp.key_of("chat_quick_1"), ControlsHelp.key_of("chat_history")]


func is_open() -> bool:
	return visible


## Opens with `prefill` (a quick line) or what was left in the bar.
func open(prefill: String = "") -> void:
	if not visible:
		_mouse_before = Input.get_mouse_mode()
	visible = true
	ChatInputGuard.suspend()
	edit.text = prefill if prefill != "" else _kept
	edit.caret_column = edit.text.length()
	edit.grab_focus()
	if not ChatFeed.can_say() and ChatFeed.mode == "say":
		ChatFeed.set_mode("post")
	_refresh_mode()
	_update_count()
	_offer_join(_last_join_offer())
	ChatFeed.measure_gas()
	opened.emit()


func close() -> void:
	if not visible:
		return
	_kept = edit.text
	edit.release_focus()
	visible = false
	join_btn.visible = false
	ChatInputGuard.restore()
	Input.set_mouse_mode(_mouse_before)
	closed.emit()


func send() -> void:
	var text := edit.text
	edit.text = ""
	_kept = ""
	var n_before: int = ChatFeed.outbox.entries.size()
	var why: String = ChatFeed.submit(text)
	if why != "":
		_set_text(text)
		_show_status(why)
		return
	# A precondition that fails at once (no wallet, no LAU, view only) keeps the
	# bar open with the reason; the text is already back (_on_outbox).
	var es: Array = ChatFeed.outbox.entries
	if es.size() > n_before and es[-1]["state"] == "failed":
		return
	status.visible = false
	close()


func _on_edit_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		edit.accept_event()
	elif event.is_action_pressed("chat_recall_prev"):
		_set_text(ChatFeed.draft.older(edit.text))
		edit.accept_event()
	elif event.is_action_pressed("chat_recall_next"):
		_set_text(ChatFeed.draft.newer(edit.text))
		edit.accept_event()
	elif event.is_action_pressed("chat_mode"):
		ChatFeed.toggle_mode()
		edit.accept_event()


func _set_text(t: String) -> void:
	edit.text = t
	edit.caret_column = t.length()
	_update_count()


func _update_count() -> void:
	var n := edit.text.length()
	_count.text = "%d/%d" % [n, ChatDraft.MAX_LEN]
	_count.add_theme_color_override("font_color", Color("#ffd27a") if n > ChatDraft.MAX_LEN - 20 else DeepFieldTheme.DIM)


func _refresh_mode() -> void:
	var say: bool = ChatFeed.mode == "say"
	mode_btn.text = "SAY" if say else "POST"
	mode_btn.disabled = not ChatFeed.can_say()
	mode_btn.tooltip_text = "Tab: say (free, not on chain) / post (on chain)" if ChatFeed.can_say() else "Posting only: no presence server here, so every line is a room line on chain."
	mode_btn.add_theme_color_override("font_color", DeepFieldTheme.MUTED if say else DeepFieldTheme.ICE)
	mode_btn.add_theme_color_override("font_disabled_color", DeepFieldTheme.ICE)
	note.text = ChatFeed.say_note() if say else ChatFeed.post_note()
	var room := ""
	if ChatFeed.current:
		room = String(ChatFeed.current.territory.get("name", ChatFeed.current.qing))
	edit.placeholder_text = ("say something to everyone here (free)" if say else "a line to %s, written on chain forever" % room)


func _show_status(t: String) -> void:
	status.text = t
	status.visible = t != ""


## A newly failed line goes back into the bar (or waits in history when the
## bar holds other text) with its reason.
func _on_outbox() -> void:
	for e in ChatFeed.outbox.entries:
		if e["state"] != "failed" or _seen_failed.has(e["id"]):
			continue
		_seen_failed[e["id"]] = true
		_kept = ChatDraft.restore(edit.text if visible else _kept, e["text"])
		if visible:
			_set_text(_kept)
			_show_status(ChatOutbox.status_text(e))
			_offer_join(e)


func _last_join_offer() -> Dictionary:
	var es: Array = ChatFeed.outbox.entries
	for i in range(es.size() - 1, -1, -1):
		var e: Dictionary = es[i]
		if e["state"] == "failed":
			return e if e["kind"] == "join" else {}
		if e["state"] == "posted":
			return {}
	return {}


func _offer_join(e: Dictionary) -> void:
	var r: RoomState = ChatFeed.last_room
	var show: bool = not e.is_empty() and e.get("kind", "") == "join" and r != null and r.ok and not r.admitted
	join_btn.visible = show
	if show:
		var steps := r.join_steps()
		join_btn.text = "Join %s · cover %s · %d approval%s · admitted for a day" % [
			String(Registry.get_territory(r.qing).get("name", "")), r.fmt(r.cover), steps.size(), "" if steps.size() == 1 else "s"]
		join_btn.disabled = not r.can_afford() or ChatController._signer_blocker() != ""
		if not r.can_afford():
			_show_status("You hold %s; the cover is %s." % [r.fmt(r.balance), r.fmt(r.cover)])
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)  # the Join button wants a click


func _join() -> void:
	join_btn.disabled = true
	_show_status("Joining: approve in the wallet…")
	var msg: String = await ChatFeed.join()
	_show_status(msg)
	join_btn.visible = ChatFeed.last_room != null and not ChatFeed.last_room.admitted
	join_btn.disabled = false
	if visible:
		edit.grab_focus()
