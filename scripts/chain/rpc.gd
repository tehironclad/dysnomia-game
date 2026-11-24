class_name Rpc
extends Node
## JSON-RPC transport for PulseChain. Rules (docs/LEARNINGS.md §9):
## - never send JSON-RPC batches (the public node serialises them);
## - at most MAX_IN_FLIGHT concurrent single requests;
## - one try per node (15 s timeout) across FALLBACKS, then the wallet-window relay, then
##   backed-off retries; a non-JSON body is a failure;
## - a JSON-RPC error is an answer (e.g. a revert), never retried.
##
## Every request returns a Dictionary:
##   {ok: true,  result: <any>}
##   {ok: false, kind: "revert",    revert: {selector,name,args,message}, error: {...}}
##   {ok: false, kind: "rpc",       error: {code, message}}
##   {ok: false, kind: "transport", error: {message}}

const MAX_IN_FLIGHT := 8
const MAX_TRIES := 4
const TIMEOUT_S := 15.0  ## short: an unreachable node must fail over fast

signal _slot_freed

var endpoint: String = Contracts.DEFAULT_RPC
## Public PulseChain nodes tried in order when the current one can't be reached
## (DNS, TLS, firewall, timeouts). All verified to answer eth_chainId = 0x171.
const FALLBACKS := ["https://rpc.pulsechain.com", "https://pulsechain-rpc.publicnode.com",
	"https://rpc-pulsechain.g4mm4.io", "https://pulsechain.publicnode.com", "https://rpc.pulsechainrpc.com"]
## Last resort: a Callable(body: String) -> {ok, code, body} that sends the request
## through the browser wallet window (the same network the site uses). Set by Wallet.
var relay: Callable = Callable()
var last_error := ""
## When every direct node failed and the relay worked, use the relay first until this
## time (ms), then give direct connections another chance.
var _relay_first_until := 0
const RELAY_FIRST_MS := 60000
var _logged := {}
var _in_flight := 0
var _next_id := 1
## Counters for diagnostics overlays.
var stats := {"requests": 0, "retries": 0, "failures": 0}


func request(method: String, params: Array = []) -> Dictionary:
	while _in_flight >= MAX_IN_FLIGHT:
		await _slot_freed
	_in_flight += 1
	var res := {"ok": false, "kind": "transport", "error": {"message": "not tried"}}
	# 0) direct nodes known to be unreachable on this PC: straight to the relay
	if relay.is_valid() and Time.get_ticks_msec() < _relay_first_until:
		res = await _via_relay(method, params)
		if res["ok"] or res["kind"] != "transport":
			_in_flight -= 1
			_slot_freed.emit()
			return res
	# 1) the current node, once, with a short timeout
	res = await _send_once(method, params)
	# 2) unreachable → every other public node once (fast failover, not 4 slow retries)
	if not res["ok"] and res["kind"] == "transport":
		_log_once(endpoint, String(res["error"]["message"]))
		for alt in FALLBACKS:
			if alt == endpoint:
				continue
			var r2 := await _send_once(method, params, alt)
			if r2["ok"] or r2["kind"] != "transport":
				print("[Rpc] %s unreachable (%s) — switched to %s" % [endpoint, res["error"]["message"], alt])
				endpoint = alt
				res = r2
				break
			_log_once(alt, String(r2["error"]["message"]))
	# 3) still nothing → through the browser wallet window, if it is linked
	if not res["ok"] and res["kind"] == "transport" and relay.is_valid():
		var rr := await _via_relay(method, params)
		if rr["ok"] or rr["kind"] != "transport":
			res = rr
			_relay_first_until = Time.get_ticks_msec() + RELAY_FIRST_MS
			if not _logged.has("relay"):
				_logged["relay"] = true
				print("[Rpc] direct connections failed — reading the chain through the wallet window")
	# 4) a blip (429, 5xx, timeout): a few backed-off retries on the node that worked last
	for attempt in range(1, MAX_TRIES):
		if res["ok"] or res["kind"] != "transport":
			break
		stats["retries"] += 1
		await get_tree().create_timer(0.3 * pow(2.0, attempt - 1)).timeout
		res = await _send_once(method, params)
	if not res["ok"] and res["kind"] == "transport":
		stats["failures"] += 1
		last_error = String(res["error"]["message"])
	_in_flight -= 1
	_slot_freed.emit()
	return res


func _via_relay(method: String, params: Array) -> Dictionary:
	var body := JSON.stringify({"jsonrpc": "2.0", "id": _next_id, "method": method, "params": params})
	_next_id += 1
	var rr: Dictionary = await relay.call(body)
	if not rr.get("ok", false):
		return {"ok": false, "kind": "transport", "error": {"message": "wallet-window relay did not answer"}}
	return classify(HTTPRequest.RESULT_SUCCESS, int(rr.get("code", 200)), String(rr.get("body", "")).to_utf8_buffer())


func _log_once(url: String, why: String) -> void:
	if _logged.has(url):
		return
	_logged[url] = true
	print("[Rpc] cannot reach %s: %s" % [url, why])


## Antivirus HTTPS scanning and corporate proxies re-sign TLS with their own root,
## which Windows trusts but Godot's bundled list doesn't (every node then fails with a
## TLS handshake error while the browser works). After such a failure the game trusts
## the operating system's own certificate store — the same one the browser uses.
static var _system_tls: TLSOptions = null
static var use_system_ca := false


static func tls_options() -> TLSOptions:
	if not use_system_ca:
		return null
	if _system_tls == null:
		var c := X509Certificate.new()
		if c.load_from_string(OS.get_system_ca_certificates()) == OK:
			_system_tls = TLSOptions.client(c)
	return _system_tls


static func apply_tls(http: HTTPRequest) -> void:
	var o := tls_options()
	if o:
		http.set_tls_options(o)


func _send_once(method: String, params: Array, url: String = "") -> Dictionary:
	var res := await _send_raw(method, params, url)
	if not res["ok"] and String(res.get("error", {}).get("message", "")).begins_with("TLS handshake") and not use_system_ca:
		use_system_ca = true
		var again := await _send_raw(method, params, url)
		if again["ok"] or again["kind"] != "transport":
			print("[Rpc] TLS handshake failed with Godot's certificate list — using the system certificate store (antivirus/proxy HTTPS scanning)")
			return again
		use_system_ca = false  # not the cause; back to the bundled list
	return res


func _send_raw(method: String, params: Array, url: String = "") -> Dictionary:
	stats["requests"] += 1
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	apply_tls(http)
	add_child(http)
	var body := JSON.stringify({"jsonrpc": "2.0", "id": _next_id, "method": method, "params": params})
	_next_id += 1
	var err := http.request(url if url != "" else endpoint, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "kind": "transport", "error": {"message": "request error %d" % err}}
	var r: Array = await http.request_completed
	http.queue_free()
	return classify(r[0], r[1], r[3])


## Pure: turns an HTTPRequest completion into a result Dictionary.
static func classify(result_code: int, http_code: int, body: PackedByteArray) -> Dictionary:
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "kind": "transport", "error": {"message": _result_name(result_code)}}
	if http_code == 429 or http_code >= 500:
		return {"ok": false, "kind": "transport", "error": {"message": "http %d" % http_code}}
	var json := JSON.new()
	var parsed = json.data if json.parse(body.get_string_from_utf8()) == OK else null
	if not (parsed is Dictionary):
		return {"ok": false, "kind": "transport", "error": {"message": "non-JSON response (http %d)" % http_code}}
	if parsed.has("error") and parsed["error"] != null:
		var e: Dictionary = parsed["error"] if parsed["error"] is Dictionary else {"message": str(parsed["error"])}
		var data = e.get("data")
		if data is String and String(data).begins_with("0x"):
			return {"ok": false, "kind": "revert", "revert": Abi.decode_revert(data), "error": e}
		var msg := String(e.get("message", ""))
		if msg.contains("execution reverted"):
			return {"ok": false, "kind": "revert", "revert": Abi.decode_revert("0x"), "error": e}
		return {"ok": false, "kind": "rpc", "error": e}
	if not parsed.has("result"):
		return {"ok": false, "kind": "transport", "error": {"message": "response without result"}}
	return {"ok": true, "result": parsed["result"]}


# --- Convenience wrappers ----------------------------------------------------

## A block selector: "latest", a block number (int) or {"blockHash": "0x…"} (EIP-1898).
static func block_param(block) -> Variant:
	if block is int:
		return "0x%x" % block
	return block


## eth_call. Pass `from` for tx.origin-keyed reads (Su, Beat, Eta, Yuan…), and
## `value_wei` ("0x…") to simulate a payable call (e.g. a swap paid in PLS).
func eth_call(to: String, data: String, from: String = "", block = "latest", value_wei: String = "") -> Dictionary:
	var tx := {"to": to, "data": data}
	if from != "":
		tx["from"] = from
	if value_wei != "" and value_wei != "0x0":
		tx["value"] = value_wei
	return await request("eth_call", [tx, block_param(block)])


## eth_call + decode. Returns {ok, values} or the failure dictionary.
func call_decoded(to: String, signature: String, args: Array, out_types: Array, from: String = "", block = "latest") -> Dictionary:
	var r := await eth_call(to, Abi.encode_call(signature, args), from, block)
	if not r["ok"]:
		return r
	var raw: String = r["result"]
	if Abi.strip0x(raw).length() < 64 * out_types.size():
		return {"ok": false, "kind": "rpc", "error": {"message": "short return data for %s" % signature}}
	return {"ok": true, "values": Abi.decode(out_types, raw)}


func block_number() -> Dictionary:
	var r := await request("eth_blockNumber")
	if r["ok"]:
		r["block"] = String(r["result"]).hex_to_int()
	return r


func get_block(block = "latest") -> Dictionary:
	return await request("eth_getBlockByNumber", [block_param(block), false])


func get_code(address: String, block = "latest") -> Dictionary:
	return await request("eth_getCode", [address, block_param(block)])


func get_transaction_count(address: String, block = "latest") -> Dictionary:
	return await request("eth_getTransactionCount", [address, block_param(block)])


func get_receipt(tx_hash: String) -> Dictionary:
	return await request("eth_getTransactionReceipt", [tx_hash])


func get_logs(address: String, topics: Array, from_block: int, to_block: int) -> Dictionary:
	return await request("eth_getLogs", [{
		"address": address, "topics": topics,
		"fromBlock": "0x%x" % from_block, "toBlock": "0x%x" % to_block,
	}])


## eth_estimateGas for {from,to,data,value}. Adds "gas" (int) on success.
func estimate_gas(from: String, to: String, data: String, value_wei: String = "0x0") -> Dictionary:
	var r := await request("eth_estimateGas", [{"from": from, "to": to, "data": data, "value": value_wei}])
	if r["ok"]:
		r["gas"] = String(r["result"]).hex_to_int()
	return r


## eth_gasPrice. Adds "wei" (PackedInt64Array BigInt) on success.
func gas_price() -> Dictionary:
	var r := await request("eth_gasPrice")
	if r["ok"]:
		r["wei"] = BigInt.from_hex(String(r["result"]))
	return r


static func _result_name(code: int) -> String:
	match code:
		HTTPRequest.RESULT_CANT_CONNECT: return "can't connect (firewall or offline?)"
		HTTPRequest.RESULT_CANT_RESOLVE: return "can't resolve the host name (DNS)"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "TLS handshake error (antivirus HTTPS scanning or a proxy?)"
		HTTPRequest.RESULT_NO_RESPONSE: return "no response"
		HTTPRequest.RESULT_TIMEOUT: return "timed out"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return "response too large"
	return "http result %d" % code
