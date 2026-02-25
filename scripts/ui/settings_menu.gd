extends PanelContainer
## In-game settings menu with tabs for Graphics, Controls, Audio, and Chain.
## Opens via F9 in HUD or Settings button in main menu.

signal settings_closed

var _tab_container: TabContainer
var _quality_dropdown: OptionButton
var _render_dist_slider: HSlider
var _render_dist_label: Label
var _fullscreen_check: CheckBox
var _vsync_check: CheckBox
var _screen_effects_check: CheckBox
var _helmet_hud_check: CheckBox
var _minimap_check: CheckBox
var _sensitivity_slider: HSlider
var _sensitivity_label: Label
var _invert_y_check: CheckBox
var _fov_slider: HSlider
var _fov_label: Label
var _master_slider: HSlider
var _master_label: Label
var _sfx_slider: HSlider
var _sfx_label: Label
var _ambient_slider: HSlider
var _ambient_label: Label
var _rpc_input: LineEdit
var _port_input: SpinBox


func _ready() -> void:
	_build_ui()
	_load_from_config()


func _build_ui() -> void:
	# Main panel styling
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.06, 0.10, 0.96)
	panel_style.set_corner_radius_all(10)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.3, 0.7, 0.7)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", panel_style)

	# Size and position (centered, 520x560)
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(520, 560)
	size = Vector2(520, 560)
	position = Vector2(-260, -280)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer_vbox)

	# Header
	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.65, 0.55, 0.98))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	outer_vbox.add_child(spacer)

	# Tab container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_tab_container)

	_tab_container.add_child(_build_graphics_tab())
	_tab_container.add_child(_build_controls_tab())
	_tab_container.add_child(_build_audio_tab())
	_tab_container.add_child(_build_chain_tab())

	# Bottom buttons
	var btn_spacer := Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 8)
	outer_vbox.add_child(btn_spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	outer_vbox.add_child(btn_row)

	var apply_btn := Button.new()
	apply_btn.text = "Apply & Save"
	apply_btn.custom_minimum_size = Vector2(120, 36)
	apply_btn.pressed.connect(_on_apply)
	btn_row.add_child(apply_btn)

	var close_btn2 := Button.new()
	close_btn2.text = "Close"
	close_btn2.custom_minimum_size = Vector2(80, 36)
	close_btn2.pressed.connect(_on_close)
	btn_row.add_child(close_btn2)


func _build_graphics_tab() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Graphics"
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Quality preset
	var q_row := _make_row("Quality Preset")
	vbox.add_child(q_row)
	_quality_dropdown = OptionButton.new()
	_quality_dropdown.add_item("Low", 0)
	_quality_dropdown.add_item("Medium", 1)
	_quality_dropdown.add_item("High", 2)
	_quality_dropdown.add_item("Ultra", 3)
	_quality_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_row.add_child(_quality_dropdown)

	# Render distance
	var rd_row := _make_row("Render Distance")
	vbox.add_child(rd_row)
	var rd_box := VBoxContainer.new()
	rd_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rd_row.add_child(rd_box)
	_render_dist_slider = HSlider.new()
	_render_dist_slider.min_value = 100.0
	_render_dist_slider.max_value = 1000.0
	_render_dist_slider.step = 50.0
	_render_dist_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_render_dist_slider.value_changed.connect(func(v: float): _render_dist_label.text = "%.0fm" % v)
	rd_box.add_child(_render_dist_slider)
	_render_dist_label = Label.new()
	_render_dist_label.add_theme_font_size_override("font_size", 12)
	_render_dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	rd_box.add_child(_render_dist_label)

	# Fullscreen
	var fs_row := _make_row("Fullscreen")
	vbox.add_child(fs_row)
	_fullscreen_check = CheckBox.new()
	fs_row.add_child(_fullscreen_check)

	# VSync
	var vs_row := _make_row("VSync")
	vbox.add_child(vs_row)
	_vsync_check = CheckBox.new()
	vs_row.add_child(_vsync_check)

	# Screen effects
	var se_row := _make_row("Screen Effects")
	vbox.add_child(se_row)
	_screen_effects_check = CheckBox.new()
	se_row.add_child(_screen_effects_check)

	# Helmet HUD
	var hh_row := _make_row("Helmet HUD Overlay")
	vbox.add_child(hh_row)
	_helmet_hud_check = CheckBox.new()
	hh_row.add_child(_helmet_hud_check)

	# Mini-map
	var mm_row := _make_row("Mini-Map")
	vbox.add_child(mm_row)
	_minimap_check = CheckBox.new()
	mm_row.add_child(_minimap_check)

	return scroll


func _build_controls_tab() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Mouse sensitivity
	var ms_row := _make_row("Mouse Sensitivity")
	vbox.add_child(ms_row)
	var ms_box := VBoxContainer.new()
	ms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ms_row.add_child(ms_box)
	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = 0.001
	_sensitivity_slider.max_value = 0.01
	_sensitivity_slider.step = 0.0005
	_sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sensitivity_slider.value_changed.connect(func(v: float): _sensitivity_label.text = "%.4f" % v)
	ms_box.add_child(_sensitivity_slider)
	_sensitivity_label = Label.new()
	_sensitivity_label.add_theme_font_size_override("font_size", 12)
	_sensitivity_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	ms_box.add_child(_sensitivity_label)

	# Invert Y
	var iy_row := _make_row("Invert Y Axis")
	vbox.add_child(iy_row)
	_invert_y_check = CheckBox.new()
	iy_row.add_child(_invert_y_check)

	# FOV
	var fov_row := _make_row("Field of View")
	vbox.add_child(fov_row)
	var fov_box := VBoxContainer.new()
	fov_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fov_row.add_child(fov_box)
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 50.0
	_fov_slider.max_value = 110.0
	_fov_slider.step = 5.0
	_fov_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fov_slider.value_changed.connect(func(v: float): _fov_label.text = "%.0f°" % v)
	fov_box.add_child(_fov_slider)
	_fov_label = Label.new()
	_fov_label.add_theme_font_size_override("font_size", 12)
	_fov_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	fov_box.add_child(_fov_label)

	return scroll


func _build_audio_tab() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Audio"
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Master volume
	var mv_row := _make_row("Master Volume")
	vbox.add_child(mv_row)
	var mv_box := VBoxContainer.new()
	mv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv_row.add_child(mv_box)
	_master_slider = HSlider.new()
	_master_slider.min_value = 0.0
	_master_slider.max_value = 1.0
	_master_slider.step = 0.05
	_master_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_master_slider.value_changed.connect(func(v: float): _master_label.text = "%.0f%%" % (v * 100))
	mv_box.add_child(_master_slider)
	_master_label = Label.new()
	_master_label.add_theme_font_size_override("font_size", 12)
	_master_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	mv_box.add_child(_master_label)

	# SFX volume
	var sfx_row := _make_row("SFX Volume")
	vbox.add_child(sfx_row)
	var sfx_box := VBoxContainer.new()
	sfx_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_row.add_child(sfx_box)
	_sfx_slider = HSlider.new()
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.05
	_sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sfx_slider.value_changed.connect(func(v: float): _sfx_label.text = "%.0f%%" % (v * 100))
	sfx_box.add_child(_sfx_slider)
	_sfx_label = Label.new()
	_sfx_label.add_theme_font_size_override("font_size", 12)
	_sfx_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	sfx_box.add_child(_sfx_label)

	# Ambient volume
	var amb_row := _make_row("Ambient Volume")
	vbox.add_child(amb_row)
	var amb_box := VBoxContainer.new()
	amb_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amb_row.add_child(amb_box)
	_ambient_slider = HSlider.new()
	_ambient_slider.min_value = 0.0
	_ambient_slider.max_value = 1.0
	_ambient_slider.step = 0.05
	_ambient_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ambient_slider.value_changed.connect(func(v: float): _ambient_label.text = "%.0f%%" % (v * 100))
	amb_box.add_child(_ambient_slider)
	_ambient_label = Label.new()
	_ambient_label.add_theme_font_size_override("font_size", 12)
	_ambient_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	amb_box.add_child(_ambient_label)

	return scroll


func _build_chain_tab() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Chain"
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# RPC URL
	var rpc_row := _make_row("RPC URL")
	vbox.add_child(rpc_row)
	_rpc_input = LineEdit.new()
	_rpc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rpc_input.placeholder_text = "https://rpc.pulsechain.com"
	rpc_row.add_child(_rpc_input)

	# Wallet bridge port
	var port_row := _make_row("Wallet Bridge Port")
	vbox.add_child(port_row)
	_port_input = SpinBox.new()
	_port_input.min_value = 1024
	_port_input.max_value = 65535
	_port_input.step = 1
	_port_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(_port_input)

	# Info label
	var info := Label.new()
	info.text = "\nChanges to RPC URL and Wallet Port\ntake effect after restarting the game."
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(info)

	return scroll


func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 36)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	row.add_child(lbl)
	return row


func _load_from_config() -> void:
	_quality_dropdown.selected = clampi(Config.graphics_quality, 0, 3)
	_render_dist_slider.value = Config.render_distance
	_render_dist_label.text = "%.0fm" % Config.render_distance
	_fullscreen_check.button_pressed = Config.fullscreen
	_vsync_check.button_pressed = Config.vsync
	_screen_effects_check.button_pressed = Config.screen_effects_enabled
	_helmet_hud_check.button_pressed = Config.helmet_hud_enabled
	_minimap_check.button_pressed = Config.minimap_enabled
	_sensitivity_slider.value = Config.mouse_sensitivity
	_sensitivity_label.text = "%.4f" % Config.mouse_sensitivity
	_invert_y_check.button_pressed = Config.invert_y
	_fov_slider.value = Config.fov
	_fov_label.text = "%.0f" % Config.fov + "\u00b0"
	_master_slider.value = Config.master_volume
	_master_label.text = "%.0f%%" % (Config.master_volume * 100)
	_sfx_slider.value = Config.sfx_volume
	_sfx_label.text = "%.0f%%" % (Config.sfx_volume * 100)
	_ambient_slider.value = Config.ambient_volume
	_ambient_label.text = "%.0f%%" % (Config.ambient_volume * 100)
	_rpc_input.text = Config.rpc_url
	_port_input.value = Config.wallet_bridge_port


func _on_apply() -> void:
	# Write to Config
	Config.graphics_quality = _quality_dropdown.selected
	Config.render_distance = _render_dist_slider.value
	Config.fullscreen = _fullscreen_check.button_pressed
	Config.vsync = _vsync_check.button_pressed
	Config.screen_effects_enabled = _screen_effects_check.button_pressed
	Config.helmet_hud_enabled = _helmet_hud_check.button_pressed
	Config.minimap_enabled = _minimap_check.button_pressed
	Config.mouse_sensitivity = _sensitivity_slider.value
	Config.invert_y = _invert_y_check.button_pressed
	Config.fov = _fov_slider.value
	Config.master_volume = _master_slider.value
	Config.sfx_volume = _sfx_slider.value
	Config.ambient_volume = _ambient_slider.value
	Config.rpc_url = _rpc_input.text
	Config.wallet_bridge_port = int(_port_input.value)

	# Apply live effects
	_apply_graphics_live()
	_apply_audio_live()

	# Save
	Config.save_settings()


func _apply_graphics_live() -> void:
	# Fullscreen
	if Config.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# VSync
	if Config.vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Quality preset — apply to active environment if available
	var viewport := get_viewport()
	if viewport:
		var world_env: WorldEnvironment = _find_world_environment(viewport.get_tree().root)
		if world_env and world_env.environment:
			Config.apply_quality_to_environment(world_env.environment)
		var sun: DirectionalLight3D = _find_directional_light(viewport.get_tree().root)
		if sun:
			Config.apply_quality_to_sun(sun)

	# FOV — apply to active camera
	var camera := get_viewport().get_camera_3d() if get_viewport() else null
	if camera:
		camera.fov = Config.fov


func _apply_audio_live() -> void:
	# Master volume (linear to dB)
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		if Config.master_volume <= 0.0:
			AudioServer.set_bus_mute(master_idx, true)
		else:
			AudioServer.set_bus_mute(master_idx, false)
			AudioServer.set_bus_volume_db(master_idx, linear_to_db(Config.master_volume))


func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var result := _find_world_environment(child)
		if result:
			return result
	return null


func _find_directional_light(node: Node) -> DirectionalLight3D:
	if node is DirectionalLight3D:
		return node
	for child in node.get_children():
		var result := _find_directional_light(child)
		if result:
			return result
	return null


func _on_close() -> void:
	settings_closed.emit()


func show_menu() -> void:
	_load_from_config()
	visible = true


func hide_menu() -> void:
	visible = false
