class_name Rpc
extends Node
## JSON-RPC transport for PulseChain. Rules (docs/LEARNINGS.md §9):
## - never send JSON-RPC batches (the public node serialises them);
## - at most MAX_IN_FLIGHT concurrent single requests;
## - 4 tries with 300·2^i ms backoff and a 25 s timeout; a non-JSON body is a failure;
## - a JSON-RPC error is an answer (e.g. a revert), never retried.
##
## Every request returns a Dictionary:
##   {ok: true,  result: <any>}
##   {ok: false, kind: "revert",    revert: {selector,name,args,message}, error: {...}}
##   {ok: false, kind: "rpc",       error: {code, message}}
##   {ok: false, kind: "transport", error: {message}}

const MAX_IN_FLIGHT := 8
const MAX_TRIES := 4
const TIMEOUT_S := 25.0

signal _slot_freed

var endpoint: String = Contracts.DEFAULT_RPC
var _in_flight := 0
var _next_id := 1
## Counters for diagnostics overlays.
var stats := {"requests": 0, "retries": 0, "failures": 0}


func request(method: String, params: Array = []) -> Dictionary:
	while _in_flight >= MAX_IN_FLIGHT:
		await _slot_freed
	_in_flight += 1
	var res := {}
	for attempt in MAX_TRIES:
		if attempt > 0:
			stats["retries"] += 1
			await get_tree().create_timer(0.3 * pow(2.0, attempt - 1)).timeout
		res = await _send_once(method, params)
		if res["ok"] or res["kind"] != "transport":
			break
	if not res["ok"] and res["kind"] == "transport":
		stats["failures"] += 1
	_in_flight -= 1
	_slot_freed.emit()
	return res


func _send_once(method: String, params: Array) -> Dictionary:
	stats["requests"] += 1
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	add_child(http)
	var body := JSON.stringify({"jsonrpc": "2.0", "id": _next_id, "method": method, "params": params})
	_next_id += 1
	var err := http.request(endpoint, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "kind": "transport", "error": {"message": "request error %d" % err}}
	var r: Array = await http.request_completed
	http.queue_free()
	return classify(r[0], r[1], r[3])


## Pure: turns an HTTPRequest completion into a result Dictionary.
static func classify(result_code: int, http_code: int, body: PackedByteArray) -> Dictionary:
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "kind": "transport", "error": {"message": "http result %d" % result_code}}
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


## eth_call. Pass `from` for tx.origin-keyed reads (Su, Beat, Eta, Yuan…).
func eth_call(to: String, data: String, from: String = "", block = "latest") -> Dictionary:
	var tx := {"to": to, "data": data}
	if from != "":
		tx["from"] = from
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
