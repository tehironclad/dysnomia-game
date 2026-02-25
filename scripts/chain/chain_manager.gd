extends Node
## ChainManager autoload singleton.
## Orchestrates chain reads, caches territory data, and bridges
## between blockchain state and the game's terrain generation pipeline.

signal chain_connected
signal chain_disconnected
signal territory_loaded(data: Dictionary)
signal territory_load_failed(message: String)
signal loading_started
signal loading_finished
signal identity_loaded(data: Dictionary)
signal identity_load_failed(message: String)
signal territory_state_loaded(data: Dictionary)
signal wallet_connected(address: String)
signal wallet_disconnected
signal tx_sent(id: int, hash: String)
signal tx_confirmed(id: int, hash: String)
signal tx_failed(id: int, error: String)
signal neighbor_discovered(direction: int, data: Dictionary)
signal chat_messages_received(messages: Array)
signal global_chat_received(messages: Array)
signal guest_list_loaded(guests: Array)
signal admitted_territories_loaded(territories: Array)
signal token_balances_updated(balances: Dictionary)

const ContractReaderScript = preload("res://scripts/chain/contract_reader.gd")
const WalletBridgeScript = preload("res://scripts/chain/wallet_bridge.gd")
const AchievementClientScript = preload("res://scripts/chain/achievement_client.gd")
const DailyChallengesScript = preload("res://scripts/chain/daily_challenges.gd")
const AllianceClientScript = preload("res://scripts/chain/alliance_client.gd")
const EmoteClientScript = preload("res://scripts/chain/emote_client.gd")
const FlagClientScript = preload("res://scripts/chain/flag_client.gd")

const CACHE_DURATION: float = 300.0 # 5 minutes
const CHAIN_ID_PULSECHAIN: int = 369
const CHOA_ADDRESS: String = "0x0f5a352fd4cA4850c2099C15B3600ff085B66197"

var _reader: Node
var _wallet_bridge: Node
var _territory_cache: Dictionary = {}
var _is_connected: bool = false
var _is_loading: bool = false
var _is_loading_identity: bool = false
var _current_qing_address: String = ""
var connected_wallet: String = ""
var achievement_client: Node  # AchievementClient instance
var daily_challenges: Node  # DailyChallenges instance
var alliance_client: Node  # AllianceClient instance
var emote_client: Node  # EmoteClient instance
var flag_client: Node  # FlagClient instance
var _terraform_tx_ids: Array[int] = []
var _chat_messages: Array[Dictionary] = []
var _chat_last_ts: int = 0  # Track highest timestamp (ms) for incremental API polling
var _chat_poll_timer: Timer
var _global_chat_messages: Array[Dictionary] = []
var _global_chat_last_ts: int = 0  # Track highest timestamp (ms) for global polling
var _global_chat_poll_timer: Timer

# Entropy API chat system — cached endpoints, much faster than eth_getLogs
const ENTROPY_API_BASE: String = "https://entropy-dysnomia.vercel.app"
const CHAT_API_LIMIT: int = 100
var _chat_api_http: HTTPRequest  # For territory chat API calls
var _global_chat_api_http: HTTPRequest  # For global chat API calls

# Godot-side fallback receipt polling — redundant with browser polling
# Handles cases where browser tab is throttled or WebSocket drops
var _pending_tx_receipts: Dictionary = {}  # tx_id -> {hash, poll_count, max_polls}
var _receipt_poll_timer: Timer
const RECEIPT_POLL_INTERVAL: float = 10.0  # Poll every 10s
const RECEIPT_MAX_POLLS: int = 36  # 36 * 10s = 6 minutes max


func _ready() -> void:
	_reader = ContractReaderScript.new()
	add_child(_reader)

	# Set RPC URL from config
	_reader.set_rpc_url(Config.rpc_url)

	# Connect signals
	_reader.qing_data_received.connect(_on_qing_data_received)
	_reader.qing_lookup_result.connect(_on_qing_lookup_result)
	_reader.chain_verified.connect(_on_chain_verified)
	_reader.read_error.connect(_on_read_error)
	_reader.lau_data_received.connect(_on_lau_data_received)
	_reader.territory_state_received.connect(_on_territory_state_received)
	_reader.neighbor_qing_discovered.connect(_on_neighbor_qing_discovered)
	_reader.chat_logs_received.connect(_on_chat_logs_received_fallback)
	_reader.global_chat_logs_received.connect(_on_global_chat_logs_received_fallback)
	_reader.admitted_territories_received.connect(_on_admitted_territories_received)
	_reader.admitted_check_result.connect(_on_admitted_check_result)
	_reader.token_balance_received.connect(_on_token_balance_received)
	_reader.qing_name_resolved.connect(func(addr: String, n: String) -> void:
		qing_name_resolved.emit(addr, n))

	# Chat polling timer (30 second interval)
	_chat_poll_timer = Timer.new()
	_chat_poll_timer.wait_time = 30.0
	_chat_poll_timer.one_shot = false

	# Receipt fallback polling timer (10 second interval)
	_receipt_poll_timer = Timer.new()
	_receipt_poll_timer.wait_time = RECEIPT_POLL_INTERVAL
	_receipt_poll_timer.one_shot = false
	_receipt_poll_timer.timeout.connect(_poll_pending_receipts)
	add_child(_receipt_poll_timer)
	_chat_poll_timer.timeout.connect(_poll_chat)
	add_child(_chat_poll_timer)

	# Global chat polling timer (30 second interval, independent of territory)
	_global_chat_poll_timer = Timer.new()
	_global_chat_poll_timer.wait_time = 30.0
	_global_chat_poll_timer.one_shot = false
	_global_chat_poll_timer.timeout.connect(_poll_global_chat)
	add_child(_global_chat_poll_timer)

	# Achievement client
	achievement_client = AchievementClientScript.new()
	achievement_client.name = "AchievementClient"
	add_child(achievement_client)

	# Daily challenges client
	daily_challenges = DailyChallengesScript.new()
	daily_challenges.name = "DailyChallenges"
	add_child(daily_challenges)

	# Alliance client
	alliance_client = AllianceClientScript.new()
	alliance_client.name = "AllianceClient"
	add_child(alliance_client)

	# Emote client
	emote_client = EmoteClientScript.new()
	emote_client.name = "EmoteClient"
	add_child(emote_client)

	# Flag/guestbook client
	flag_client = FlagClientScript.new()
	flag_client.name = "FlagClient"
	add_child(flag_client)

	# HTTP request nodes for entropy API chat
	_chat_api_http = HTTPRequest.new()
	_chat_api_http.timeout = 15.0
	_chat_api_http.request_completed.connect(_on_territory_chat_api_response)
	add_child(_chat_api_http)

	_global_chat_api_http = HTTPRequest.new()
	_global_chat_api_http.timeout = 15.0
	_global_chat_api_http.request_completed.connect(_on_global_chat_api_response)
	add_child(_global_chat_api_http)

	# Initialize wallet bridge
	_wallet_bridge = WalletBridgeScript.new()
	add_child(_wallet_bridge)
	_wallet_bridge.wallet_connected.connect(_on_wallet_connected)
	_wallet_bridge.wallet_disconnected.connect(_on_wallet_disconnected)
	_wallet_bridge.tx_result.connect(_on_tx_result)
	_wallet_bridge.tx_confirmed.connect(_on_tx_confirmed)
	_wallet_bridge.tx_failed.connect(_on_tx_failed)

	# Wire multiplayer signals from wallet bridge
	_connect_multiplayer_signals()

	# Wire Phase 13F forwarding signals
	_connect_phase_13f_signals()

	# Verify chain connectivity on startup
	_reader.verify_chain()


func load_territory(qing_address: String) -> void:
	## Load territory data from a QING contract address.
	var addr := qing_address.strip_edges().to_lower()
	if not HexUtils.is_valid_address(addr):
		territory_load_failed.emit("Invalid address format. Expected 0x followed by 40 hex characters.")
		return

	# Check cache
	if _territory_cache.has(addr):
		var cached: Dictionary = _territory_cache[addr]
		var age: float = Time.get_unix_time_from_system() - cached.get("timestamp", 0.0)
		if age < CACHE_DURATION:
			_apply_territory_data(cached)
			territory_loaded.emit(cached)
			return

	# Make chain read
	_is_loading = true
	_current_qing_address = addr
	loading_started.emit()
	_reader.read_qing(addr)


func load_territory_by_waat(waat_value: int) -> void:
	## Look up a QING contract by Waat value, then load it.
	_is_loading = true
	loading_started.emit()
	_reader.lookup_qing_by_waat(waat_value)


func is_loading() -> bool:
	return _is_loading


func clear_cache() -> void:
	_territory_cache.clear()


func _on_chain_verified(chain_id: int) -> void:
	if chain_id == CHAIN_ID_PULSECHAIN:
		_is_connected = true
		chain_connected.emit()
	else:
		_is_connected = false
		chain_disconnected.emit()


func _on_qing_lookup_result(qing_address: String) -> void:
	# Got a QING address from ZUO.GetQing — now load it
	_current_qing_address = qing_address
	_reader.read_qing(qing_address)


func _on_qing_data_received(data: Dictionary) -> void:
	var addr: String = data.get("address", _current_qing_address)
	data["address"] = addr

	# Compute terrain seed from Waat
	var waat_hex: String = data.get("waat_hex", "0x0")
	var seed_value: int = HexUtils.hex_mod(waat_hex, GameManager.MOTZKIN_PRIME)
	if seed_value == 0:
		seed_value = 42
	data["seed"] = seed_value

	# Cache
	data["timestamp"] = Time.get_unix_time_from_system()
	_territory_cache[addr] = data

	# Bridge to GameManager
	_apply_territory_data(data)

	_is_loading = false
	loading_finished.emit()
	territory_loaded.emit(data)

	# Auto-read territory state (Phase 3A: HECKE coords, XIE power, YUE bars, AFFECTION FAUNG)
	_auto_read_territory_state(addr, waat_hex)

	# Auto-load chat history for this territory (Phase 6)
	clear_chat()
	start_chat_polling()


func _on_read_error(message: String) -> void:
	_is_loading = false
	loading_finished.emit()
	territory_load_failed.emit(message)


func load_identity(lau_address: String) -> void:
	## Load identity data from a LAU contract address.
	var addr := lau_address.strip_edges().to_lower()
	if not HexUtils.is_valid_address(addr):
		identity_load_failed.emit("Invalid LAU address format. Expected 0x followed by 40 hex characters.")
		return

	_is_loading_identity = true
	loading_started.emit()
	_reader.read_lau(addr)


func _on_lau_data_received(data: Dictionary) -> void:
	_is_loading_identity = false
	loading_finished.emit()

	# Check if we got meaningful data (at least username or non-zero saat)
	var username: String = data.get("username", "")
	var saat_0: int = data.get("saat_0", 0)
	var saat_1: int = data.get("saat_1", 0)
	var saat_2: int = data.get("saat_2", 0)

	# Bridge to GameManager
	GameManager.load_identity_data(data)

	# Save LAU address for next session
	Config.lau_address = data.get("lau_address", "")
	Config.save_settings()

	identity_loaded.emit(data)

	# Auto-load territory if CurrentArea is set
	var current_area: String = data.get("current_area", "")
	if not current_area.is_empty() and HexUtils.is_valid_address(current_area):
		load_territory(current_area)


func _apply_territory_data(data: Dictionary) -> void:
	## Push chain data into GameManager to trigger terrain generation.
	# Store territory name before load_from_chain_data (which emits the signal)
	var tname: String = data.get("name", "")
	if not tname.is_empty():
		GameManager.territory_name = tname
	GameManager.load_from_chain_data(
		data.get("address", ""),
		data.get("waat_hex", "0x0"),
		data.get("entropy_hex", "0x0"),
		data.get("owner_hex", ""),
		data.get("seed", 42)
	)


func _auto_read_territory_state(qing_address: String, waat_hex: String) -> void:
	## Automatically read territory state after a territory loads.
	## Uses whatever identity data is already available (YUE, wallet).
	var yue_address: String = GameManager.lau_yue_address
	var wallet_address: String = GameManager.lau_wallet
	_reader.read_territory_state(qing_address, waat_hex, yue_address, wallet_address)


func _on_territory_state_received(data: Dictionary) -> void:
	## Bridge territory state from ContractReader to GameManager.
	# If YUE was resolved during territory state reads, update GameManager
	var resolved_yue: String = data.get("yue_address", "")
	if not resolved_yue.is_empty() and GameManager.lau_yue_address.is_empty():
		GameManager.lau_yue_address = resolved_yue
	GameManager.load_territory_state(data)
	territory_state_loaded.emit(data)


# ─── Wallet Bridge ────────────────────────────────────────────────────────

func start_wallet_bridge() -> void:
	## Start the wallet bridge server and open the wallet page in the browser.
	## Safe to call multiple times — won't restart a running server or open duplicate tabs.
	if _wallet_bridge.is_wallet_connected():
		return  # Already connected, nothing to do
	# If server is already listening (waiting for browser to connect), just try opening page
	if _wallet_bridge.is_server_running():
		_wallet_bridge.open_wallet_page()  # No-op if already opened
		return
	# Fresh start — launch servers and open browser
	if _wallet_bridge.start_server(Config.wallet_bridge_port):
		_wallet_bridge.open_wallet_page()


func disconnect_wallet() -> void:
	## Disconnect the wallet and stop the bridge server.
	_wallet_bridge.stop_server()


func is_wallet_connected() -> bool:
	return _wallet_bridge.is_wallet_connected()


func get_wallet_address() -> String:
	return connected_wallet


func focus_wallet_page() -> void:
	_wallet_bridge.focus_wallet_page()


func reopen_wallet_page() -> void:
	## Force-reopen the wallet popup (e.g., if user closed the window).
	_wallet_bridge.reopen_wallet_page()


func _on_wallet_connected(address: String, _chain_id: int) -> void:
	connected_wallet = address
	if achievement_client:
		achievement_client.set_wallet(address)
	wallet_connected.emit(address)


func _on_wallet_disconnected() -> void:
	connected_wallet = ""
	wallet_disconnected.emit()


func _on_tx_result(id: int, hash: String) -> void:
	print("[ChainManager] Tx broadcast: id=%d hash=%s" % [id, hash.left(18)])
	tx_sent.emit(id, hash)
	# Start Godot-side fallback receipt polling for this tx
	if not hash.is_empty():
		_start_receipt_polling(id, hash)


func _on_tx_confirmed(id: int, hash: String) -> void:
	# Stop fallback polling for this tx (browser confirmed it)
	_stop_receipt_polling(id)
	print("[ChainManager] Transaction confirmed on-chain: %s" % hash)
	tx_confirmed.emit(id, hash)
	if id in _terraform_tx_ids:
		_terraform_tx_ids.erase(id)
		_refresh_territory_state_after_terraform()
		# Try terraform achievements (server validates actual counts)
		if achievement_client:
			achievement_client.try_unlock("first_terraform")
			achievement_client.try_unlock("terraform_10")
			achievement_client.try_unlock("terraform_50")
			achievement_client.try_unlock("terraform_100")
	if id in _beat_tx_ids:
		_beat_tx_ids.erase(id)
		beat_confirmed.emit(id)
		# Refresh territory state after beat too
		_refresh_territory_state_after_terraform()
		# Try beat achievements (server validates actual counts)
		if achievement_client:
			achievement_client.try_unlock("first_beat")
			achievement_client.try_unlock("beat_10")
			achievement_client.try_unlock("beat_50")
		# Reload progression data (XP increased)
		await get_tree().create_timer(2.0).timeout
		load_player_progression()


func _on_tx_failed(id: int, error: String) -> void:
	_stop_receipt_polling(id)
	_terraform_tx_ids.erase(id)
	if id in _beat_tx_ids:
		_beat_tx_ids.erase(id)
		beat_failed.emit(id, error)
	tx_failed.emit(id, error)


# ─── Fallback Receipt Polling ────────────────────────────────────────────
# Godot-side redundant polling via RPC client — handles cases where the
# browser tab is throttled, WebSocket drops, or browser polling fails.

func _start_receipt_polling(tx_id: int, tx_hash: String) -> void:
	_pending_tx_receipts[tx_id] = {
		"hash": tx_hash,
		"poll_count": 0,
		"max_polls": RECEIPT_MAX_POLLS,
	}
	# Start timer if not already running
	if _receipt_poll_timer.is_stopped():
		_receipt_poll_timer.start()
	print("[ChainManager] Fallback receipt polling started for tx %d (%s)" % [tx_id, tx_hash.left(18)])


func _stop_receipt_polling(tx_id: int) -> void:
	_pending_tx_receipts.erase(tx_id)
	# Stop timer if no more pending receipts
	if _pending_tx_receipts.is_empty() and not _receipt_poll_timer.is_stopped():
		_receipt_poll_timer.stop()


func _poll_pending_receipts() -> void:
	## Timer callback — check receipt for each pending tx via RPC.
	if _pending_tx_receipts.is_empty():
		_receipt_poll_timer.stop()
		return

	# Copy keys to avoid modifying dict during iteration
	var tx_ids := _pending_tx_receipts.keys().duplicate()
	for tx_id in tx_ids:
		var info: Dictionary = _pending_tx_receipts.get(tx_id, {})
		if info.is_empty():
			continue

		var tx_hash: String = info.get("hash", "")
		var poll_count: int = info.get("poll_count", 0)
		var max_polls: int = info.get("max_polls", RECEIPT_MAX_POLLS)

		poll_count += 1
		info["poll_count"] = poll_count

		if poll_count > max_polls:
			# Timed out — stop polling but don't emit failure
			# (the browser or user may still handle it)
			print("[ChainManager] Fallback poll timed out for tx %d after %d attempts" % [tx_id, poll_count])
			_stop_receipt_polling(tx_id)
			continue

		# Query receipt via Godot's own RPC client
		print("[ChainManager] Fallback poll #%d for tx %d (%s)" % [poll_count, tx_id, tx_hash.left(18)])
		_reader.get_rpc().eth_get_transaction_receipt(tx_hash,
			func(result_hex: String) -> void:
				_on_fallback_receipt(tx_id, tx_hash, result_hex),
			func(error: String) -> void:
				print("[ChainManager] Fallback poll RPC error for tx %d: %s" % [tx_id, error])
		)


func _on_fallback_receipt(tx_id: int, tx_hash: String, result_json: String) -> void:
	## Handle a receipt response from Godot-side fallback polling.
	## Only act if the browser hasn't already confirmed/failed this tx.
	if tx_id not in _pending_tx_receipts:
		return  # Already handled by browser — ignore

	# The result is the raw hex string from the RPC response.
	# For eth_getTransactionReceipt, the RPC client returns the JSON result value.
	# If tx is pending, result is "null" or empty. If confirmed, it's a JSON object.
	if result_json.is_empty() or result_json == "null" or result_json == "0x":
		return  # Still pending

	# Parse the receipt JSON to check status
	var parsed = JSON.parse_string(result_json)
	if parsed == null or not (parsed is Dictionary):
		return

	var status_hex: String = parsed.get("status", "")
	if status_hex.is_empty():
		return  # No status field yet

	var status_val := HexUtils.hex_to_int(status_hex)

	# Remove from pending BEFORE emitting to prevent re-entry
	_stop_receipt_polling(tx_id)

	if status_val == 1:
		print("[ChainManager] Fallback poll: tx %d CONFIRMED (%s)" % [tx_id, tx_hash.left(18)])
		_on_tx_confirmed(tx_id, tx_hash)
	else:
		print("[ChainManager] Fallback poll: tx %d REVERTED (%s)" % [tx_id, tx_hash.left(18)])
		_on_tx_failed(tx_id, "Transaction reverted (detected by fallback polling)")


# ─── Neighbor Discovery ──────────────────────────────────────────────────

func discover_neighbors() -> void:
	## Discover real on-chain neighbors from MAP.GetMapQing using HECKE coordinates.
	## Requires territory_latitude_hex and territory_longitude_hex to be populated.
	var lat_hex := GameManager.territory_latitude_hex
	var lon_hex := GameManager.territory_longitude_hex
	if lat_hex.is_empty() or lon_hex.is_empty():
		return
	_reader.discover_neighbors(lat_hex, lon_hex)


func _on_neighbor_qing_discovered(direction: int, data: Dictionary) -> void:
	neighbor_discovered.emit(direction, data)


func refresh_qing_map() -> void:
	## Force a fresh scan of all QINGs from event logs + HECKE coordinate resolution.
	## Clears cached data and re-runs discovery from scratch.
	_reader._all_qings.clear()
	_reader._qings_with_coords.clear()
	_reader._is_discovering = false

	# Delete cache file so it's rebuilt
	if FileAccess.file_exists(_reader.QING_CACHE_PATH):
		DirAccess.remove_absolute(_reader.QING_CACHE_PATH)
		print("[ChainManager] Deleted QING map cache for refresh")

	# Re-run discovery
	discover_neighbors()


# ─── Chat System (Phase 6 → Phase 7: Entropy API) ───────────────────────
# Primary: entropy-ai cached API (fast, all QINGs indexed)
# Fallback: direct eth_getLogs on-chain (slow, but no external dependency)

func load_chat_history() -> void:
	## Load territory chat via entropy API. Falls back to chain on failure.
	if GameManager.territory_address.is_empty():
		return
	var url := ENTROPY_API_BASE + "/api/qing-chat?qing=%s&limit=%d" % [
		GameManager.territory_address, CHAT_API_LIMIT]
	if _chat_last_ts > 0:
		url += "&after=%d" % _chat_last_ts
	var err := _chat_api_http.request(url)
	if err != OK:
		push_warning("[ChainManager] Territory chat API request failed (err=%d), falling back to chain" % err)
		_load_chat_from_chain()


func _on_territory_chat_api_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	## Handle entropy API response for territory chat.
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("[ChainManager] Territory chat API error (result=%d code=%d), falling back to chain" % [result, response_code])
		_load_chat_from_chain()
		return

	var json_text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("[ChainManager] Territory chat API invalid JSON, falling back to chain")
		_load_chat_from_chain()
		return

	var api_messages: Array = parsed.get("messages", [])
	if api_messages.is_empty() and _chat_messages.is_empty():
		chat_messages_received.emit([])
		return
	_merge_api_chat_messages(api_messages, false)


func _load_chat_from_chain() -> void:
	## Fallback: load territory chat from on-chain eth_getLogs.
	if GameManager.territory_address.is_empty():
		return
	var from_block := "0x0"
	if _chat_messages.size() > 0:
		var last_block: int = _chat_messages[-1].get("block", 0)
		if last_block > 0:
			from_block = "0x" + "%x" % (last_block + 1)
	_reader.read_chat_logs(GameManager.territory_address, from_block)


func _on_chat_logs_received_fallback(messages: Array) -> void:
	## Handle chain fallback chat messages — same merge logic.
	if messages.is_empty():
		if _chat_messages.is_empty():
			chat_messages_received.emit([])
		return

	var new_count: int = 0
	for msg in messages:
		if not (msg is Dictionary):
			continue
		var block: int = msg.get("block", 0)
		var is_dup := false
		for existing in _chat_messages:
			if existing.block == block and existing.message == msg.message and existing.username == msg.username:
				is_dup = true
				break
		if not is_dup:
			_chat_messages.append(msg)
			new_count += 1

	_chat_messages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.block < b.block
	)
	if _chat_messages.size() > 100:
		_chat_messages = _chat_messages.slice(_chat_messages.size() - 100)
	if _chat_messages.size() > 0:
		_chat_last_ts = _chat_messages[-1].get("ts", 0)
	if new_count > 0:
		print("[ChainManager] %d new chat messages via chain fallback (total: %d)" % [new_count, _chat_messages.size()])
	chat_messages_received.emit(_chat_messages.duplicate())


func _merge_api_chat_messages(api_messages: Array, is_global: bool) -> void:
	## Normalize entropy API messages and merge into cache.
	## API format: {from, fromName, text, txHash, block, ts, qingAddr, qingName}
	## Game format: {username, message, block, ts, source, qing, qing_name}
	## NOTE: We operate directly on member arrays — GDScript typed arrays copy on assignment.
	var max_size: int = 200 if is_global else 100
	var new_count: int = 0

	for api_msg in api_messages:
		if not (api_msg is Dictionary):
			continue
		var ts: int = int(api_msg.get("ts", 0))
		var block: int = int(api_msg.get("block", 0))
		var text: String = api_msg.get("text", "")
		var username: String = api_msg.get("fromName", "Anon")
		if username.is_empty():
			username = "Anon"

		# Dedup by block + text + username
		var is_dup := false
		var check_array: Array[Dictionary] = _global_chat_messages if is_global else _chat_messages
		for existing in check_array:
			if existing.block == block and existing.message == text and existing.username == username:
				is_dup = true
				break
		if is_dup:
			continue

		var entry := {
			"username": username,
			"message": text,
			"block": block,
			"ts": ts,
			"source": "global" if is_global else "territory",
			"qing": api_msg.get("qingAddr", ""),
			"qing_name": api_msg.get("qingName", ""),
			"tx_hash": api_msg.get("txHash", ""),
		}
		if is_global:
			_global_chat_messages.append(entry)
		else:
			_chat_messages.append(entry)
		new_count += 1

	# Sort by timestamp (ascending)
	if is_global:
		_global_chat_messages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.ts < b.ts
		)
	else:
		_chat_messages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.ts < b.ts
		)

	# Cap size
	if is_global and _global_chat_messages.size() > max_size:
		_global_chat_messages = _global_chat_messages.slice(_global_chat_messages.size() - max_size)
	elif not is_global and _chat_messages.size() > max_size:
		_chat_messages = _chat_messages.slice(_chat_messages.size() - max_size)

	# Update last timestamp for incremental polling
	if is_global and _global_chat_messages.size() > 0:
		_global_chat_last_ts = _global_chat_messages[-1].get("ts", 0)
	elif not is_global and _chat_messages.size() > 0:
		_chat_last_ts = _chat_messages[-1].get("ts", 0)

	if new_count > 0:
		var label := "global" if is_global else "territory"
		var sz: int = _global_chat_messages.size() if is_global else _chat_messages.size()
		print("[ChainManager] %d new %s chat messages via API (total: %d)" % [new_count, label, sz])

	if is_global:
		global_chat_received.emit(_global_chat_messages.duplicate())
	else:
		chat_messages_received.emit(_chat_messages.duplicate())


func get_chat_messages() -> Array[Dictionary]:
	## Return cached chat messages.
	return _chat_messages


func start_chat_polling() -> void:
	## Start periodic chat polling (called when entering a territory).
	if _chat_poll_timer and not _chat_poll_timer.is_stopped():
		return  # Already polling
	if _chat_poll_timer:
		_chat_poll_timer.start()
	# Load initial history
	load_chat_history()


func stop_chat_polling() -> void:
	## Stop periodic chat polling.
	if _chat_poll_timer:
		_chat_poll_timer.stop()


func _poll_chat() -> void:
	## Timer callback — fetch new messages since last known block.
	if GameManager.territory_address.is_empty():
		return
	load_chat_history()


func clear_chat() -> void:
	## Clear territory chat history (e.g. when switching territories).
	## Does NOT clear global chat — that persists across territory switches.
	_chat_messages.clear()
	_chat_last_ts = 0


# ─── Global Chat System (All QINGs via Entropy API) ──────────────────────

func load_global_chat() -> void:
	## Load global chat via entropy API (all QINGs). Falls back to chain on failure.
	var url := ENTROPY_API_BASE + "/api/qing-chat?limit=%d" % CHAT_API_LIMIT
	if _global_chat_last_ts > 0:
		url += "&after=%d" % _global_chat_last_ts
	var err := _global_chat_api_http.request(url)
	if err != OK:
		push_warning("[ChainManager] Global chat API request failed (err=%d), falling back to chain" % err)
		_load_global_chat_from_chain()


func _on_global_chat_api_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	## Handle entropy API response for global chat.
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("[ChainManager] Global chat API error (result=%d code=%d), falling back to chain" % [result, response_code])
		_load_global_chat_from_chain()
		return

	var json_text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("[ChainManager] Global chat API invalid JSON, falling back to chain")
		_load_global_chat_from_chain()
		return

	var api_messages: Array = parsed.get("messages", [])
	if api_messages.is_empty() and _global_chat_messages.is_empty():
		global_chat_received.emit([])
		return
	_merge_api_chat_messages(api_messages, true)


func _load_global_chat_from_chain() -> void:
	## Fallback: load global chat from on-chain LOG_STORAGE eth_getLogs.
	var from_block := "0x0"
	if _global_chat_messages.size() > 0:
		var last_block: int = _global_chat_messages[-1].get("block", 0)
		if last_block > 0:
			from_block = "0x" + "%x" % (last_block + 1)
	_reader.read_global_chat_logs(from_block)


func _on_global_chat_logs_received_fallback(messages: Array) -> void:
	## Handle chain fallback global chat messages.
	if messages.is_empty():
		if _global_chat_messages.is_empty():
			global_chat_received.emit([])
		return

	var new_count: int = 0
	for msg in messages:
		if not (msg is Dictionary):
			continue
		var block: int = msg.get("block", 0)
		var is_dup := false
		for existing in _global_chat_messages:
			if existing.block == block and existing.message == msg.message and existing.username == msg.username:
				is_dup = true
				break
		if not is_dup:
			_global_chat_messages.append(msg)
			new_count += 1

	_global_chat_messages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.block < b.block
	)
	if _global_chat_messages.size() > 200:
		_global_chat_messages = _global_chat_messages.slice(_global_chat_messages.size() - 200)
	if _global_chat_messages.size() > 0:
		_global_chat_last_ts = _global_chat_messages[-1].get("ts", 0)
	if new_count > 0:
		print("[ChainManager] %d new global chat messages via chain fallback (total: %d)" % [new_count, _global_chat_messages.size()])
	global_chat_received.emit(_global_chat_messages.duplicate())


func get_global_chat_messages() -> Array[Dictionary]:
	return _global_chat_messages


func start_global_chat_polling() -> void:
	## Start periodic global chat polling (called on game enter).
	if _global_chat_poll_timer and not _global_chat_poll_timer.is_stopped():
		return
	if _global_chat_poll_timer:
		_global_chat_poll_timer.start()
	load_global_chat()


func stop_global_chat_polling() -> void:
	if _global_chat_poll_timer:
		_global_chat_poll_timer.stop()


func _poll_global_chat() -> void:
	load_global_chat()


# ─── Guest List / Admitted Territories ────────────────────────────────────
# Scans all known QINGs to find which ones the current user's LAU is admitted to.
# Also provides single-QING admitted checks for the join flow.

var _guest_list: Array[Dictionary] = []  # Admitted territories
var _is_loading_guests: bool = false
var _admitted_cache: Dictionary = {}  # qing_address -> bool (single-check cache)


func load_guest_list() -> void:
	## Scan all known QINGs for the current user's LAU admitted status.
	print("[ChainManager] load_guest_list: lau='%s' is_loading=%s" % [
		GameManager.lau_address.left(14), str(_is_loading_guests)])
	if GameManager.lau_address.is_empty():
		print("[ChainManager] load_guest_list: no LAU address, emitting empty")
		guest_list_loaded.emit([])
		return
	if _is_loading_guests:
		print("[ChainManager] load_guest_list: already scanning, skipping")
		return  # Already scanning
	_is_loading_guests = true
	_reader.scan_admitted_territories(GameManager.lau_address)


func _on_admitted_territories_received(territories: Array) -> void:
	_is_loading_guests = false
	_guest_list.clear()
	_admitted_cache.clear()
	for t in territories:
		if t is Dictionary:
			_guest_list.append(t)
			# Cache for fast lookup
			if t.get("admitted", false):
				_admitted_cache[t.get("address", "").to_lower()] = true
	guest_list_loaded.emit(_guest_list.duplicate())
	admitted_territories_loaded.emit(_guest_list.duplicate())


func get_guest_list() -> Array[Dictionary]:
	return _guest_list


func is_loading_guests() -> bool:
	return _is_loading_guests


func is_admitted_to(qing_address: String) -> bool:
	## Quick check if user is admitted to a QING (from cached scan results).
	return _admitted_cache.get(qing_address.to_lower(), false)


func check_admitted_single(qing_address: String) -> void:
	## Check if user's LAU is admitted to a single QING (for join flow).
	## Result arrives via admitted_check_result signal → _on_admitted_check_result.
	if GameManager.lau_address.is_empty():
		return
	_reader.check_admitted(qing_address, GameManager.lau_address)


var _join_admitted_callback: Callable = Callable()
var _join_admitted_qing: String = ""


func check_admitted_for_join(qing_address: String, callback: Callable) -> void:
	## Check if user's LAU is admitted to a QING, with a direct callback.
	## callback(qing_address: String, admitted: bool) is called when result arrives.
	## Used by territory_manager's join flow to avoid signal conflicts.
	if GameManager.lau_address.is_empty():
		callback.call(qing_address, false)
		return
	_join_admitted_callback = callback
	_join_admitted_qing = qing_address.to_lower()
	_reader.check_admitted(qing_address, GameManager.lau_address)


func _on_admitted_check_result(lau_address: String, admitted: bool) -> void:
	## Route admitted check result to the join callback if one is pending.
	print("[ChainManager] _on_admitted_check_result: lau=%s admitted=%s cb_valid=%s pending_qing=%s" % [
		lau_address.left(12), str(admitted),
		str(_join_admitted_callback.is_valid()), _join_admitted_qing.left(12)])
	if _join_admitted_callback.is_valid() and not _join_admitted_qing.is_empty():
		if lau_address.to_lower() == GameManager.lau_address.to_lower():
			var qing := _join_admitted_qing
			var cb := _join_admitted_callback
			_join_admitted_callback = Callable()
			_join_admitted_qing = ""
			# Cache result
			if admitted:
				_admitted_cache[qing] = true
			cb.call(qing, admitted)


# ─── Transaction Helpers ──────────────────────────────────────────────────

func set_username(new_name: String) -> int:
	## Send LAU.Username(string) via wallet bridge.
	if GameManager.lau_address.is_empty():
		push_error("[ChainManager] Cannot set username — no LAU address loaded")
		return -1
	return _wallet_bridge.send_transaction(GameManager.lau_address, "Username", [new_name])


func send_chat(message: String) -> int:
	## Send CHOA.Chat(address qing, string message) via wallet bridge.
	## Routes through CHOA contract — same path as entropy-ai web UI.
	if GameManager.territory_address.is_empty():
		push_error("[ChainManager] Cannot send chat — not in a territory")
		return -1
	print("[ChainManager] send_chat: CHOA=%s QING=%s msg='%s'" % [
		CHOA_ADDRESS, GameManager.territory_address, message.left(30)])

	# Local echo — show message immediately in both territory + global chat
	var local_msg := {
		"username": GameManager.player_identity if not GameManager.player_identity.is_empty() else "You",
		"message": message,
		"block": 0,
		"ts": int(Time.get_unix_time_from_system() * 1000),
		"source": "local",
		"qing": GameManager.territory_address,
		"qing_name": GameManager.territory_name,
		"tx_hash": "",
	}
	_chat_messages.append(local_msg)
	chat_messages_received.emit(_chat_messages.duplicate())
	_global_chat_messages.append(local_msg)
	global_chat_received.emit(_global_chat_messages.duplicate())

	return _wallet_bridge.send_transaction(CHOA_ADDRESS, "Chat", [GameManager.territory_address, message])


func join_territory(qing_address: String) -> int:
	## Send QING.Join(lau_address) via wallet bridge.
	if GameManager.lau_address.is_empty():
		push_error("[ChainManager] Cannot join territory — no LAU address loaded")
		return -1
	return _wallet_bridge.send_transaction(qing_address, "Join", [GameManager.lau_address])


# ─── Territory Lifecycle ──────────────────────────────────────────────────

func leave_territory() -> int:
	## Send LAU.Leave() — sets CurrentArea to 0x0 on-chain.
	## After tx confirms, caller should clear game state and return to menu.
	if GameManager.lau_address.is_empty():
		push_error("[ChainManager] Cannot leave — no LAU address loaded")
		return -1
	print("[ChainManager] leave_territory: LAU=%s" % GameManager.lau_address.left(14))
	return _wallet_bridge.send_transaction(GameManager.lau_address, "Leave", [])


func void_identity() -> int:
	## Send LAU.Void(true, true) — DESTRUCTIVE reset of entire LAU identity.
	## Resets Saat, On, and all accumulated state. Cannot be undone.
	if GameManager.lau_address.is_empty():
		push_error("[ChainManager] Cannot void — no LAU address loaded")
		return -1
	print("[ChainManager] void_identity: LAU=%s (DESTRUCTIVE)" % GameManager.lau_address.left(14))
	return _wallet_bridge.send_transaction(GameManager.lau_address, "Void", [true, true])


# ─── Terraform Operations ────────────────────────────────────────────────

func terraform_alpha(seed_value: int) -> int:
	## Send AFFECTION.Alpha(uint64) via wallet bridge.
	if not _check_terraform_preconditions():
		return -1
	var tx_id: int = _wallet_bridge.send_transaction(
		_reader.AFFECTION_ADDRESS, "Alpha", [seed_value])
	if tx_id >= 0:
		_terraform_tx_ids.append(tx_id)
	return tx_id


func terraform_beta(seed_value: int) -> int:
	## Send AFFECTION.Beta(uint64) via wallet bridge.
	if not _check_terraform_preconditions():
		return -1
	var tx_id: int = _wallet_bridge.send_transaction(
		_reader.AFFECTION_ADDRESS, "Beta", [seed_value])
	if tx_id >= 0:
		_terraform_tx_ids.append(tx_id)
	return tx_id


func terraform_pi() -> int:
	## Send AFFECTION.Pi() via wallet bridge.
	if not _check_terraform_preconditions():
		return -1
	var tx_id: int = _wallet_bridge.send_transaction(
		_reader.AFFECTION_ADDRESS, "Pi", [])
	if tx_id >= 0:
		_terraform_tx_ids.append(tx_id)
	return tx_id


func terraform_rho() -> int:
	## Send AFFECTION.Rho() via wallet bridge.
	if not _check_terraform_preconditions():
		return -1
	var tx_id: int = _wallet_bridge.send_transaction(
		_reader.AFFECTION_ADDRESS, "Rho", [])
	if tx_id >= 0:
		_terraform_tx_ids.append(tx_id)
	return tx_id


func terraform_generate() -> int:
	## Send AFFECTION.Generate() via wallet bridge.
	if not _check_terraform_preconditions():
		return -1
	var tx_id: int = _wallet_bridge.send_transaction(
		_reader.AFFECTION_ADDRESS, "Generate", [])
	if tx_id >= 0:
		_terraform_tx_ids.append(tx_id)
	return tx_id


func terraform_upsilon(seed_value: int, phi: bool) -> int:
	## Send AFFECTION.Upsilon(uint64, bool) via wallet bridge.
	if not _check_terraform_preconditions():
		return -1
	var tx_id: int = _wallet_bridge.send_transaction(
		_reader.AFFECTION_ADDRESS, "Upsilon", [seed_value, phi])
	if tx_id >= 0:
		_terraform_tx_ids.append(tx_id)
	return tx_id


func _check_terraform_preconditions() -> bool:
	if not _wallet_bridge.is_wallet_connected():
		push_error("[ChainManager] Cannot terraform — wallet not connected")
		return false
	if GameManager.territory_address.is_empty():
		push_error("[ChainManager] Cannot terraform — no territory loaded")
		return false
	return true


func _refresh_territory_state_after_terraform() -> void:
	## Re-read territory state after a terraform tx confirms.
	if GameManager.territory_address.is_empty():
		return
	await get_tree().create_timer(1.0).timeout
	_auto_read_territory_state(
		GameManager.territory_address,
		GameManager.territory_waat_hex
	)


# ─── Beat Operation (META contract) ──────────────────────────────────────

signal beat_sent(tx_id: int)
signal beat_confirmed(tx_id: int)
signal beat_failed(tx_id: int, error: String)

var _beat_tx_ids: Array[int] = []

func send_beat() -> int:
	## Send META.Beat(waat) — complex state operation that aggregates terraform state.
	## Requires: non-zero Waat, entropy, Yuan weight, XIE power, YUE bars.
	## Awards 150 XP vs 100 XP for terraform. 60s cooldown in entropy-ai.
	if not _wallet_bridge.is_wallet_connected():
		push_error("[ChainManager] Cannot beat — wallet not connected")
		return -1
	if GameManager.territory_waat_hex.is_empty() or GameManager.territory_waat_hex == "0x0":
		push_error("[ChainManager] Cannot beat — no Waat value (territory needs terraforming)")
		return -1

	# Beat takes the territory's Waat value as uint256
	var waat_hex := GameManager.territory_waat_hex
	# Ensure it's a proper hex string for ethers.js to parse as uint256
	if not waat_hex.begins_with("0x"):
		waat_hex = "0x" + waat_hex

	print("[ChainManager] send_beat: META=%s Waat=%s" % [
		_reader.META_ADDRESS, waat_hex.left(18)])

	var tx_id: int = _wallet_bridge.send_transaction(
		_reader.META_ADDRESS, "Beat", [waat_hex])
	if tx_id >= 0:
		_beat_tx_ids.append(tx_id)
		beat_sent.emit(tx_id)
	return tx_id


func is_beat_tx(tx_id: int) -> bool:
	return tx_id in _beat_tx_ids


# ─── Player Progression (Entropy API) ──────────────────────────────────

signal player_progression_loaded(data: Dictionary)
signal achievements_loaded(data: Dictionary)
signal activity_feed_loaded(events: Array)
signal online_players_loaded(data: Dictionary)

var _progression_http: HTTPRequest
var _achievements_http: HTTPRequest
var _activity_http: HTTPRequest
var _online_http: HTTPRequest
var _presence_http: HTTPRequest

var _cached_progression: Dictionary = {}
var _cached_achievements: Dictionary = {}
var _cached_activity: Array = []
var _cached_online: Dictionary = {}

var _progression_cache_time: float = 0.0
var _achievements_cache_time: float = 0.0
const PROGRESSION_CACHE_TTL: float = 60.0  # 1 minute


func load_player_progression() -> void:
	## Fetch full player progression (level, XP, terraforms, beats, tier).
	if connected_wallet.is_empty():
		return

	var now := Time.get_ticks_msec() / 1000.0
	if not _cached_progression.is_empty() and (now - _progression_cache_time) < PROGRESSION_CACHE_TTL:
		player_progression_loaded.emit(_cached_progression)
		return

	if not _progression_http:
		_progression_http = HTTPRequest.new()
		_progression_http.name = "ProgressionHTTP"
		_progression_http.timeout = 15.0
		add_child(_progression_http)
		_progression_http.request_completed.connect(_on_progression_response)

	var url := ENTROPY_API_BASE + "/api/player/" + connected_wallet
	var err := _progression_http.request(url)
	if err != OK:
		push_error("[ChainManager] Progression request failed: %d" % err)


func _on_progression_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		player_progression_loaded.emit({})
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		player_progression_loaded.emit({})
		return

	_cached_progression = json.data
	_progression_cache_time = Time.get_ticks_msec() / 1000.0
	print("[ChainManager] Player progression: Level %s, XP %s, Tier %s" % [
		str(_cached_progression.get("level", 1)),
		str(_cached_progression.get("xp", 0)),
		str(_cached_progression.get("evolutionTitle", "Unknown"))])
	player_progression_loaded.emit(_cached_progression)

	# Check weapon/vehicle unlock conditions
	_check_progression_unlocks(_cached_progression)

	# Check level-based achievements
	if achievement_client:
		var level: int = _cached_progression.get("level", 1)
		achievement_client.check_level_milestones(level)


func load_achievements() -> void:
	## Fetch player achievements from entropy API.
	if connected_wallet.is_empty():
		return

	var now := Time.get_ticks_msec() / 1000.0
	if not _cached_achievements.is_empty() and (now - _achievements_cache_time) < PROGRESSION_CACHE_TTL:
		achievements_loaded.emit(_cached_achievements)
		return

	if not _achievements_http:
		_achievements_http = HTTPRequest.new()
		_achievements_http.name = "AchievementsHTTP"
		_achievements_http.timeout = 15.0
		add_child(_achievements_http)
		_achievements_http.request_completed.connect(_on_achievements_response)

	var url := ENTROPY_API_BASE + "/api/achievements?wallet=" + connected_wallet
	var err := _achievements_http.request(url)
	if err != OK:
		push_error("[ChainManager] Achievements request failed: %d" % err)


func _on_achievements_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		achievements_loaded.emit({})
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		achievements_loaded.emit({})
		return

	_cached_achievements = json.data
	_achievements_cache_time = Time.get_ticks_msec() / 1000.0
	achievements_loaded.emit(_cached_achievements)

	# Sync server achievements into local cache
	if achievement_client:
		achievement_client.sync_from_server(_cached_achievements)


func load_activity_feed() -> void:
	## Fetch recent activity events (terraforms, beats, joins, chats).
	if not _activity_http:
		_activity_http = HTTPRequest.new()
		_activity_http.name = "ActivityHTTP"
		_activity_http.timeout = 15.0
		add_child(_activity_http)
		_activity_http.request_completed.connect(_on_activity_response)

	var url := ENTROPY_API_BASE + "/api/activity"
	var err := _activity_http.request(url)
	if err != OK:
		push_error("[ChainManager] Activity request failed: %d" % err)


func _on_activity_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		activity_feed_loaded.emit([])
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		activity_feed_loaded.emit([])
		return

	var events: Array = json.data.get("events", [])
	_cached_activity = events
	activity_feed_loaded.emit(events)


func load_online_players() -> void:
	## Fetch online players grouped by territory.
	if not _online_http:
		_online_http = HTTPRequest.new()
		_online_http.name = "OnlineHTTP"
		_online_http.timeout = 10.0
		add_child(_online_http)
		_online_http.request_completed.connect(_on_online_response)

	var url := ENTROPY_API_BASE + "/api/online-players"
	var err := _online_http.request(url)
	if err != OK:
		push_error("[ChainManager] Online players request failed: %d" % err)


func _on_online_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		online_players_loaded.emit({})
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		online_players_loaded.emit({})
		return

	_cached_online = json.data
	online_players_loaded.emit(_cached_online)


# ─── Multiplayer Presence (Phase 12B) ──────────────────────────────────

signal mp_sync_received(players: Array)
signal mp_player_joined(wallet: String, presence: Dictionary)
signal mp_player_left(wallet: String)
signal mp_position_received(wallet: String, x: float, y: float, z: float, yaw: float, vx: float, vz: float)
signal mp_channel_joined(channel: String)
signal mp_channel_left()
signal vc_speaking_received(wallet: String, speaking: bool)


func _connect_multiplayer_signals() -> void:
	## Wire wallet bridge MP signals to chain manager forwarding signals.
	_wallet_bridge.mp_sync.connect(func(players: Array) -> void:
		mp_sync_received.emit(players))
	_wallet_bridge.mp_player_join.connect(func(wallet: String, presence: Dictionary) -> void:
		mp_player_joined.emit(wallet, presence))
	_wallet_bridge.mp_player_leave.connect(func(wallet: String) -> void:
		mp_player_left.emit(wallet))
	_wallet_bridge.mp_position_update.connect(func(w: String, x: float, y: float, z: float, yaw: float, vx: float, vz: float) -> void:
		mp_position_received.emit(w, x, y, z, yaw, vx, vz))
	_wallet_bridge.mp_joined.connect(func(ch: String) -> void:
		mp_channel_joined.emit(ch))
	_wallet_bridge.mp_left.connect(func() -> void:
		mp_channel_left.emit())
	_wallet_bridge.vc_speaking.connect(func(w: String, s: bool) -> void:
		vc_speaking_received.emit(w, s))


func join_multiplayer_channel(qing_address: String) -> void:
	## Join the Supabase multiplayer channel for a territory.
	if connected_wallet.is_empty():
		return
	var username := GameManager.player_identity
	if username.is_empty():
		username = connected_wallet.left(6) + ".." + connected_wallet.right(4)
	var tier: int = _cached_progression.get("evolutionTier", 0)
	_wallet_bridge.send_mp_join(qing_address, connected_wallet, username, tier)


func leave_multiplayer_channel() -> void:
	## Leave the current Supabase multiplayer channel.
	_wallet_bridge.send_mp_leave()


func send_multiplayer_position(x: float, y: float, z: float, yaw: float, vx: float, vz: float) -> void:
	## Broadcast local player position via wallet bridge to Supabase.
	_wallet_bridge.send_mp_position(x, y, z, yaw, vx, vz)


func start_voice_chat() -> void:
	_wallet_bridge.send_vc_start()


func stop_voice_chat() -> void:
	_wallet_bridge.send_vc_stop()


func toggle_voice_mute() -> void:
	_wallet_bridge.send_vc_mute()


func send_presence_heartbeat() -> void:
	## Send a presence heartbeat so other players can see us online.
	if connected_wallet.is_empty():
		return

	if not _presence_http:
		_presence_http = HTTPRequest.new()
		_presence_http.name = "PresenceHTTP"
		_presence_http.timeout = 10.0
		add_child(_presence_http)
		# We don't need to handle the response

	var url := ENTROPY_API_BASE + "/api/online-players"
	var body_data := {
		"wallet": connected_wallet,
		"username": GameManager.player_identity,
		"qingAddr": GameManager.territory_address,
		"qingName": GameManager.territory_name,
	}
	var json_body := JSON.stringify(body_data)
	var headers := PackedStringArray(["Content-Type: application/json"])
	_presence_http.request(url, headers, HTTPClient.METHOD_POST, json_body)


func get_cached_progression() -> Dictionary:
	return _cached_progression


func get_player_level() -> int:
	return _cached_progression.get("level", 1)


func get_player_xp() -> int:
	return _cached_progression.get("xp", 0)


func get_player_terraform_count() -> int:
	return _cached_progression.get("terraforms", 0)


func get_player_beat_count() -> int:
	return _cached_progression.get("beats", 0)


func get_evolution_title() -> String:
	return _cached_progression.get("evolutionTitle", "Drifter")


# ─── Progression-Based Unlocks ──────────────────────────────────────────

signal weapon_unlocked(weapon_type: int, weapon_name: String)
signal vehicle_unlocked(vehicle_type: int, vehicle_name: String)

# Unlock thresholds based on entropy API data
const UNLOCK_PULSE_RIFLE_TERRAFORMS: int = 25
const UNLOCK_PULSE_RIFLE_LEVEL: int = 5
const UNLOCK_GRAVITY_HAMMER_TERRAFORMS: int = 75
const UNLOCK_GRAVITY_HAMMER_BEATS: int = 10
const UNLOCK_GRAVITY_HAMMER_LEVEL: int = 15
const UNLOCK_HOVERBIKE_TERRAFORMS: int = 50
const UNLOCK_HOVERBIKE_LEVEL: int = 10
const UNLOCK_TANK_TERRAFORMS: int = 100
const UNLOCK_TANK_BEATS: int = 25
const UNLOCK_TANK_LEVEL: int = 20


func _check_progression_unlocks(progression: Dictionary) -> void:
	## Check if player meets unlock conditions for weapons/vehicles.
	var terraforms: int = progression.get("terraforms", 0)
	var beats: int = progression.get("beats", 0)
	var level: int = progression.get("level", 1)

	# Pulse Rifle: 25 terraforms OR level 5
	if terraforms >= UNLOCK_PULSE_RIFLE_TERRAFORMS or level >= UNLOCK_PULSE_RIFLE_LEVEL:
		weapon_unlocked.emit(2, "Pulse Rifle")  # WeaponType.PULSE_RIFLE = 2

	# Gravity Hammer: 75 terraforms + 10 beats OR level 15
	if (terraforms >= UNLOCK_GRAVITY_HAMMER_TERRAFORMS and beats >= UNLOCK_GRAVITY_HAMMER_BEATS) or level >= UNLOCK_GRAVITY_HAMMER_LEVEL:
		weapon_unlocked.emit(3, "Gravity Hammer")  # WeaponType.GRAVITY_HAMMER = 3

	# Hoverbike: 50 terraforms OR level 10
	if terraforms >= UNLOCK_HOVERBIKE_TERRAFORMS or level >= UNLOCK_HOVERBIKE_LEVEL:
		vehicle_unlocked.emit(1, "Hoverbike")  # VehicleType.HOVERBIKE = 1

	# Tank: 100 terraforms + 25 beats OR level 20
	if (terraforms >= UNLOCK_TANK_TERRAFORMS and beats >= UNLOCK_TANK_BEATS) or level >= UNLOCK_TANK_LEVEL:
		vehicle_unlocked.emit(2, "Tank")  # VehicleType.TANK = 2


# ─── Token Economy (Phase 9) ────────────────────────────────────────────
# Read ERC20 token balances for the player's wallet.
# Currently only CHOA is known; extensible for future tokens.

var _token_balances: Dictionary = {}  # token_addr -> {symbol, balance_hex, decimals, display}


func load_token_balances() -> void:
	## Read token balances for the player's wallet address.
	if GameManager.lau_wallet.is_empty():
		push_warning("[ChainManager] Cannot load balances — no wallet address")
		return
	_reader.read_token_balance(CHOA_ADDRESS, GameManager.lau_wallet)


func get_token_balances() -> Dictionary:
	return _token_balances


func _on_token_balance_received(token_address: String, balance_hex: String, decimals: int) -> void:
	## Normalize and format a token balance for display.
	var symbol := "CHOA" if token_address.to_lower() == CHOA_ADDRESS.to_lower() else "TOKEN"

	# Convert hex balance to float using decimals
	var display := _format_token_balance(balance_hex, decimals)

	_token_balances[token_address.to_lower()] = {
		"symbol": symbol,
		"balance_hex": balance_hex,
		"decimals": decimals,
		"display": display,
	}
	print("[ChainManager] Token balance: %s = %s (%s)" % [symbol, display, balance_hex.left(18)])
	token_balances_updated.emit(_token_balances.duplicate())


func _format_token_balance(balance_hex: String, decimals: int) -> String:
	## Convert a hex balance with N decimals to a human-readable string.
	## e.g., 0xDE0B6B3A7640000 with 18 decimals → "1.00"
	var stripped := HexUtils.strip_0x(balance_hex)
	if stripped.is_empty() or stripped == "0":
		return "0"

	# For very large hex values, use digit-by-digit division
	# Simple approach: convert to string of digits, insert decimal point
	var digits := _hex_to_decimal_string(stripped)
	if digits.length() <= decimals:
		# Value is less than 1.0 — pad with leading zeros
		var padded := "0." + "0".repeat(decimals - digits.length()) + digits
		# Trim trailing zeros but keep at least 2 decimal places
		while padded.ends_with("0") and padded.length() > padded.find(".") + 3:
			padded = padded.left(padded.length() - 1)
		return padded
	else:
		# Insert decimal point
		var integer_part := digits.left(digits.length() - decimals)
		var frac_part := digits.right(decimals)
		# Show up to 4 decimal places
		if frac_part.length() > 4:
			frac_part = frac_part.left(4)
		# Trim trailing zeros
		while frac_part.ends_with("0") and frac_part.length() > 2:
			frac_part = frac_part.left(frac_part.length() - 1)
		# Add comma separators to integer part
		var formatted_int := ""
		for i in range(integer_part.length()):
			if i > 0 and (integer_part.length() - i) % 3 == 0:
				formatted_int += ","
			formatted_int += integer_part[i]
		return formatted_int + "." + frac_part


func _hex_to_decimal_string(hex_str: String) -> String:
	## Convert a hex string to decimal digit string using long division.
	## Handles arbitrarily large numbers without overflow.
	var result: Array[int] = [0]  # Decimal digits, most significant first

	for ch in hex_str:
		var digit := 0
		if ch >= "0" and ch <= "9":
			digit = ch.unicode_at(0) - "0".unicode_at(0)
		elif ch >= "a" and ch <= "f":
			digit = ch.unicode_at(0) - "a".unicode_at(0) + 10
		elif ch >= "A" and ch <= "F":
			digit = ch.unicode_at(0) - "A".unicode_at(0) + 10

		# Multiply result by 16 and add digit
		var carry := digit
		for i in range(result.size() - 1, -1, -1):
			var val: int = result[i] * 16 + carry
			result[i] = val % 10
			carry = val / 10
		while carry > 0:
			result.insert(0, carry % 10)
			carry = carry / 10

	# Convert to string
	var s := ""
	for d in result:
		s += str(d)
	return s


# ─── World Map Data (Phase 10) ──────────────────────────────────────────

signal qing_name_resolved(address: String, qing_name: String)

func get_all_qings() -> Array[Dictionary]:
	## Return all cached QING coordinates for the world map.
	return _reader.get_cached_qings()


func load_all_qing_names() -> void:
	## Start batch-reading name() for all cached QINGs.
	_reader.read_all_qing_names()


func read_qing_name(qing_address: String) -> void:
	## Read a single QING's name.
	_reader.read_qing_name(qing_address)


# ─── Leaderboard (Entropy API) ────────────────────────────────────────

signal leaderboard_loaded(data: Dictionary)
signal player_stats_loaded(data: Dictionary)

var _leaderboard_http: HTTPRequest
var _player_stats_http: HTTPRequest
var _cached_leaderboard: Dictionary = {}
var _leaderboard_cache_time: float = 0.0
const LEADERBOARD_CACHE_TTL: float = 120.0  # 2 minutes


func load_leaderboard() -> void:
	## Fetch leaderboard from entropy API.
	# Check cache
	var now := Time.get_ticks_msec() / 1000.0
	if not _cached_leaderboard.is_empty() and (now - _leaderboard_cache_time) < LEADERBOARD_CACHE_TTL:
		leaderboard_loaded.emit(_cached_leaderboard)
		return

	if not _leaderboard_http:
		_leaderboard_http = HTTPRequest.new()
		_leaderboard_http.name = "LeaderboardHTTP"
		add_child(_leaderboard_http)
		_leaderboard_http.request_completed.connect(_on_leaderboard_response)

	var url := ENTROPY_API_BASE + "/api/leaderboard"
	var err := _leaderboard_http.request(url)
	if err != OK:
		push_error("[ChainManager] Leaderboard request failed: %d" % err)


func _on_leaderboard_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("[ChainManager] Leaderboard API error: result=%d code=%d" % [result, code])
		leaderboard_loaded.emit({})
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("[ChainManager] Leaderboard JSON parse error")
		leaderboard_loaded.emit({})
		return

	_cached_leaderboard = json.data
	_leaderboard_cache_time = Time.get_ticks_msec() / 1000.0
	leaderboard_loaded.emit(_cached_leaderboard)


func load_player_stats(wallet_address: String) -> void:
	## Fetch individual player stats from entropy API.
	if wallet_address.is_empty():
		return

	if not _player_stats_http:
		_player_stats_http = HTTPRequest.new()
		_player_stats_http.name = "PlayerStatsHTTP"
		add_child(_player_stats_http)
		_player_stats_http.request_completed.connect(_on_player_stats_response)

	var url := ENTROPY_API_BASE + "/api/player/" + wallet_address
	var err := _player_stats_http.request(url)
	if err != OK:
		push_error("[ChainManager] Player stats request failed: %d" % err)


func _on_player_stats_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		player_stats_loaded.emit({})
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		player_stats_loaded.emit({})
		return

	player_stats_loaded.emit(json.data)


# ─── Daily Challenges / Alliances / Emotes (Phase 13F) ──────────────────

signal daily_loaded(data: Dictionary)
signal challenges_loaded(challenges: Array)
signal alliance_loaded(data: Dictionary)
signal emote_sent(emote_id: int)

func load_daily_challenges() -> void:
	if daily_challenges:
		daily_challenges.fetch_daily()

func load_challenges_list() -> void:
	if daily_challenges:
		daily_challenges.fetch_challenges()

func load_alliance() -> void:
	if alliance_client and not connected_wallet.is_empty():
		alliance_client.fetch_alliance(connected_wallet)

func send_emote(emote_id: int) -> void:
	if emote_client and not connected_wallet.is_empty():
		emote_client.send_emote(connected_wallet, emote_id, GameManager.territory_address)

func _connect_phase_13f_signals() -> void:
	## Connect forwarding signals for Phase 13F clients.
	if daily_challenges:
		daily_challenges.daily_loaded.connect(func(data: Dictionary): daily_loaded.emit(data))
		daily_challenges.challenges_loaded.connect(func(data: Array): challenges_loaded.emit(data))
	if alliance_client:
		alliance_client.alliance_loaded.connect(func(data: Dictionary): alliance_loaded.emit(data))
	if emote_client:
		emote_client.emote_sent.connect(func(eid: int): emote_sent.emit(eid))
	if flag_client:
		flag_client.flags_loaded.connect(func(flags: Array): flags_loaded.emit(flags))
		flag_client.flag_planted.connect(func(ok: bool, msg: String): flag_planted.emit(ok, msg))


# ─── Flags / Guestbook (Phase 13L) ──────────────────────────────────────

signal flags_loaded(flags: Array)
signal flag_planted(success: bool, message: String)

func load_territory_flags() -> void:
	if flag_client:
		flag_client.load_flags(GameManager.territory_address)

func plant_flag(message: String, position: Vector3) -> void:
	if flag_client and not connected_wallet.is_empty():
		var username: String = GameManager.player_identity
		flag_client.plant_flag(
			connected_wallet, username, message,
			position, GameManager.territory_address
		)
