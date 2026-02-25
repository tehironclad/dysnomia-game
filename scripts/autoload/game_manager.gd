extends Node

# Dysnomia constants (from contracts)
const MOTZKIN_PRIME: int = 953467954114363

# Terrain state
var terrain_seed: int = 42
var terrain_params: Dictionary = {}

# Day/night cycle — Dysnomia orbits Eris in ~15.8 Earth days
# At dev scale: 1 full cycle = ~15 real minutes (900s)
# Later tied to PulseChain blocks
var time_of_day: float = 0.35 # Start at mid-morning
var day_cycle_speed: float = 0.0011 # Full cycle in ~900s (~15 min)

# Camera/player mode
var is_flying: bool = false
var is_first_person: bool = false

# Territory info (populated from chain in Phase 1+)
var territory_address: String = "0x0"
var territory_name: String = ""  # QING name from chain (e.g. "AFFECTION™ QING")
var territory_waat_hex: String = ""
var territory_entropy_hex: String = ""
var territory_owner: String = ""
var territory_entropy: int = 0
var territory_latitude: float = 0.0
var territory_longitude: float = 0.0
var player_identity: String = "Anonymous"
var is_chain_sourced: bool = false

# Identity state (populated from LAU in Phase 2+)
var lau_address: String = ""
var lau_username: String = ""
var lau_saat: Array[int] = [0, 0, 0]
var lau_owner: String = ""
var lau_current_area: String = ""
var lau_wallet: String = ""
var lau_yue_address: String = ""
var has_identity: bool = false

# Territory state (populated from Phase 3A reads: HECKE, XIE, YUE, AFFECTION)
var territory_latitude_hex: String = ""  # Raw 64-char int256 hex for MAP.GetMapQing lookups
var territory_longitude_hex: String = "" # Raw 64-char int256 hex for MAP.GetMapQing lookups
var territory_charge: int = 0
var territory_omicron: int = 0
var territory_omega: int = 0
var territory_hypobar: int = 0
var territory_epibar: int = 0
var faung_scalars: Dictionary = {}
var has_territory_state: bool = false

# Signals
signal terrain_seed_changed(new_seed: int)
signal terrain_params_changed(params: Dictionary)
signal time_of_day_changed(time: float)
signal fly_mode_changed(is_flying: bool)
signal camera_mode_changed(is_first_person: bool)
signal territory_data_changed(data: Dictionary)
signal identity_data_changed(data: Dictionary)
signal territory_state_changed(data: Dictionary)


func set_terrain_seed(seed_value: int) -> void:
	terrain_seed = seed_value
	terrain_params = seed_to_params(seed_value)
	terrain_seed_changed.emit(seed_value)
	terrain_params_changed.emit(terrain_params)


func seed_to_params(seed_value: int) -> Dictionary:
	# Normalize seed using Motzkin Prime (mirrors QING Waat % MotzkinPrime on-chain)
	var normalized: int = absi(seed_value) % MOTZKIN_PRIME if seed_value != 0 else 42

	return {
		"frequency": 0.005 + (normalized % 1000) / 100000.0,
		"max_height": 30.0 + (normalized % 10000) / 333.0,
		"lacunarity": 1.8 + (normalized % 100) / 250.0,
		"octaves": 5 + (normalized % 3),
		"gain": 0.4 + (normalized % 100) / 500.0,
		"biome_type": normalized % 4,
		"ridge_strength": 0.2 + (normalized % 100) / 200.0,
		"erosion_strength": 0.1 + (normalized % 100) / 500.0,
	}


func load_from_chain_data(qing_address: String, waat_hex: String, entropy_hex: String, owner_address: String, seed_value: int) -> void:
	territory_address = qing_address
	territory_waat_hex = waat_hex
	territory_entropy_hex = entropy_hex
	territory_owner = owner_address
	# Extract lower 64 bits of entropy for local use
	var entropy_stripped := HexUtils.strip_0x(entropy_hex)
	if entropy_stripped.length() > 16:
		entropy_stripped = entropy_stripped.right(16)
	territory_entropy = HexUtils.hex_to_int("0x" + entropy_stripped) if entropy_stripped.length() > 0 else 0
	is_chain_sourced = true
	set_terrain_seed(seed_value)
	territory_data_changed.emit({
		"address": qing_address,
		"name": territory_name,
		"waat_hex": waat_hex,
		"entropy_hex": entropy_hex,
		"owner": owner_address,
		"seed": seed_value,
	})


func load_identity_data(data: Dictionary) -> void:
	lau_address = data.get("lau_address", "")
	lau_username = data.get("username", "")
	lau_saat[0] = data.get("saat_0", 0)
	lau_saat[1] = data.get("saat_1", 0)
	lau_saat[2] = data.get("saat_2", 0)
	lau_owner = data.get("owner", "")
	lau_current_area = data.get("current_area", "")
	lau_wallet = data.get("wallet", "")
	lau_yue_address = data.get("yue_address", "")
	has_identity = true

	# Update player identity display name
	if not lau_username.is_empty():
		player_identity = lau_username
	elif not lau_address.is_empty():
		player_identity = HexUtils.strip_0x(lau_address).left(6) + "..." + lau_address.right(4)
	else:
		player_identity = "Anonymous"

	identity_data_changed.emit(data)


func is_territory_owner() -> bool:
	## Check if current LAU owner matches territory owner.
	if lau_owner.is_empty() or territory_owner.is_empty():
		return false
	return lau_owner.to_lower() == territory_owner.to_lower()


func load_territory_state(data: Dictionary) -> void:
	## Store territory state from Phase 3A reads (HECKE coords, XIE power, YUE bars, FAUNG).
	## HECKE coordinates are cosmically large integers (not geographic degrees).
	## Map to -90..+90 range for shader use and display.
	var raw_lat: int = data.get("latitude", 0)
	var raw_lon: int = data.get("longitude", 0)
	# Store raw hex for MAP.GetMapQing neighbor lookups (±1 arithmetic)
	territory_latitude_hex = data.get("latitude_hex", "")
	territory_longitude_hex = data.get("longitude_hex", "")
	# Use modular reduction to get a stable value in -90..+90 range
	# Sign is preserved from the int256 parsing (negative = South/West)
	var lat_sign := signf(float(raw_lat)) if raw_lat != 0 else 1.0
	var lon_sign := signf(float(raw_lon)) if raw_lon != 0 else 1.0
	territory_latitude = lat_sign * float(absi(raw_lat) % 90)
	territory_longitude = lon_sign * float(absi(raw_lon) % 180)
	territory_charge = data.get("charge", 0)
	territory_omicron = data.get("omicron", 0)
	territory_omega = data.get("omega", 0)
	territory_hypobar = data.get("hypobar", 0)
	territory_epibar = data.get("epibar", 0)
	faung_scalars = data.get("faung_scalars", {})
	has_territory_state = true
	territory_state_changed.emit(data)


func clear_territory() -> void:
	## Reset all territory state — used when leaving a territory.
	territory_address = "0x0"
	territory_name = ""
	territory_waat_hex = ""
	territory_entropy_hex = ""
	territory_owner = ""
	territory_entropy = 0
	territory_latitude = 0.0
	territory_longitude = 0.0
	territory_latitude_hex = ""
	territory_longitude_hex = ""
	territory_charge = 0
	territory_omicron = 0
	territory_omega = 0
	territory_hypobar = 0
	territory_epibar = 0
	faung_scalars = {}
	has_territory_state = false
	is_chain_sourced = false


func clear_identity() -> void:
	## Reset all identity state — used when voiding LAU.
	lau_address = ""
	lau_username = ""
	lau_saat = [0, 0, 0]
	lau_owner = ""
	lau_current_area = ""
	lau_wallet = ""
	lau_yue_address = ""
	has_identity = false
	player_identity = "Anonymous"


func toggle_fly_mode() -> void:
	is_flying = !is_flying
	fly_mode_changed.emit(is_flying)


func toggle_camera_mode() -> void:
	is_first_person = !is_first_person
	camera_mode_changed.emit(is_first_person)
