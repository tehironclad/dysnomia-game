extends Control
## Main menu: seed input, Generate/Random, PulseChain territory loading,
## and LAU identity loading. Transitions to the main game scene.

@onready var seed_input: LineEdit = $VBoxContainer/SeedInput
@onready var generate_button: Button = $VBoxContainer/GenerateButton
@onready var random_button: Button = $VBoxContainer/RandomButton
@onready var territory_input: LineEdit = $VBoxContainer/TerritoryInput
@onready var chain_button: Button = $VBoxContainer/ChainButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var lau_input: LineEdit = $VBoxContainer/LAUInput
@onready var identity_button: Button = $VBoxContainer/IdentityButton
@onready var identity_status: Label = $VBoxContainer/IdentityStatus
@onready var wallet_button: Button = $VBoxContainer/WalletButton
@onready var wallet_status: Label = $VBoxContainer/WalletStatus
@onready var username_row: HBoxContainer = $VBoxContainer/UsernameRow
@onready var username_input: LineEdit = $VBoxContainer/UsernameRow/UsernameInput
@onready var username_button: Button = $VBoxContainer/UsernameRow/UsernameButton


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	seed_input.text = "42"
	seed_input.placeholder_text = "Enter terrain seed..."
	generate_button.pressed.connect(_on_generate)
	random_button.pressed.connect(_on_random)
	seed_input.text_submitted.connect(_on_seed_submitted)

	# Chain loading
	chain_button.pressed.connect(_on_chain_load)
	territory_input.text_submitted.connect(_on_territory_submitted)
	status_label.text = ""

	# Identity loading
	identity_button.pressed.connect(_on_identity_load)
	lau_input.text_submitted.connect(_on_lau_submitted)
	identity_status.text = ""

	# Wallet connection
	wallet_button.pressed.connect(_on_wallet_toggle)
	wallet_status.text = ""

	# Username setting (requires wallet)
	username_button.pressed.connect(_on_set_username)
	username_input.text_submitted.connect(_on_username_submitted)
	username_row.visible = false

	# Settings button (added dynamically below the existing controls)
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.name = "SettingsButton"
	$VBoxContainer.add_child(settings_btn)
	settings_btn.pressed.connect(_on_settings_pressed)

	# Pre-fill LAU from saved config
	if not Config.lau_address.is_empty():
		lau_input.text = Config.lau_address

	# If identity was already loaded (e.g. returning to menu), show it
	if GameManager.has_identity:
		identity_status.text = "Welcome, %s!" % GameManager.player_identity

	# If wallet already connected (e.g. returning to menu), show it
	if ChainManager.is_wallet_connected():
		_on_wallet_connected(ChainManager.get_wallet_address())
	else:
		username_row.visible = false

	# Connect to ChainManager signals
	ChainManager.territory_loaded.connect(_on_territory_loaded)
	ChainManager.territory_load_failed.connect(_on_territory_load_failed)
	ChainManager.loading_started.connect(_on_loading_started)
	ChainManager.loading_finished.connect(_on_loading_finished)
	ChainManager.identity_loaded.connect(_on_identity_loaded)
	ChainManager.identity_load_failed.connect(_on_identity_load_failed)
	ChainManager.wallet_connected.connect(_on_wallet_connected)
	ChainManager.wallet_disconnected.connect(_on_wallet_disconnected)
	ChainManager.tx_sent.connect(_on_tx_sent)
	ChainManager.tx_failed.connect(_on_tx_failed)


func _on_generate() -> void:
	if GameManager.is_chain_sourced:
		# Territory already loaded from chain — just enter the game
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	_start_game(seed_input.text)


func _on_random() -> void:
	var random_seed: int = randi()
	seed_input.text = str(random_seed)
	_start_game(str(random_seed))


func _on_seed_submitted(text: String) -> void:
	_start_game(text)


func _start_game(seed_text: String) -> void:
	var seed_value: int = seed_text.to_int() if seed_text.is_valid_int() else seed_text.hash()
	GameManager.is_chain_sourced = false
	GameManager.territory_address = "0x0"
	GameManager.set_terrain_seed(seed_value)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_chain_load() -> void:
	var address_text: String = territory_input.text.strip_edges()
	if address_text.is_empty():
		status_label.text = "Enter a QING contract address"
		return
	if HexUtils.is_valid_address(address_text):
		ChainManager.load_territory(address_text)
	elif address_text.is_valid_int():
		ChainManager.load_territory_by_waat(address_text.to_int())
	else:
		status_label.text = "Invalid address format (expected 0x... or a number)"


func _on_territory_submitted(_text: String) -> void:
	_on_chain_load()


func _on_territory_loaded(_data: Dictionary) -> void:
	if ChainManager.is_wallet_connected():
		# Wallet connected — stay on menu so user can set username, etc.
		status_label.text = "Territory loaded! Click Generate World to enter."
		generate_button.text = "Enter World"
	else:
		status_label.text = "Territory loaded! Generating world..."
		await get_tree().create_timer(0.5).timeout
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_territory_load_failed(message: String) -> void:
	status_label.text = message


func _on_loading_started() -> void:
	chain_button.disabled = true
	chain_button.text = "Loading..."
	identity_button.disabled = true
	status_label.text = "Reading chain data..."


func _on_loading_finished() -> void:
	chain_button.disabled = false
	chain_button.text = "Load from Chain"
	identity_button.disabled = false


# --- Identity ---

func _on_identity_load() -> void:
	var lau_text: String = lau_input.text.strip_edges()
	if lau_text.is_empty():
		identity_status.text = "Enter your LAU address (from entropy site)"
		return
	if not HexUtils.is_valid_address(lau_text):
		identity_status.text = "Invalid address format (expected 0x + 40 hex chars)"
		return
	identity_status.text = "Reading identity..."
	identity_button.disabled = true
	identity_button.text = "Loading..."
	ChainManager.load_identity(lau_text)


func _on_lau_submitted(_text: String) -> void:
	_on_identity_load()


func _on_identity_loaded(data: Dictionary) -> void:
	identity_button.disabled = false
	identity_button.text = "Load Identity"

	var username: String = data.get("username", "")
	var saat_0: int = data.get("saat_0", 0)
	var saat_1: int = data.get("saat_1", 0)
	var saat_2: int = data.get("saat_2", 0)
	var current_area: String = data.get("current_area", "")
	var wallet: String = data.get("wallet", "")
	var yue_address: String = data.get("yue_address", "")

	var identity_text := ""
	if not username.is_empty():
		identity_text = "Welcome, %s! (Soul: %d  Spirit: %d  Aura: %d)" % [username, saat_0, saat_1, saat_2]
	elif saat_0 > 0 or saat_1 > 0 or saat_2 > 0:
		identity_text = "Identity loaded (Soul: %d  Spirit: %d  Aura: %d)" % [saat_0, saat_1, saat_2]
	else:
		identity_text = "Identity loaded (no Saat data found)"

	# Show wallet and YUE if resolved
	if not wallet.is_empty():
		identity_text += "\nWallet: %s" % _truncate_address(wallet)
	if not yue_address.is_empty():
		identity_text += "  YUE: %s" % _truncate_address(yue_address)

	# Show if auto-loading territory from QING discovery
	if not current_area.is_empty() and HexUtils.is_valid_address(current_area):
		identity_text += "\nQING: %s — loading territory..." % _truncate_address(current_area)
		status_label.text = "Loading QING territory..."
	else:
		identity_text += "\nNo QING found — enter a territory address above"

	identity_status.text = identity_text


func _on_identity_load_failed(message: String) -> void:
	identity_button.disabled = false
	identity_button.text = "Load Identity"
	identity_status.text = message


func _truncate_address(addr: String) -> String:
	if addr.length() > 12:
		return addr.left(6) + "..." + addr.right(4)
	return addr


# --- Wallet ---

func _on_wallet_toggle() -> void:
	if ChainManager.is_wallet_connected():
		ChainManager.disconnect_wallet()
	else:
		wallet_status.text = "Starting wallet bridge..."
		wallet_button.disabled = true
		ChainManager.start_wallet_bridge()
		# Re-enable after a short delay (browser should be opening)
		await get_tree().create_timer(2.0).timeout
		if not ChainManager.is_wallet_connected():
			wallet_status.text = "Wallet page opened in browser — connect your wallet there"
		wallet_button.disabled = false


func _on_wallet_connected(address: String) -> void:
	wallet_status.text = "Wallet: %s" % _truncate_address(address)
	wallet_button.text = "Disconnect Wallet"
	username_row.visible = true


func _on_wallet_disconnected() -> void:
	wallet_status.text = ""
	wallet_button.text = "Connect Wallet"
	username_row.visible = false


# --- Username ---

var _pending_username_tx: int = -1

func _on_set_username() -> void:
	var name_text := username_input.text.strip_edges()
	if name_text.is_empty():
		wallet_status.text = "Enter a username first"
		return
	if not ChainManager.is_wallet_connected():
		wallet_status.text = "Connect wallet first"
		return
	if GameManager.lau_address.is_empty():
		wallet_status.text = "Load your identity first (LAU address above)"
		return
	username_button.disabled = true
	username_button.text = "Sending..."
	wallet_status.text = "Confirm transaction in your wallet..."
	_pending_username_tx = ChainManager.set_username(name_text)
	if _pending_username_tx >= 0:
		ChainManager.focus_wallet_page()
	if _pending_username_tx < 0:
		wallet_status.text = "Failed to send — check wallet connection"
		username_button.disabled = false
		username_button.text = "Set Username"
		_pending_username_tx = -1


func _on_username_submitted(_text: String) -> void:
	_on_set_username()


func _on_tx_sent(id: int, hash: String) -> void:
	if id == _pending_username_tx:
		wallet_status.text = "Username tx sent: %s..." % hash.left(14)
		username_button.disabled = false
		username_button.text = "Set Username"
		_pending_username_tx = -1


func _on_tx_failed(id: int, error: String) -> void:
	if id == _pending_username_tx:
		wallet_status.text = "Failed: %s" % error.left(50)
		username_button.disabled = false
		username_button.text = "Set Username"
		_pending_username_tx = -1


# --- Settings ---

const SettingsMenuScript = preload("res://scripts/ui/settings_menu.gd")
var _settings_menu: PanelContainer

func _on_settings_pressed() -> void:
	if _settings_menu and _settings_menu.visible:
		_settings_menu.hide_menu()
		return
	if not _settings_menu:
		_settings_menu = PanelContainer.new()
		_settings_menu.set_script(SettingsMenuScript)
		_settings_menu.name = "SettingsMenu"
		_settings_menu.visible = false
		add_child(_settings_menu)
		_settings_menu.settings_closed.connect(func(): _settings_menu.hide_menu())
	_settings_menu.show_menu()
