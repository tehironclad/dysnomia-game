extends Node
## Browser wallet bridge: serves wallet.html over HTTP and talks to it over a
## WebSocket; the page relays requests to the browser wallet (Rabby, MetaMask, …).
##
## Flow: Godot (HTTP + WebSocket servers) <-> Browser (wallet.html) <-> Wallet <-> PulseChain
##
## Two TCP servers on adjacent ports, both on 127.0.0.1:
##   - HTTP (port): serves wallet.html, so extensions inject window.ethereum;
##   - WebSocket (port+1): the link to the page.
##
## The link (tested end to end by tools/e2e_wallet.sh):
##   - every socket is accepted; it stays unauthenticated (ignored) until its first
##     message is {"type":"hello", token} with this session's token;
##   - a valid hello makes that page THE linked page ("welcome", then
##     "request_accounts"); while one is linked, a second window is told
##     "superseded" and closes itself (the linked one keeps working);
##   - a wrong token (a window left open from an earlier game session) is told
##     "stale": the page reloads itself from this server and links with the new token;
##   - losing the link keeps the wallet address (the wallet didn't change); requests
##     wait for the page to relink, and the page re-sends any answer it couldn't deliver.
##
## Hardening (docs/SECURITY_AUDIT.md):
##   - the page (and so the token) is served only to a request whose Host header is
##     localhost:PORT or 127.0.0.1:PORT: a DNS-rebinding site (evil.example resolving
##     to 127.0.0.1) gets 403 and never sees the token;
##   - the page is served with a CSP, frame-ancestors 'none' (no clickjacking frame),
##     no-referrer, nosniff and a same-origin opener policy;
##   - sockets that have not said a valid hello are capped (MAX_UNAUTHED) and time out.

signal wallet_connected(address: String, chain_id: int)
signal wallet_disconnected()
signal chain_changed(chain_id: int)
## The page linked (true) or the link dropped (false).
signal link_changed(linked: bool)
## The page said which wallet it found (page_info).
signal page_info_changed(info: Dictionary)
## eth_requestAccounts was refused or failed in the page.
signal connect_failed(error: String)
signal tx_result(id: int, hash: String)
signal tx_failed(id: int, error: String)
## personal_sign (EIP-191): a free signature, not a transaction (the game server's sign-in).
signal sign_result(id: int, signature: String)
signal sign_failed(id: int, error: String)

# ── Multiplayer signals (legacy; the page no longer serves these) ──
signal mp_sync(players: Array)
signal mp_player_join(wallet: String, presence: Dictionary)
signal mp_player_leave(wallet: String)
signal mp_position_update(wallet: String, x: float, y: float, z: float, yaw: float, vx: float, vz: float)
signal mp_joined(channel: String)
signal mp_left()

# ── Voice chat signals (legacy) ──
signal vc_started()
signal vc_stopped()
signal vc_mute_changed(muted: bool)
signal vc_speaking(wallet: String, speaking: bool)
signal vc_error(error: String)

const DEFAULT_PORT: int = 38420
const MAX_PORT_RETRIES: int = 10
const PING_INTERVAL: float = 15.0
## An open socket that hasn't said a valid hello within this is closed.
const HELLO_TIMEOUT_MS := 5000
## At most this many sockets still handshaking or waiting for their hello: a web page
## opening sockets to 127.0.0.1 in a loop can't make the game hold memory for each.
const MAX_UNAUTHED := 8
## An HTTP request's headers must arrive within this many bytes and milliseconds.
const HTTP_MAX_HEADER := 8192
const HTTP_TIMEOUT_MS := 5000
## The relay nodes the page may fetch (also in wallet.html; the CSP's connect-src).
const RELAY_NODES := ["https://rpc.pulsechain.com", "https://pulsechain-rpc.publicnode.com"]
## The window title the page sets (FindWindow / EnumWindows match on it).
const WINDOW_TITLE := "Dysnomia Wallet Bridge"

var _http_server: TCPServer
var _ws_server: TCPServer
var _ws_peer: WebSocketPeer      # the linked (authenticated) page
var _pending_peers: Array = []   # WebSocketPeer still in the HTTP upgrade handshake
var _unauthed: Array = []        # {ws: WebSocketPeer, t0: int}: open, waiting for hello
var _closing_ws: Array = []      # {ws, t0}: closing; polled so the last message and close frame go out
var _pending_http: Array = []    # {peer: StreamPeerTCP, buf: PackedByteArray, t0}: reading the request
var _closing_http: Array = []    # {peer, frames}: answered, flushing
var _http_port: int = DEFAULT_PORT
var _ws_port: int = DEFAULT_PORT + 1
var _wallet_address: String = ""
var _chain_id: int = 0
var _next_tx_id: int = 1
var _ping_timer: float = 0.0
var _cached_html: String = ""    # wallet.html with the port and token baked in
var _browser_opened: bool = false
var _browser_opened_at := -1000000
var _browser_pid: int = -1
## false: never launch a browser (headless tools and the e2e harness open the page themselves).
var launch_browser := true
## What the linked page reported: {hasProvider, wallet, wallets, ua}.
var page_info := {}
## How the page was last opened ("chrome.exe --app", "default browser", …), for the wallet test.
var browser_used := ""
## The last error the page reported for eth_requestAccounts ("" when none).
var connect_error := ""

enum State {
	STOPPED,
	LISTENING,
	CONNECTED,
}
var _state: int = State.STOPPED
## Session token baked into the served page; a socket is ignored until the page
## echoes it in "hello". Other web pages can open a socket to 127.0.0.1 but cannot
## read our page (no CORS read of a cross-origin response).
var _token := ""
var _authed := false


func _ready() -> void:
	_http_server = TCPServer.new()
	_ws_server = TCPServer.new()


func start_server(port: int = DEFAULT_PORT) -> bool:
	## HTTP on `port`, WebSocket on `port + 1`; then port+2…, up to MAX_PORT_RETRIES pairs.
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
		_token = Crypto.new().generate_random_bytes(16).hex_encode()
		_authed = false
		_cached_html = _get_wallet_html().replace("{{PORT}}", str(_ws_port)).replace("{{TOKEN}}", _token)
		print("[WalletBridge] HTTP on localhost:%d, WS on localhost:%d" % [_http_port, _ws_port])
		return true

	push_error("[WalletBridge] Failed to bind to any port pair")
	return false


func stop_server() -> void:
	## Stop both servers and close every connection (an explicit disconnect).
	if _ws_peer:
		_ws_peer.close()
		_ws_peer = null
	for ws_peer in _pending_peers:
		ws_peer.close()
	_pending_peers.clear()
	for u in _unauthed:
		u["ws"].close()
	_unauthed.clear()
	_closing_ws.clear()
	for h in _pending_http:
		h["peer"].disconnect_from_host()
	_pending_http.clear()
	for item in _closing_http:
		item.peer.disconnect_from_host()
	_closing_http.clear()
	_http_server.stop()
	_ws_server.stop()
	var was_linked := _authed
	_state = State.STOPPED
	_authed = false
	_browser_opened = false
	page_info = {}
	if was_linked:
		link_changed.emit(false)
	if not _wallet_address.is_empty():
		_wallet_address = ""
		_chain_id = 0
		wallet_disconnected.emit()


func page_url() -> String:
	return "http://localhost:%d" % _http_port


func open_wallet_page(force: bool = false) -> void:
	## Opens the wallet page: as a Chromium --app window (no tabs or address bar) in the
	## browser that holds the wallet, else in the default browser. Once per server
	## session unless `force` (the window was closed, or the player asked).
	if _state == State.STOPPED:
		push_error("[WalletBridge] Server not running")
		return
	if _browser_opened and not force:
		print("[WalletBridge] Browser already opened — skipping")
		return
	_browser_opened = true
	_browser_opened_at = Time.get_ticks_msec()
	if not launch_browser:
		browser_used = "not launched (tool run): %s" % page_url()
		print("[WalletBridge] Wallet page at %s (not launching a browser)" % page_url())
		return
	var url := page_url()
	var browser_path := find_browser()
	if not browser_path.is_empty():
		# --app: no address bar or tabs. No --user-data-dir: that would hide the wallet extension.
		var args := PackedStringArray(["--app=%s" % url, "--window-size=420,560"])
		_browser_pid = OS.create_process(browser_path, args)
		if _browser_pid > 0:
			browser_used = "%s --app" % browser_path.get_file()
			print("[WalletBridge] Opened wallet window: %s (pid=%d)" % [browser_path, _browser_pid])
			return
		push_warning("[WalletBridge] Failed to launch %s, falling back to the default browser" % browser_path)
	OS.shell_open(url)
	browser_used = "default browser (%s)" % (default_browser_progid() if OS.get_name() == "Windows" else OS.get_name())
	print("[WalletBridge] Opened wallet page in the default browser: %s" % url)


func focus_wallet_page() -> void:
	## Brings the wallet window to the front so the wallet's approval opens on top.
	## Windows: Win32 SetForegroundWindow (window.focus() can't raise a background
	## window). Elsewhere: a "focus" message (best effort). Not linked: reopen it.
	if _state == State.STOPPED:
		return
	if is_linked():
		_activate_browser_window()
	elif not _browser_opened or Time.get_ticks_msec() - _browser_opened_at > 15000:
		print("[WalletBridge] Wallet window not linked — opening it again")
		open_wallet_page(true)


func reopen_wallet_page() -> void:
	## The player asked for the wallet window: raise the linked one, else open it again.
	if _state == State.STOPPED:
		return
	if is_linked():
		_activate_browser_window()
	else:
		open_wallet_page(true)


## Sends a fully built transaction ({from, to, data, value[, gas]}) for the user to
## sign. Calldata is built in Godot (Abi); the page only relays it to the browser
## wallet (eth_sendTransaction). `raise`: the game is raising the wallet window, so
## the page waits (≤ 4 s) to be in front before asking the wallet. `label` and
## `summary` (what it is, the decoded call) are shown on the page next to the
## contract, value and selector, so the player can compare them with the wallet's
## popup. Returns the request id (-1 if no page is linked).
func send_raw(tx: Dictionary, raise: bool = false, label: String = "", summary: String = "") -> int:
	if not is_linked():
		return -1
	var tx_id := _next_tx_id
	_next_tx_id += 1
	_send_json({"type": "send_raw", "id": tx_id, "tx": tx, "raise": raise, "label": label, "summary": summary})
	return tx_id


## Asks the wallet to personal_sign `message` (UTF-8 text) with the connected
## account. Free: nothing is sent to the chain. Returns the request id (-1 if not ready).
func personal_sign(message: String, raise: bool = false) -> int:
	if not is_linked() or _wallet_address == "":
		return -1
	var id := _next_tx_id
	_next_tx_id += 1
	_send_json({"type": "personal_sign", "id": id, "message": message, "address": _wallet_address, "raise": raise})
	return id


## Asks the page to switch the wallet to PulseChain (wallet_switchEthereumChain;
## added first if the wallet doesn't know it). The answer arrives as chain_changed.
func request_switch_chain() -> bool:
	if not is_linked():
		return false
	_send_json({"type": "switch_chain"})
	return true


## Asks the page to connect again (eth_requestAccounts).
func request_accounts() -> bool:
	if not is_linked():
		return false
	_send_json({"type": "request_accounts"})
	return true


var _status_results := {}


## What the wallet says right now, without a popup (eth_accounts, eth_chainId):
## {ok, hasProvider, wallet, wallets, accounts, chainId, error} or {ok:false, error}.
func query_status(timeout_s: float = 8.0) -> Dictionary:
	if not is_linked():
		return {"ok": false, "error": "the wallet window is not linked to the game"}
	var id := _next_tx_id
	_next_tx_id += 1
	_send_json({"type": "status", "id": id})
	var t0 := Time.get_ticks_msec()
	while not _status_results.has(id) and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await get_tree().create_timer(0.05).timeout
	if not _status_results.has(id):
		return {"ok": false, "error": "the wallet window did not answer within %d s" % int(timeout_s)}
	var r: Dictionary = _status_results[id]
	_status_results.erase(id)
	r["ok"] = true
	return r


var _relay_next := 1
var _relay_waiting := {}
var _relay_results := {}


## Sends one JSON-RPC body through the wallet page's fetch (the browser's network).
## {ok, code, body}; {ok:false} if the page isn't linked or doesn't answer in 25 s.
func relay_rpc(body: String) -> Dictionary:
	if not is_linked():
		return {"ok": false}
	var rid := _relay_next
	_relay_next += 1
	_relay_waiting[rid] = true
	_send_json({"type": "rpc", "id": rid, "body": body})
	var t0 := Time.get_ticks_msec()
	while not _relay_results.has(rid) and Time.get_ticks_msec() - t0 < 25000:
		await get_tree().create_timer(0.05).timeout
	_relay_waiting.erase(rid)
	var r: Dictionary = _relay_results.get(rid, {"ok": false})
	_relay_results.erase(rid)
	return r


## A page is linked (authenticated socket open).
func is_linked() -> bool:
	return _state == State.CONNECTED and _authed and _ws_peer != null


func is_authenticated() -> bool:
	return _authed


func get_chain_id() -> int:
	return _chain_id


func is_wallet_connected() -> bool:
	return is_linked() and not _wallet_address.is_empty()


func is_server_running() -> bool:
	## Returns true if servers are up (LISTENING or CONNECTED).
	return _state != State.STOPPED


func get_wallet_address() -> String:
	return _wallet_address


func get_port() -> int:
	return _http_port


func get_token() -> String:
	return _token


# ─── Multiplayer / voice commands (legacy) ───────────────────────────────

func send_mp_join(qing_address: String, wallet: String, username: String, tier: int) -> void:
	_send_json({"type": "mp_join", "qing": qing_address, "wallet": wallet, "username": username, "tier": tier})


func send_mp_leave() -> void:
	_send_json({"type": "mp_leave"})


func send_mp_position(x: float, y: float, z: float, yaw: float, vx: float, vz: float) -> void:
	_send_json({"type": "mp_position", "x": x, "y": y, "z": z, "r": yaw, "vx": vx, "vz": vz})


func send_vc_start() -> void:
	_send_json({"type": "vc_start"})


func send_vc_stop() -> void:
	_send_json({"type": "vc_stop"})


func send_vc_mute() -> void:
	_send_json({"type": "vc_mute"})


# ─── Process Loop ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _state == State.STOPPED:
		return

	while _http_server.is_connection_available():
		var peer := _http_server.take_connection()
		if peer:
			if _pending_http.size() >= MAX_UNAUTHED * 4:
				peer.disconnect_from_host()
				continue
			_pending_http.append({"peer": peer, "buf": PackedByteArray(), "t0": Time.get_ticks_msec()})
	_poll_http_peers()
	_flush_closing_http()

	while _ws_server.is_connection_available():
		var peer := _ws_server.take_connection()
		if peer:
			_try_ws_accept(peer)
	_poll_pending_peers()
	_poll_unauthed()
	_poll_closing_ws()

	if _ws_peer:
		_ws_peer.poll()
		var ws_state := _ws_peer.get_ready_state()
		if ws_state == WebSocketPeer.STATE_OPEN:
			while _ws_peer and _ws_peer.get_available_packet_count() > 0:
				var packet := _ws_peer.get_packet()
				_handle_ws_message(packet.get_string_from_utf8())
			_ping_timer += delta
			if _ping_timer >= PING_INTERVAL:
				_ping_timer = 0.0
				_send_json({"type": "ping"})
		elif ws_state == WebSocketPeer.STATE_CLOSED:
			_on_ws_disconnected()


# ─── HTTP Server ──────────────────────────────────────────────────────────

func _poll_http_peers() -> void:
	var keep: Array = []
	for h in _pending_http:
		var peer: StreamPeerTCP = h["peer"]
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTING:
			keep.append(h)
			continue
		if status != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var buf: PackedByteArray = h["buf"]
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_data(mini(n, HTTP_MAX_HEADER + 1 - buf.size()))
			if got[0] == OK:
				buf.append_array(got[1])
				h["buf"] = buf
		var text: String = buf.get_string_from_utf8()
		var complete := text.contains("\r\n\r\n")
		var too_big: bool = buf.size() > HTTP_MAX_HEADER
		var late := Time.get_ticks_msec() - int(h["t0"]) > HTTP_TIMEOUT_MS
		if not (complete or too_big or late):
			keep.append(h)
			continue
		var verdict := http_verdict(text, _http_port) if complete else "bad_request"
		match verdict:
			"ok":
				_respond(peer, "200 OK", "text/html; charset=utf-8", _cached_html)
			"bad_method":
				_respond(peer, "405 Method Not Allowed", "text/plain; charset=utf-8", "Only GET.\n")
			"bad_host":
				# DNS rebinding (or a proxy): never serve the token to another host name
				push_warning("[WalletBridge] refused a request for host %s (only localhost:%d)" % [header_value(text, "host").left(80), _http_port])
				_respond(peer, "403 Forbidden", "text/plain; charset=utf-8", "This wallet relay only answers http://localhost:%d/\n" % _http_port)
			_:
				_respond(peer, "400 Bad Request", "text/plain; charset=utf-8", "Bad request.\n")
	_pending_http = keep


func _respond(peer: StreamPeerTCP, status: String, content_type: String, body_text: String) -> void:
	var body := body_text.to_utf8_buffer()
	var header := "HTTP/1.1 %s\r\n" % status
	header += "Content-Type: %s\r\n" % content_type
	header += "Content-Length: %d\r\n" % body.size()
	for line in security_headers(_ws_port):
		header += line + "\r\n"
	header += "Connection: close\r\n"
	header += "\r\n"
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body)
	_closing_http.append({"peer": peer, "frames": 10})


## Pure: what to do with an HTTP request (its text up to the blank line). "ok" for a
## GET (any path: a favicon request gets the page too, harmlessly) whose Host is
## localhost:PORT or 127.0.0.1:PORT; "bad_host" for any other Host (DNS rebinding:
## a site whose name now resolves to 127.0.0.1 sends its own name); "bad_method";
## "bad_request" when there is no request line or no Host.
static func http_verdict(request_text: String, port: int) -> String:
	var first := request_text.get_slice("\r\n", 0).strip_edges()
	var parts := first.split(" ", false)
	if parts.size() != 3 or not parts[2].begins_with("HTTP/1."):
		return "bad_request"
	if parts[0] != "GET":
		return "bad_method"
	var host := header_value(request_text, "host").to_lower()
	if host == "":
		return "bad_request"
	if host == "localhost:%d" % port or host == "127.0.0.1:%d" % port:
		return "ok"
	return "bad_host"


## Pure: the value of header `name` (case-insensitive), "" if absent.
static func header_value(request_text: String, name: String) -> String:
	var lines := request_text.split("\r\n")
	for i in range(1, lines.size()):
		var line: String = lines[i]
		if line == "":
			break
		var colon := line.find(":")
		if colon > 0 and line.left(colon).strip_edges().to_lower() == name.to_lower():
			return line.substr(colon + 1).strip_edges()
	return ""


## Pure: the response headers of every answer. The page has no external scripts and
## writes untrusted text only with textContent; the CSP is a second line: no framing,
## no plugins, no <base>, no forms, and the page may only talk to the game's socket and
## the two relay nodes. Inline script stays allowed ('unsafe-inline') because wallet
## extensions inject their provider that way; chrome-/moz-extension: for the same reason.
static func security_headers(ws_port: int) -> PackedStringArray:
	var ext := "chrome-extension: moz-extension:"
	var csp := "; ".join(PackedStringArray([
		"default-src 'none'",
		"script-src 'self' 'unsafe-inline' " + ext,
		"style-src 'self' 'unsafe-inline'",
		"img-src 'self' data: " + ext,
		"connect-src 'self' ws://127.0.0.1:%d %s %s" % [ws_port, " ".join(PackedStringArray(RELAY_NODES)), ext],
		"object-src 'none'",
		"base-uri 'none'",
		"form-action 'none'",
		"frame-ancestors 'none'",
	]))
	return PackedStringArray([
		"Content-Security-Policy: " + csp,
		"X-Frame-Options: DENY",
		"X-Content-Type-Options: nosniff",
		"Referrer-Policy: no-referrer",
		"Cross-Origin-Opener-Policy: same-origin",
		"Cross-Origin-Resource-Policy: same-origin",
		"Cache-Control: no-store",
	])


func _flush_closing_http() -> void:
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
	## Every connection is upgraded; only a valid hello links it (a stale or second
	## window must never lock the real page out).
	if _pending_peers.size() + _unauthed.size() >= MAX_UNAUTHED:
		if _unauthed.is_empty():
			peer.disconnect_from_host()  # a flood of half-open handshakes: refuse the newest
			return
		_close_later(_unauthed.pop_front()["ws"])  # the oldest silent socket makes room
	var new_ws := WebSocketPeer.new()
	# Relayed chain reads (multicall results, logs) can be far larger than the 64 KiB
	# default; an oversized message would be dropped and the read lost.
	new_ws.inbound_buffer_size = 16 * 1024 * 1024
	new_ws.outbound_buffer_size = 1024 * 1024
	new_ws.max_queued_packets = 4096
	if new_ws.accept_stream(peer) != OK:
		peer.disconnect_from_host()
		return
	_pending_peers.append(new_ws)


func _poll_pending_peers() -> void:
	var to_remove: Array[int] = []
	for i in range(_pending_peers.size()):
		var ws: WebSocketPeer = _pending_peers[i]
		ws.poll()
		var ws_state := ws.get_ready_state()
		if ws_state == WebSocketPeer.STATE_OPEN:
			to_remove.append(i)
			_unauthed.append({"ws": ws, "t0": Time.get_ticks_msec()})
		elif ws_state == WebSocketPeer.STATE_CLOSED:
			to_remove.append(i)
	to_remove.reverse()
	for idx in to_remove:
		_pending_peers.remove_at(idx)


func _poll_unauthed() -> void:
	var keep: Array = []
	for u in _unauthed:
		var ws: WebSocketPeer = u["ws"]
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		if ws.get_available_packet_count() > 0:
			var verdict := hello_verdict(ws.get_packet().get_string_from_utf8(), _token)
			if verdict == "ok":
				_promote(ws)
			else:
				# "stale": a page from an earlier game session reloads itself and links
				push_warning("[WalletBridge] wallet page rejected (%s)" % verdict)
				if verdict == "stale":
					ws.send_text(JSON.stringify({"type": "stale"}))
				_close_later(ws)
			continue
		if Time.get_ticks_msec() - int(u["t0"]) > HELLO_TIMEOUT_MS:
			_close_later(ws)
			continue
		keep.append(u)
	_unauthed = keep


## Pure: what a socket's first message means. "ok" (this session's hello), "stale"
## (a hello with another token: an old page), or "bad" (anything else).
static func hello_verdict(text: String, token: String) -> String:
	var p := JSON.new()
	var j = p.data if p.parse(text) == OK else null
	if not (j is Dictionary) or String(j.get("type", "")) != "hello":
		return "bad"
	var t := String(j.get("token", ""))
	if token != "" and t == token:
		return "ok"
	return "stale" if t != "" else "bad"


func _promote(ws: WebSocketPeer) -> void:
	# One linked window at a time, and the one already linked keeps the link (the
	# player may be approving something in it): a second window is told to stop.
	if _ws_peer and _ws_peer != ws and _ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify({"type": "superseded"}))
		_close_later(ws)
		print("[WalletBridge] A second wallet window opened; it was told to close (one is already linked)")
		return
	_ws_peer = ws
	_state = State.CONNECTED
	_authed = true
	_ping_timer = 0.0
	page_info = {}
	print("[WalletBridge] Wallet page linked")
	_send_json({"type": "welcome"})
	_send_json({"type": "request_accounts"})
	link_changed.emit(true)


func _close_later(ws: WebSocketPeer) -> void:
	ws.close(1000, "")
	_closing_ws.append({"ws": ws, "t0": Time.get_ticks_msec()})


func _poll_closing_ws() -> void:
	var keep: Array = []
	for c in _closing_ws:
		var ws: WebSocketPeer = c["ws"]
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec() - int(c["t0"]) < 3000:
			keep.append(c)
	_closing_ws = keep


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
	var msg_type: String = String(data.get("type", ""))
	# JSON numbers arrive as floats: ids are read with int() so they match the int keys.
	var id := int(data.get("id", -1))

	match msg_type:
		"connected":
			var addr := String(data.get("address", "")).to_lower()
			var cid := int(data.get("chainId", 0))
			connect_error = ""
			if addr.is_empty():
				return
			var changed := addr != _wallet_address or cid != _chain_id
			_wallet_address = addr
			_chain_id = cid
			if changed:
				print("[WalletBridge] Wallet connected: %s (chain %d)" % [addr, cid])
			wallet_connected.emit(addr, cid)

		"connect_error":
			connect_error = String(data.get("error", "refused"))
			print("[WalletBridge] The wallet refused to connect: %s" % connect_error)
			connect_failed.emit(connect_error)

		"accounts_changed":
			var addr := String(data.get("address", "")).to_lower()
			if addr != _wallet_address:
				_wallet_address = addr
				if addr.is_empty():
					wallet_disconnected.emit()
				else:
					wallet_connected.emit(addr, _chain_id)

		"chain_changed":
			var cid := int(data.get("chainId", 0))
			if cid != _chain_id:
				print("[WalletBridge] Wallet chain is now %d" % cid)
			_chain_id = cid
			chain_changed.emit(cid)

		"page_info":
			page_info = data
			page_info_changed.emit(page_info)

		"tx_result":
			if id >= 0:
				tx_result.emit(id, String(data.get("hash", "")))

		"tx_error":
			if id >= 0:
				tx_failed.emit(id, String(data.get("error", "Unknown error")))

		"sign_result":
			sign_result.emit(id, String(data.get("signature", "")))

		"sign_error":
			sign_failed.emit(id, String(data.get("error", "refused")))

		"status_result":
			_status_results[id] = data

		"rpc_result":
			if _relay_waiting.has(id):
				_relay_results[id] = {"ok": bool(data.get("ok", false)), "code": int(data.get("status", 0)), "body": String(data.get("body", ""))}
				_relay_waiting.erase(id)

		"pong":
			pass


func _on_ws_disconnected() -> void:
	## The page's socket closed (window closed, reload, sleep). The wallet address is
	## kept: requests wait for the page to relink, and the page re-sends its answers.
	_authed = false
	_ws_peer = null
	_state = State.LISTENING
	_ping_timer = 0.0
	page_info = {}
	print("[WalletBridge] Wallet page link closed")
	link_changed.emit(false)


# ─── Browser Window Activation ─────────────────────────────────────────────

func _activate_browser_window() -> void:
	## Raises the wallet window. Windows: EnumWindows for a visible window whose title
	## starts with WINDOW_TITLE (an --app window, or a tab of a normal browser window),
	## then ShowWindow (restore only if minimised) + SetForegroundWindow. Allowed
	## because the game (the foreground process) starts this PowerShell.
	if OS.get_name() == "Windows":
		var cs := (
			"using System; using System.Text; using System.Runtime.InteropServices; " +
			"public class DysWin { " +
			"public delegate bool EnumProc(IntPtr h, IntPtr l); " +
			"[DllImport(\"user32.dll\")] public static extern bool EnumWindows(EnumProc f, IntPtr l); " +
			"[DllImport(\"user32.dll\", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n); " +
			"[DllImport(\"user32.dll\")] public static extern bool IsWindowVisible(IntPtr h); " +
			"[DllImport(\"user32.dll\")] public static extern bool IsIconic(IntPtr h); " +
			"[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr h, int n); " +
			"[DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr h); " +
			"public static bool Raise(string prefix) { IntPtr found = IntPtr.Zero; " +
			"EnumWindows(delegate (IntPtr h, IntPtr l) { if (!IsWindowVisible(h)) return true; " +
			"StringBuilder sb = new StringBuilder(512); GetWindowText(h, sb, 512); string t = sb.ToString(); " +
			"if (t.StartsWith(prefix) && t.IndexOf(\"(closed)\") < 0) { found = h; return false; } return true; }, IntPtr.Zero); " +
			"if (found == IntPtr.Zero) return false; if (IsIconic(found)) ShowWindow(found, 9); return SetForegroundWindow(found); } }"
		)
		var ps_script := "try { Add-Type -TypeDefinition '%s' -Language CSharp -ErrorAction SilentlyContinue; [void][DysWin]::Raise('%s') } catch {}" % [cs, WINDOW_TITLE]
		# -EncodedCommand (UTF-16LE base64): no command-line quoting of the C# quotes
		OS.create_process("powershell.exe", PackedStringArray([
			"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
			"-EncodedCommand", Marshalls.raw_to_base64(ps_script.to_utf16_buffer()),
		]))
	else:
		_send_json({"type": "focus"})


# ─── Browser Detection ────────────────────────────────────────────────────

## The wallet window's browser: Config.wallet_browser when set; on Windows the
## default browser when it is Chrome, Brave or Edge (where the player's wallet
## extension lives); "" = open the page in the default browser itself (Firefox, …).
func find_browser() -> String:
	var forced := String(Config.wallet_browser).strip_edges() if Config else ""
	if forced != "":
		if FileAccess.file_exists(forced):
			return forced
		push_warning("[WalletBridge] wallet browser %s not found; choosing automatically" % forced)
	if OS.get_name() != "Windows":
		for p in ["/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/usr/bin/brave-browser",
				"/usr/bin/chromium-browser", "/usr/bin/chromium",
				"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
				"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
				"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"]:
			if FileAccess.file_exists(p):
				return p
		return ""
	var progid := default_browser_progid()
	var kind := browser_kind(progid)
	print("[WalletBridge] Default browser: %s (%s)" % [progid if progid != "" else "unknown", kind if kind != "" else "?"])
	if kind == "other":
		return ""  # Firefox, Opera…: the default browser opens the page (its wallet is there)
	var order: Array = [kind] if kind != "" else []
	for k in ["chrome", "brave", "edge"]:
		if not k in order:
			order.append(k)
	for k in order:
		for p in windows_paths(k, OS.get_environment("LOCALAPPDATA")):
			if FileAccess.file_exists(p):
				return p
	return ""


## Windows: the ProgId of the default http handler ("ChromeHTML", "BraveHTML", "MSEdgeHTM"…), "" if unknown.
static func default_browser_progid() -> String:
	if OS.get_name() != "Windows":
		return ""
	var out: Array = []
	OS.execute("reg", PackedStringArray(["query",
		"HKCU\\Software\\Microsoft\\Windows\\Shell\\Associations\\UrlAssociations\\http\\UserChoice",
		"/v", "ProgId"]), out, true)
	return parse_reg_progid("\n".join(out))


## Pure: the ProgId value in `reg query … /v ProgId` output.
static func parse_reg_progid(text: String) -> String:
	for line in text.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() >= 3 and parts[0] == "ProgId" and parts[1] == "REG_SZ":
			return parts[2].strip_edges()
	return ""


## Pure: "chrome" | "brave" | "edge" | "other" (a non-Chromium default) | "" (unknown).
static func browser_kind(progid: String) -> String:
	var p := progid.to_lower()
	if p == "":
		return ""
	if p.contains("brave"):
		return "brave"
	if p.begins_with("msedge"):
		return "edge"
	if p.begins_with("chrome"):
		return "chrome"
	return "other"


## Pure: where each browser is installed on Windows (per-user first).
static func windows_paths(kind: String, local_app_data: String) -> Array:
	var out: Array = []
	match kind:
		"chrome":
			if local_app_data != "":
				out.append(local_app_data + "/Google/Chrome/Application/chrome.exe")
			out.append_array(["C:/Program Files/Google/Chrome/Application/chrome.exe",
				"C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"])
		"brave":
			if local_app_data != "":
				out.append(local_app_data + "/BraveSoftware/Brave-Browser/Application/brave.exe")
			out.append_array(["C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe",
				"C:/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"])
		"edge":
			if local_app_data != "":
				out.append(local_app_data + "/Microsoft/Edge/Application/msedge.exe")
			out.append_array(["C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
				"C:/Program Files/Microsoft/Edge/Application/msedge.exe"])
	return out
