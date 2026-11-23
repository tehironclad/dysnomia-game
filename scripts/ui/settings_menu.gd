extends PanelContainer
## Settings (WP 7.4). Every control here changes something real: graphics
## quality (SSAO/SSIL/fog/MSAA/shadow distance), render distance (camera far
## plane), display mode and vsync, mouse and FOV, the Master/Music/SFX buses,
## and where the chain is read from. Apply saves and applies at once.

signal settings_closed

var _quality: OptionButton
var _render: HSlider
var _fullscreen: CheckBox
var _vsync: CheckBox
var _sens: HSlider
var _invert: CheckBox
var _fov: HSlider
var _master: HSlider
var _music: HSlider
var _sfx: HSlider
var _rpc: LineEdit
var _site_on: CheckBox
var _site: LineEdit
var _port: SpinBox
var _note: Label


func _ready() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.96
	add_theme_stylebox_override("panel", sb)
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(560, 0)
	position = Vector2(-280, -300)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 20)
	title.text = "SETTINGS"
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	col.add_child(grid)
	_quality = OptionButton.new()
	for n in Config.QUALITY_NAMES:
		_quality.add_item(n)
	_row(grid, "Graphics quality", _quality)
	_render = _slider(grid, "Render distance (m)", 300.0, 2000.0, 50.0)
	_fullscreen = _check(grid, "Fullscreen")
	_vsync = _check(grid, "V-Sync")
	_sens = _slider(grid, "Mouse sensitivity", 0.0005, 0.01, 0.0005)
	_invert = _check(grid, "Invert Y")
	_fov = _slider(grid, "Field of view", 50.0, 110.0, 1.0)
	_master = _slider(grid, "Master volume", 0.0, 1.0, 0.05)
	_music = _slider(grid, "Music (territory score)", 0.0, 1.0, 0.05)
	_sfx = _slider(grid, "Effects (event cues)", 0.0, 1.0, 0.05)
	_rpc = LineEdit.new()
	_rpc.custom_minimum_size = Vector2(300, 0)
	_row(grid, "PulseChain RPC", _rpc)
	_site_on = _check(grid, "Site accelerator (optional)")
	_site = LineEdit.new()
	_row(grid, "Site base URL", _site)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65000
	_row(grid, "Wallet relay port", _port)
	_note = Label.new()
	_note.theme_type_variation = "MutedLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(520, 0)
	_note.text = "The chain is the source of truth; the site accelerator only speeds up a few reads. RPC and port changes apply to new requests and the next wallet connection."
	col.add_child(_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(_apply)
	row.add_child(apply_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): settings_closed.emit())
	row.add_child(close_btn)
	_load_from_config()


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.theme_type_variation = "MutedLabel"
	l.text = label
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _check(grid: GridContainer, label: String) -> CheckBox:
	var c := CheckBox.new()
	_row(grid, label, c)
	return c


func _slider(grid: GridContainer, label: String, lo: float, hi: float, step: float) -> HSlider:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(220, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(s)
	var v := Label.new()
	v.theme_type_variation = "MonoLabel"
	v.custom_minimum_size = Vector2(64, 0)
	h.add_child(v)
	s.value_changed.connect(func(x: float): v.text = ("%.0f%%" % (x * 100.0)) if hi <= 1.0 else (("%.4f" % x) if step < 0.01 else "%.0f" % x))
	_row(grid, label, h)
	return s


func _load_from_config() -> void:
	_quality.select(clampi(Config.graphics_quality, 0, Config.QUALITY_NAMES.size() - 1))
	_render.value = Config.render_distance
	_fullscreen.button_pressed = Config.fullscreen
	_vsync.button_pressed = Config.vsync
	_sens.value = Config.mouse_sensitivity
	_invert.button_pressed = Config.invert_y
	_fov.value = Config.fov
	_master.value = Config.master_volume
	_music.value = Config.music_volume
	_sfx.value = Config.sfx_volume
	_rpc.text = Config.rpc_url
	_site_on.button_pressed = Config.site_api_enabled
	_site.text = Config.site_api_base
	_port.value = Config.wallet_bridge_port


func _apply() -> void:
	Config.graphics_quality = _quality.selected
	Config.render_distance = _render.value
	Config.fullscreen = _fullscreen.button_pressed
	Config.vsync = _vsync.button_pressed
	Config.mouse_sensitivity = _sens.value
	Config.invert_y = _invert.button_pressed
	Config.fov = _fov.value
	Config.master_volume = _master.value
	Config.music_volume = _music.value
	Config.sfx_volume = _sfx.value
	var rpc := _rpc.text.strip_edges()
	if rpc.begins_with("https://") or rpc.begins_with("http://"):
		Config.rpc_url = rpc
	Config.site_api_enabled = _site_on.button_pressed
	Config.site_api_base = _site.text.strip_edges()
	Config.wallet_bridge_port = int(_port.value)
	Config.save_settings()
	Config.apply()
	Chain.apply_config()
	_note.text = "Applied and saved."


func show_menu() -> void:
	_load_from_config()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func hide_menu() -> void:
	visible = false
