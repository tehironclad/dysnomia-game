extends Node
## High-level contract reading interface for Dysnomia contracts.
## Pre-computed function selectors — no keccak256 needed at runtime.

signal qing_data_received(data: Dictionary)
signal qing_lookup_result(qing_address: String)
signal chain_verified(chain_id: int)
signal read_error(message: String)
signal lau_data_received(data: Dictionary)
signal territory_state_received(data: Dictionary)
signal neighbor_qing_discovered(direction: int, data: Dictionary)
signal chat_logs_received(messages: Array)
signal global_chat_logs_received(messages: Array)
signal admitted_check_result(lau_address: String, admitted: bool)
signal token_balance_received(token_address: String, balance_hex: String, decimals: int)

# Contract addresses
const VOID_ADDRESS: String = "0x965b0d74591bf30327075a247c47dbf487dcff08"
const META_ADDRESS: String = "0xE77Bdae31b2219e032178d88504Cc0170a5b9B97"
const ZUO_ADDRESS: String = "0x583d1C1427308f7f96BFd3E0d7A3F9674D8BF8ec"
const HECKE_ADDRESS: String = "0x29A924D9B0233026B9844f2aFeB202F1791D7593"
const MAP_ADDRESS: String = "0xD3a7A95012Edd46Ea115c693B74c5e524b3DdA75"
const AFFECTION_ADDRESS: String = "0x24F0154C1dCe548AdF15da2098Fdd8B8A3B8151D"
const CHO_ADDRESS: String = "0xB6be11F0A788014C1F68C92F8D6CcC1AbF78F2aB" # Kept for future Soul lookups
const CHAN_ADDRESS: String = "0xe250bf9729076B14A8399794B61C72d0F4AeFcd8"
const XIE_ADDRESS: String = "0x4Df51741F2926525A21bF63E4769bA70633D2792"

# Pre-computed function selectors (keccak256 of signature, first 4 bytes)
const SEL_WAAT: String = "0xa138da0b"
const SEL_ENTROPY: String = "0x40c48dfa"
const SEL_CHO: String = "0x9d45c73f"
const SEL_GET_QING: String = "0xb6e9bf85"
const SEL_GWAT: String = "0x8dd6363c"
const SEL_OWNER: String = "0x8da5cb5b"
const SEL_USERNAME: String = "0xc584460d"
const SEL_CURRENT_AREA: String = "0x8e3bb9fb"
const SEL_ASSET: String = "0xdf42e80e"
const SEL_SAAT: String = "0x088aee78" # LAU.Saat(uint256) → uint64
const SEL_GET_ADDR_BY_SOUL: String = "0x60844f9d" # CHO.GetAddressBySoul(uint64)
const SEL_YAN: String = "0x18025d89" # CHAN.Yan(address) → YUE address
const SEL_COMPLIMENT: String = "0x3353268d" # HECKE.Compliment(uint256) → (int256, int256)
const SEL_POWER: String = "0x07cd2de8" # XIE.Power(uint256) → (uint256, uint256, uint256)
const SEL_BAR: String = "0xc253aded" # YUE.Bar(address) → (uint256, uint256)
const SEL_VIEW: String = "0x1686f265" # AFFECTION.View() → FAUNG struct
const SEL_GET_MAP_QING: String = "0x7326117b" # MAP.GetMapQing(int256, int256) → address
const SEL_NAME: String = "0x06fdde03" # ERC-20 name() → string
const SEL_ADMITTED: String = "0xdfffcc74" # QING.Admitted(address) → bool
const SEL_GET_USER_TOKEN: String = "0xe80c28bf" # CHO.GetUserTokenAddress(address) → address
const SEL_COVER_CHARGE: String = "0xe64a6c99" # QING.CoverCharge() → uint256
const SEL_BALANCE_OF: String = "0x70a08231" # ERC20.balanceOf(address) → uint256
const SEL_DECIMALS: String = "0x313ce567"   # ERC20.decimals() → uint8
const SEL_SYMBOL: String = "0x95d89b41"     # ERC20.symbol() → string

# Event topic hashes
const TOPIC_NEW_QING: String = "0x692bc76be0a4b0d71d90e36ee97b1f3c4141095ea3c22b01b9f620da2e4b5e2e"
const TOPIC_LOG_EVENT: String = "0x6b81130c485ac9b98332fa40c2e57900867815b0fe1497e1a168caf930fc9c9d"

# LOG_STORAGE contract address (emits LogEvent from all QINGs)
const LOG_STORAGE_ADDRESS: String = "0x7ae73c498a308247be73688c09c96b3fd06ddb84"

# Saat array: Saat[0]=Pole, Saat[1]=Soul (CHO key), Saat[2]=Aura
# Read via Saat(uint256) function call, not storage slots (storage layout varies by inheritance)

const RPCClientScript = preload("res://scripts/chain/rpc_client.gd")

var _rpc: Node
var _pending_qing: Dictionary = {}
var _pending_lau: Dictionary = {}
var _pending_state: Dictionary = {}


func _ready() -> void:
	_rpc = RPCClientScript.new()
	add_child(_rpc)


func set_rpc_url(url: String) -> void:
	_rpc.rpc_url = url


func get_rpc() -> Node:
	## Access the underlying RPC client (for direct calls like receipt polling).
	return _rpc


func verify_chain() -> void:
	_rpc.eth_chain_id(
		func(result_hex: String) -> void:
			var chain_id := HexUtils.hex_to_int(result_hex)
			chain_verified.emit(chain_id),
		func(error_msg: String) -> void:
			read_error.emit("Chain verification failed: " + error_msg)
	)


func read_qing(qing_address: String) -> void:
	## Read Waat, Entropy, and owner from a QING contract sequentially.
	_pending_qing = {"address": qing_address}

	# Step 1: Read Waat
	_rpc.eth_call(qing_address, SEL_WAAT,
		func(result_hex: String) -> void:
			_on_waat_result(result_hex),
		func(error_msg: String) -> void:
			_pending_qing.clear()
			read_error.emit("Failed to read Waat: " + error_msg)
	)


func _on_waat_result(result_hex: String) -> void:
	if result_hex == "0x" or result_hex.length() < 3:
		_pending_qing.clear()
		read_error.emit("Contract returned empty result — address may not be a QING contract")
		return

	_pending_qing["waat_hex"] = result_hex
	var addr: String = _pending_qing["address"]

	# Step 2: Read Entropy
	_rpc.eth_call(addr, SEL_ENTROPY,
		func(entropy_hex: String) -> void:
			_on_entropy_result(entropy_hex),
		func(error_msg: String) -> void:
			# Entropy read failed, but we have Waat — emit with what we have
			_pending_qing["entropy_hex"] = "0x0"
			_pending_qing["owner_hex"] = ""
			var data := _pending_qing.duplicate()
			_pending_qing.clear()
			qing_data_received.emit(data)
	)


func _on_entropy_result(result_hex: String) -> void:
	_pending_qing["entropy_hex"] = result_hex if result_hex.length() >= 3 else "0x0"
	var addr: String = _pending_qing["address"]

	# Step 3: Read owner
	_rpc.eth_call(addr, SEL_OWNER,
		func(owner_hex: String) -> void:
			_on_owner_result(owner_hex),
		func(_error_msg: String) -> void:
			# Owner read failed — emit with what we have
			_pending_qing["owner_hex"] = ""
			var data := _pending_qing.duplicate()
			_pending_qing.clear()
			qing_data_received.emit(data)
	)


func _on_owner_result(result_hex: String) -> void:
	_pending_qing["owner_hex"] = HexUtils.parse_address_result(result_hex)
	var addr: String = _pending_qing["address"]

	# Step 4: Read name (ERC-20 name())
	_rpc.eth_call(addr, SEL_NAME,
		func(name_hex: String) -> void:
			_pending_qing["name"] = HexUtils.parse_abi_string(name_hex)
			var data := _pending_qing.duplicate()
			_pending_qing.clear()
			qing_data_received.emit(data),
		func(_error_msg: String) -> void:
			# Name read failed — emit with what we have
			_pending_qing["name"] = ""
			var data := _pending_qing.duplicate()
			_pending_qing.clear()
			qing_data_received.emit(data)
	)


func lookup_qing_by_waat(waat_value: int) -> void:
	## Look up a QING contract address via ZUO.GetQing(uint256).
	var data_field := SEL_GET_QING + HexUtils.pad_uint256(waat_value)

	_rpc.eth_call(ZUO_ADDRESS, data_field,
		func(result_hex: String) -> void:
			var addr := HexUtils.parse_address_result(result_hex)
			if addr.is_empty():
				read_error.emit("No QING territory found for Waat value %d" % waat_value)
			else:
				qing_lookup_result.emit(addr),
		func(error_msg: String) -> void:
			read_error.emit("Failed to look up QING: " + error_msg)
	)


func read_lau(lau_address: String) -> void:
	## Read Username, Saat values, and owner from a LAU contract sequentially.
	_pending_lau = {"lau_address": lau_address}

	# Step 1: Read Username
	_rpc.eth_call(lau_address, SEL_USERNAME,
		func(result_hex: String) -> void:
			_on_lau_username_result(result_hex),
		func(error_msg: String) -> void:
			# Username failed — continue with default
			_pending_lau["username"] = ""
			_read_lau_saat_0()
	)


func _on_lau_username_result(result_hex: String) -> void:
	if result_hex == "0x" or result_hex.length() < 3:
		_pending_lau["username"] = ""
	else:
		var username := HexUtils.parse_abi_string(result_hex)
		_pending_lau["username"] = username if not username.is_empty() else ""
	_read_lau_saat_0()


func _read_lau_saat_0() -> void:
	var addr: String = _pending_lau["lau_address"]
	# Step 2: Read Saat(0) — Pole
	var data_field := SEL_SAAT + HexUtils.pad_uint256(0)
	_rpc.eth_call(addr, data_field,
		func(result_hex: String) -> void:
			_pending_lau["saat_0"] = HexUtils.parse_uint64_result(result_hex)
			_read_lau_saat_1(),
		func(_error_msg: String) -> void:
			_pending_lau["saat_0"] = 0
			_read_lau_saat_1()
	)


func _read_lau_saat_1() -> void:
	var addr: String = _pending_lau["lau_address"]
	# Step 3: Read Saat(1) — Soul (used as CHO key)
	# Store raw hex for CHO.GetAddressBySoul (avoids int64 overflow on large uint64 values)
	var data_field := SEL_SAAT + HexUtils.pad_uint256(1)
	_rpc.eth_call(addr, data_field,
		func(result_hex: String) -> void:
			_pending_lau["saat_1"] = HexUtils.parse_uint64_result(result_hex)
			# Keep raw hex of the uint64 portion for CHO lookup
			var hex := HexUtils.strip_0x(result_hex)
			if hex.length() > 16:
				hex = hex.right(16)
			_pending_lau["saat_1_hex"] = hex
			_read_lau_saat_2(),
		func(_error_msg: String) -> void:
			_pending_lau["saat_1"] = 0
			_pending_lau["saat_1_hex"] = ""
			_read_lau_saat_2()
	)


func _read_lau_saat_2() -> void:
	var addr: String = _pending_lau["lau_address"]
	# Step 4: Read Saat(2) — Aura
	var data_field := SEL_SAAT + HexUtils.pad_uint256(2)
	_rpc.eth_call(addr, data_field,
		func(result_hex: String) -> void:
			_pending_lau["saat_2"] = HexUtils.parse_uint64_result(result_hex)
			_read_lau_owner(),
		func(_error_msg: String) -> void:
			_pending_lau["saat_2"] = 0
			_read_lau_owner()
	)


func _read_lau_owner() -> void:
	var addr: String = _pending_lau["lau_address"]
	# Step 5: Read owner
	_rpc.eth_call(addr, SEL_OWNER,
		func(owner_hex: String) -> void:
			_pending_lau["owner"] = HexUtils.parse_address_result(owner_hex)
			_read_lau_current_area(),
		func(_error_msg: String) -> void:
			_pending_lau["owner"] = ""
			_read_lau_current_area()
	)


func _read_lau_current_area() -> void:
	var addr: String = _pending_lau["lau_address"]
	# Step 6: Read CurrentArea (which QING territory this LAU is in)
	_rpc.eth_call(addr, SEL_CURRENT_AREA,
		func(result_hex: String) -> void:
			var area := HexUtils.parse_address_result(result_hex)
			if not area.is_empty():
				_pending_lau["current_area"] = area
				_finalize_lau()
			else:
				# CurrentArea is empty — try MAP._qings[lau_address] fallback
				_read_map_qing_for_lau(),
		func(_error_msg: String) -> void:
			# CurrentArea call failed — try MAP fallback
			_read_map_qing_for_lau()
	)


func _read_map_qing_for_lau() -> void:
	## Fallback: scan MAP's NewQing events to find which QING has this LAU as its
	## Integrative (Asset). This mirrors the entropy site's findAndLoadQing() approach.
	## event NewQing(address Qing, address Integrative, uint256 Waat)
	## All three params are non-indexed, so they appear in the log's data field.
	var filter := {
		"address": MAP_ADDRESS,
		"topics": [TOPIC_NEW_QING],
		"fromBlock": "0x0",
		"toBlock": "latest",
	}

	_rpc.eth_get_logs(filter,
		func(result_json: String) -> void:
			_on_newqing_logs(result_json),
		func(_error_msg: String) -> void:
			_pending_lau["current_area"] = ""
			_finalize_lau()
	)


func _on_newqing_logs(result_json: String) -> void:
	## Parse NewQing event logs and find the one whose Integrative matches our LAU.
	## Each log's data field is ABI-encoded: (address Qing, address Integrative, uint256 Waat)
	## = 3 × 32 bytes = 192 hex chars (96 bytes).
	var lau_addr: String = _pending_lau["lau_address"].to_lower()

	var json := JSON.new()
	if json.parse(result_json) != OK or not (json.data is Array):
		_pending_lau["current_area"] = ""
		_finalize_lau()
		return

	var logs: Array = json.data
	for log_entry in logs:
		if not (log_entry is Dictionary):
			continue
		var data_hex: String = log_entry.get("data", "")
		var hex := HexUtils.strip_0x(data_hex)
		# Need at least 128 chars (64 for Qing address + 64 for Integrative address)
		if hex.length() < 128:
			continue
		# Integrative is the second 32-byte word (chars 64..127)
		var integrative := HexUtils.parse_address_result("0x" + hex.substr(64, 64))
		if integrative.to_lower() == lau_addr:
			# Found it! First 32-byte word is the QING address
			var qing_addr := HexUtils.parse_address_result("0x" + hex.substr(0, 64))
			if not qing_addr.is_empty():
				_pending_lau["current_area"] = qing_addr
				_finalize_lau()
				return

	# No matching QING found in any event
	_pending_lau["current_area"] = ""
	_finalize_lau()


func _finalize_lau() -> void:
	## After QING discovery, resolve wallet and YUE.
	## Chain: Soul (Saat[1]) → CHO.GetAddressBySoul(soul) → wallet → CHAN.Yan(wallet) → YUE.
	## Uses raw hex Soul to avoid GDScript int64 overflow on large uint64 values.
	var soul_hex: String = _pending_lau.get("saat_1_hex", "")
	if soul_hex.is_empty() or soul_hex == "0".repeat(soul_hex.length()):
		_pending_lau["wallet"] = ""
		_pending_lau["yue_address"] = ""
		_emit_lau_data()
		return
	_resolve_wallet_from_soul(soul_hex)


func _resolve_wallet_from_soul(soul_hex: String) -> void:
	## CHO.GetAddressBySoul(uint64 soul) → wallet address.
	## soul_hex is the raw uint64 hex (up to 16 chars) from Saat(1) function call.
	## Padded to 64 hex chars for ABI uint256 encoding.
	var padded := soul_hex
	# Ensure exactly 64 hex chars for ABI encoding
	while padded.length() < 64:
		padded = "0" + padded
	if padded.length() > 64:
		padded = padded.right(64)
	var data_field := SEL_GET_ADDR_BY_SOUL + padded
	_rpc.eth_call(CHO_ADDRESS, data_field,
		func(result_hex: String) -> void:
			var wallet := HexUtils.parse_address_result(result_hex)
			if wallet.is_empty():
				_pending_lau["wallet"] = ""
				_pending_lau["yue_address"] = ""
				_emit_lau_data()
				return
			_pending_lau["wallet"] = wallet
			_resolve_yue_from_wallet(wallet),
		func(_error_msg: String) -> void:
			_pending_lau["wallet"] = ""
			_pending_lau["yue_address"] = ""
			_emit_lau_data()
	)


func _resolve_yue_from_wallet(wallet: String) -> void:
	## CHAN.Yan(wallet) → YUE address
	var data_field := SEL_YAN + HexUtils.pad_address(wallet)
	_rpc.eth_call(CHAN_ADDRESS, data_field,
		func(result_hex: String) -> void:
			var yue := HexUtils.parse_address_result(result_hex)
			_pending_lau["yue_address"] = yue
			_emit_lau_data(),
		func(_error_msg: String) -> void:
			_pending_lau["yue_address"] = ""
			_emit_lau_data()
	)


func _emit_lau_data() -> void:
	var data := _pending_lau.duplicate()
	_pending_lau.clear()
	lau_data_received.emit(data)


# ─── Territory State Reads (Phase 3A) ───────────────────────────────────

func read_territory_state(qing_address: String, waat_hex: String, yue_address: String, wallet_address: String) -> void:
	## Read HECKE coordinates, XIE power, YUE bars, and AFFECTION FAUNG for a territory.
	## All reads are optional — each graceful-fails to defaults.
	_pending_state = {
		"qing_address": qing_address,
		"waat_hex": waat_hex,
		"yue_address": yue_address,
		"wallet_address": wallet_address,
		"latitude": 0,
		"longitude": 0,
		"charge": 0,
		"omicron": 0,
		"omega": 0,
		"hypobar": 0,
		"epibar": 0,
		"faung_scalars": {},
	}

	# Step 1: HECKE.Compliment(waat) → (longitude, latitude)
	# Waat is stored as hex — need to pass it as uint256
	var waat_stripped := HexUtils.strip_0x(waat_hex)
	var data_field := SEL_COMPLIMENT + _pad_hex_to_uint256(waat_stripped)

	_rpc.eth_call(HECKE_ADDRESS, data_field,
		func(result_hex: String) -> void:
			_on_compliment_result(result_hex),
		func(_error_msg: String) -> void:
			# HECKE failed — continue with default coordinates
			_read_xie_power()
	)


func _pad_hex_to_uint256(hex_str: String) -> String:
	## Left-pad a hex string (no 0x prefix) to 64 chars for ABI uint256 encoding.
	var hex := hex_str.to_lower()
	while hex.length() < 64:
		hex = "0" + hex
	# Truncate to 64 if somehow longer
	if hex.length() > 64:
		hex = hex.right(64)
	return hex


func _on_compliment_result(result_hex: String) -> void:
	var hex := HexUtils.strip_0x(result_hex)
	# Response: 2 × 32-byte words = 128 hex chars (longitude, latitude)
	if hex.length() >= 128:
		var lon_hex := hex.substr(0, 64)
		var lat_hex := hex.substr(64, 64)
		_pending_state["longitude"] = HexUtils.parse_int256_result("0x" + lon_hex)
		_pending_state["latitude"] = HexUtils.parse_int256_result("0x" + lat_hex)
		# Store raw hex for MAP.GetMapQing neighbor lookups
		_pending_state["longitude_hex"] = lon_hex
		_pending_state["latitude_hex"] = lat_hex
	_read_xie_power()


func _read_xie_power() -> void:
	## Step 2: XIE.Power(waat) → (charge, omicron, omega)
	var waat_stripped := HexUtils.strip_0x(_pending_state["waat_hex"])
	var data_field := SEL_POWER + _pad_hex_to_uint256(waat_stripped)

	_rpc.eth_call(XIE_ADDRESS, data_field,
		func(result_hex: String) -> void:
			_on_power_result(result_hex),
		func(_error_msg: String) -> void:
			# XIE failed — continue with zero power
			_read_yue_bar()
	)


func _on_power_result(result_hex: String) -> void:
	var hex := HexUtils.strip_0x(result_hex)
	# Response: 3 × 32-byte words = 192 hex chars (charge, omicron, omega)
	if hex.length() >= 192:
		# These are uint256 — use hex_mod with a large modulus to get safe int values
		_pending_state["charge"] = HexUtils.hex_mod("0x" + hex.substr(0, 64), GameManager.MOTZKIN_PRIME)
		_pending_state["omicron"] = HexUtils.hex_mod("0x" + hex.substr(64, 64), GameManager.MOTZKIN_PRIME)
		_pending_state["omega"] = HexUtils.hex_mod("0x" + hex.substr(128, 64), GameManager.MOTZKIN_PRIME)
	_read_yue_bar()


func _read_yue_bar() -> void:
	## Step 3: User's YUE.Bar(qing_address) → (hypobar, epibar).
	## Bar values are per-user — each user's YUE tracks their contributions to each territory.
	## If no YUE address was pre-resolved, resolve via CHAN.Yan(wallet) first.
	var yue_addr: String = _pending_state["yue_address"]
	if not yue_addr.is_empty() and HexUtils.is_valid_address(yue_addr):
		_read_bar_from_yue(yue_addr)
		return

	# No YUE yet — try to resolve via CHAN.Yan(wallet)
	var wallet: String = _pending_state["wallet_address"]
	if wallet.is_empty() or not HexUtils.is_valid_address(wallet):
		_read_affection_view()
		return

	var data_field := SEL_YAN + HexUtils.pad_address(wallet)
	_rpc.eth_call(CHAN_ADDRESS, data_field,
		func(result_hex: String) -> void:
			var resolved_yue := HexUtils.parse_address_result(result_hex)
			if resolved_yue.is_empty() or not HexUtils.is_valid_address(resolved_yue):
				_read_affection_view()
				return
			_pending_state["yue_address"] = resolved_yue
			_read_bar_from_yue(resolved_yue),
		func(_error_msg: String) -> void:
			_read_affection_view()
	)


func _read_bar_from_yue(yue_addr: String) -> void:
	## Call YUE.Bar(qing_address) on the given YUE contract.
	var qing_addr: String = _pending_state["qing_address"]
	var data_field := SEL_BAR + HexUtils.pad_address(qing_addr)

	_rpc.eth_call(yue_addr, data_field,
		func(result_hex: String) -> void:
			_on_bar_result(result_hex),
		func(_error_msg: String) -> void:
			_read_affection_view()
	)


func _on_bar_result(result_hex: String) -> void:
	var hex := HexUtils.strip_0x(result_hex)
	# Response: 2 × 32-byte words = 128 hex chars (hypobar, epibar)
	if hex.length() >= 128:
		_pending_state["hypobar"] = HexUtils.hex_mod("0x" + hex.substr(0, 64), GameManager.MOTZKIN_PRIME)
		_pending_state["epibar"] = HexUtils.hex_mod("0x" + hex.substr(64, 64), GameManager.MOTZKIN_PRIME)
	_read_affection_view()


func _read_affection_view() -> void:
	## Step 4: AFFECTION.View() → FAUNG scalars (requires wallet as 'from')
	var wallet: String = _pending_state["wallet_address"]
	if wallet.is_empty() or not HexUtils.is_valid_address(wallet):
		# No wallet — skip AFFECTION, emit what we have
		_emit_territory_state()
		return

	_rpc.eth_call_from(wallet, AFFECTION_ADDRESS, SEL_VIEW,
		func(result_hex: String) -> void:
			_on_view_result(result_hex),
		func(_error_msg: String) -> void:
			_emit_territory_state()
	)


func _on_view_result(result_hex: String) -> void:
	## Parse the 12 top-level FAUNG scalars from the View() response.
	## FAUNG layout: Rod (18 uint64 + 1 uint8 = 19 words), Cone (same = 19 words),
	## then 12 scalars: Phi, Eta, Mu, Xi, Sigma, Rho, Upsilon, Ohm, Pi, Omicron, Omega (uint64), Chi (uint8).
	## Each field occupies one 32-byte ABI word.
	## Rod starts at word 0, Cone at word 19, scalars start at word 38.
	var hex := HexUtils.strip_0x(result_hex)
	var scalar_offset := 38 * 64 # 38 words × 64 hex chars per word
	var scalar_names: Array[String] = ["phi", "eta", "mu", "xi", "sigma", "rho", "upsilon", "ohm", "pi", "omicron", "omega", "chi"]

	if hex.length() >= scalar_offset + 12 * 64:
		var scalars := {}
		for i in range(12):
			var word_hex := hex.substr(scalar_offset + i * 64, 64)
			scalars[scalar_names[i]] = HexUtils.parse_uint64_result("0x" + word_hex)
		_pending_state["faung_scalars"] = scalars

	_emit_territory_state()


func _emit_territory_state() -> void:
	var data := _pending_state.duplicate()
	_pending_state.clear()
	territory_state_received.emit(data)


# ─── Neighbor Discovery (Phase 4B) ──────────────────────────────────────
# Discovers real on-chain QING neighbors by:
# 1. Querying NewQing event logs from MAP → all QING addresses + Waat values
# 2. Calling HECKE.Compliment(Waat) for each → (lon, lat) coordinates
# 3. Finding the nearest QING in each cardinal direction (N/S/E/W)
# 4. Reading name() for those neighbors and emitting signals

# Direction constants matching TerritoryManager.Direction enum
const DIR_NORTH: int = 0
const DIR_SOUTH: int = 1
const DIR_EAST: int = 2
const DIR_WEST: int = 3

# All known QINGs from event log scan: [{address, waat_hex}]
var _all_qings: Array[Dictionary] = []
# QINGs with coordinates resolved: [{address, waat_hex, lat_hex, lon_hex}]
var _qings_with_coords: Array[Dictionary] = []
# Center territory coords for comparison (64-char hex strings)
var _center_lat_hex: String = ""
var _center_lon_hex: String = ""
var _center_address: String = ""
var _is_discovering: bool = false


func discover_neighbors(lat_hex: String, lon_hex: String) -> void:
	## Discover nearest on-chain QING neighbors in each cardinal direction.
	## Queries NewQing event logs, resolves HECKE coordinates, finds nearest 4.
	if lat_hex.is_empty() or lon_hex.is_empty():
		return
	if _is_discovering:
		return  # Already in progress

	_is_discovering = true
	_center_lat_hex = lat_hex.to_lower()
	_center_lon_hex = lon_hex.to_lower()
	_center_address = GameManager.territory_address.to_lower()

	# Fast path: try loading from local cache (instant, no RPC needed)
	if _load_qing_cache():
		_find_nearest_neighbors()
		return

	# Medium path: already have event log data in memory, just resolve coords
	_qings_with_coords.clear()
	if _all_qings.size() > 0:
		_resolve_all_coordinates()
		return

	# Slow path: full scan — query NewQing event logs from MAP contract
	_rpc.eth_get_logs(
		{
			"address": MAP_ADDRESS,
			"topics": [TOPIC_NEW_QING],
			"fromBlock": "0x0",
			"toBlock": "latest",
		},
		func(result_json: String) -> void:
			_parse_new_qing_events(result_json),
		func(error_msg: String) -> void:
			push_error("[ContractReader] NewQing event log query failed: " + error_msg)
			_is_discovering = false
	)


func _parse_new_qing_events(result_json: String) -> void:
	## Parse NewQing event logs to extract QING addresses and Waat values.
	## Event: NewQing(address Qing, address Integrative, uint256 Waat)
	## No indexed params → Topics[0] = event sig only.
	## Data = abi.encode(address, address, uint256) = 3 × 32 bytes = 192 hex chars.
	_all_qings.clear()

	var parsed = JSON.parse_string(result_json)
	if parsed == null or not (parsed is Array):
		push_error("[ContractReader] Failed to parse NewQing event logs")
		_is_discovering = false
		return

	var logs: Array = parsed
	for log in logs:
		if not (log is Dictionary):
			continue
		var data_hex: String = log.get("data", "0x0")
		var data := HexUtils.strip_0x(data_hex)

		# Need at least 3 × 64 = 192 hex chars (Qing addr + Integrative addr + Waat)
		if data.length() < 192:
			continue

		# Word 0 (chars 0-63): QING contract address (left-padded)
		var qing_addr := HexUtils.parse_address_result("0x" + data.substr(0, 64))
		if qing_addr.is_empty():
			continue

		# Word 2 (chars 128-191): Waat (uint256)
		var waat_hex := "0x" + data.substr(128, 64)

		_all_qings.append({
			"address": qing_addr,
			"waat_hex": waat_hex,
		})

	print("[ContractReader] Found %d QINGs from event logs" % _all_qings.size())

	if _all_qings.is_empty():
		_is_discovering = false
		return

	# Step 2: Resolve HECKE coordinates for all QINGs
	_resolve_all_coordinates()


func _resolve_all_coordinates() -> void:
	## Call HECKE.Compliment(Waat) for each QING to get (lon, lat).
	## Uses batch RPC for speed (50 calls per HTTP request).
	_qings_with_coords.clear()

	print("[ContractReader] Batch resolving HECKE coordinates for %d QINGs..." % _all_qings.size())

	# Build batch calls: HECKE.Compliment(Waat) for each QING
	var calls: Array = []
	for qing in _all_qings:
		var waat_stripped := HexUtils.strip_0x(qing.waat_hex)
		var data_field := SEL_COMPLIMENT + _pad_hex_to_uint256(waat_stripped)
		calls.append({"to": HECKE_ADDRESS, "data": data_field})

	_rpc.eth_call_batch(calls, func(results: Array) -> void:
		_on_hecke_batch_results(results)
	)


func _on_hecke_batch_results(results: Array) -> void:
	## Handle batch HECKE coordinate resolution results.
	var success_count: int = 0
	var error_count: int = 0

	for i in range(_all_qings.size()):
		var qing: Dictionary = _all_qings[i]
		var r: Dictionary = results[i] if i < results.size() else {}

		if not r.get("success", false):
			error_count += 1
			continue

		var hex := HexUtils.strip_0x(r.get("result", ""))
		if hex.length() >= 128:
			var lon_hex := hex.substr(0, 64).to_lower()
			var lat_hex := hex.substr(64, 64).to_lower()

			_qings_with_coords.append({
				"address": qing.address,
				"waat_hex": qing.waat_hex,
				"lat_hex": lat_hex,
				"lon_hex": lon_hex,
			})
			success_count += 1
		else:
			error_count += 1

	print("[ContractReader] HECKE batch resolution: %d resolved, %d errors, %d total" % [
		success_count, error_count, _all_qings.size()])

	_find_nearest_neighbors()


func _find_nearest_neighbors() -> void:
	## From all QINGs with coordinates, find the nearest in each cardinal direction.
	## Uses hex int256 comparison for full precision (no 64-bit truncation).
	## North = higher lat, South = lower lat, East = higher lon, West = lower lon.
	## "Nearest" = the QING whose primary-axis distance is smallest in that direction.
	print("[ContractReader] Resolving nearest neighbors from %d QINGs with coordinates" % _qings_with_coords.size())

	# Cache the resolved coordinates for future sessions
	if _qings_with_coords.size() > 0:
		_save_qing_cache()

	# Best candidate per direction: {address, waat_hex, lat_hex, lon_hex}
	var best: Dictionary = {}  # direction -> Dictionary

	for qing in _qings_with_coords:
		# Skip self (the center territory)
		if qing.address.to_lower() == _center_address:
			continue

		var lat_hex: String = qing.lat_hex
		var lon_hex: String = qing.lon_hex

		# Compare latitude: is this QING north or south of center?
		var lat_cmp: int = HexUtils.int256_compare(lat_hex, _center_lat_hex)
		# Compare longitude: is this QING east or west of center?
		var lon_cmp: int = HexUtils.int256_compare(lon_hex, _center_lon_hex)

		# North: lat > center (lat_cmp == 1), prefer closest lat
		if lat_cmp > 0:
			if not best.has(DIR_NORTH) or HexUtils.int256_compare(lat_hex, best[DIR_NORTH].lat_hex) < 0:
				best[DIR_NORTH] = {"address": qing.address, "waat_hex": qing.waat_hex, "lat_hex": lat_hex, "lon_hex": lon_hex}

		# South: lat < center (lat_cmp == -1), prefer closest lat (largest negative = closest to center)
		if lat_cmp < 0:
			if not best.has(DIR_SOUTH) or HexUtils.int256_compare(lat_hex, best[DIR_SOUTH].lat_hex) > 0:
				best[DIR_SOUTH] = {"address": qing.address, "waat_hex": qing.waat_hex, "lat_hex": lat_hex, "lon_hex": lon_hex}

		# East: lon > center (lon_cmp == 1), prefer closest lon
		if lon_cmp > 0:
			if not best.has(DIR_EAST) or HexUtils.int256_compare(lon_hex, best[DIR_EAST].lon_hex) < 0:
				best[DIR_EAST] = {"address": qing.address, "waat_hex": qing.waat_hex, "lat_hex": lat_hex, "lon_hex": lon_hex}

		# West: lon < center (lon_cmp == -1), prefer closest lon (largest = closest to center)
		if lon_cmp < 0:
			if not best.has(DIR_WEST) or HexUtils.int256_compare(lon_hex, best[DIR_WEST].lon_hex) > 0:
				best[DIR_WEST] = {"address": qing.address, "waat_hex": qing.waat_hex, "lat_hex": lat_hex, "lon_hex": lon_hex}

	# Step 3: Read name() for each nearest neighbor and emit
	var directions_to_resolve: Array[int] = []
	for dir in [DIR_NORTH, DIR_SOUTH, DIR_EAST, DIR_WEST]:
		if best.has(dir):
			directions_to_resolve.append(dir)

	if directions_to_resolve.is_empty():
		print("[ContractReader] No neighbors found in any direction")
		_is_discovering = false
		return

	var dir_labels := {DIR_NORTH: "North", DIR_SOUTH: "South", DIR_EAST: "East", DIR_WEST: "West"}
	for dir in directions_to_resolve:
		var b: Dictionary = best[dir]
		print("[ContractReader] %s neighbor: %s" % [dir_labels.get(dir, "?"), b.address])
		_read_neighbor_name_and_emit(dir, b.address, b.waat_hex)

	_is_discovering = false


func _read_neighbor_name_and_emit(direction: int, qing_address: String, waat_hex: String) -> void:
	## Read QING.name() and QING.CoverCharge() then emit neighbor_qing_discovered.
	## Uses batch RPC to read both in a single HTTP request.
	var calls: Array = [
		{"to": qing_address, "data": SEL_NAME},
		{"to": qing_address, "data": SEL_COVER_CHARGE},
	]
	_rpc.eth_call_batch(calls, func(results: Array) -> void:
		# Parse name
		var qing_name: String = ""
		var r_name = results[0] if results.size() > 0 else {}
		if r_name is Dictionary and r_name.get("success", false):
			qing_name = HexUtils.parse_abi_string(r_name.get("result", ""))
		if qing_name.is_empty():
			qing_name = HexUtils.strip_0x(qing_address).left(6) + "..." + qing_address.right(4)

		# Parse CoverCharge (uint256 — 0 means free entry)
		var cover_charge: int = 0
		var r_cc = results[1] if results.size() > 1 else {}
		if r_cc is Dictionary and r_cc.get("success", false):
			cover_charge = HexUtils.hex_to_int(r_cc.get("result", "0x0"))

		_emit_neighbor(direction, qing_address, qing_name, waat_hex, cover_charge)
	)


func _emit_neighbor(direction: int, qing_address: String, qing_name: String, waat_hex: String, cover_charge: int = 0) -> void:
	## Compute seed and emit the neighbor_qing_discovered signal.
	var seed_value := HexUtils.hex_mod(waat_hex, GameManager.MOTZKIN_PRIME)
	if seed_value == 0:
		seed_value = 42
	var has_cover: bool = cover_charge > 0
	if has_cover:
		print("[ContractReader] Neighbor %s has CoverCharge=%d" % [qing_address.left(10), cover_charge])
	neighbor_qing_discovered.emit(direction, {
		"address": qing_address,
		"name": qing_name,
		"waat_hex": waat_hex,
		"seed": seed_value,
		"cover_charge": cover_charge,
	})


# ─── QING Map Cache (user://qing_map.json) ─────────────────────────────

const QING_CACHE_PATH: String = "user://qing_map.json"
const BUNDLED_CACHE_PATH: String = "res://assets/data/qing_map.json"  # Ships with the game
const QING_CACHE_VERSION: int = 1
const CACHE_MAX_AGE: int = 86400  # 24 hours in seconds


func _save_qing_cache() -> void:
	## Save resolved QING coordinates to local cache for fast startup.
	var qings_array: Array = []
	for q in _qings_with_coords:
		qings_array.append({
			"address": q.address,
			"waat_hex": q.waat_hex,
			"lat_hex": q.lat_hex,
			"lon_hex": q.lon_hex,
		})

	var cache := {
		"version": QING_CACHE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"count": qings_array.size(),
		"qings": qings_array,
	}

	var file := FileAccess.open(QING_CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(cache, "\t"))
		file.close()
		print("[ContractReader] Saved %d QINGs to cache: %s" % [qings_array.size(), QING_CACHE_PATH])
	else:
		push_error("[ContractReader] Failed to write QING cache: %s" % QING_CACHE_PATH)


func _load_qing_cache() -> bool:
	## Load QING coordinates from local cache. Returns true if valid cache loaded.
	## Falls back to bundled cache shipped with the game on first launch.
	var cache_path := QING_CACHE_PATH
	var is_bundled := false

	if not FileAccess.file_exists(QING_CACHE_PATH):
		# First launch — try the bundled cache that ships with the game
		if FileAccess.file_exists(BUNDLED_CACHE_PATH):
			cache_path = BUNDLED_CACHE_PATH
			is_bundled = true
		else:
			return false

	var file := FileAccess.open(cache_path, FileAccess.READ)
	if not file:
		return false

	var json_str := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_str)
	if parsed == null or not (parsed is Dictionary):
		return false

	var cache: Dictionary = parsed
	if cache.get("version", 0) != QING_CACHE_VERSION:
		print("[ContractReader] QING cache version mismatch, re-scanning...")
		return false

	# Check cache age — refresh once per day to pick up new QINGs
	# Bundled cache skips the age check (it's always "old") — use it now, refresh in background
	if not is_bundled:
		var saved_at: int = cache.get("saved_at", 0)
		if saved_at > 0:
			var age: int = int(Time.get_unix_time_from_system()) - saved_at
			if age > CACHE_MAX_AGE:
				var hours := age / 3600.0
				print("[ContractReader] QING cache is %.1f hours old, refreshing..." % hours)
				return false

	var qings: Array = cache.get("qings", [])
	if qings.is_empty():
		return false

	_qings_with_coords.clear()
	for q in qings:
		if not (q is Dictionary):
			continue
		if q.get("address", "").is_empty() or q.get("lat_hex", "").is_empty():
			continue
		_qings_with_coords.append({
			"address": q.address,
			"waat_hex": q.get("waat_hex", "0x0"),
			"lat_hex": q.lat_hex,
			"lon_hex": q.get("lon_hex", ""),
		})

	var source := "bundled cache" if is_bundled else "cache"
	print("[ContractReader] Loaded %d QINGs from %s" % [_qings_with_coords.size(), source])
	return _qings_with_coords.size() > 0


# ─── Chat Log Reading (Phase 6) ──────────────────────────────────────────

func read_chat_logs(qing_address: String, from_block: String = "0x0") -> void:
	## Read LogEvent events from a QING contract.
	## LogEvent(string Username, uint64 Soul, uint64 Aura, string LogLine)
	## All 4 params are non-indexed → appear in data field.
	## ABI layout: 4 dynamic/static params, strings have offset pointers.
	var filter := {
		"address": qing_address,
		"topics": [TOPIC_LOG_EVENT],
		"fromBlock": from_block,
		"toBlock": "latest",
	}

	_rpc.eth_get_logs(filter,
		func(result_json: String) -> void:
			_parse_chat_logs(result_json, qing_address),
		func(error_msg: String) -> void:
			push_error("[ContractReader] Chat log query failed: " + error_msg)
			chat_logs_received.emit([])
	)


func _parse_chat_logs(result_json: String, qing_address: String) -> void:
	## Parse LogEvent logs into chat messages.
	## ABI encoding for (string, uint64, uint64, string):
	##   Word 0: offset to Username string data
	##   Word 1: Soul (uint64, right-padded in 32B)
	##   Word 2: Aura (uint64, right-padded in 32B)
	##   Word 3: offset to LogLine string data
	## Each string at its offset: [32B length][data padded to 32B]
	var parsed = JSON.parse_string(result_json)
	if parsed == null or not (parsed is Array):
		chat_logs_received.emit([])
		return

	var messages: Array[Dictionary] = []
	var logs: Array = parsed

	for log_entry in logs:
		if not (log_entry is Dictionary):
			continue
		var data_hex: String = log_entry.get("data", "")
		var hex := HexUtils.strip_0x(data_hex)

		# Need at least 4 words (256 hex chars) for the fixed-size portion
		if hex.length() < 256:
			continue

		# Word 0 (chars 0-63): offset to Username string
		var username_offset: int = HexUtils.hex_to_int("0x" + hex.substr(0, 64)) * 2  # byte offset → char offset
		# Word 1 (chars 64-127): Soul (uint64)
		var soul: int = HexUtils.parse_uint64_result("0x" + hex.substr(64, 64))
		# Word 2 (chars 128-191): Aura (uint64)
		var aura: int = HexUtils.parse_uint64_result("0x" + hex.substr(128, 64))
		# Word 3 (chars 192-255): offset to LogLine string
		var logline_offset: int = HexUtils.hex_to_int("0x" + hex.substr(192, 64)) * 2

		# Parse Username string at its offset
		var username := _read_abi_string_at(hex, username_offset)
		# Parse LogLine string at its offset
		var logline := _read_abi_string_at(hex, logline_offset)

		if logline.is_empty():
			continue  # Skip empty messages

		# Get block number for ordering
		var block_hex: String = log_entry.get("blockNumber", "0x0")
		var block_num: int = HexUtils.hex_to_int(block_hex)

		messages.append({
			"username": username if not username.is_empty() else "Anon",
			"soul": soul,
			"aura": aura,
			"message": logline,
			"block": block_num,
			"qing": qing_address,
		})

	# Sort by block number (ascending — oldest first)
	messages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.block < b.block
	)

	print("[ContractReader] Parsed %d chat messages from %s" % [messages.size(), qing_address])
	chat_logs_received.emit(messages)


func _read_abi_string_at(hex_data: String, char_offset: int) -> String:
	## Read an ABI-encoded string at a byte offset within the data field.
	## Layout at offset: [32B length][string bytes padded to 32B]
	if char_offset + 64 > hex_data.length():
		return ""
	var str_len := HexUtils.hex_to_int("0x" + hex_data.substr(char_offset, 64))
	if str_len <= 0 or str_len > 1000:
		return ""
	var data_start := char_offset + 64
	if data_start + str_len * 2 > hex_data.length():
		return ""
	var str_hex := hex_data.substr(data_start, str_len * 2)
	var bytes := PackedByteArray()
	for i in range(0, str_hex.length(), 2):
		if i + 1 >= str_hex.length():
			break
		var byte_val := HexUtils.hex_char_to_int(str_hex[i]) * 16 + HexUtils.hex_char_to_int(str_hex[i + 1])
		bytes.append(byte_val)
	return bytes.get_string_from_utf8()


# ─── Global Chat Log Reading (VOID level via LOG_STORAGE) ────────────────

func read_global_chat_logs(from_block: String = "0x0") -> void:
	## Read LogEvent events from LOG_STORAGE — captures all VOID-level chat.
	## LogEvent(uint64 Soul, uint64 Aura, string LogLine) — 3 params in data.
	## LogLine format: "<Username> message text"
	var filter := {
		"address": LOG_STORAGE_ADDRESS,
		"topics": [TOPIC_LOG_EVENT],
		"fromBlock": from_block,
		"toBlock": "latest",
	}

	_rpc.eth_get_logs(filter,
		func(result_json: String) -> void:
			_parse_global_chat_logs(result_json),
		func(error_msg: String) -> void:
			push_error("[ContractReader] Global chat log query failed: " + error_msg)
			global_chat_logs_received.emit([])
	)


func _parse_global_chat_logs(result_json: String) -> void:
	## Parse VOID-level LogEvent logs into chat messages.
	## ABI encoding for (uint64, uint64, string):
	##   Word 0 (chars 0-63):   Soul (uint64)
	##   Word 1 (chars 64-127): Aura (uint64)
	##   Word 2 (chars 128-191): offset to LogLine string
	## LogLine contains "<Username> message text"
	var parsed = JSON.parse_string(result_json)
	if parsed == null or not (parsed is Array):
		global_chat_logs_received.emit([])
		return

	var messages: Array[Dictionary] = []
	var logs: Array = parsed

	for log_entry in logs:
		if not (log_entry is Dictionary):
			continue
		var data_hex: String = log_entry.get("data", "")
		var hex := HexUtils.strip_0x(data_hex)

		# VOID format: 3 words minimum = 192 hex chars
		if hex.length() < 192:
			continue

		# Word 0: Soul (uint64)
		var soul: int = HexUtils.parse_uint64_result("0x" + hex.substr(0, 64))
		# Word 1: Aura (uint64)
		var aura: int = HexUtils.parse_uint64_result("0x" + hex.substr(64, 64))
		# Word 2: offset to LogLine string
		var logline_offset: int = HexUtils.hex_to_int("0x" + hex.substr(128, 64)) * 2

		# Parse LogLine string at its offset
		var logline := _read_abi_string_at(hex, logline_offset)
		if logline.is_empty():
			continue

		# Parse username from "<Username> message" format
		var username := "Anon"
		var message := logline
		if logline.begins_with("<"):
			var close_idx := logline.find(">")
			if close_idx > 1:
				username = logline.substr(1, close_idx - 1)
				# Skip "> " after the closing bracket
				message = logline.substr(close_idx + 1).strip_edges()

		# Get block number for ordering
		var block_hex: String = log_entry.get("blockNumber", "0x0")
		var block_num: int = HexUtils.hex_to_int(block_hex)

		messages.append({
			"username": username,
			"soul": soul,
			"aura": aura,
			"message": message,
			"block": block_num,
			"source": "global",
		})

	# Sort by block number (ascending)
	messages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.block < b.block
	)

	print("[ContractReader] Parsed %d global chat messages from LOG_STORAGE" % messages.size())
	global_chat_logs_received.emit(messages)


# ─── Admitted Checks ──────────────────────────────────────────────────────
# Check which QINGs a user's LAU is currently admitted to (24hr guestlist).
# Uses the QING map cache (_qings_with_coords) to know all QING addresses.

signal admitted_territories_received(territories: Array)  # [{address, name, waat_hex, admitted}]

var _admitted_results: Array[Dictionary] = []
var _admitted_lau_address: String = ""
var _admitted_total_queued: int = 0  # Total QINGs queued at scan start (for logging)
var _is_scanning_admitted: bool = false


func check_admitted(qing_address: String, lau_address: String) -> void:
	## Check if a single LAU address is admitted to a QING.
	## Emits admitted_check_result(lau_address, admitted).
	print("[ContractReader] Checking Admitted(%s) on QING %s" % [
		lau_address.left(10), qing_address.left(10)])
	var data_field := SEL_ADMITTED + HexUtils.pad_address(lau_address)
	_rpc.eth_call(qing_address, data_field,
		func(result_hex: String) -> void:
			var admitted := _parse_bool_result(result_hex)
			print("[ContractReader] Admitted result for %s on %s: %s (raw: %s)" % [
				lau_address.left(10), qing_address.left(10), str(admitted), result_hex.left(20)])
			admitted_check_result.emit(lau_address, admitted),
		func(error_msg: String) -> void:
			print("[ContractReader] Admitted check ERROR for %s: %s" % [
				qing_address.left(10), error_msg])
			admitted_check_result.emit(lau_address, false)
	)


func scan_admitted_territories(lau_address: String) -> void:
	## Scan ALL known QINGs to find which ones this LAU is admitted to.
	## Uses batch RPC for speed (50 calls per HTTP request instead of serial).
	## Emits admitted_territories_received with list of admitted QINGs.
	if _is_scanning_admitted:
		return  # Already scanning
	if lau_address.is_empty():
		admitted_territories_received.emit([])
		return

	# Use cached QING data — load cache if not already loaded
	if _qings_with_coords.is_empty():
		if not _load_qing_cache():
			print("[ContractReader] No QING cache available for admitted scan")
			admitted_territories_received.emit([])
			return

	_is_scanning_admitted = true
	_admitted_lau_address = lau_address
	_admitted_results.clear()

	var qing_list: Array = _qings_with_coords.duplicate()
	_admitted_total_queued = qing_list.size()
	print("[ContractReader] Batch scanning %d QINGs for admitted status of %s" % [
		_admitted_total_queued, lau_address.left(10) + "..."])

	# Build batch calls: Admitted(lau_address) on each QING
	var data_field := SEL_ADMITTED + HexUtils.pad_address(lau_address)
	var calls: Array = []
	for q in qing_list:
		calls.append({"to": q.address, "data": data_field})

	_rpc.eth_call_batch(calls, func(results: Array) -> void:
		_on_admitted_batch_results(qing_list, results)
	)


func _on_admitted_batch_results(qing_list: Array, results: Array) -> void:
	## Handle batch admitted check results. Now batch-read names for admitted QINGs.
	var admitted_qings: Array = []  # [{address, waat_hex}] for admitted ones
	var non_admitted: Array = []

	# Debug: log first 3 results to verify batch is working
	for dbg_i in range(mini(3, results.size())):
		var dbg_r = results[dbg_i]
		if dbg_r is Dictionary:
			print("[ContractReader] Batch result[%d]: success=%s result='%s'" % [
				dbg_i, str(dbg_r.get("success", "?")), str(dbg_r.get("result", "")).left(30)])
		else:
			print("[ContractReader] Batch result[%d]: unexpected type: %s" % [dbg_i, str(dbg_r).left(40)])

	for i in range(qing_list.size()):
		var q: Dictionary = qing_list[i]
		var r = results[i] if i < results.size() else {}
		var admitted := false
		if r is Dictionary and r.get("success", false):
			admitted = _parse_bool_result(r.get("result", ""))
		if admitted:
			admitted_qings.append(q)
		else:
			non_admitted.append(q)

	print("[ContractReader] Batch admitted check: %d admitted, %d not admitted, %d total" % [
		admitted_qings.size(), non_admitted.size(), qing_list.size()])

	# Add non-admitted results immediately (no detail read needed)
	for q in non_admitted:
		_admitted_results.append({
			"address": q.address,
			"name": q.address.left(6) + "..." + q.address.right(4),
			"waat_hex": q.get("waat_hex", "0x0"),
			"admitted": false,
			"cover_charge": -1,  # Unknown — not admitted so doesn't matter
		})

	if admitted_qings.is_empty():
		_finish_admitted_scan()
		return

	# Batch-read name() + CoverCharge() for admitted QINGs (interleaved: name, cc, name, cc, ...)
	var detail_calls: Array = []
	for q in admitted_qings:
		detail_calls.append({"to": q.address, "data": SEL_NAME})
		detail_calls.append({"to": q.address, "data": SEL_COVER_CHARGE})

	_rpc.eth_call_batch(detail_calls, func(detail_results: Array) -> void:
		_on_admitted_details_batch(admitted_qings, detail_results)
	)


func _on_admitted_details_batch(admitted_qings: Array, detail_results: Array) -> void:
	## Handle batch name + CoverCharge results for admitted QINGs.
	## Results are interleaved: [name0, cc0, name1, cc1, ...]
	for i in range(admitted_qings.size()):
		var q: Dictionary = admitted_qings[i]
		var name_idx: int = i * 2
		var cc_idx: int = i * 2 + 1

		# Parse name
		var r_name = detail_results[name_idx] if name_idx < detail_results.size() else {}
		var qing_name: String = ""
		if r_name is Dictionary and r_name.get("success", false):
			qing_name = HexUtils.parse_abi_string(r_name.get("result", ""))
		if qing_name.is_empty():
			qing_name = q.address.left(6) + "..." + q.address.right(4)

		# Parse CoverCharge
		var r_cc = detail_results[cc_idx] if cc_idx < detail_results.size() else {}
		var cover_charge: int = -1
		if r_cc is Dictionary and r_cc.get("success", false):
			cover_charge = HexUtils.hex_to_int(r_cc.get("result", "0x0"))

		_admitted_results.append({
			"address": q.address,
			"name": qing_name,
			"waat_hex": q.get("waat_hex", "0x0"),
			"admitted": true,
			"cover_charge": cover_charge,
		})

	_finish_admitted_scan()


func _finish_admitted_scan() -> void:
	## Finalize admitted scan: sort, log, emit signal.
	_is_scanning_admitted = false

	# Sort: admitted first, then by name
	_admitted_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.admitted != b.admitted:
			return a.admitted  # admitted = true sorts first
		return a.get("name", "").to_lower() < b.get("name", "").to_lower()
	)

	var admitted_count: int = 0
	for r in _admitted_results:
		if r.get("admitted", false):
			admitted_count += 1
	print("[ContractReader] Admitted scan complete: %d admitted out of %d QINGs" % [
		admitted_count, _admitted_results.size()])

	admitted_territories_received.emit(_admitted_results.duplicate())
	_admitted_results.clear()


func _parse_bool_result(result_hex: String) -> bool:
	## Parse a Solidity bool return value (any non-zero = true).
	## Handles both full 64-char ABI results and shortened RPC results like "0x1".
	var hex := HexUtils.strip_0x(result_hex)
	if hex.is_empty():
		return false
	# Strip leading zeros and check if anything remains
	var stripped := hex.lstrip("0")
	return not stripped.is_empty()


func is_scanning_admitted() -> bool:
	return _is_scanning_admitted


# ─── Hex Arithmetic for int256 ──────────────────────────────────────────

func _hex_add_one(hex64: String) -> String:
	## Add 1 to a 64-char hex string (int256 two's complement).
	## Propagates carry from least significant digit.
	var digits := hex64.to_lower()
	var arr := PackedByteArray()
	arr.resize(64)
	for i in range(64):
		arr[i] = HexUtils.hex_char_to_int(digits[i])

	# Add 1 from the right
	var carry: int = 1
	for i in range(63, -1, -1):
		var val: int = arr[i] + carry
		arr[i] = val % 16
		carry = val / 16
		if carry == 0:
			break

	# Convert back to hex string
	var result := ""
	for i in range(64):
		result += HexUtils.HEX_CHARS[arr[i]]
	return result


func _hex_sub_one(hex64: String) -> String:
	## Subtract 1 from a 64-char hex string (int256 two's complement).
	## Propagates borrow from least significant digit.
	var digits := hex64.to_lower()
	var arr := PackedByteArray()
	arr.resize(64)
	for i in range(64):
		arr[i] = HexUtils.hex_char_to_int(digits[i])

	# Subtract 1 from the right
	var borrow: int = 1
	for i in range(63, -1, -1):
		var val: int = arr[i] - borrow
		if val < 0:
			arr[i] = val + 16
			borrow = 1
		else:
			arr[i] = val
			borrow = 0
			break

	# Convert back to hex string
	var result := ""
	for i in range(64):
		result += HexUtils.HEX_CHARS[arr[i]]
	return result


# ─── ERC20 Token Balance (Phase 9) ──────────────────────────────────────

func read_token_balance(token_address: String, wallet_address: String) -> void:
	## Read an ERC20 token's decimals and balanceOf for the given wallet.
	## Emits token_balance_received(token_address, balance_hex, decimals).
	var addr := token_address.to_lower()
	var wallet := HexUtils.strip_0x(wallet_address).to_lower()
	# Pad wallet to 32 bytes for balanceOf(address) call data
	var padded_wallet := wallet.lstrip("0")
	padded_wallet = "0".repeat(64 - padded_wallet.length()) + padded_wallet

	# Step 1: Read decimals()
	_rpc.eth_call(addr, SEL_DECIMALS,
		func(decimals_hex: String) -> void:
			var decimals := HexUtils.hex_to_int(decimals_hex)
			if decimals <= 0:
				decimals = 18  # Default to 18 if decimals() fails or returns 0
			# Step 2: Read balanceOf(wallet)
			var balance_data := SEL_BALANCE_OF + padded_wallet
			_rpc.eth_call(addr, balance_data,
				func(balance_hex: String) -> void:
					token_balance_received.emit(addr, balance_hex, decimals),
				func(error: String) -> void:
					push_warning("[ContractReader] balanceOf failed for %s: %s" % [addr.left(12), error])
					token_balance_received.emit(addr, "0x0", decimals)
			),
		func(error: String) -> void:
			push_warning("[ContractReader] decimals() failed for %s: %s — defaulting to 18" % [addr.left(12), error])
			# Try balanceOf anyway with default 18 decimals
			var balance_data := SEL_BALANCE_OF + padded_wallet
			_rpc.eth_call(addr, balance_data,
				func(balance_hex: String) -> void:
					token_balance_received.emit(addr, balance_hex, 18),
				func(error2: String) -> void:
					push_warning("[ContractReader] balanceOf failed for %s: %s" % [addr.left(12), error2])
					token_balance_received.emit(addr, "0x0", 18)
			)
	)


# ─── QING Map Accessor (Phase 10) ──────────────────────────────────────

func get_cached_qings() -> Array[Dictionary]:
	## Return all cached QING coordinates for the world map.
	return _qings_with_coords


signal qing_name_resolved(address: String, qing_name: String)

func read_qing_name(qing_address: String) -> void:
	## Read the ERC-20 name() for a single QING and emit qing_name_resolved.
	_rpc.eth_call(qing_address, SEL_NAME,
		func(name_hex: String) -> void:
			var qing_name := HexUtils.parse_abi_string(name_hex)
			qing_name_resolved.emit(qing_address.to_lower(), qing_name),
		func(_error_msg: String) -> void:
			qing_name_resolved.emit(qing_address.to_lower(), "")
	)


func read_all_qing_names() -> void:
	## Batch-read name() for all cached QINGs, emitting qing_name_resolved for each.
	for q in _qings_with_coords:
		read_qing_name(q.address)
