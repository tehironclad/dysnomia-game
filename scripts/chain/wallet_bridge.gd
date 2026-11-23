extends Node
## Browser wallet bridge — serves wallet.html over HTTP and communicates
## via WebSocket for wallet transaction signing (Rabby, MetaMask, etc.).
##
## Flow: Godot (HTTP + WebSocket servers) <-> Browser (wallet.html + ethers.js) <-> Wallet <-> PulseChain
##
## Two TCP servers on adjacent ports:
##   - HTTP server (port): serves wallet.html so extensions inject window.ethereum
##   - WebSocket server (port+1): handles the persistent WS connection
##
## open_wallet_page() launches the user's browser pointing at http://localhost:PORT

signal wallet_connected(address: String, chain_id: int)
signal wallet_disconnected()
signal tx_result(id: int, hash: String)
signal tx_confirmed(id: int, hash: String)
signal tx_failed(id: int, error: String)

# ── Multiplayer signals ──
signal mp_sync(players: Array)
signal mp_player_join(wallet: String, presence: Dictionary)
signal mp_player_leave(wallet: String)
signal mp_position_update(wallet: String, x: float, y: float, z: float, yaw: float, vx: float, vz: float)
signal mp_joined(channel: String)
signal mp_left()

# ── Voice chat signals ──
signal vc_started()
signal vc_stopped()
signal vc_mute_changed(muted: bool)
signal vc_speaking(wallet: String, speaking: bool)
signal vc_error(error: String)

const DEFAULT_PORT: int = 38420
const MAX_PORT_RETRIES: int = 10
const PING_INTERVAL: float = 15.0

var _http_server: TCPServer
var _ws_server: TCPServer
var _ws_peer: WebSocketPeer
var _pending_peers: Array = []  # Array of WebSocketPeer waiting for handshake completion
var _pending_http: Array = []   # Array of StreamPeerTCP waiting to receive request
var _closing_http: Array = []   # Array of {peer, frames_left} — sent response, waiting to flush
var _http_port: int = DEFAULT_PORT
var _ws_port: int = DEFAULT_PORT + 1
var _wallet_address: String = ""
var _chain_id: int = 0
var _next_tx_id: int = 1
var _ping_timer: float = 0.0
var _cached_html: String = ""   # wallet.html with ports baked in
var _browser_opened: bool = false  # True once we've opened the browser (avoid duplicate tabs)
var _browser_pid: int = -1         # PID of the Chrome --app process (for cleanup)

enum State {
	STOPPED,
	LISTENING,
	CONNECTED,
}
var _state: int = State.STOPPED


func _ready() -> void:
	_http_server = TCPServer.new()
	_ws_server = TCPServer.new()


func start_server(port: int = DEFAULT_PORT) -> bool:
	## Start the HTTP + WebSocket servers on localhost.
	## HTTP on `port`, WebSocket on `port + 1`.
	## Tries the given port first, then falls back to port+2..port+MAX_PORT_RETRIES*2.
	if _state != State.STOPPED:
		stop_server()

	for i in range(MAX_PORT_RETRIES):
		var try_http := port + (i * 2)
		var try_ws := try_http + 1

		var err_http := _http_server.listen(try_http, "127.0.0.1")
		if err_http != OK:
			push_warning("[WalletBridge] HTTP port %d unavailable, trying next..." % try_http)
			continue

		var err_ws := _ws_server.listen(try_ws, "127.0.0.1")
		if err_ws != OK:
			_http_server.stop()
			push_warning("[WalletBridge] WS port %d unavailable, trying next..." % try_ws)
			continue

		_http_port = try_http
		_ws_port = try_ws
		_state = State.LISTENING
		_wallet_address = ""
		_chain_id = 0

		# Pre-build the HTML with both ports baked in
		_cached_html = _get_wallet_html()
		_cached_html = _cached_html.replace("{{PORT}}", str(_ws_port))

		print("[WalletBridge] HTTP on localhost:%d, WS on localhost:%d" % [_http_port, _ws_port])
		return true

	push_error("[WalletBridge] Failed to bind to any port pair")
	return false


func stop_server() -> void:
	## Stop both servers and close all connections.
	if _ws_peer:
		_ws_peer.close()
		_ws_peer = null
	for ws_peer in _pending_peers:
		if ws_peer is WebSocketPeer:
			ws_peer.close()
	_pending_peers.clear()
	for http_peer in _pending_http:
		if http_peer is StreamPeerTCP:
			http_peer.disconnect_from_host()
	_pending_http.clear()
	for item in _closing_http:
		if item.peer is StreamPeerTCP:
			item.peer.disconnect_from_host()
	_closing_http.clear()
	_http_server.stop()
	_ws_server.stop()
	_state = State.STOPPED
	_browser_opened = false
	if not _wallet_address.is_empty():
		_wallet_address = ""
		_chain_id = 0
		wallet_disconnected.emit()


func open_wallet_page() -> void:
	## Open the wallet page as a Chrome/Edge --app popup (no tabs, no address bar).
	## Falls back to OS.shell_open() if no Chromium browser is found.
	## Only opens once per server session — calling again is a no-op.
	if _state == State.STOPPED:
		push_error("[WalletBridge] Server not running")
		return
	if _browser_opened:
		print("[WalletBridge] Browser already opened — skipping")
		return

	var url := "http://localhost:%d" % _http_port
	var browser_path := _find_chromium_browser()

	if not browser_path.is_empty():
		# Launch as --app popup: no address bar, no tabs, looks like a native window.
		# Do NOT use --user-data-dir — that kills wallet extension access.
		# --window-size sets initial size; wallet.html also calls resizeTo() as backup.
		var args: PackedStringArray = PackedStringArray([
			"--app=%s" % url,
			"--window-size=400,520",
		])
		_browser_pid = OS.create_process(browser_path, args)
		if _browser_pid > 0:
			_browser_opened = true
			print("[WalletBridge] Opened wallet popup: %s (pid=%d)" % [browser_path.get_file(), _browser_pid])
			return
		else:
			push_warning("[WalletBridge] Failed to launch %s, falling back to shell_open" % browser_path)

	# Fallback: default browser (may open as a regular tab)
	OS.shell_open(url)
	_browser_opened = true
	print("[WalletBridge] Opened wallet page (fallback): %s" % url)


func focus_wallet_page() -> void:
	## Bring the wallet popup window to front for transaction signing.
	## Uses OS-level window activation (Win32 SetForegroundWindow via PowerShell)
	## because JavaScript window.focus() is blocked by the OS for background windows.
	## If the WS is disconnected (browser was closed), reopen the popup.
	if _state == State.STOPPED:
		return
	if not _browser_opened:
		open_wallet_page()
		return
	if _ws_peer and _state == State.CONNECTED:
		_activate_browser_window()
	else:
		# WS is down — browser was probably closed. Reopen it.
		print("[WalletBridge] WS disconnected — reopening wallet popup")
		_browser_opened = false
		_browser_pid = -1
		open_wallet_page()


func reopen_wallet_page() -> void:
	## Force-reopen the wallet popup. Used when the user manually requests it
	## (e.g., W key) or if the wallet window was closed.
	## Resets the _browser_opened flag so open_wallet_page() will launch again.
	if _state == State.STOPPED:
		return
	_browser_opened = false
	_browser_pid = -1
	open_wallet_page()


func send_transaction(to: String, fn_name: String, params: Array) -> int:
	## Send a transaction request to the browser wallet.
	## Returns a transaction ID for tracking.
	if _state != State.CONNECTED or not _ws_peer:
		push_error("[WalletBridge] Cannot send tx — wallet not connected")
		return -1
	var tx_id := _next_tx_id
	_next_tx_id += 1
	_send_json({
		"type": "send_transaction",
		"id": tx_id,
		"to": to,
		"function": fn_name,
		"params": params,
	})
	return tx_id


func is_wallet_connected() -> bool:
	return _state == State.CONNECTED and not _wallet_address.is_empty()


func is_server_running() -> bool:
	## Returns true if servers are up (LISTENING or CONNECTED).
	return _state != State.STOPPED


func get_wallet_address() -> String:
	return _wallet_address


# ─── Multiplayer Commands ────────────────────────────────────────────────

## Set by MultiplayerManager while the native Realtime client (realtime_client.gd) owns
## the QING channel. The browser page then stays out of the channel so the same wallet
## isn't present twice; it is re-used as a fallback if the native socket can't connect.
static var native_mp_active: bool = false


func send_mp_join(qing_address: String, wallet: String, username: String, tier: int) -> void:
	## Tell wallet.html to join a Supabase channel for the given territory.
	if native_mp_active:
		return
	_send_json({
		"type": "mp_join",
		"qing": qing_address,
		"wallet": wallet,
		"username": username,
		"tier": tier,
	})


func send_mp_leave() -> void:
	## Tell wallet.html to leave the current Supabase channel.
	_send_json({"type": "mp_leave"})


func send_mp_position(x: float, y: float, z: float, yaw: float, vx: float, vz: float) -> void:
	## Broadcast local player position to the Supabase channel.
	if native_mp_active:
		return
	_send_json({
		"type": "mp_position",
		"x": x, "y": y, "z": z,
		"r": yaw,
		"vx": vx, "vz": vz,
	})


# ─── Voice Chat Commands ────────────────────────────────────────────────

func send_vc_start() -> void:
	_send_json({"type": "vc_start"})


func send_vc_stop() -> void:
	_send_json({"type": "vc_stop"})


func send_vc_mute() -> void:
	_send_json({"type": "vc_mute"})


func get_port() -> int:
	return _http_port


# ─── Process Loop ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _state == State.STOPPED:
		return

	# ── HTTP server: accept and respond ──
	while _http_server.is_connection_available():
		var peer := _http_server.take_connection()
		if peer:
			_pending_http.append(peer)

	_poll_http_peers()
	_flush_closing_http()

	# ── WebSocket server: accept and upgrade ──
	while _ws_server.is_connection_available():
		var peer := _ws_server.take_connection()
		if peer:
			_try_ws_accept(peer)

	_poll_pending_peers()

	# ── Poll active WebSocket ──
	if _ws_peer:
		_ws_peer.poll()
		var ws_state := _ws_peer.get_ready_state()

		if ws_state == WebSocketPeer.STATE_OPEN:
			while _ws_peer.get_available_packet_count() > 0:
				var packet := _ws_peer.get_packet()
				_handle_ws_message(packet.get_string_from_utf8())

			# Ping keepalive
			_ping_timer += delta
			if _ping_timer >= PING_INTERVAL:
				_ping_timer = 0.0
				_send_json({"type": "ping"})

		elif ws_state == WebSocketPeer.STATE_CLOSED:
			_on_ws_disconnected()


# ─── HTTP Server ──────────────────────────────────────────────────────────

func _poll_http_peers() -> void:
	## Check pending HTTP connections for incoming data and respond.
	var to_remove: Array[int] = []

	for i in range(_pending_http.size()):
		var peer: StreamPeerTCP = _pending_http[i]
		peer.poll()
		var status := peer.get_status()

		if status == StreamPeerTCP.STATUS_CONNECTED:
			if peer.get_available_bytes() > 0:
				# Read and discard the request data
				var _request := peer.get_utf8_string(peer.get_available_bytes())
				# Send the HTML response regardless of path
				var body := _cached_html.to_utf8_buffer()
				var header := "HTTP/1.1 200 OK\r\n"
				header += "Content-Type: text/html; charset=utf-8\r\n"
				header += "Content-Length: %d\r\n" % body.size()
				header += "Connection: close\r\n"
				header += "Access-Control-Allow-Origin: *\r\n"
				header += "\r\n"
				peer.put_data(header.to_utf8_buffer())
				peer.put_data(body)
				# Move to closing queue — give TCP time to flush
				_closing_http.append({"peer": peer, "frames": 10})
				to_remove.append(i)

		elif status != StreamPeerTCP.STATUS_CONNECTING:
			# Error or disconnected
			to_remove.append(i)

	to_remove.reverse()
	for idx in to_remove:
		_pending_http.remove_at(idx)


func _flush_closing_http() -> void:
	## Give HTTP peers that sent their response time to flush, then disconnect.
	var to_remove: Array[int] = []
	for i in range(_closing_http.size()):
		var item: Dictionary = _closing_http[i]
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		item.frames -= 1
		if item.frames <= 0 or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			to_remove.append(i)
	to_remove.reverse()
	for idx in to_remove:
		_closing_http.remove_at(idx)


# ─── WebSocket Server ────────────────────────────────────────────────────

func _try_ws_accept(peer: StreamPeerTCP) -> void:
	## Try to upgrade a TCP connection to WebSocket.
	## Reject if we already have an active connection.
	if _ws_peer and _ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		# Already have a good connection — reject the new one
		peer.disconnect_from_host()
		return

	var new_ws := WebSocketPeer.new()
	var err := new_ws.accept_stream(peer)
	if err != OK:
		peer.disconnect_from_host()
		return

	_pending_peers.append(new_ws)


func _poll_pending_peers() -> void:
	## Poll pending WebSocket peers to check handshake completion.
	var to_remove: Array[int] = []

	for i in range(_pending_peers.size()):
		var ws: WebSocketPeer = _pending_peers[i]
		ws.poll()
		var ws_state := ws.get_ready_state()

		if ws_state == WebSocketPeer.STATE_OPEN:
			to_remove.append(i)
			_ws_peer = ws
			_state = State.CONNECTED
			_ping_timer = 0.0
			print("[WalletBridge] WebSocket connection established")
			_send_json({"type": "request_accounts"})

		elif ws_state == WebSocketPeer.STATE_CLOSED:
			to_remove.append(i)

	to_remove.reverse()
	for idx in to_remove:
		_pending_peers.remove_at(idx)


# ─── HTML Source ──────────────────────────────────────────────────────────

func _get_wallet_html() -> String:
	var file := FileAccess.open("res://assets/web/wallet.html", FileAccess.READ)
	if file:
		var content := file.get_as_text()
		file.close()
		return content
	push_error("[WalletBridge] Failed to read res://assets/web/wallet.html")
	return "<!DOCTYPE html><html><body><h1>Error: wallet.html not found</h1></body></html>"


# ─── WebSocket Messages ──────────────────────────────────────────────────

func _send_json(data: Dictionary) -> void:
	if _ws_peer and _ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws_peer.send_text(JSON.stringify(data))


func _handle_ws_message(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[WalletBridge] Invalid JSON: %s" % text.left(100))
		return
	if not (json.data is Dictionary):
		return

	var data: Dictionary = json.data
	var msg_type: String = data.get("type", "")

	match msg_type:
		"connected":
			var addr: String = data.get("address", "")
			var cid: int = data.get("chainId", 0)
			if not addr.is_empty() and addr != _wallet_address:
				_wallet_address = addr
				_chain_id = cid
				print("[WalletBridge] Wallet connected: %s (chain %d)" % [addr, cid])
				wallet_connected.emit(addr, cid)

		"accounts_changed":
			var addr: String = data.get("address", "")
			if addr != _wallet_address:
				_wallet_address = addr
				if addr.is_empty():
					wallet_disconnected.emit()
				else:
					wallet_connected.emit(addr, _chain_id)

		"chain_changed":
			_chain_id = data.get("chainId", 0)

		"tx_result":
			var tx_id: int = data.get("id", -1)
			var hash: String = data.get("hash", "")
			if tx_id >= 0:
				tx_result.emit(tx_id, hash)

		"tx_confirmed":
			var conf_id: int = data.get("id", -1)
			var conf_hash: String = data.get("hash", "")
			if conf_id >= 0:
				tx_confirmed.emit(conf_id, conf_hash)

		"tx_reverted":
			var rev_id: int = data.get("id", -1)
			var rev_error: String = data.get("error", "Transaction reverted")
			if rev_id >= 0:
				tx_failed.emit(rev_id, rev_error)

		"tx_error":
			var tx_id: int = data.get("id", -1)
			var error: String = data.get("error", "Unknown error")
			if tx_id >= 0:
				tx_failed.emit(tx_id, error)

		"pong":
			pass  # Keepalive response

		"disconnected":
			_on_ws_disconnected()

		# ── Multiplayer presence ──
		"mp_sync":
			var players: Variant = data.get("players", [])
			if players is Array:
				mp_sync.emit(players)

		"mp_player_join":
			var join_wallet: String = data.get("wallet", "")
			var presence: Variant = data.get("presence", {})
			if not join_wallet.is_empty() and presence is Dictionary:
				mp_player_join.emit(join_wallet, presence)

		"mp_player_leave":
			var leave_wallet: String = data.get("wallet", "")
			if not leave_wallet.is_empty():
				mp_player_leave.emit(leave_wallet)

		"mp_position_update":
			var pos_wallet: String = data.get("wallet", "")
			if not pos_wallet.is_empty():
				mp_position_update.emit(
					pos_wallet,
					float(data.get("x", 0)),
					float(data.get("y", 0)),
					float(data.get("z", 0)),
					float(data.get("r", 0)),
					float(data.get("vx", 0)),
					float(data.get("vz", 0)),
				)

		"mp_joined":
			mp_joined.emit(data.get("channel", ""))

		"mp_left":
			mp_left.emit()

		# ── Voice chat ──
		"vc_started":
			vc_started.emit()

		"vc_stopped":
			vc_stopped.emit()

		"vc_mute_changed":
			vc_mute_changed.emit(data.get("muted", false))

		"vc_speaking":
			var spk_wallet: String = data.get("wallet", "")
			var spk_state: bool = data.get("speaking", false)
			if not spk_wallet.is_empty():
				vc_speaking.emit(spk_wallet, spk_state)

		"vc_error":
			vc_error.emit(data.get("error", "Unknown voice chat error"))


func _on_ws_disconnected() -> void:
	_ws_peer = null
	_state = State.LISTENING
	var had_wallet := not _wallet_address.is_empty()
	_wallet_address = ""
	_chain_id = 0
	_ping_timer = 0.0
	if had_wallet:
		print("[WalletBridge] Wallet disconnected")
		wallet_disconnected.emit()


# ─── Browser Window Activation ─────────────────────────────────────────────

func _activate_browser_window() -> void:
	## Bring the wallet --app window to the foreground using OS-level calls.
	## JavaScript window.focus() doesn't work on Windows for background windows.
	## We use PowerShell + Win32 FindWindow/SetForegroundWindow to find by title.
	## Title comes from wallet.html <title> tag: "Dysnomia Wallet Bridge".
	if OS.get_name() == "Windows":
		var ps_script := (
			"try { " +
			"Add-Type -TypeDefinition '" +
			"using System; using System.Runtime.InteropServices; " +
			"public class WinAPI { " +
			"[DllImport(\"user32.dll\")] public static extern IntPtr FindWindow(string cls, string title); " +
			"[DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd); " +
			"[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); " +
			"}'" +
			" -Language CSharp -ErrorAction SilentlyContinue; " +
			"$h = [WinAPI]::FindWindow([NullString]::Value, 'Dysnomia Wallet Bridge'); " +
			"if ($h -ne [IntPtr]::Zero) { " +
			"[WinAPI]::ShowWindow($h, 9); " +
			"[WinAPI]::SetForegroundWindow($h) " +
			"} } catch {}"
		)
		OS.create_process("powershell.exe", PackedStringArray([
			"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
			"-Command", ps_script,
		]))
	else:
		# Non-Windows: fall back to WS focus message (best effort)
		_send_json({"type": "focus"})


# ─── Browser Detection ────────────────────────────────────────────────────

func _find_chromium_browser() -> String:
	## Find a Chromium-based browser on the system (Chrome or Edge).
	## Returns the full path to the executable, or "" if none found.
	## Only Chrome/Edge support --app mode and wallet extension injection.
	if OS.get_name() != "Windows":
		# Linux/Mac: try common paths
		var unix_paths: Array[String] = [
			"/usr/bin/google-chrome",
			"/usr/bin/google-chrome-stable",
			"/usr/bin/chromium-browser",
			"/usr/bin/chromium",
			"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
			"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
		]
		for p in unix_paths:
			if FileAccess.file_exists(p):
				return p
		return ""

	# Windows: check common install locations
	var win_paths: Array[String] = [
		"C:/Program Files/Google/Chrome/Application/chrome.exe",
		"C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
		"C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
		"C:/Program Files/Microsoft/Edge/Application/msedge.exe",
	]

	# Also check user-local Chrome install (common when installed per-user)
	var local_app_data := OS.get_environment("LOCALAPPDATA")
	if not local_app_data.is_empty():
		win_paths.insert(0, local_app_data + "/Google/Chrome/Application/chrome.exe")
		win_paths.insert(1, local_app_data + "/Microsoft/Edge/Application/msedge.exe")

	for p in win_paths:
		if FileAccess.file_exists(p):
			print("[WalletBridge] Found browser: %s" % p)
			return p

	push_warning("[WalletBridge] No Chromium browser found — will use OS.shell_open fallback")
	return ""
