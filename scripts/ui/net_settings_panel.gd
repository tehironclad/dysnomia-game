class_name NetSettingsPanel
extends PanelContainer
## Settings → "Online & voice" (Net): the game server, sign-in, the mic
## (off by default, push-to-talk), voice volume and the local mute list; and
## Notifications (Alerts' AlertPrefs): each alert kind, the sound, the taskbar flash.

var _online: CheckBox
var _url: LineEdit
var _status: Label
var _sign: Button
var _mic: CheckBox
var _device: OptionButton
var _volume: HSlider
var _mute_all: CheckBox
var _people: VBoxContainer
var _alert_boxes := {}  # kind | "sound" | "flash" → CheckBox


func _ready() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.97
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(560, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 20)
	title.text = "ONLINE & VOICE"
	col.add_child(title)
	_status = Label.new()
	_status.theme_type_variation = "MonoLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 0)
	col.add_child(_status)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	col.add_child(grid)
	_online = CheckBox.new()
	_row(grid, "Play online (see others, chat)", _online)
	_url = LineEdit.new()
	_url.placeholder_text = "blank = automatic (from the site)"
	_url.custom_minimum_size = Vector2(300, 0)
	_row(grid, "Game server", _url)
	_mic = CheckBox.new()
	_row(grid, "Microphone (hold %s to talk)" % ControlsHelp.key_of("push_to_talk"), _mic)
	_device = OptionButton.new()
	_row(grid, "Mic device", _device)
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.custom_minimum_size = Vector2(220, 0)
	_row(grid, "Voice volume", _volume)
	_mute_all = CheckBox.new()
	_row(grid, "Mute everyone else", _mute_all)
	var note := Label.new()
	note.theme_type_variation = "MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(520, 0)
	note.text = "Guests see everyone. With a wallet connected the game signs in by itself (once: a free signature, not a transaction), so others see your LAU name and you can talk. Chat (the chat bar, %s, Tab: say) and voice here are not on chain. Mutes stay on this computer." % ControlsHelp.key_of("chat")
	col.add_child(note)
	_people = VBoxContainer.new()
	col.add_child(_people)
	_build_alerts(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_sign = Button.new()
	_sign.text = "Sign in (one free signature)"
	_sign.tooltip_text = "So others see your LAU name instead of \"guest\". Not a transaction. The game signs in by itself once a wallet is connected, unless you said no."
	_sign.pressed.connect(func(): Net.sign_in())
	row.add_child(_sign)
	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(_apply)
	row.add_child(apply_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): visible = false)
	row.add_child(close_btn)
	_load()


## Notifications: saved at once (user://alerts.cfg), no Apply needed.
func _build_alerts(col: VBoxContainer) -> void:
	col.add_child(HSeparator.new())
	var t := Label.new()
	t.theme_type_variation = "DisplayLabel"
	t.add_theme_font_size_override("font_size", DeepFieldTheme.FS_LEAD)
	t.text = "NOTIFICATIONS"
	col.add_child(t)
	var note := Label.new()
	note.theme_type_variation = "MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(520, 0)
	note.text = "A toast, the bell (%s) and a short sound. Repeats merge; your own lines never alert. Saved on this computer at once." % ControlsHelp.key_of("notifications")
	col.add_child(note)
	var prefs: AlertPrefs = Alerts.prefs
	for k in AlertGate.KINDS:
		_alert_box(col, k, String(AlertPrefs.LABELS[k]), prefs.on(k))
	_alert_box(col, "sound", "Sound with an alert", prefs.sound)
	_alert_box(col, "flash", "Flash the taskbar when the game window is not focused", prefs.flash)


func _alert_box(col: VBoxContainer, key: String, text: String, on: bool) -> void:
	var b := CheckBox.new()
	b.text = text
	b.button_pressed = on
	b.toggled.connect(func(v: bool):
		var prefs: AlertPrefs = Alerts.prefs
		match key:
			"sound": prefs.sound = v
			"flash": prefs.flash = v
			_: prefs.set_kind(key, v)
		prefs.save_prefs())
	col.add_child(b)
	_alert_boxes[key] = b


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.theme_type_variation = "MutedLabel"
	l.text = label
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _load() -> void:
	_online.button_pressed = Net.online_enabled
	_url.text = Net.server_url
	_mic.button_pressed = Net.mic_enabled
	_device.clear()
	var devs := AudioServer.get_input_device_list()
	for i in devs.size():
		_device.add_item(devs[i])
		if devs[i] == Net.mic_device:
			_device.select(i)
	_volume.value = Net.voice_volume
	_mute_all.button_pressed = Net.mute_others
	_refresh()


func _refresh() -> void:
	_status.text = Net.status_text()
	_sign.disabled = not Net.can_sign_in()
	for c in _people.get_children():
		c.queue_free()
	var shown := {}
	for w in Net.muted.keys() + Net.heard.keys():
		if shown.has(w):
			continue
		shown[w] = true
		var h := HBoxContainer.new()
		var l := Label.new()
		l.theme_type_variation = "MonoLabel"
		l.text = "%s  %s" % [String(Net.heard.get(w, "")), NetProto.short_wallet(w)]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var b := Button.new()
		b.text = "Unmute" if Net.is_muted(w) else "Mute"
		b.pressed.connect(func():
			if Net.is_muted(w):
				Net.unmute(w)
			else:
				Net.mute(w)
			_refresh())
		h.add_child(b)
		_people.add_child(h)


func _apply() -> void:
	var url_changed := _url.text.strip_edges() != Net.server_url or _online.button_pressed != Net.online_enabled
	Net.online_enabled = _online.button_pressed
	Net.server_url = _url.text.strip_edges()
	Net.mic_enabled = _mic.button_pressed
	if _device.selected >= 0:
		Net.mic_device = _device.get_item_text(_device.selected)
	Net.voice_volume = _volume.value
	Net.mute_others = _mute_all.button_pressed
	Net.save_settings()
	if Net.mic:
		Net.mic.apply_device()
	if url_changed:
		if Net.online_enabled:
			Net.restart()
		else:
			Net.stop()
	_refresh()


var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if visible and _t > 1.0:
		_t = 0.0
		_status.text = Net.status_text()
		_sign.disabled = not Net.can_sign_in()
