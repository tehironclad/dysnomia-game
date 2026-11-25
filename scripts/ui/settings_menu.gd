extends PanelContainer
## Settings (WP 7.4). Every control here changes something real: graphics
## quality (SSAO/SSIL/fog/MSAA/shadow distance), render distance (camera far
## plane), display mode and vsync, mouse and FOV, the Master/Music/SFX buses,
## and where the chain is read from. Apply saves and applies at once.

signal settings_closed

var _quality: OptionButton
var _auto: CheckBox
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
var _browser: LineEdit
var _note: Label
var _perf_mode: CheckBox
var _dynamic: CheckBox
var _target: OptionButton
var _gpu: Label
var _live: Label
var _cal: Label
var _live_t := 0.0
var _scroll: ScrollContainer
var _col: VBoxContainer
const EDGE_PX := 16.0  ## kept clear around the panel when the window is short
const TOP_PX := 44.0   ## and clear of the wallet chip (top centre)
const TARGETS := [0, 30, 60, 120]  ## frame-rate target choices (0 = automatic)


func _ready() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.96
	add_theme_stylebox_override("panel", sb)
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(560, 0)
	position = Vector2(-280, -300)
	# Scrolls when the window is shorter than the panel (720p laptops: Apply/Close were
	# below the bottom edge and out of reach; audit 2026-11-25).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(col)
	_col = col
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 20)
	title.text = "SETTINGS"
	col.add_child(title)
	var ver := Label.new()  # this build (release.yml writes application/config/version)
	ver.theme_type_variation = "MutedLabel"
	var cur := UpdateCheck.current_version()
	ver.text = ("Dysnomia %s · new versions: %s" % [cur, UpdateCheck.DOWNLOAD_PAGE]) if cur != "" else "Dysnomia · dev build"
	col.add_child(ver)
	var who := Label.new()  # who made it (About)
	who.theme_type_variation = "MutedLabel"
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.text = About.COMMUNITY_NOTICE
	col.add_child(who)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	col.add_child(grid)
	_quality = OptionButton.new()
	for n in Config.QUALITY_NAMES:
		_quality.add_item(n)
	_row(grid, "Graphics quality", _quality)
	_auto = _check(grid, "Adjust graphics automatically")
	_quality.item_selected.connect(func(_i): _auto.button_pressed = false)  # a level picked by hand stays
	_perf_mode = _check(grid, "Performance mode (frame rate first)")
	_perf_mode.tooltip_text = "Low at most; the resolution drops before the frame rate does. For weak or hot laptops."
	_dynamic = _check(grid, "Dynamic resolution (hold the frame rate)")
	_target = OptionButton.new()
	for t in TARGETS:
		_target.add_item("Automatic" if t == 0 else "%d fps" % t)
	_row(grid, "Frame-rate target", _target)
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
	_browser = LineEdit.new()
	_browser.placeholder_text = "blank = automatic (your default browser)"
	_browser.tooltip_text = "The browser that has your wallet extension, e.g. C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
	_row(grid, "Wallet browser (.exe)", _browser)
	_note = Label.new()
	_note.theme_type_variation = "MutedLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(520, 0)
	_note.text = _detected_line() + "Potato and Low render at about half resolution (upscaled), with a shorter view, a coarser ground, fewer visitors and no shadows: for integrated graphics. The chain is the source of truth; the site accelerator only speeds up a few reads. RPC and port changes apply to new requests and the next wallet connection."
	col.add_child(_note)
	_build_graphics_status(col)
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
	var net_btn := Button.new()  # Online & voice (Net): the game server, sign-in, mic, mutes
	net_btn.text = "Online & voice…"
	net_btn.pressed.connect(_open_net)
	row.add_child(net_btn)
	var wallet_btn := Button.new()  # the payment path, step by step (WalletDiagnosis)
	wallet_btn.text = "Test my wallet…"
	wallet_btn.pressed.connect(_open_wallet_test)
	row.add_child(wallet_btn)
	_load_from_config()


## What the graphics are doing right now: the GPU and renderer in use, the level, the
## render scale and the measured frame rate (live), the last calibration, and its buttons.
func _build_graphics_status(col: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	col.add_child(box)
	_gpu = Label.new()
	_gpu.theme_type_variation = "MutedLabel"
	_gpu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gpu.custom_minimum_size = Vector2(520, 0)
	box.add_child(_gpu)
	_live = Label.new()
	_live.theme_type_variation = "MonoLabel"
	box.add_child(_live)
	_cal = Label.new()
	_cal.theme_type_variation = "MutedLabel"
	_cal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cal.custom_minimum_size = Vector2(520, 0)
	box.add_child(_cal)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var recal := Button.new()
	recal.text = "Recalibrate"
	recal.tooltip_text = "Measure this computer again (a few seconds, here): the level that holds the frame-rate target is kept."
	recal.pressed.connect(_recalibrate)
	row.add_child(recal)
	var other := Button.new()
	var cur := RenderingServer.get_current_rendering_method()
	other.text = "Try %s…" % ("Forward+" if cur == "gl_compatibility" else "Compatibility")
	other.tooltip_text = "Restart with the other renderer and measure it; the faster one is kept."
	other.pressed.connect(func(): Config.try_other_renderer())
	row.add_child(other)
	_refresh_status()


func _refresh_status() -> void:
	if _gpu == null:
		return
	_gpu.text = "GPU in use: %s" % Config.gpu_line() + ("\n" + Config.hybrid_hint if Config.hybrid_hint != "" else "")
	_live.text = Config.status_line()
	var recs := []
	for r in Config.calib_records:
		var rec: Dictionary = Config.calib_records[r]
		recs.append("%s: %s, %.1f ms" % [Config.renderer_label(String(r)).split(" ")[0], String(Config.QUALITY_NAMES[int(rec.get("level", 0))]).split(" ")[0], float(rec.get("cost_ms", 0.0))])
	if Config.is_calibrating():
		_cal.text = "Measuring…"
	elif Config.calib_note != "":
		_cal.text = "Last calibration: %s%s" % [Config.calib_note, (" · by renderer: " + "; ".join(recs)) if recs.size() > 1 else ""]
	else:
		_cal.text = "Not measured yet: the next territory arrival measures this computer."


func _process(delta: float) -> void:
	if not visible:
		return
	_live_t -= delta
	if _live_t <= 0.0:
		_live_t = 0.5
		_refresh_status()


func _recalibrate() -> void:
	var run := Config.recalibrate()
	if run == null:
		_note.text = "Calibration runs on the next territory arrival."
		return
	_note.text = "Measuring… (a few seconds; the picture changes as levels are tried)"
	run.finished.connect(func(_l, _f, _r):
		_load_from_config()
		_note.text = "Measured: " + Config.calib_note)


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
	s.value_changed.connect(func(x: float): v.text = slider_text(x, hi, step))
	_row(grid, label, h)
	return s


## Pure: a slider's value as shown beside it. Volumes (0–1 in 0.05 steps) are percentages;
## fine steps (mouse sensitivity, 0.0005) show their digits, not "0%".
static func slider_text(x: float, hi: float, step: float) -> String:
	if step < 0.01:
		return "%.4f" % x
	if hi <= 1.0:
		return "%.0f%%" % (x * 100.0)
	return "%.0f" % x


func _detected_line() -> String:
	return ("This PC: %s. Automatic starts from it, measures this computer on arrival, holds the frame rate with the render resolution, then steps levels (Ultra only if measured with lots of headroom); picking a level turns it off.\n" % Config.detected) if Config.detected != "" else ""


func _load_from_config() -> void:
	_quality.select(clampi(Config.graphics_quality, 0, Config.QUALITY_NAMES.size() - 1))
	_auto.button_pressed = Config.auto_quality
	_perf_mode.button_pressed = Config.performance_mode
	_dynamic.button_pressed = Config.dynamic_resolution
	_target.select(maxi(0, TARGETS.find(Config.target_fps_setting)))
	_refresh_status()
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
	_browser.text = Config.wallet_browser


func _apply() -> void:
	Config.graphics_quality = _quality.selected
	Config.auto_quality = _auto.button_pressed
	Config.performance_mode = _perf_mode.button_pressed
	Config.dynamic_resolution = _dynamic.button_pressed
	Config.target_fps_setting = TARGETS[maxi(0, _target.selected)]
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
	if Rpc.url_ok(rpc):  # https://, or http:// to this computer only
		Config.rpc_url = rpc
	Config.site_api_enabled = _site_on.button_pressed
	Config.site_api_base = _site.text.strip_edges()
	Config.wallet_bridge_port = int(_port.value)
	Config.wallet_browser = _browser.text.strip_edges().replace("\\", "/").trim_prefix("\"").trim_suffix("\"")
	Config.save_settings()
	Config.apply()
	Chain.apply_config()
	_note.text = "Applied and saved."


var _net: NetSettingsPanel
var _wallet_test: WalletTestPanel


func _open_wallet_test() -> void:
	if _wallet_test == null:
		_wallet_test = WalletTestPanel.new()
		add_child(_wallet_test)
		_wallet_test.top_level = true
	_wallet_test.visible = true
	await get_tree().process_frame
	_wallet_test.global_position = ((get_viewport_rect().size - _wallet_test.size) * 0.5).max(Vector2.ZERO)
	_wallet_test.run()


func _open_net() -> void:
	if _net == null:
		_net = NetSettingsPanel.new()
		add_child(_net)
		_net.top_level = true
	_net.visible = true
	await get_tree().process_frame
	_net.global_position = ((get_viewport_rect().size - _net.size) * 0.5).max(Vector2.ZERO)


func show_menu() -> void:
	_load_from_config()
	visible = true
	# Centre in the window (works whether the parent is a Control or a CanvasLayer).
	await get_tree().process_frame
	_fit()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## As tall as the content, at most the window's height (then it scrolls); centred.
func _fit() -> void:
	var vp := get_viewport_rect().size
	_scroll.custom_minimum_size.y = minf(_col.get_combined_minimum_size().y, maxf(200.0, vp.y - TOP_PX - EDGE_PX - 16.0))
	reset_size()
	var at := ((vp - size) * 0.5).max(Vector2.ZERO)
	at.y = clampf(at.y, minf(TOP_PX, maxf(0.0, vp.y - size.y)), maxf(0.0, vp.y - size.y))
	global_position = at


func hide_menu() -> void:
	visible = false
