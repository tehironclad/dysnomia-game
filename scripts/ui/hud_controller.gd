extends CanvasLayer
## HUD displaying FPS, player coordinates, seed/territory info, mode,
## identity panel, and debug panel.

@onready var fps_label: Label = $FPSLabel
@onready var coords_label: Label = $CoordsLabel
@onready var seed_label: Label = $SeedLabel
@onready var mode_label: Label = $ModeLabel
@onready var debug_panel: VBoxContainer = $DebugPanel
@onready var territory_panel: VBoxContainer = $TerritoryPanel
@onready var territory_label: RichTextLabel = $TerritoryPanel/TerritoryLabel
@onready var identity_panel: VBoxContainer = $IdentityPanel
@onready var identity_label: RichTextLabel = $IdentityPanel/IdentityLabel
@onready var terraform_panel: VBoxContainer = $TerraformPanel
@onready var terraform_label: Label = $TerraformPanel/TerraformLabel
@onready var tx_status: Label = $TxStatus
@onready var chat_input: LineEdit = $ChatPanel/ChatVBox/ChatInputRow/ChatInput
@onready var chat_send_btn: Button = $ChatPanel/ChatVBox/ChatInputRow/ChatSendBtn
@onready var interact_prompt: Label = $InteractPrompt
@onready var location_label: Label = $LocationLabel
@onready var chat_panel: PanelContainer = $ChatPanel
@onready var chat_history: RichTextLabel = $ChatPanel/ChatVBox/ChatHistory
@onready var global_tab_btn: Button = $ChatPanel/ChatVBox/ChatHeader/GlobalTabBtn
@onready var territory_tab_btn: Button = $ChatPanel/ChatVBox/ChatHeader/TerritoryTabBtn
@onready var chat_close_btn: Button = $ChatPanel/ChatVBox/ChatHeader/ChatCloseBtn
@onready var guest_panel: PanelContainer = $GuestPanel
@onready var guest_list_label: RichTextLabel = $GuestPanel/GuestVBox/GuestList
@onready var guest_refresh_btn: Button = $GuestPanel/GuestVBox/GuestHeader/GuestRefreshBtn
@onready var guest_close_btn: Button = $GuestPanel/GuestVBox/GuestHeader/GuestCloseBtn
@onready var leave_btn: Button = $TerritoryPanel/LifecycleRow/LeaveBtn
@onready var void_btn: Button = $TerritoryPanel/LifecycleRow/VoidBtn
@onready var inventory_panel: PanelContainer = $InventoryPanel
@onready var inventory_list: RichTextLabel = $InventoryPanel/InventoryVBox/InventoryList
@onready var inventory_close_btn: Button = $InventoryPanel/InventoryVBox/InventoryHeader/InventoryCloseBtn
@onready var inventory_refresh_btn: Button = $InventoryPanel/InventoryVBox/InventoryHeader/InventoryRefreshBtn
@onready var world_map: Control = $WorldMap
@onready var terraform_actions: PanelContainer = $TerraformActionsPanel
@onready var seed_input_terraform: LineEdit = $TerraformActionsPanel/ActionsVBox/SeedRow/SeedInput
@onready var random_seed_btn: Button = $TerraformActionsPanel/ActionsVBox/SeedRow/RandomSeedButton
@onready var alpha_btn: Button = $TerraformActionsPanel/ActionsVBox/ButtonRow1/AlphaButton
@onready var beta_btn: Button = $TerraformActionsPanel/ActionsVBox/ButtonRow1/BetaButton
@onready var pi_btn: Button = $TerraformActionsPanel/ActionsVBox/ButtonRow2/PiButton
@onready var rho_btn: Button = $TerraformActionsPanel/ActionsVBox/ButtonRow2/RhoButton
@onready var upsilon_btn: Button = $TerraformActionsPanel/ActionsVBox/ButtonRow3/UpsilonButton
@onready var phi_toggle: CheckBox = $TerraformActionsPanel/ActionsVBox/ButtonRow3/PhiToggle
@onready var generate_btn: Button = $TerraformActionsPanel/ActionsVBox/GenerateButton
@onready var batch_row: HBoxContainer = $TerraformActionsPanel/ActionsVBox/BatchRow
@onready var batch_checkbox: CheckBox = $TerraformActionsPanel/ActionsVBox/BatchRow/BatchCheckBox
@onready var batch_count_input: SpinBox = $TerraformActionsPanel/ActionsVBox/BatchRow/BatchCountInput
@onready var batch_status: Label = $TerraformActionsPanel/ActionsVBox/BatchRow/BatchStatus
@onready var beat_btn: Button = $TerraformActionsPanel/ActionsVBox/BeatRow/BeatButton
@onready var beat_status_label: Label = $TerraformActionsPanel/ActionsVBox/BeatRow/BeatStatusLabel
@onready var controls_button: Button = $ControlsButton

var _player: Node3D
var _debug_visible: bool = false
var _chat_open: bool = false
var _chat_panel_visible: bool = false
var _chat_tab: int = 0  # 0 = Global, 1 = Territory
var _terraform_panel_open: bool = false
var _guest_panel_visible: bool = false
var _pending_terraform_tx: int = -1
var _pending_terraform_time: float = 0.0  # When non-batch tx was sent
var _at_monument: bool = false
var _batch_terraform: Node  # BatchTerraform controller
var _inventory_visible: bool = false
var _world_map_visible: bool = false
var _leaderboard_visible: bool = false
var _pending_leave_tx: int = -1
var _pending_void_tx: int = -1
var _pending_beat_tx: int = -1
var _beat_cooldown: float = 0.0
const BEAT_COOLDOWN_TIME: float = 60.0  # Same as entropy-ai
var _controls_visible: bool = false
var _achievement_visible: bool = false
var _screen_flash: ColorRect
var _damage_vignette: ColorRect
var _settings_visible: bool = false
var _settings_menu: PanelContainer
var _screen_effects: Node
var _minimap: Control
var _minimap_visible: bool = true
var _minigame_manager: Node
var _minigame_active: bool = false
var _daily_panel: PanelContainer
var _daily_visible: bool = false
var _emote_wheel: Control
var _emote_wheel_visible: bool = false
var _weather_label: Label
var _photo_mode: CanvasLayer
var _photo_mode_active: bool = false
var _guestbook_panel: PanelContainer
var _guestbook_visible: bool = false

# ── Screen Recording ────────────────────────────────────────────────
var _is_recording: bool = false
var _record_frame_timer: float = 0.0
var _record_frame_count: int = 0
var _record_folder: String = ""
var _record_fps: float = 30.0  # Capture at 30fps
var _record_indicator: Label
var _record_start_time: float = 0.0

# Signal emitted when player wants to travel to a QING from the world map
signal map_territory_selected(qing_address: String)

const TERRAFORM_TX_TIMEOUT: float = 360.0  # 6 minutes max wait for non-batch tx


func _ready() -> void:
	debug_panel.visible = false
	territory_panel.visible = GameManager.is_chain_sourced
	identity_panel.visible = GameManager.has_identity
	GameManager.territory_data_changed.connect(_on_territory_data_changed)
	GameManager.identity_data_changed.connect(_on_identity_data_changed)
	GameManager.territory_state_changed.connect(_on_territory_state_changed)
	ChainManager.tx_sent.connect(_on_tx_sent)
	ChainManager.tx_failed.connect(_on_tx_failed)
	ChainManager.wallet_connected.connect(func(_addr: String) -> void: _update_identity_display())
	ChainManager.wallet_disconnected.connect(_update_identity_display)
	tx_status.text = ""

	# Copy-to-clipboard: connect [url=copy:...] click handlers
	territory_label.meta_clicked.connect(_on_meta_clicked)
	identity_label.meta_clicked.connect(_on_meta_clicked)

	# Chat panel + input + tabs
	chat_panel.visible = false
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_send_btn.pressed.connect(_on_chat_send_pressed)
	chat_close_btn.pressed.connect(_close_chat_panel)
	global_tab_btn.pressed.connect(_on_global_tab)
	territory_tab_btn.pressed.connect(_on_territory_tab)
	ChainManager.chat_messages_received.connect(_on_chat_messages_received)
	ChainManager.global_chat_received.connect(_on_global_chat_received)

	# Guest list panel
	guest_panel.visible = false
	guest_close_btn.pressed.connect(_close_guest_panel)
	guest_refresh_btn.pressed.connect(_refresh_guest_list)
	ChainManager.guest_list_loaded.connect(_on_guest_list_loaded)

	# Leave / Void buttons (Phase 8)
	leave_btn.pressed.connect(_on_leave_pressed)
	void_btn.pressed.connect(_on_void_pressed)
	ChainManager.tx_confirmed.connect(_on_lifecycle_tx_confirmed)

	# Inventory panel (Phase 9)
	inventory_panel.visible = false
	inventory_close_btn.pressed.connect(_close_inventory_panel)
	inventory_refresh_btn.pressed.connect(_refresh_inventory)
	inventory_list.meta_clicked.connect(_on_meta_clicked)
	ChainManager.token_balances_updated.connect(_on_token_balances_updated)

	# World map (Phase 10)
	world_map.visible = false
	world_map.territory_selected.connect(_on_map_territory_selected)
	world_map.map_closed.connect(_close_world_map)
	world_map.name_requested.connect(_on_map_name_requested)
	ChainManager.qing_name_resolved.connect(_on_qing_name_resolved)

	# Terraform actions panel
	terraform_actions.visible = false
	batch_row.visible = false
	random_seed_btn.pressed.connect(_on_random_seed)
	alpha_btn.pressed.connect(_on_terraform_alpha)
	beta_btn.pressed.connect(_on_terraform_beta)
	pi_btn.pressed.connect(_on_terraform_pi)
	rho_btn.pressed.connect(_on_terraform_rho)
	upsilon_btn.pressed.connect(_on_terraform_upsilon)
	generate_btn.pressed.connect(_on_terraform_generate)
	beat_btn.pressed.connect(_on_beat_pressed)
	ChainManager.tx_confirmed.connect(_on_terraform_tx_confirmed)
	ChainManager.beat_confirmed.connect(_on_beat_tx_confirmed)
	ChainManager.beat_failed.connect(_on_beat_tx_failed)

	# Player progression — load on start if wallet connected
	ChainManager.weapon_unlocked.connect(_on_weapon_unlocked)
	ChainManager.vehicle_unlocked.connect(_on_vehicle_unlocked)
	ChainManager.player_progression_loaded.connect(_on_progression_loaded)

	# Controls button — always visible on screen
	controls_button.pressed.connect(_toggle_controls)

	# Batch terraform controller
	batch_count_input.value_changed.connect(_on_batch_count_changed)

	var BatchTerraformScript = preload("res://scripts/ui/batch_terraform.gd")
	_batch_terraform = BatchTerraformScript.new()
	_batch_terraform.name = "BatchTerraform"
	_batch_terraform.batch_progress.connect(_on_batch_progress)
	_batch_terraform.batch_completed.connect(_on_batch_completed)
	_batch_terraform.batch_failed.connect(_on_batch_failed)
	add_child(_batch_terraform)

	# If chain data was loaded before this scene (from main menu), populate now
	if GameManager.is_chain_sourced:
		_on_territory_data_changed({
			"name": GameManager.territory_name,
			"address": GameManager.territory_address,
			"owner": GameManager.territory_owner,
			"waat_hex": GameManager.territory_waat_hex,
			"seed": GameManager.terrain_seed,
		})

	# If identity was loaded before this scene, populate now
	if GameManager.has_identity:
		_update_identity_display()

	# If territory state was loaded before this scene, populate now
	terraform_panel.visible = GameManager.has_territory_state
	if GameManager.has_territory_state:
		_update_terraform_display()

	# Beat screen flash overlay — transparent full-screen rect
	_screen_flash = ColorRect.new()
	_screen_flash.name = "ScreenFlash"
	_screen_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_flash)

	# Damage vignette — red flash when player takes damage
	_damage_vignette = ColorRect.new()
	_damage_vignette.name = "DamageVignette"
	_damage_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_vignette.color = Color(0.8, 0.05, 0.02, 0.0)
	_damage_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_vignette)

	# Holographic scanline overlay — subtle EVA suit display aesthetic
	var scanline_overlay := ColorRect.new()
	scanline_overlay.name = "ScanlineOverlay"
	scanline_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	scanline_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scanline_shader := load("res://assets/shaders/hud_scanline.gdshader") as Shader
	if scanline_shader:
		var scanline_mat := ShaderMaterial.new()
		scanline_mat.shader = scanline_shader
		scanline_overlay.material = scanline_mat
	scanline_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	add_child(scanline_overlay)

	# Weather indicator label (top-center, Phase 13I)
	_weather_label = Label.new()
	_weather_label.name = "WeatherLabel"
	_weather_label.text = ""
	_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weather_label.add_theme_font_size_override("font_size", 16)
	_weather_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_weather_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_weather_label.add_theme_constant_override("shadow_offset_x", 1)
	_weather_label.add_theme_constant_override("shadow_offset_y", 1)
	_weather_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_weather_label.position = Vector2(-100.0, 4.0)
	_weather_label.size = Vector2(200.0, 30.0)
	_weather_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_label.visible = false
	add_child(_weather_label)


func set_player(player: Node3D) -> void:
	_player = player
	# Initialize screen effects (helmet HUD, chromatic aberration, motion blur)
	if not _screen_effects:
		var ScreenEffectsScript = load("res://scripts/ui/screen_effects.gd")
		_screen_effects = Node.new()
		_screen_effects.set_script(ScreenEffectsScript)
		_screen_effects.name = "ScreenEffects"
		add_child(_screen_effects)
		_screen_effects.initialize(self, player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_visible = !_debug_visible
		debug_panel.visible = _debug_visible

	if not _chat_open and not _world_map_visible and event is InputEventKey and event.pressed:
		# Toggle terraform panel with T
		if event.keycode == KEY_T:
			_toggle_terraform_panel()
			get_viewport().set_input_as_handled()
		# Toggle chat panel with C
		elif event.keycode == KEY_C:
			_toggle_chat_panel()
			get_viewport().set_input_as_handled()
		# Toggle guest list panel with G
		elif event.keycode == KEY_G:
			_toggle_guest_panel()
			get_viewport().set_input_as_handled()
		# Toggle inventory panel with I
		elif event.keycode == KEY_I:
			_toggle_inventory_panel()
			get_viewport().set_input_as_handled()
		# Toggle world map with M
		elif event.keycode == KEY_M:
			_toggle_world_map()
			get_viewport().set_input_as_handled()
		# Toggle leaderboard with L
		elif event.keycode == KEY_L:
			_toggle_leaderboard()
			get_viewport().set_input_as_handled()
		# Toggle achievement panel with P
		elif event.keycode == KEY_P:
			_toggle_achievement_panel()
			get_viewport().set_input_as_handled()
		# Toggle voice chat with O
		elif event.keycode == KEY_O:
			_toggle_voice_chat()
			get_viewport().set_input_as_handled()
		# Toggle controls help with H
		elif event.keycode == KEY_H:
			_toggle_controls()
			get_viewport().set_input_as_handled()
		# Toggle minimap with N
		elif event.keycode == KEY_N:
			_toggle_minimap()
			get_viewport().set_input_as_handled()
		# Toggle daily challenges with J
		elif event.keycode == KEY_J:
			_toggle_daily_panel()
			get_viewport().set_input_as_handled()
		# Toggle guestbook with B
		elif event.keycode == KEY_B:
			_toggle_guestbook()
			get_viewport().set_input_as_handled()
		# Hold Q for emote wheel
		elif event.keycode == KEY_Q and not GameManager.is_flying:
			_show_emote_wheel()
			get_viewport().set_input_as_handled()
		# Toggle photo mode with F6
		elif event.keycode == KEY_F6:
			_toggle_photo_mode()
			get_viewport().set_input_as_handled()
		# Reopen wallet window with F5
		elif event.keycode == KEY_F5:
			_reopen_wallet()
			get_viewport().set_input_as_handled()
		# Screenshot with F7
		elif event.keycode == KEY_F7:
			_take_screenshot()
			get_viewport().set_input_as_handled()
		# Toggle screen recording with F8
		elif event.keycode == KEY_F8:
			_toggle_recording()
			get_viewport().set_input_as_handled()
		# Toggle settings menu with F9
		elif event.keycode == KEY_F9:
			_toggle_settings()
			get_viewport().set_input_as_handled()
		# Open chat input with Enter or /
		elif event.keycode == KEY_ENTER or event.keycode == KEY_SLASH:
			_open_chat()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Emote wheel: Q release
	if event is InputEventKey and not event.pressed and event.keycode == KEY_Q:
		if _emote_wheel_visible:
			_release_emote_wheel()
			get_viewport().set_input_as_handled()
			return

	# Close panels with Escape (needs _input since chat_input grabs focus)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _world_map_visible:
			_close_world_map()
			get_viewport().set_input_as_handled()
		elif _chat_open:
			_close_chat()
			get_viewport().set_input_as_handled()
		elif _chat_panel_visible:
			_close_chat_panel()
			get_viewport().set_input_as_handled()
		elif _guest_panel_visible:
			_close_guest_panel()
			get_viewport().set_input_as_handled()
		elif _leaderboard_visible:
			_close_leaderboard()
			get_viewport().set_input_as_handled()
		elif _controls_visible:
			_close_controls()
			get_viewport().set_input_as_handled()
		elif _inventory_visible:
			_close_inventory_panel()
			get_viewport().set_input_as_handled()
		elif _achievement_visible:
			_close_achievement_panel()
			get_viewport().set_input_as_handled()
		elif _daily_visible:
			_close_daily_panel()
			get_viewport().set_input_as_handled()
		elif _guestbook_visible:
			_close_guestbook()
			get_viewport().set_input_as_handled()
		elif _emote_wheel_visible:
			_hide_emote_wheel()
			get_viewport().set_input_as_handled()
		elif _minigame_active:
			_close_minigame()
			get_viewport().set_input_as_handled()
		elif _settings_visible:
			_close_settings()
			get_viewport().set_input_as_handled()


var _presence_timer: float = 0.0
const PRESENCE_INTERVAL: float = 120.0  # Heartbeat every 2 minutes
var _progression_loaded_once: bool = false

func _process(delta: float) -> void:
	# Beat cooldown timer
	if _beat_cooldown > 0.0:
		_beat_cooldown = maxf(0.0, _beat_cooldown - delta)
		if _beat_cooldown > 0.0 and beat_status_label:
			beat_status_label.text = "Cooldown: %.0fs" % _beat_cooldown

	# ── Screen recording frame capture ──
	if _is_recording:
		_record_frame_timer += delta
		var interval := 1.0 / _record_fps
		if _record_frame_timer >= interval:
			_record_frame_timer -= interval
			_capture_frame()
		# Update indicator with elapsed time
		if _record_indicator:
			var elapsed := Time.get_ticks_msec() / 1000.0 - _record_start_time
			_record_indicator.text = "⏺ REC  %02d:%02d  [%d frames]" % [int(elapsed) / 60, int(elapsed) % 60, _record_frame_count]

	# Presence heartbeat — send periodically so other players see us online
	_presence_timer += delta
	if _presence_timer >= PRESENCE_INTERVAL:
		_presence_timer = 0.0
		ChainManager.send_presence_heartbeat()

	# Load progression once when wallet connects
	if not _progression_loaded_once and ChainManager.is_wallet_connected():
		_progression_loaded_once = true
		ChainManager.load_player_progression()

	# Auto-close panels if mouse got re-captured (e.g. by Escape in player controller)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if _terraform_panel_open:
			_terraform_panel_open = false
			terraform_actions.visible = false
		if _guest_panel_visible:
			_guest_panel_visible = false
			guest_panel.visible = false
		if _inventory_visible:
			_inventory_visible = false
			inventory_panel.visible = false
		if _world_map_visible:
			_world_map_visible = false
			world_map.visible = false
		if _chat_open:
			_close_chat()
		if _settings_visible:
			_settings_visible = false
			if _settings_menu:
				_settings_menu.hide_menu()
		if _minigame_active:
			_close_minigame()

	# Safety timeout for non-batch terraform tx
	if _pending_terraform_tx >= 0 and _pending_terraform_time > 0.0:
		var elapsed := Time.get_unix_time_from_system() - _pending_terraform_time
		if elapsed > TERRAFORM_TX_TIMEOUT:
			print("[HUD] Terraform tx %d timed out after %.0fs — re-enabling buttons" % [
				_pending_terraform_tx, elapsed])
			_pending_terraform_tx = -1
			_pending_terraform_time = 0.0
			_set_terraform_buttons_disabled(false)
			tx_status.text = "Tx confirmation timed out — check explorer"
			_auto_clear_tx_status(8.0)

	# Screen effects update
	if _screen_effects and _player:
		_screen_effects.update(delta, _player)

	# Minimap update
	if _minimap and _player and _minimap.visible:
		var heading := -_player.rotation.y
		_minimap.update_player(_player.global_position, heading)

	# FPS
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	# Player position
	if _player:
		var pos: Vector3 = _player.global_position
		coords_label.text = "X: %.1f  Y: %.1f  Z: %.1f" % [pos.x, pos.y, pos.z]

	# Seed / Territory display
	if GameManager.is_chain_sourced:
		seed_label.text = "QING: %s" % _truncate_address(GameManager.territory_address)
	else:
		seed_label.text = "Seed: %d" % GameManager.terrain_seed

	# Mode + Day/Night indicator
	var fly_text := "FLY" if GameManager.is_flying else "GROUND"
	var cam_text := "3RD"
	if _player:
		var rig = _player.get_node_or_null("CameraRig")
		if rig and rig.has_method("get_camera_mode_name"):
			cam_text = rig.get_camera_mode_name()
		elif GameManager.is_first_person:
			cam_text = "1ST"
	var t := GameManager.time_of_day
	var time_text := _get_time_of_day_text(t)
	mode_label.text = "%s | %s | %s" % [fly_text, cam_text, time_text]
	# Tint mode label color by time of day
	var is_night := t < 0.22 or t > 0.78
	mode_label.add_theme_color_override("font_color",
		Color(0.5, 0.6, 0.9) if is_night else Color(0.9, 0.85, 0.7))

	# Debug info
	if _debug_visible and debug_panel.get_child_count() > 0:
		var params := GameManager.terrain_params
		var biome := BiomeSystem.get_biome(GameManager.terrain_seed)
		var debug_text := "Biome: %s\n" % biome.get("biome_name", "Unknown")
		debug_text += "Freq: %.4f\n" % params.get("frequency", 0.0)
		debug_text += "Height: %.1f\n" % params.get("max_height", 0.0)
		debug_text += "Time: %.2f\n" % GameManager.time_of_day
		debug_text += "Octaves: %d\n" % params.get("octaves", 0)
		debug_text += "Source: %s\n" % ("Chain" if GameManager.is_chain_sourced else "Manual")
		if GameManager.has_identity:
			debug_text += "Identity: %s\n" % GameManager.player_identity
			debug_text += "LAU: %s\n" % GameManager.lau_address
			if not GameManager.lau_wallet.is_empty():
				debug_text += "Wallet: %s\n" % GameManager.lau_wallet
			if not GameManager.lau_yue_address.is_empty():
				debug_text += "YUE: %s\n" % GameManager.lau_yue_address
			if not GameManager.lau_current_area.is_empty():
				debug_text += "Area: %s\n" % GameManager.lau_current_area
		if GameManager.has_territory_state:
			debug_text += "Lat: %.6f  Lon: %.6f\n" % [GameManager.territory_latitude, GameManager.territory_longitude]
			debug_text += "Charge: %d  Omi: %d  Ome: %d\n" % [GameManager.territory_charge, GameManager.territory_omicron, GameManager.territory_omega]
			debug_text += "Hypo: %d  Epi: %d" % [GameManager.territory_hypobar, GameManager.territory_epibar]

		var debug_label: Label = debug_panel.get_child(0)
		if debug_label is Label:
			debug_label.text = debug_text


func _on_territory_data_changed(data: Dictionary) -> void:
	territory_panel.visible = true
	var tname: String = data.get("name", "")
	var addr: String = data.get("address", "")
	var owner: String = data.get("owner", "Unknown")
	var waat: String = data.get("waat_hex", "")
	var seed_val: int = data.get("seed", 0)
	var biome := BiomeSystem.get_biome(seed_val)
	var bbcode := ""
	if not tname.is_empty():
		bbcode += "[font_size=16][b]%s[/b][/font_size]\n" % _escape_bbcode(tname)
	bbcode += "[color=#aaaaaa]QING:[/color] %s [url=copy:%s][color=#8b5cf6]📋[/color][/url]\n" % [_truncate_address(addr), _escape_bbcode(addr)]
	bbcode += "[color=#aaaaaa]Owner:[/color] %s [url=copy:%s][color=#8b5cf6]📋[/color][/url]\n" % [_truncate_address(owner), _escape_bbcode(owner)]
	bbcode += "[color=#aaaaaa]Waat:[/color] %s [url=copy:%s][color=#8b5cf6]📋[/color][/url]\n" % [_escape_bbcode(waat.left(20)) + "...", _escape_bbcode(waat)]
	bbcode += "[color=#aaaaaa]Seed:[/color] %d [url=copy:%d][color=#8b5cf6]📋[/color][/url]\n" % [seed_val, seed_val]
	bbcode += "[color=#aaaaaa]Biome:[/color] %s" % biome.get("biome_name", "Unknown")
	if GameManager.has_identity and GameManager.is_territory_owner():
		bbcode += "\n[color=#ffd700][b]⭐ HOME TERRITORY[/b][/color]"
	territory_label.clear()
	territory_label.append_text(bbcode)

	# Update location indicator with territory name + address
	if not tname.is_empty():
		location_label.text = "%s  |  %s" % [tname, _truncate_address(addr)]
	elif not addr.is_empty():
		location_label.text = _truncate_address(addr)


func update_location(direction: int, territory_name: String, _address: String) -> void:
	## Update the location indicator when player enters a different territory.
	## direction: -1 = center/home territory, 0-3 = neighbor direction.
	if territory_name.is_empty():
		location_label.text = ""
		return
	if direction < 0:
		location_label.text = territory_name
		location_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	else:
		location_label.text = territory_name
		location_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7, 0.9))


func _on_identity_data_changed(_data: Dictionary) -> void:
	_update_identity_display()


func _update_identity_display() -> void:
	identity_panel.visible = true
	var bbcode := "[font_size=16][b]%s[/b][/font_size]" % _escape_bbcode(GameManager.player_identity)
	if not GameManager.lau_address.is_empty():
		bbcode += "\n[color=#aaaaaa]LAU:[/color] %s [url=copy:%s][color=#8b5cf6]📋[/color][/url]" % [_truncate_address(GameManager.lau_address), _escape_bbcode(GameManager.lau_address)]
	# Show Saat values if any are non-zero
	var saat := GameManager.lau_saat
	if saat[0] > 0 or saat[1] > 0 or saat[2] > 0:
		bbcode += "\n[color=#aaaaaa]Soul:[/color] %d [url=copy:%d][color=#8b5cf6]📋[/color][/url]  [color=#aaaaaa]Spirit:[/color] %d  [color=#aaaaaa]Aura:[/color] %d" % [saat[0], saat[0], saat[1], saat[2]]
	# Show wallet if resolved
	if not GameManager.lau_wallet.is_empty():
		bbcode += "\n[color=#aaaaaa]Wallet:[/color] %s [url=copy:%s][color=#8b5cf6]📋[/color][/url]" % [_truncate_address(GameManager.lau_wallet), _escape_bbcode(GameManager.lau_wallet)]
	# Show YUE if resolved
	if not GameManager.lau_yue_address.is_empty():
		bbcode += "\n[color=#aaaaaa]YUE:[/color] %s [url=copy:%s][color=#8b5cf6]📋[/color][/url]" % [_truncate_address(GameManager.lau_yue_address), _escape_bbcode(GameManager.lau_yue_address)]
	# Ownership badge
	if GameManager.is_territory_owner():
		bbcode += "\n[color=#ffd700][b]⭐ HOME TERRITORY[/b][/color]"
	# Wallet connection indicator
	if ChainManager.is_wallet_connected():
		bbcode += "\n[color=#22c55e]● WALLET CONNECTED[/color]"
	else:
		bbcode += "\n[color=#888888]○ [F5] Open Wallet[/color]"
	identity_label.clear()
	identity_label.append_text(bbcode)


func _on_territory_state_changed(_data: Dictionary) -> void:
	_update_terraform_display()


func _update_terraform_display() -> void:
	terraform_panel.visible = true
	var text := "Territory Power\n"

	# Charge / Omicron / Omega
	text += "  Charge: %s\n" % _format_large_number(GameManager.territory_charge)
	text += "  Omi: %s | Ome: %s\n" % [
		_format_large_number(GameManager.territory_omicron),
		_format_large_number(GameManager.territory_omega),
	]

	# Bar values (Hypobar / Epibar)
	text += "  Hypo: %s\n" % _format_large_number(GameManager.territory_hypobar)
	text += "  Epi: %s\n" % _format_large_number(GameManager.territory_epibar)

	# Coordinates
	var lat := GameManager.territory_latitude
	var lon := GameManager.territory_longitude
	var lat_dir := "N" if lat >= 0.0 else "S"
	var lon_dir := "E" if lon >= 0.0 else "W"
	text += "  %d%s, %d%s" % [int(absf(lat)), lat_dir, int(absf(lon)), lon_dir]

	terraform_label.text = text


func _format_large_number(value: int) -> String:
	## Format large numbers with K/M/T suffixes for readability.
	if value >= 1_000_000_000_000:
		return "%.1fT" % (float(value) / 1_000_000_000_000.0)
	elif value >= 1_000_000_000:
		return "%.1fB" % (float(value) / 1_000_000_000.0)
	elif value >= 1_000_000:
		return "%.1fM" % (float(value) / 1_000_000.0)
	elif value >= 1_000:
		return "%.1fK" % (float(value) / 1_000.0)
	else:
		return str(value)


func _get_time_of_day_text(t: float) -> String:
	## Convert 0-1 time to a human-readable day phase.
	if t < 0.20:
		return "NIGHT"
	elif t < 0.27:
		return "DAWN"
	elif t < 0.40:
		return "MORNING"
	elif t < 0.60:
		return "MIDDAY"
	elif t < 0.73:
		return "AFTERNOON"
	elif t < 0.80:
		return "DUSK"
	else:
		return "NIGHT"


func _try_recapture_mouse() -> void:
	## Re-capture mouse only if no UI panels are open that need it visible.
	if not _terraform_panel_open and not _chat_open and not _chat_panel_visible \
			and not _guest_panel_visible and not _inventory_visible \
			and not _world_map_visible and not _controls_visible \
			and not _leaderboard_visible and not _settings_visible \
			and not _minigame_active and not _daily_visible \
			and not _emote_wheel_visible and not _photo_mode_active \
			and not _guestbook_visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _truncate_address(addr: String) -> String:
	if addr.length() > 12:
		return addr.left(6) + "..." + addr.right(4)
	return addr


# ─── Interact Prompt ─────────────────────────────────────────────────────

func show_interact_prompt(text: String) -> void:
	interact_prompt.text = text
	interact_prompt.visible = true


func hide_interact_prompt() -> void:
	interact_prompt.visible = false
	interact_prompt.text = ""


# ─── Health & Weapon HUD ────────────────────────────────────────────────

var _health_bar: ProgressBar
var _health_label: Label
var _weapon_label: Label
var _crosshair: Label
var _player_count_label: Label

func _create_combat_hud() -> void:
	## Create health bar, weapon indicator, and crosshair dynamically.
	if _health_bar:
		return  # Already created

	# Health bar — bottom-left, above coords/seed area
	_health_bar = ProgressBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.custom_minimum_size = Vector2(180, 14)
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	_health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_bar.position = Vector2(10, -78)

	# Style the health bar
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.8, 0.3, 0.8)
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	_health_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	_health_bar.add_theme_stylebox_override("background", bg_style)
	add_child(_health_bar)

	# Health label — compact, next to health bar
	_health_label = Label.new()
	_health_label.name = "HealthLabel"
	_health_label.text = "HP: 100/100"
	_health_label.add_theme_font_size_override("font_size", 11)
	_health_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_health_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_label.position = Vector2(195, -78)
	add_child(_health_label)

	# Weapon label — bottom-right
	_weapon_label = Label.new()
	_weapon_label.name = "WeaponLabel"
	_weapon_label.text = "Fists [1]"
	_weapon_label.add_theme_font_size_override("font_size", 13)
	_weapon_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_weapon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_label.position = Vector2(-180, -30)
	add_child(_weapon_label)

	# Crosshair — positioned above the bear's head in third-person view
	_crosshair = Label.new()
	_crosshair.name = "Crosshair"
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 24)
	_crosshair.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.5))
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position = Vector2(-6, -160)
	add_child(_crosshair)


func update_health(current: float, maximum: float) -> void:
	if not _health_bar:
		_create_combat_hud()
	_health_bar.max_value = maximum
	_health_bar.value = current

	# Color changes: green > yellow > red
	var pct := current / maximum if maximum > 0 else 0.0
	var fill: StyleBoxFlat = _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		if pct > 0.6:
			fill.bg_color = Color(0.2, 0.8, 0.3, 0.8)
		elif pct > 0.3:
			fill.bg_color = Color(0.9, 0.7, 0.1, 0.8)
		else:
			fill.bg_color = Color(0.9, 0.2, 0.1, 0.8)

	if _health_label:
		_health_label.text = "HP: %d/%d" % [int(current), int(maximum)]


func update_weapon(weapon_name: String) -> void:
	if not _weapon_label:
		_create_combat_hud()
	_weapon_label.text = weapon_name


func update_player_count(count: int) -> void:
	## Update the online player count indicator in the top-right.
	if not _player_count_label:
		_player_count_label = Label.new()
		_player_count_label.name = "PlayerCount"
		_player_count_label.add_theme_font_size_override("font_size", 13)
		_player_count_label.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0, 0.85))
		_player_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_player_count_label.anchors_preset = Control.PRESET_TOP_RIGHT
		_player_count_label.offset_left = -200
		_player_count_label.offset_top = 60
		_player_count_label.offset_right = -12
		add_child(_player_count_label)
	if count > 0:
		_player_count_label.text = "%d player%s nearby" % [count, "s" if count != 1 else ""]
		_player_count_label.visible = true
	else:
		_player_count_label.visible = false


# ─── Transaction Status ──────────────────────────────────────────────────

func _on_tx_sent(_id: int, hash: String) -> void:
	if hash.is_empty():
		tx_status.text = "Transaction pending... confirm in your wallet"
	else:
		tx_status.text = "Tx sent: %s..." % hash.left(14)
	_auto_clear_tx_status(8.0)


func _on_tx_failed(_id: int, error: String) -> void:
	tx_status.text = "Tx failed: %s" % error.left(60)
	_auto_clear_tx_status(6.0)
	if _id == _pending_terraform_tx:
		_pending_terraform_tx = -1
		_pending_terraform_time = 0.0
		_set_terraform_buttons_disabled(false)


func _auto_clear_tx_status(delay: float) -> void:
	var current_text := tx_status.text
	await get_tree().create_timer(delay).timeout
	# Only clear if the text hasn't changed (newer tx might have overwritten it)
	if tx_status.text == current_text:
		tx_status.text = ""


# ─── Chat Panel & Input ──────────────────────────────────────────────────

func _toggle_chat_panel() -> void:
	if _chat_panel_visible:
		_close_chat_panel()
	else:
		_open_chat_panel()


func _open_chat_panel() -> void:
	_chat_panel_visible = true
	chat_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_update_tab_style()
	_refresh_chat_display()


func _close_chat_panel() -> void:
	_chat_panel_visible = false
	chat_panel.visible = false
	_chat_open = false
	chat_input.release_focus()
	_try_recapture_mouse()


func _open_chat() -> void:
	if not ChainManager.is_wallet_connected():
		tx_status.text = "Connect wallet to chat (main menu → Connect Wallet)"
		_auto_clear_tx_status(4.0)
		return
	_chat_open = true
	# Show chat panel if not already visible
	if not _chat_panel_visible:
		_open_chat_panel()
	chat_input.text = ""
	chat_input.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_chat() -> void:
	_chat_open = false
	chat_input.release_focus()
	_try_recapture_mouse()


func _on_chat_send_pressed() -> void:
	## Send button clicked — submit whatever is in the input field.
	_on_chat_submitted(chat_input.text)


func _on_chat_submitted(text: String) -> void:
	var message := text.strip_edges()
	chat_input.text = ""
	if message.is_empty():
		return
	if not ChainManager.is_wallet_connected():
		tx_status.text = "Wallet not connected"
		_auto_clear_tx_status(4.0)
		return
	if GameManager.territory_address.is_empty():
		tx_status.text = "Join a territory first to chat"
		_auto_clear_tx_status(4.0)
		return
	tx_status.text = "Sending chat... confirm in your wallet"
	ChainManager.send_chat(message)


func _on_chat_messages_received(messages: Array) -> void:
	## Called when ChainManager receives new/updated territory chat messages.
	if _chat_panel_visible and _chat_tab == 1:
		_render_chat_messages(messages)


func _on_global_chat_received(messages: Array) -> void:
	## Called when ChainManager receives new/updated global chat messages.
	if _chat_panel_visible and _chat_tab == 0:
		_render_chat_messages(messages)


func _on_global_tab() -> void:
	_chat_tab = 0
	_update_tab_style()
	_refresh_chat_display()


func _on_territory_tab() -> void:
	_chat_tab = 1
	_update_tab_style()
	_refresh_chat_display()


func _update_tab_style() -> void:
	## Highlight the active tab button.
	if _chat_tab == 0:
		global_tab_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		territory_tab_btn.modulate = Color(0.5, 0.5, 0.5, 0.7)
	else:
		global_tab_btn.modulate = Color(0.5, 0.5, 0.5, 0.7)
		territory_tab_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _refresh_chat_display() -> void:
	## Re-render the chat panel based on the active tab.
	if _chat_tab == 0:
		var messages := ChainManager.get_global_chat_messages()
		if messages.size() > 0:
			_render_chat_messages(messages)
		else:
			chat_history.clear()
			chat_history.append_text("[color=#888888]No global messages yet.[/color]")
	else:
		var messages := ChainManager.get_chat_messages()
		if messages.size() > 0:
			_render_chat_messages(messages)
		else:
			chat_history.clear()
			chat_history.append_text("[color=#888888]No territory messages. Press Enter to chat.[/color]")


func _render_chat_messages(messages: Array) -> void:
	## Render chat messages into the RichTextLabel.
	chat_history.clear()

	if messages.is_empty():
		chat_history.append_text("[color=#888888]No messages yet. Press Enter to chat.[/color]")
		return

	# Show last 50 messages max in the panel
	var start_idx := maxi(0, messages.size() - 50)
	for i in range(start_idx, messages.size()):
		var msg: Dictionary = messages[i]
		var username: String = msg.get("username", "Anon")
		var logline: String = msg.get("message", "")

		# Color the username based on a hash of the name for variety
		var name_color := _username_color(username)

		# For global tab, show which QING the message came from
		var qing_tag := ""
		if _chat_tab == 0:
			var qing_name: String = msg.get("qing_name", "")
			if not qing_name.is_empty():
				# Strip " QING" suffix if present for brevity
				if qing_name.ends_with(" QING"):
					qing_name = qing_name.left(qing_name.length() - 5)
				qing_tag = "[color=#666666][%s][/color] " % _escape_bbcode(qing_name)

		# Format: [QINGName] [Username]: message
		chat_history.append_text("%s[color=%s][b]%s[/b][/color]: %s" % [
			qing_tag, name_color, _escape_bbcode(username), _escape_bbcode(logline)
		])
		if i < messages.size() - 1:
			chat_history.append_text("\n")


func _username_color(username: String) -> String:
	## Generate a consistent color hex string for a username.
	var hash_val: int = 0
	for ch in username:
		hash_val = (hash_val * 31 + ch.unicode_at(0)) % 0xFFFFFF
	# Ensure minimum brightness by setting lower bounds on RGB channels
	var r: int = 100 + (hash_val >> 16 & 0xFF) % 156
	var g: int = 100 + (hash_val >> 8 & 0xFF) % 156
	var b: int = 100 + (hash_val & 0xFF) % 156
	return "#%02x%02x%02x" % [r, g, b]


func _escape_bbcode(text: String) -> String:
	## Escape BBCode special characters to prevent injection.
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _on_meta_clicked(meta: Variant) -> void:
	## Handle [url=copy:VALUE] clicks — copy VALUE to clipboard.
	var meta_str: String = str(meta)
	if meta_str.begins_with("copy:"):
		var value := meta_str.substr(5)
		DisplayServer.clipboard_set(value)
		tx_status.text = "Copied!"
		_auto_clear_tx_status(2.0)


# ─── Terraform Actions ──────────────────────────────────────────────────

func _toggle_terraform_panel() -> void:
	if _terraform_panel_open:
		_close_terraform_panel()
	else:
		_open_terraform_panel()


func _open_terraform_panel() -> void:
	if not ChainManager.is_wallet_connected():
		tx_status.text = "Connect wallet to terraform (main menu)"
		_auto_clear_tx_status(4.0)
		return
	if not GameManager.has_territory_state:
		tx_status.text = "Load a territory first"
		_auto_clear_tx_status(4.0)
		return
	_terraform_panel_open = true
	terraform_actions.visible = true
	# Re-enable buttons unless a batch is actively running
	if not _batch_terraform or not _batch_terraform.is_running():
		_set_terraform_buttons_disabled(false)
	# Show batch row only at monument
	batch_row.visible = _at_monument
	batch_status.text = ""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if seed_input_terraform.text.is_empty():
		_generate_random_seed()


func open_terraform_from_monument() -> void:
	## Called when player interacts with the monument — opens panel with batch mode.
	_at_monument = true
	_open_terraform_panel()


func _close_terraform_panel() -> void:
	_terraform_panel_open = false
	_at_monument = false
	terraform_actions.visible = false
	batch_row.visible = false
	batch_status.text = ""
	seed_input_terraform.release_focus()
	_try_recapture_mouse()


func _generate_random_seed() -> void:
	var seed_val: int = randi() % 1_000_000_000 + 1
	seed_input_terraform.text = str(seed_val)


func _on_random_seed() -> void:
	_generate_random_seed()


func _get_terraform_seed() -> int:
	var text := seed_input_terraform.text.strip_edges()
	if text.is_empty() or not text.is_valid_int():
		tx_status.text = "Enter a valid seed number"
		_auto_clear_tx_status(3.0)
		return -1
	var val := text.to_int()
	if val <= 0:
		tx_status.text = "Seed must be a positive number"
		_auto_clear_tx_status(3.0)
		return -1
	return val


func _set_terraform_buttons_disabled(disabled: bool) -> void:
	alpha_btn.disabled = disabled
	beta_btn.disabled = disabled
	pi_btn.disabled = disabled
	rho_btn.disabled = disabled
	upsilon_btn.disabled = disabled
	generate_btn.disabled = disabled
	# Beat has its own cooldown, only disable if all terraform ops disabled
	if disabled:
		beat_btn.disabled = true
	elif _beat_cooldown <= 0.0:
		beat_btn.disabled = false


func _send_terraform_op(tx_id: int, op_name: String) -> void:
	if tx_id < 0:
		tx_status.text = "Failed to send %s — check wallet" % op_name
		_auto_clear_tx_status(4.0)
		return
	_pending_terraform_tx = tx_id
	_pending_terraform_time = Time.get_unix_time_from_system()
	_set_terraform_buttons_disabled(true)
	tx_status.text = "%s — confirm in your wallet" % op_name
	ChainManager.focus_wallet_page()


func _should_batch() -> bool:
	return _at_monument and batch_checkbox.button_pressed


func _on_terraform_alpha() -> void:
	if _should_batch():
		_set_terraform_buttons_disabled(true)
		_batch_terraform.start_batch("Alpha", ChainManager.terraform_alpha, true)
		return
	var seed_val := _get_terraform_seed()
	if seed_val < 0:
		return
	_send_terraform_op(ChainManager.terraform_alpha(seed_val), "Alpha")


func _on_terraform_beta() -> void:
	if _should_batch():
		_set_terraform_buttons_disabled(true)
		_batch_terraform.start_batch("Beta", ChainManager.terraform_beta, true)
		return
	var seed_val := _get_terraform_seed()
	if seed_val < 0:
		return
	_send_terraform_op(ChainManager.terraform_beta(seed_val), "Beta")


func _on_terraform_pi() -> void:
	if _should_batch():
		_set_terraform_buttons_disabled(true)
		_batch_terraform.start_batch("Pi", ChainManager.terraform_pi, false)
		return
	_send_terraform_op(ChainManager.terraform_pi(), "Pi")


func _on_terraform_rho() -> void:
	if _should_batch():
		_set_terraform_buttons_disabled(true)
		_batch_terraform.start_batch("Rho", ChainManager.terraform_rho, false)
		return
	_send_terraform_op(ChainManager.terraform_rho(), "Rho")


func _on_terraform_upsilon() -> void:
	if _should_batch():
		var phi: bool = phi_toggle.button_pressed
		_set_terraform_buttons_disabled(true)
		_batch_terraform.start_batch("Upsilon", ChainManager.terraform_upsilon, true, [phi])
		return
	var seed_val := _get_terraform_seed()
	if seed_val < 0:
		return
	var phi: bool = phi_toggle.button_pressed
	var dir_label := "fwd" if phi else "rev"
	_send_terraform_op(
		ChainManager.terraform_upsilon(seed_val, phi), "Upsilon (%s)" % dir_label)


func _on_terraform_generate() -> void:
	if _should_batch():
		_set_terraform_buttons_disabled(true)
		_batch_terraform.start_batch("Generate", ChainManager.terraform_generate, false)
		return
	_send_terraform_op(ChainManager.terraform_generate(), "Generate")


func _on_terraform_tx_confirmed(id: int, _hash: String) -> void:
	if id == _pending_terraform_tx:
		_pending_terraform_tx = -1
		_pending_terraform_time = 0.0
		_set_terraform_buttons_disabled(false)
		tx_status.text = "Terraform confirmed! Refreshing state..."
		_auto_clear_tx_status(5.0)
		_generate_random_seed()


# ─── Beat Operation ──────────────────────────────────────────────────────

func _on_beat_pressed() -> void:
	## Send META.Beat(waat) — advanced state aggregation.
	if _beat_cooldown > 0.0:
		beat_status_label.text = "Cooldown: %.0fs" % _beat_cooldown
		return
	if not ChainManager.is_wallet_connected():
		tx_status.text = "Connect wallet first"
		_auto_clear_tx_status(3.0)
		return
	if GameManager.territory_waat_hex.is_empty() or GameManager.territory_waat_hex == "0x0":
		tx_status.text = "Territory needs terraforming first (Waat = 0)"
		_auto_clear_tx_status(4.0)
		return

	var tx_id := ChainManager.send_beat()
	if tx_id < 0:
		tx_status.text = "Beat failed — check wallet"
		_auto_clear_tx_status(4.0)
		return

	_pending_beat_tx = tx_id
	beat_btn.disabled = true
	beat_status_label.text = "Confirm in wallet..."
	tx_status.text = "Beat — confirm in your wallet"
	ChainManager.focus_wallet_page()


func _on_beat_tx_confirmed(_id: int) -> void:
	_pending_beat_tx = -1
	beat_status_label.text = "Beat confirmed! +150 XP"
	tx_status.text = "Beat confirmed! Refreshing state..."
	_auto_clear_tx_status(5.0)
	# Chromatic aberration pulse on Beat
	if _screen_effects:
		_screen_effects.trigger_chromatic_pulse(0.02, 0.6)
	# Start cooldown
	_beat_cooldown = BEAT_COOLDOWN_TIME
	# Re-enable after cooldown
	get_tree().create_timer(BEAT_COOLDOWN_TIME).timeout.connect(func():
		_beat_cooldown = 0.0
		beat_btn.disabled = false
		beat_status_label.text = "")


func _on_beat_tx_failed(_id: int, error: String) -> void:
	_pending_beat_tx = -1
	beat_btn.disabled = false
	beat_status_label.text = ""
	tx_status.text = "Beat failed: %s" % error
	_auto_clear_tx_status(6.0)


func flash_screen_beat() -> void:
	## Brief white flash on beat confirmation, fades over 0.5s.
	if not _screen_flash:
		return
	_screen_flash.color = Color(1.0, 1.0, 1.0, 0.6)
	var tween := create_tween()
	tween.tween_property(_screen_flash, "color:a", 0.0, 0.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func flash_damage(intensity: float) -> void:
	## Red vignette flash when player takes damage. Intensity 0-1.
	if not _damage_vignette:
		return
	var alpha := clampf(intensity * 0.45, 0.05, 0.45)
	_damage_vignette.color = Color(0.8, 0.05, 0.02, alpha)
	var tween := create_tween()
	tween.tween_property(_damage_vignette, "color:a", 0.0, 0.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Chromatic aberration on damage
	if _screen_effects:
		_screen_effects.trigger_chromatic_pulse(0.012 * intensity, 0.3)


# ─── Player Progression ─────────────────────────────────────────────────

var _progression_label: Label
var _xp_bar: ProgressBar

func _create_progression_hud() -> void:
	## Create player level/XP display — top-left below debug info.
	if _progression_label:
		return

	_progression_label = Label.new()
	_progression_label.name = "ProgressionLabel"
	_progression_label.text = ""
	_progression_label.add_theme_font_size_override("font_size", 11)
	_progression_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85, 0.85))
	_progression_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_progression_label.position = Vector2(10, 30)
	add_child(_progression_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.name = "XPBar"
	_xp_bar.custom_minimum_size = Vector2(140, 4)
	_xp_bar.max_value = 100.0
	_xp_bar.value = 0.0
	_xp_bar.show_percentage = false
	_xp_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_xp_bar.position = Vector2(10, 46)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.5, 0.3, 0.9, 0.8)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	_xp_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.5)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_left = 3
	bg_style.corner_radius_bottom_right = 3
	_xp_bar.add_theme_stylebox_override("background", bg_style)
	add_child(_xp_bar)


func _on_progression_loaded(data: Dictionary) -> void:
	if data.is_empty():
		return
	if not _progression_label:
		_create_progression_hud()

	var level: int = data.get("level", 1)
	var xp: int = data.get("xp", 0)
	var xp_next: int = data.get("xpForNextLevel", 500)
	var xp_into: int = data.get("xpIntoLevel", 0)
	var title: String = data.get("evolutionTitle", "Drifter")
	var terraforms: int = data.get("terraforms", 0)
	var beats: int = data.get("beats", 0)

	_progression_label.text = "Lv.%d %s  |  T:%d  B:%d" % [level, title, terraforms, beats]

	if _xp_bar and xp_next > 0:
		_xp_bar.max_value = xp_next
		_xp_bar.value = xp_into


func _on_weapon_unlocked(weapon_type: int, weapon_name: String) -> void:
	## A weapon was unlocked based on progression — notify in-game.
	tx_status.text = "Weapon Unlocked: %s!" % weapon_name
	_auto_clear_tx_status(5.0)


func _on_vehicle_unlocked(vehicle_type: int, vehicle_name: String) -> void:
	## A vehicle was unlocked based on progression — notify in-game.
	tx_status.text = "Vehicle Unlocked: %s!" % vehicle_name
	_auto_clear_tx_status(5.0)


# ─── Guest List Panel ────────────────────────────────────────────────────

func _toggle_guest_panel() -> void:
	if _guest_panel_visible:
		_close_guest_panel()
	else:
		_open_guest_panel()


func _open_guest_panel() -> void:
	if GameManager.lau_address.is_empty():
		tx_status.text = "Load your identity first (LAU address)"
		_auto_clear_tx_status(3.0)
		return
	_guest_panel_visible = true
	guest_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Show cached admitted list or trigger a scan
	var cached := ChainManager.get_guest_list()
	if cached.size() > 0:
		_render_guest_list(cached)
	elif ChainManager.is_loading_guests():
		guest_list_label.clear()
		guest_list_label.append_text("[color=#888888]Scanning territories...[/color]")
	else:
		guest_list_label.clear()
		guest_list_label.append_text("[color=#888888]Scanning all QINGs for admitted status...[/color]")
		ChainManager.load_guest_list()


func _close_guest_panel() -> void:
	_guest_panel_visible = false
	guest_panel.visible = false
	_try_recapture_mouse()


func _refresh_guest_list() -> void:
	guest_list_label.clear()
	guest_list_label.append_text("[color=#888888]Rescanning all QINGs...[/color]")
	ChainManager.load_guest_list()


func _on_guest_list_loaded(guests: Array) -> void:
	if _guest_panel_visible:
		_render_guest_list(guests)


func _render_guest_list(territories: Array) -> void:
	guest_list_label.clear()

	if territories.is_empty():
		guest_list_label.append_text("[color=#888888]No QINGs scanned yet.\nPress R to scan.[/color]")
		return

	# Separate into paid-admitted (CoverCharge > 0) and free (CoverCharge == 0)
	var paid_admitted: Array = []   # Actively joined via Join tx (CoverCharge > 0)
	var free_qings: Array = []      # Open access, no cover charge
	var not_admitted: Array = []    # Has cover charge but not admitted

	for t in territories:
		if not (t is Dictionary):
			continue
		var admitted: bool = t.get("admitted", false)
		var cover_charge: int = t.get("cover_charge", -1)
		if cover_charge == 0:
			free_qings.append(t)
		elif admitted:
			paid_admitted.append(t)
		else:
			not_admitted.append(t)

	# Header
	if paid_admitted.size() > 0:
		guest_list_label.append_text("[color=#55ff55][b]Joined QINGs (%d)[/b][/color]\n" % paid_admitted.size())
		guest_list_label.append_text("[color=#888888]Admission lasts 24 hours[/color]\n\n")
	else:
		guest_list_label.append_text("[color=#aaaaaa][b]Guest List[/b][/color]\n\n")

	# Show paid-admitted QINGs first (these are the ones the user actively joined)
	for territory in paid_admitted:
		_render_guest_entry(territory, true)

	if paid_admitted.is_empty() and not_admitted.is_empty():
		# No QINGs with cover charges at all
		guest_list_label.append_text("[color=#888888]No QINGs with cover charges found.\n")
		guest_list_label.append_text("All %d QINGs are open access.[/color]\n\n" % free_qings.size())
	elif paid_admitted.is_empty() and not_admitted.size() > 0:
		guest_list_label.append_text("[color=#888888]Not admitted to any gated QINGs.[/color]\n\n")

	# Show not-admitted gated QINGs
	if not_admitted.size() > 0:
		guest_list_label.append_text("\n[color=#ff8855][b]Gated QINGs (%d)[/b][/color]\n" % not_admitted.size())
		guest_list_label.append_text("[color=#888888]Requires Join tx + cover charge[/color]\n\n")
		for territory in not_admitted:
			_render_guest_entry(territory, false)

	# Show free QINGs count (don't list all ~260 individually)
	if free_qings.size() > 0:
		guest_list_label.append_text("\n[color=#aaddff][b]Open QINGs: %d[/b][/color]\n" % free_qings.size())
		guest_list_label.append_text("[color=#888888]No cover charge — freely accessible[/color]\n")


func _render_guest_entry(territory: Dictionary, admitted: bool) -> void:
	## Render a single QING entry in the guest list.
	var qing_name: String = territory.get("name", "???")
	var qing_addr: String = territory.get("address", "")
	var is_current: bool = qing_addr.to_lower() == GameManager.territory_address.to_lower()

	if is_current:
		guest_list_label.append_text("[color=#55ff55]> [b]%s[/b][/color]" % _escape_bbcode(qing_name))
		guest_list_label.append_text(" [color=#55ff55](here)[/color]")
	elif admitted:
		guest_list_label.append_text("[color=#aaddff]  %s[/color]" % _escape_bbcode(qing_name))
	else:
		guest_list_label.append_text("[color=#996666]  %s[/color]" % _escape_bbcode(qing_name))

	# Show truncated address
	if qing_addr.length() > 10:
		guest_list_label.append_text(" [color=#666666]%s[/color]" % _truncate_address(qing_addr))

	guest_list_label.append_text("\n")


# ─── Wallet Reopen ─────────────────────────────────────────────────────

func _reopen_wallet() -> void:
	## Reopen the wallet browser popup (W key).
	## Useful if the user closed the wallet window by accident.
	if ChainManager.is_wallet_connected():
		tx_status.text = "Wallet already connected"
		_auto_clear_tx_status(3.0)
		ChainManager.focus_wallet_page()
	else:
		tx_status.text = "Reopening wallet..."
		_auto_clear_tx_status(5.0)
		ChainManager.reopen_wallet_page()


# ─── Batch Terraform Handlers ───────────────────────────────────────────

func _on_batch_count_changed(value: float) -> void:
	## Update the batch controller when the user changes the count spinner.
	if _batch_terraform:
		_batch_terraform.set_batch_count(int(value))


func _on_batch_progress(op_name: String, current: int, total: int) -> void:
	batch_status.text = "%s %d/%d" % [op_name, current, total]
	tx_status.text = "%s (%d/%d) — confirm in your wallet" % [op_name, current, total]
	# Only focus wallet page on first tx — subsequent txs keep the wallet page open
	# Calling focus_wallet_page() repeatedly opens new browser tabs
	if current == 1:
		ChainManager.focus_wallet_page()


func _on_batch_completed(op_name: String, total: int) -> void:
	_set_terraform_buttons_disabled(false)
	batch_status.text = "%s x%d done!" % [op_name, total]
	tx_status.text = "%s batch complete! (%dx) Refreshing..." % [op_name, total]
	_auto_clear_tx_status(5.0)
	_generate_random_seed()


func _on_batch_failed(op_name: String, error: String, completed: int) -> void:
	_set_terraform_buttons_disabled(false)
	batch_status.text = "%s failed at %d" % [op_name, completed + 1]
	tx_status.text = "%s batch failed: %s (%d completed)" % [op_name, error.left(40), completed]
	_auto_clear_tx_status(6.0)


# ─── Territory Lifecycle (Phase 8) ───────────────────────────────────────

func _on_leave_pressed() -> void:
	## Show confirmation dialog before leaving territory.
	if not ChainManager.is_wallet_connected():
		tx_status.text = "Connect wallet first"
		_auto_clear_tx_status(3.0)
		return
	if GameManager.lau_address.is_empty():
		tx_status.text = "No LAU identity loaded"
		_auto_clear_tx_status(3.0)
		return

	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Leave this territory?\n\nYou can rejoin later if you have admission."
	dialog.title = "Leave Territory"
	dialog.ok_button_text = "Leave"
	dialog.confirmed.connect(_on_leave_confirmed.bind(dialog))
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _on_leave_confirmed(dialog: ConfirmationDialog) -> void:
	dialog.queue_free()
	var tx_id := ChainManager.leave_territory()
	if tx_id >= 0:
		_pending_leave_tx = tx_id
		tx_status.text = "Leaving territory... confirm in wallet"
		ChainManager.focus_wallet_page()
	else:
		tx_status.text = "Failed to send Leave tx"
		_auto_clear_tx_status(4.0)


func _on_void_pressed() -> void:
	## Show scary confirmation dialog before voiding identity.
	if not ChainManager.is_wallet_connected():
		tx_status.text = "Connect wallet first"
		_auto_clear_tx_status(3.0)
		return
	if GameManager.lau_address.is_empty():
		tx_status.text = "No LAU identity loaded"
		_auto_clear_tx_status(3.0)
		return

	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "VOID YOUR IDENTITY?\n\nThis is IRREVERSIBLE!\nYour LAU will be completely reset.\nAll accumulated state (Saat, On) will be destroyed."
	dialog.title = "Void Identity"
	dialog.ok_button_text = "VOID"
	dialog.confirmed.connect(_on_void_confirmed.bind(dialog))
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _on_void_confirmed(dialog: ConfirmationDialog) -> void:
	dialog.queue_free()
	var tx_id := ChainManager.void_identity()
	if tx_id >= 0:
		_pending_void_tx = tx_id
		tx_status.text = "Voiding identity... confirm in wallet"
		ChainManager.focus_wallet_page()
	else:
		tx_status.text = "Failed to send Void tx"
		_auto_clear_tx_status(4.0)


func _on_lifecycle_tx_confirmed(id: int, _hash: String) -> void:
	## Handle Leave or Void tx confirmation — clear state and return to menu.
	if id == _pending_leave_tx:
		_pending_leave_tx = -1
		print("[HUD] Leave tx confirmed — clearing territory and returning to menu")
		GameManager.clear_territory()
		ChainManager.stop_chat_polling()
		ChainManager.stop_global_chat_polling()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	elif id == _pending_void_tx:
		_pending_void_tx = -1
		print("[HUD] Void tx confirmed — clearing identity and territory, returning to menu")
		GameManager.clear_identity()
		GameManager.clear_territory()
		ChainManager.stop_chat_polling()
		ChainManager.stop_global_chat_polling()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ─── Inventory Panel (Phase 9) ──────────────────────────────────────────

func _toggle_inventory_panel() -> void:
	if _inventory_visible:
		_close_inventory_panel()
	else:
		_open_inventory_panel()


func _open_inventory_panel() -> void:
	_inventory_visible = true
	inventory_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if GameManager.lau_wallet.is_empty():
		inventory_list.clear()
		inventory_list.append_text("[color=#888888]Connect wallet to view balances.\n\nUse the main menu to connect.[/color]")
	else:
		# Show cached balances or trigger a load
		var balances := ChainManager.get_token_balances()
		if balances.size() > 0:
			_render_token_balances(balances)
		else:
			inventory_list.clear()
			inventory_list.append_text("[color=#888888]Loading balances...[/color]")
			ChainManager.load_token_balances()


func _close_inventory_panel() -> void:
	_inventory_visible = false
	inventory_panel.visible = false
	_try_recapture_mouse()


func _refresh_inventory() -> void:
	if GameManager.lau_wallet.is_empty():
		return
	inventory_list.clear()
	inventory_list.append_text("[color=#888888]Refreshing balances...[/color]")
	ChainManager.load_token_balances()


func _on_token_balances_updated(balances: Dictionary) -> void:
	if _inventory_visible:
		_render_token_balances(balances)


func _render_token_balances(balances: Dictionary) -> void:
	inventory_list.clear()

	if balances.is_empty():
		inventory_list.append_text("[color=#888888]No token balances found.[/color]")
		return

	inventory_list.append_text("[b]Token Balances[/b]\n\n")

	for token_addr in balances:
		var info: Dictionary = balances[token_addr]
		var symbol: String = info.get("symbol", "???")
		var display: String = info.get("display", "0")
		var raw_hex: String = info.get("balance_hex", "0x0")

		inventory_list.append_text("[color=#a78bfa][b]%s[/b][/color]: %s" % [
			_escape_bbcode(symbol), _escape_bbcode(display)])
		inventory_list.append_text(" [url=copy:%s][color=#8b5cf6]📋[/color][/url]\n" % _escape_bbcode(raw_hex))

	inventory_list.append_text("\n[color=#666666]Wallet: %s[/color]" % _truncate_address(GameManager.lau_wallet))


# ─── Leaderboard (Phase 11) ─────────────────────────────────────────────

var _leaderboard_panel: PanelContainer
var _leaderboard_list: RichTextLabel

func _create_leaderboard_panel() -> void:
	## Create leaderboard panel dynamically (no scene node needed).
	_leaderboard_panel = PanelContainer.new()
	_leaderboard_panel.name = "LeaderboardPanel"
	_leaderboard_panel.visible = false

	# Style: dark semi-transparent panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.5, 0.6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_leaderboard_panel.add_theme_stylebox_override("panel", style)

	# Anchor: center of screen
	_leaderboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	_leaderboard_panel.custom_minimum_size = Vector2(420, 500)
	_leaderboard_panel.position = Vector2(-210, -250)

	var vbox := VBoxContainer.new()
	vbox.name = "LeaderboardVBox"

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Leaderboard [L]"
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	header.add_child(HSeparator.new())  # Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_leaderboard)
	header.add_child(close_btn)
	var refresh_btn := Button.new()
	refresh_btn.text = "↻"
	refresh_btn.pressed.connect(_refresh_leaderboard)
	header.add_child(refresh_btn)
	vbox.add_child(header)

	# Content
	_leaderboard_list = RichTextLabel.new()
	_leaderboard_list.name = "LeaderboardList"
	_leaderboard_list.bbcode_enabled = true
	_leaderboard_list.scroll_active = true
	_leaderboard_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_leaderboard_list.custom_minimum_size = Vector2(400, 420)
	_leaderboard_list.meta_clicked.connect(_on_meta_clicked)
	vbox.add_child(_leaderboard_list)

	_leaderboard_panel.add_child(vbox)
	add_child(_leaderboard_panel)


func _toggle_leaderboard() -> void:
	if _leaderboard_visible:
		_close_leaderboard()
	else:
		_open_leaderboard()


func _open_leaderboard() -> void:
	if not _leaderboard_panel:
		_create_leaderboard_panel()
		ChainManager.leaderboard_loaded.connect(_on_leaderboard_loaded)
		ChainManager.activity_feed_loaded.connect(_on_activity_feed_loaded)
		ChainManager.online_players_loaded.connect(_on_online_players_loaded)

	_leaderboard_visible = true
	_leaderboard_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Show loading state and fetch
	_leaderboard_list.clear()
	_leaderboard_list.append_text("[color=#888888]Loading leaderboard...[/color]")
	ChainManager.load_leaderboard()
	ChainManager.load_activity_feed()
	ChainManager.load_online_players()


func _close_leaderboard() -> void:
	_leaderboard_visible = false
	if _leaderboard_panel:
		_leaderboard_panel.visible = false
	_try_recapture_mouse()


func _refresh_leaderboard() -> void:
	if not _leaderboard_list:
		return
	_leaderboard_list.clear()
	_leaderboard_list.append_text("[color=#888888]Refreshing...[/color]")
	# Clear cache to force fresh fetch
	ChainManager._cached_leaderboard = {}
	ChainManager.load_leaderboard()


func _on_leaderboard_loaded(data: Dictionary) -> void:
	if not _leaderboard_visible or not _leaderboard_list:
		return
	_render_leaderboard(data)


func _render_leaderboard(data: Dictionary) -> void:
	_leaderboard_list.clear()

	if data.is_empty():
		_leaderboard_list.append_text("[color=#ff6666]Failed to load leaderboard.[/color]\n")
		_leaderboard_list.append_text("[color=#888888]Check your internet connection.[/color]")
		return

	# Global stats
	var totals: Dictionary = data.get("totals", {})
	if not totals.is_empty():
		_leaderboard_list.append_text("[color=#a78bfa][b]═══ DYSNOMIA LEADERBOARD ═══[/b][/color]\n")
		_leaderboard_list.append_text("[color=#888888]Total Terraforms: %s  |  Beats: %s  |  Active: %s[/color]\n\n" % [
			str(totals.get("terraforms", 0)),
			str(totals.get("beats", 0)),
			str(totals.get("activePlayers", 0)),
		])

	# Terraform leaderboard
	var terraform_list: Array = data.get("terraform", [])
	if terraform_list.size() > 0:
		_leaderboard_list.append_text("[color=#60a5fa][b]🏔️ Top Terraformers[/b][/color]\n")
		for i in range(mini(terraform_list.size(), 15)):
			var entry: Dictionary = terraform_list[i]
			var name_str: String = entry.get("lauName", "")
			var addr: String = entry.get("address", "")
			var count: int = entry.get("count", 0)
			var display_name := name_str if not name_str.is_empty() else _truncate_address(addr)
			var rank_color := "#ffd700" if i == 0 else ("#c0c0c0" if i == 1 else ("#cd7f32" if i == 2 else "#cccccc"))
			_leaderboard_list.append_text("[color=%s]%2d. [b]%s[/b]  —  %d[/color]\n" % [
				rank_color, i + 1, _escape_bbcode(display_name), count])
		_leaderboard_list.append_text("\n")

	# Beats leaderboard
	var beats_list: Array = data.get("beats", [])
	if beats_list.size() > 0:
		_leaderboard_list.append_text("[color=#f472b6][b]🥁 Top Beat Callers[/b][/color]\n")
		for i in range(mini(beats_list.size(), 15)):
			var entry: Dictionary = beats_list[i]
			var name_str: String = entry.get("lauName", "")
			var addr: String = entry.get("address", "")
			var count: int = entry.get("count", 0)
			var display_name := name_str if not name_str.is_empty() else _truncate_address(addr)
			var rank_color := "#ffd700" if i == 0 else ("#c0c0c0" if i == 1 else ("#cd7f32" if i == 2 else "#cccccc"))
			_leaderboard_list.append_text("[color=%s]%2d. [b]%s[/b]  —  %d[/color]\n" % [
				rank_color, i + 1, _escape_bbcode(display_name), count])

	if terraform_list.is_empty() and beats_list.is_empty():
		_leaderboard_list.append_text("[color=#888888]No leaderboard data available yet.[/color]\n")

	# Footer
	var updated_at: int = data.get("updatedAt", 0)
	if updated_at > 0:
		_leaderboard_list.append_text("\n[color=#555555]Updated: %s[/color]" % _format_timestamp(updated_at))


func _on_activity_feed_loaded(events: Array) -> void:
	## Append recent activity to the leaderboard panel.
	if not _leaderboard_visible or not _leaderboard_list:
		return
	if events.is_empty():
		return

	_leaderboard_list.append_text("\n\n[color=#34d399][b]⚡ Recent Activity[/b][/color]\n")
	var count := mini(events.size(), 10)
	for i in range(count):
		var ev: Dictionary = events[i]
		var event_type: String = ev.get("type", "unknown")
		var from_name: String = ev.get("fromName", "")
		var from_addr: String = ev.get("from", "")
		var qing_name: String = ev.get("qingName", "")
		var ts: int = ev.get("timestamp", 0)

		var actor := from_name if not from_name.is_empty() else _truncate_address(from_addr)
		var icon := "🏔️" if event_type == "terraform" else ("🥁" if event_type == "beat" else ("🚪" if event_type == "join" else "💬"))
		var where := " @ %s" % _escape_bbcode(qing_name) if not qing_name.is_empty() else ""
		var when := _format_timestamp(ts) if ts > 0 else ""

		_leaderboard_list.append_text("[color=#888888]%s %s %s%s  %s[/color]\n" % [
			icon, _escape_bbcode(actor), event_type, where, when])


func _on_online_players_loaded(data: Dictionary) -> void:
	## Append online player count to the leaderboard panel.
	if not _leaderboard_visible or not _leaderboard_list:
		return

	var players: Array = data.get("players", [])
	var count: int = data.get("count", players.size())
	if count > 0:
		_leaderboard_list.append_text("\n\n[color=#fbbf24][b]🟢 Online Players: %d[/b][/color]\n" % count)
		for i in range(mini(players.size(), 10)):
			var p: Dictionary = players[i]
			var name_str: String = p.get("username", "")
			var addr: String = p.get("wallet", "")
			var qing: String = p.get("qingName", "")
			var display := name_str if not name_str.is_empty() else _truncate_address(addr)
			var where := " @ %s" % _escape_bbcode(qing) if not qing.is_empty() else ""
			_leaderboard_list.append_text("[color=#aaaaaa]  • %s%s[/color]\n" % [
				_escape_bbcode(display), where])


func _format_timestamp(ts_ms: int) -> String:
	## Format a Unix timestamp (ms) as a relative time string.
	var now_ms := Time.get_unix_time_from_system() * 1000
	var diff_s := int((now_ms - ts_ms) / 1000)
	if diff_s < 60:
		return "%ds ago" % diff_s
	elif diff_s < 3600:
		return "%dm ago" % (diff_s / 60)
	elif diff_s < 86400:
		return "%dh ago" % (diff_s / 3600)
	else:
		return "%dd ago" % (diff_s / 86400)


# ─── World Map (Phase 10) ───────────────────────────────────────────────

func _toggle_world_map() -> void:
	if _world_map_visible:
		_close_world_map()
	else:
		_open_world_map()


func open_world_map(shuttle_mode: bool) -> void:
	## Public entry: the Landing Pad shuttle terminal opens the map in shuttle mode.
	_shuttle_map = shuttle_mode
	_open_world_map()


var _shuttle_map: bool = false


func _open_world_map() -> void:
	# Load QING data from chain manager cache
	var qings := ChainManager.get_all_qings()
	if qings.is_empty():
		tx_status.text = "No QING map data — waiting for cache to load"
		_auto_clear_tx_status(4.0)
		return

	_world_map_visible = true
	world_map.visible = true
	world_map.initialize(qings, GameManager.territory_address)
	world_map.set_travel_context(_shuttle_map, ChainManager.get_joined_qings())
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_world_map() -> void:
	_shuttle_map = false
	_world_map_visible = false
	world_map.visible = false
	_try_recapture_mouse()


func _on_map_territory_selected(qing_address: String) -> void:
	## Player selected a QING on the world map to travel to.
	_close_world_map()
	map_territory_selected.emit(qing_address)


func _on_map_name_requested(qing_address: String) -> void:
	## World map requests a name for a QING (on select/hover).
	ChainManager.read_qing_name(qing_address)


func _on_qing_name_resolved(address: String, qing_name: String) -> void:
	## A QING name was resolved — forward to world map.
	if _world_map_visible:
		world_map.set_qing_name(address, qing_name)


# ─── Controls Help Screen ──────────────────────────────────────────────

var _controls_panel: PanelContainer
var _controls_list: RichTextLabel

func _create_controls_panel() -> void:
	## Create the controls help panel dynamically.
	_controls_panel = PanelContainer.new()
	_controls_panel.name = "ControlsPanel"
	_controls_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.35, 0.55, 0.7)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_controls_panel.add_theme_stylebox_override("panel", style)

	_controls_panel.set_anchors_preset(Control.PRESET_CENTER)
	_controls_panel.custom_minimum_size = Vector2(480, 520)
	_controls_panel.position = Vector2(-240, -260)

	var vbox := VBoxContainer.new()

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Controls [H]"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_controls)
	header.add_child(close_btn)
	vbox.add_child(header)

	# Content
	_controls_list = RichTextLabel.new()
	_controls_list.bbcode_enabled = true
	_controls_list.scroll_active = true
	_controls_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls_list.custom_minimum_size = Vector2(450, 440)
	_controls_list.add_theme_font_size_override("normal_font_size", 13)
	vbox.add_child(_controls_list)

	_controls_panel.add_child(vbox)
	add_child(_controls_panel)

	# Populate content
	_controls_list.clear()
	_controls_list.append_text("[color=#a78bfa][b]═══ DYSNOMIA — GAME CONTROLS ═══[/b][/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]Movement[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  WASD          Walk / Strafe\n")
	_controls_list.append_text("  Shift          Sprint\n")
	_controls_list.append_text("  Space         Jump (triple jump)\n")
	_controls_list.append_text("  Q               Toggle Fly Mode\n")
	_controls_list.append_text("  Space/Ctrl  Fly Up / Down (fly mode)[/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]Camera[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  Mouse         Look Around\n")
	_controls_list.append_text("  Scroll         Zoom In / Out\n")
	_controls_list.append_text("  Z               Cycle Camera (3rd → Free → 1st)[/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]Combat[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  Left Click   Fire Weapon\n")
	_controls_list.append_text("  1-4             Switch Weapon\n")
	_controls_list.append_text("  Scroll         Cycle Weapons[/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]Vehicles[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  V               Mount / Dismount Vehicle[/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]World[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  E               Interact (Monument / Join / Minigame)\n")
	_controls_list.append_text("[color=#cccccc]  K               Invite friends to this QING (Telegram)\n")
	_controls_list.append_text("[color=#cccccc]  Y               Things to do here · daily quests\n")
	_controls_list.append_text("  F               Toggle Flashlight\n")
	_controls_list.append_text("  Esc            Release / Capture Mouse[/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]Panels[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  H               Controls (this screen)\n")
	_controls_list.append_text("  T               Terraform Operations\n")
	_controls_list.append_text("  C               Chat Panel\n")
	_controls_list.append_text("  Enter / /     Open Chat Input\n")
	_controls_list.append_text("  M               World Map\n")
	_controls_list.append_text("  L               Leaderboard + Activity\n")
	_controls_list.append_text("  G               Guest List (Admitted QINGs)\n")
	_controls_list.append_text("  I                Inventory (Token Balances)\n")
	_controls_list.append_text("  P               Achievements\n")
	_controls_list.append_text("  O               Toggle Voice Chat\n")
	_controls_list.append_text("  N               Toggle Mini-Map\n")
	_controls_list.append_text("  B               Guestbook / Flags\n")
	_controls_list.append_text("  J                Daily Challenges\n")
	_controls_list.append_text("  Q (hold)     Emote Wheel\n")
	_controls_list.append_text("  F5              Reopen Wallet Page\n")
	_controls_list.append_text("  F6              Photo Mode\n")
	_controls_list.append_text("  F9              Settings Menu[/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]Photo Mode[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  WASD          Free Camera\n")
	_controls_list.append_text("  1-7             Filter (None/Sepia/Hi-Con/Cool/Warm/Noir/IR)\n")
	_controls_list.append_text("  F / G           Cycle Frame Overlay\n")
	_controls_list.append_text("  V               Toggle Vignette\n")
	_controls_list.append_text("  Up/Down     DOF Distance\n")
	_controls_list.append_text("  Enter          Capture Screenshot\n")
	_controls_list.append_text("  Esc             Exit Photo Mode[/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]Capture[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  F7              Screenshot (saved to Documents)\n")
	_controls_list.append_text("  F8              Start / Stop Screen Recording[/color]\n\n")

	_controls_list.append_text("[color=#60a5fa][b]Debug[/b][/color]\n")
	_controls_list.append_text("[color=#cccccc]  F3              Toggle Debug Info[/color]\n\n")

	_controls_list.append_text("[color=#888888]Close: H / Esc[/color]")


func _toggle_controls() -> void:
	if _controls_visible:
		_close_controls()
	else:
		_open_controls()


func _open_controls() -> void:
	if not _controls_panel:
		_create_controls_panel()
	_controls_visible = true
	_controls_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_controls() -> void:
	_controls_visible = false
	if _controls_panel:
		_controls_panel.visible = false
	_try_recapture_mouse()


# ─── Achievement Panel (Phase 12A) ──────────────────────────────────────

var _achievement_panel: PanelContainer
var _achievement_list: RichTextLabel

func _create_achievement_panel() -> void:
	## Create achievement panel dynamically.
	_achievement_panel = PanelContainer.new()
	_achievement_panel.name = "AchievementPanel"
	_achievement_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.94)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.84, 0.0, 0.4)
	style.set_content_margin_all(12)
	_achievement_panel.add_theme_stylebox_override("panel", style)

	_achievement_panel.set_anchors_preset(Control.PRESET_CENTER)
	_achievement_panel.custom_minimum_size = Vector2(440, 520)
	_achievement_panel.position = Vector2(-220, -260)

	var vbox := VBoxContainer.new()

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Achievements [P]"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_achievements)
	header.add_child(refresh_btn)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_achievement_panel)
	header.add_child(close_btn)
	vbox.add_child(header)

	# Content
	_achievement_list = RichTextLabel.new()
	_achievement_list.name = "AchievementList"
	_achievement_list.bbcode_enabled = true
	_achievement_list.scroll_active = true
	_achievement_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_achievement_list.custom_minimum_size = Vector2(420, 440)
	vbox.add_child(_achievement_list)

	_achievement_panel.add_child(vbox)
	add_child(_achievement_panel)


func _toggle_achievement_panel() -> void:
	if _achievement_visible:
		_close_achievement_panel()
	else:
		_open_achievement_panel()


func _open_achievement_panel() -> void:
	if not _achievement_panel:
		_create_achievement_panel()

	_achievement_visible = true
	_achievement_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_render_achievements()
	# Also refresh from server
	ChainManager.load_achievements()


func _close_achievement_panel() -> void:
	_achievement_visible = false
	if _achievement_panel:
		_achievement_panel.visible = false
	_try_recapture_mouse()


func _refresh_achievements() -> void:
	if _achievement_list:
		_achievement_list.clear()
		_achievement_list.append_text("[color=#888888]Refreshing...[/color]")
	ChainManager.load_achievements()
	# Re-render after a short delay for API response
	get_tree().create_timer(1.5).timeout.connect(_render_achievements)


func _render_achievements() -> void:
	if not _achievement_list:
		return
	_achievement_list.clear()

	var ac: Node = ChainManager.achievement_client
	if not ac:
		_achievement_list.append_text("[color=#888888]Achievement system loading...[/color]")
		return

	var unlocked: Dictionary = ac.get_all_unlocked()
	var total: int = ac.ACHIEVEMENTS.size()
	var count: int = unlocked.size()
	var total_xp: int = ac.get_total_xp()
	var title: String = ac.get_title()
	var tier: int = ac.get_tier()

	# Header stats
	_achievement_list.append_text("[b][color=#FFD700]%s[/color][/b]  (Tier %d)\n" % [title, tier])
	_achievement_list.append_text("[color=#aaaaaa]%d / %d unlocked  |  %d XP[/color]\n" % [count, total, total_xp])

	# Progress bar
	var pct: float = float(count) / float(total) * 100.0
	var bar_len: int = 30
	var filled: int = int(pct / 100.0 * bar_len)
	var bar: String = "[color=#FFD700]%s[/color][color=#333333]%s[/color]" % [
		"█".repeat(filled), "█".repeat(bar_len - filled)]
	_achievement_list.append_text("%s %.0f%%\n\n" % [bar, pct])

	# Tier progress
	var next_tier: Dictionary = _get_next_tier(total_xp)
	if not next_tier.is_empty():
		_achievement_list.append_text("[color=#888888]Next: %s at %d XP (%d to go)[/color]\n\n" % [
			next_tier.get("title", ""), next_tier.get("threshold", 0),
			next_tier.get("threshold", 0) - total_xp])

	# Group achievements by category
	_render_achievement_group("Distance", ["dist_500", "dist_2k", "dist_5k", "dist_10k", "dist_50k"], unlocked)
	_render_achievement_group("Session", ["jump_100", "alt_30", "sess_30m", "sess_60m"], unlocked)
	_render_achievement_group("Terraform", ["first_terraform", "terraform_10", "terraform_50", "terraform_100"], unlocked)
	_render_achievement_group("Beat", ["first_beat", "beat_10", "beat_50"], unlocked)
	_render_achievement_group("Level & Rank", ["level_5", "level_10", "level_20", "top_10_tf", "top_10_bt"], unlocked)
	_render_achievement_group("Territory", ["terr_3", "terr_10", "terr_25", "terr_visit_10"], unlocked)
	_render_achievement_group("Streaks", ["streak_3", "streak_7", "streak_14", "streak_30", "streak_7_ach"], unlocked)
	_render_achievement_group("Gameplay", [
		"pioneer_3", "first_chat", "explorer_5", "first_quest", "all_quests",
		"resource_10", "anomaly_1", "daily_complete", "first_emote", "first_flag",
		"challenge_1", "challenge_all"], unlocked)


func _render_achievement_group(group_name: String, ids: Array, unlocked: Dictionary) -> void:
	var group_count: int = 0
	for mid: String in ids:
		if unlocked.has(mid):
			group_count += 1

	_achievement_list.append_text("[b][color=#8b8bff]--- %s (%d/%d) ---[/color][/b]\n" % [
		group_name, group_count, ids.size()])

	var ac: Node = ChainManager.achievement_client
	for mid: String in ids:
		var ach: Dictionary = ac.ACHIEVEMENTS.get(mid, {})
		var name_str: String = ach.get("name", mid)
		var desc_str: String = ach.get("desc", "")
		var xp_val: int = ach.get("xp", 50)

		if unlocked.has(mid):
			_achievement_list.append_text("[color=#22c55e]✓[/color] [b]%s[/b]  [color=#FFD700]+%d XP[/color]\n" % [
				name_str, xp_val])
			_achievement_list.append_text("  [color=#666666]%s[/color]\n" % desc_str)
		else:
			_achievement_list.append_text("[color=#444444]🔒[/color] [color=#888888]%s[/color]\n" % name_str)
			_achievement_list.append_text("  [color=#555555]%s[/color]\n" % desc_str)
	_achievement_list.append_text("\n")


func _get_next_tier(current_xp: int) -> Dictionary:
	var ac_script = load("res://scripts/chain/achievement_client.gd")
	if ac_script == null:
		return {}
	for t: Dictionary in ac_script.TITLE_TIERS:
		if t["threshold"] > current_xp:
			return t
	return {}  # Already at max tier


# ─── Mini-Map (Phase 13C) ────────────────────────────────────────────────

const MinimapScript = preload("res://scripts/ui/minimap.gd")

func create_minimap(terrain_gen: Node3D) -> void:
	## Called from main.gd after terrain is generated.
	if _minimap:
		return
	_minimap = Control.new()
	_minimap.set_script(MinimapScript)
	_minimap.name = "Minimap"
	add_child(_minimap)
	_minimap.initialize(terrain_gen)
	_minimap_visible = Config.minimap_enabled
	_minimap.visible = _minimap_visible


func register_minimap_poi(poi_name: String, world_pos: Vector3, color: Color, poi_type: int) -> void:
	## Register a point of interest on the minimap.
	if _minimap:
		_minimap.add_poi(poi_name, world_pos, color, poi_type)


func update_minimap_creatures(positions: Array[Vector3]) -> void:
	if _minimap:
		_minimap.update_creatures(positions)


func update_minimap_remote_players(positions: Dictionary) -> void:
	if _minimap:
		_minimap.update_remote_players(positions)


func update_minimap_flags(positions: Array[Vector3]) -> void:
	if _minimap:
		_minimap.update_flags(positions)


func _toggle_minimap() -> void:
	_minimap_visible = not _minimap_visible
	if _minimap:
		_minimap.visible = _minimap_visible


# ─── Settings Menu (Phase 13A) ───────────────────────────────────────────

const SettingsMenuScript = preload("res://scripts/ui/settings_menu.gd")

func _toggle_settings() -> void:
	if _settings_visible:
		_close_settings()
	else:
		_open_settings()


func _open_settings() -> void:
	if not _settings_menu:
		_settings_menu = PanelContainer.new()
		_settings_menu.set_script(SettingsMenuScript)
		_settings_menu.name = "SettingsMenu"
		_settings_menu.visible = false
		add_child(_settings_menu)
		_settings_menu.settings_closed.connect(_close_settings)
	_settings_visible = true
	_settings_menu.show_menu()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_settings() -> void:
	_settings_visible = false
	if _settings_menu:
		_settings_menu.hide_menu()
	_try_recapture_mouse()


# ─── Voice Chat Toggle (Phase 12C) ──────────────────────────────────────

var _vc_enabled: bool = false

func _toggle_voice_chat() -> void:
	## O key — toggle voice chat on/off.
	if _vc_enabled:
		ChainManager.stop_voice_chat()
		_vc_enabled = false
		tx_status.text = "Voice chat disabled"
		_auto_clear_tx_status(3.0)
	else:
		ChainManager.start_voice_chat()
		_vc_enabled = true
		tx_status.text = "Voice chat enabled (O to disable)"
		_auto_clear_tx_status(4.0)


# ─── Screen Recording & Screenshots ─────────────────────────────────────

func _get_captures_dir() -> String:
	## Returns path to Dysnomia captures directory, creating it if needed.
	var docs_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var captures_dir := docs_dir.path_join("Dysnomia-Captures")
	if not DirAccess.dir_exists_absolute(captures_dir):
		DirAccess.make_dir_recursive_absolute(captures_dir)
	return captures_dir


func _take_screenshot() -> void:
	## F7 — Capture a single screenshot and save as PNG.
	var viewport := get_viewport()
	if not viewport:
		return

	# Wait for the frame to finish rendering
	await RenderingServer.frame_post_draw

	var img := viewport.get_texture().get_image()
	if not img:
		tx_status.text = "Screenshot failed — no image"
		_auto_clear_tx_status(3.0)
		return

	var captures_dir := _get_captures_dir()
	var datetime := Time.get_datetime_dict_from_system()
	var filename := "screenshot_%04d%02d%02d_%02d%02d%02d.png" % [
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"], datetime["second"]]
	var filepath := captures_dir.path_join(filename)

	var err := img.save_png(filepath)
	if err == OK:
		tx_status.text = "Screenshot saved: %s" % filename
		print("[HUD] Screenshot saved: %s" % filepath)
	else:
		tx_status.text = "Screenshot save failed (error %d)" % err
	_auto_clear_tx_status(4.0)


func _toggle_recording() -> void:
	## F8 — Start or stop screen recording (frame sequence).
	if _is_recording:
		_stop_recording()
	else:
		_start_recording()


func _start_recording() -> void:
	## Begin recording frames to a timestamped folder.
	var captures_dir := _get_captures_dir()
	var datetime := Time.get_datetime_dict_from_system()
	var folder_name := "recording_%04d%02d%02d_%02d%02d%02d" % [
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"], datetime["second"]]
	_record_folder = captures_dir.path_join(folder_name)
	DirAccess.make_dir_recursive_absolute(_record_folder)

	_is_recording = true
	_record_frame_count = 0
	_record_frame_timer = 0.0
	_record_start_time = Time.get_ticks_msec() / 1000.0

	# Create or show recording indicator
	if not _record_indicator:
		_record_indicator = Label.new()
		_record_indicator.name = "RecordIndicator"
		_record_indicator.add_theme_font_size_override("font_size", 16)
		_record_indicator.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		_record_indicator.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
		_record_indicator.add_theme_constant_override("shadow_offset_x", 1)
		_record_indicator.add_theme_constant_override("shadow_offset_y", 1)
		# Position top-right area, below FPS
		_record_indicator.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_record_indicator.position = Vector2(-220, 30)
		_record_indicator.size = Vector2(200, 30)
		_record_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_record_indicator)
	_record_indicator.visible = true
	_record_indicator.text = "⏺ REC  00:00  [0 frames]"

	tx_status.text = "Recording started (F8 to stop)"
	_auto_clear_tx_status(3.0)
	print("[HUD] Recording started: %s" % _record_folder)


func _stop_recording() -> void:
	## Stop recording and report results.
	_is_recording = false
	if _record_indicator:
		_record_indicator.visible = false

	var elapsed := Time.get_ticks_msec() / 1000.0 - _record_start_time
	var msg := "Recording saved: %d frames (%.0fs) → %s" % [
		_record_frame_count, elapsed, _record_folder.get_file()]
	tx_status.text = msg
	_auto_clear_tx_status(6.0)
	print("[HUD] Recording stopped: %d frames in %.1fs → %s" % [
		_record_frame_count, elapsed, _record_folder])


func _capture_frame() -> void:
	## Capture a single frame during recording.
	var viewport := get_viewport()
	if not viewport:
		return

	var img := viewport.get_texture().get_image()
	if not img:
		return

	var filename := "frame_%06d.png" % _record_frame_count
	var filepath := _record_folder.path_join(filename)
	img.save_png(filepath)
	_record_frame_count += 1


# ─── Pub Minigames (Phase 13E) ──────────────────────────────────────────

const MinigameManagerScript = preload("res://scripts/minigames/minigame_manager.gd")

func create_minigame_manager() -> void:
	## Called from main.gd to initialize the minigame system.
	if _minigame_manager:
		return
	_minigame_manager = Node.new()
	_minigame_manager.set_script(MinigameManagerScript)
	_minigame_manager.name = "MinigameManager"
	add_child(_minigame_manager)
	_minigame_manager.initialize(self)
	_minigame_manager.minigame_closed.connect(_on_minigame_closed)


func open_minigame(table_index: int) -> void:
	## Open a minigame by pub table index (called from main.gd).
	if not _minigame_manager:
		create_minigame_manager()
	if _minigame_active:
		return
	_minigame_active = true
	_minigame_manager.open_game(table_index)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_minigame() -> void:
	## Close the active minigame and return to gameplay.
	if _minigame_manager and _minigame_manager.is_game_active():
		_minigame_manager.close_game()
	_minigame_active = false
	_try_recapture_mouse()


func _on_minigame_closed() -> void:
	## Signal handler when minigame closes itself (X button or game_closed signal).
	_minigame_active = false
	_try_recapture_mouse()


# ─── Daily Challenges Panel (Phase 13F) ─────────────────────────────────

const DailyPanelScript = preload("res://scripts/ui/daily_panel.gd")

func _toggle_daily_panel() -> void:
	if _daily_visible:
		_close_daily_panel()
	else:
		_open_daily_panel()


func _open_daily_panel() -> void:
	if not _daily_panel:
		_daily_panel = PanelContainer.new()
		_daily_panel.set_script(DailyPanelScript)
		_daily_panel.name = "DailyPanel"
		_daily_panel.visible = false
		add_child(_daily_panel)
		_daily_panel.panel_closed.connect(_close_daily_panel)

	_daily_visible = true
	_daily_panel.show_panel()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Fetch daily challenges data
	ChainManager.load_daily_challenges()
	ChainManager.daily_loaded.connect(_on_daily_loaded, CONNECT_ONE_SHOT)


func _close_daily_panel() -> void:
	_daily_visible = false
	if _daily_panel:
		_daily_panel.hide_panel()
	_try_recapture_mouse()


func _on_daily_loaded(data: Dictionary) -> void:
	if _daily_panel and _daily_visible:
		_daily_panel.populate(data)


# ─── Emote Wheel (Phase 13F) ────────────────────────────────────────────

const EmoteWheelScript = preload("res://scripts/ui/emote_wheel.gd")

func _show_emote_wheel() -> void:
	if _emote_wheel_visible:
		return
	if not _emote_wheel:
		_emote_wheel = Control.new()
		_emote_wheel.set_script(EmoteWheelScript)
		_emote_wheel.name = "EmoteWheel"
		add_child(_emote_wheel)
		_emote_wheel.emote_selected.connect(_on_emote_selected)
		_emote_wheel.wheel_closed.connect(_hide_emote_wheel)

	_emote_wheel_visible = true
	_emote_wheel.show_wheel()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _hide_emote_wheel() -> void:
	_emote_wheel_visible = false
	if _emote_wheel:
		_emote_wheel.hide_wheel()
	_try_recapture_mouse()


func _release_emote_wheel() -> void:
	## Called when Q is released — select the hovered emote and close.
	if _emote_wheel and _emote_wheel_visible:
		if _emote_wheel.has_method("get_hovered_segment"):
			var seg: int = _emote_wheel.get_hovered_segment()
			if seg >= 0:
				_on_emote_selected(seg)
	_hide_emote_wheel()


func _on_emote_selected(emote_id: int) -> void:
	## Send emote to API and show locally.
	ChainManager.send_emote(emote_id)
	var emote_names := ["Wave", "Salute", "Dance", "Sit", "Point", "Laugh", "Shrug", "Clap"]
	var emote_icons := ["👋", "🫡", "💃", "🪑", "👉", "😂", "🤷", "👏"]
	if emote_id >= 0 and emote_id < emote_names.size():
		tx_status.text = "%s %s" % [emote_icons[emote_id], emote_names[emote_id]]
		_auto_clear_tx_status(2.0)


# ─── Weather Indicator (Phase 13I) ─────────────────────────────────────

func update_weather_indicator(state: int, weather_name: String) -> void:
	## Show/hide the weather indicator label at top-center.
	## state=0 is CLEAR (hide), any other state shows the weather name.
	if not _weather_label:
		return

	if state == 0:  # CLEAR
		# Fade out
		var tween := create_tween()
		tween.tween_property(_weather_label, "modulate:a", 0.0, 1.5)
		tween.tween_callback(func() -> void:
			_weather_label.visible = false
			_weather_label.text = ""
		)
	else:
		# Show weather event name with icon
		var icons := {1: "🌪️", 2: "☄️", 3: "☀️", 4: "⚡"}
		var icon: String = icons.get(state, "🌤️")
		_weather_label.text = "%s %s" % [icon, weather_name]
		_weather_label.modulate.a = 0.0
		_weather_label.visible = true
		# Fade in
		var tween := create_tween()
		tween.tween_property(_weather_label, "modulate:a", 1.0, 1.0)


func flash_screen(color: Color, duration: float) -> void:
	## Brief colored flash overlay, fades out over duration.
	if not _screen_flash:
		return
	_screen_flash.color = color
	var tween := create_tween()
	tween.tween_property(_screen_flash, "color:a", 0.0, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


# ─── Photo Mode (Phase 13K) ────────────────────────────────────────────

func _toggle_photo_mode() -> void:
	if _photo_mode_active:
		_exit_photo_mode()
	else:
		_enter_photo_mode()


func _enter_photo_mode() -> void:
	if not _player:
		return
	if _photo_mode_active:
		return

	# Create photo mode if needed
	if not _photo_mode:
		var PhotoModeScript = load("res://scripts/ui/photo_mode.gd")
		_photo_mode = CanvasLayer.new()
		_photo_mode.set_script(PhotoModeScript)
		_photo_mode.name = "PhotoMode"
		add_child(_photo_mode)
		_photo_mode.photo_mode_exited.connect(_on_photo_mode_exited)

	_photo_mode_active = true

	# Hide HUD panels during photo mode
	_set_hud_visibility(false)

	# Enter photo mode
	_photo_mode.enter_photo_mode(_player)


func _exit_photo_mode() -> void:
	if not _photo_mode_active:
		return
	_photo_mode_active = false
	if _photo_mode:
		_photo_mode.exit_photo_mode()
	_set_hud_visibility(true)


func _on_photo_mode_exited() -> void:
	_photo_mode_active = false
	_set_hud_visibility(true)


func _set_hud_visibility(show_hud: bool) -> void:
	## Show or hide all HUD panels for photo mode.
	fps_label.visible = show_hud and _debug_visible
	coords_label.visible = show_hud
	seed_label.visible = show_hud
	mode_label.visible = show_hud
	controls_button.visible = show_hud
	if _health_bar:
		_health_bar.visible = show_hud
	if _health_label:
		_health_label.visible = show_hud
	if _weapon_label:
		_weapon_label.visible = show_hud
	if _progression_label:
		_progression_label.visible = show_hud
	if _xp_bar:
		_xp_bar.visible = show_hud
	if _minimap:
		_minimap.visible = show_hud and _minimap_visible
	if _weather_label:
		_weather_label.visible = show_hud and _weather_label.text != ""
	if _player_count_label:
		_player_count_label.visible = show_hud
	if location_label:
		location_label.visible = show_hud


# ─── Guestbook / Flags Panel (Phase 13L) ────────────────────────────────

func _toggle_guestbook() -> void:
	if _guestbook_visible:
		_close_guestbook()
	else:
		_open_guestbook()


func _open_guestbook() -> void:
	if not _guestbook_panel:
		var GuestbookPanelScript = load("res://scripts/ui/guestbook_panel.gd")
		_guestbook_panel = PanelContainer.new()
		_guestbook_panel.set_script(GuestbookPanelScript)
		_guestbook_panel.name = "GuestbookPanel"
		add_child(_guestbook_panel)
		_guestbook_panel.panel_closed.connect(_close_guestbook)
		_guestbook_panel.plant_flag_requested.connect(_on_plant_flag_requested)
		ChainManager.flags_loaded.connect(_on_flags_loaded)
		ChainManager.flag_planted.connect(_on_flag_planted)

	_guestbook_visible = true
	_guestbook_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Load flags from API
	ChainManager.load_territory_flags()


func _close_guestbook() -> void:
	_guestbook_visible = false
	if _guestbook_panel:
		_guestbook_panel.visible = false
	_try_recapture_mouse()


func _on_flags_loaded(flags: Array) -> void:
	if _guestbook_panel and _guestbook_panel.has_method("populate"):
		_guestbook_panel.populate(flags)


func _on_plant_flag_requested(message: String) -> void:
	## Plant a flag at the player's current position.
	if not _player:
		if _guestbook_panel:
			_guestbook_panel.set_status("No player reference")
		return
	if not ChainManager.is_wallet_connected():
		if _guestbook_panel:
			_guestbook_panel.set_status("Connect wallet first")
		return
	ChainManager.plant_flag(message, _player.global_position)


func _on_flag_planted(success: bool, message: String) -> void:
	if _guestbook_panel:
		_guestbook_panel.set_status(message)
	if success:
		# Reload flags to show the new one
		ChainManager.load_territory_flags()
