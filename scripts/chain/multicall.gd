class_name Multicall
extends RefCounted
## Batched reads through Multicall3.aggregate3 (one eth_call per chunk).
## ≤ CHUNK calls per eth_call, ≤ PARALLEL chunks in flight.
##
## Each call: {target: "0x…", data: "0x…", allow_failure: bool = true}.
## Result per call, in order: {ok: bool, data: "0x…"}; if the whole chunk
## failed: {ok: false, data: "", chunk_error: <rpc failure dictionary>}.

const CHUNK := 300
const PARALLEL := 6

var rpc: Rpc


func _init(p_rpc: Rpc) -> void:
	rpc = p_rpc


static func encode(calls: Array) -> String:
	var tuples: Array = []
	for c in calls:
		tuples.append([c["target"], c.get("allow_failure", true), c["data"]])
	return Contracts.selector("aggregate3((address,bool,bytes)[])") \
		+ Abi.encode(["(address,bool,bytes)[]"], [tuples])


static func decode(return_data: String) -> Array:
	var out: Array = []
	for pair in Abi.decode(["(bool,bytes)[]"], return_data)[0]:
		out.append({"ok": pair[0], "data": pair[1]})
	return out


## Runs every call; `from` matters for tx.origin-keyed reads. `block` may be a
## {"blockHash": …} pin so all chunks read the same state.
func run(calls: Array, from: String = "", block = "latest") -> Array:
	var results: Array = []
	results.resize(calls.size())
	var chunks: Array = []
	for start in range(0, calls.size(), CHUNK):
		chunks.append([start, calls.slice(start, mini(start + CHUNK, calls.size()))])
	var state := {"next": 0}
	var waiter := _Waiter.new()
	for i in mini(PARALLEL, chunks.size()):
		_run_worker(chunks, state, results, from, block, waiter)
	if chunks.size() > 0:
		await waiter.finished
	return results


class _Waiter:
	extends RefCounted
	signal finished
	var active := 0


func _run_worker(chunks: Array, state: Dictionary, results: Array, from: String, block, waiter: _Waiter) -> void:
	waiter.active += 1
	while state["next"] < chunks.size():
		var chunk: Array = chunks[state["next"]]
		state["next"] += 1
		var start: int = chunk[0]
		var part: Array = chunk[1]
		var r := await rpc.eth_call(Contracts.MULTICALL3, encode(part), from, block)
		if r["ok"]:
			var decoded := decode(r["result"])
			for j in decoded.size():
				results[start + j] = decoded[j]
		else:
			for j in part.size():
				results[start + j] = {"ok": false, "data": "", "chunk_error": r}
	waiter.active -= 1
	if waiter.active == 0:
		waiter.finished.emit()


## Helper: build a call for a known signature.
static func make_call(target: String, signature: String, args: Array = [], allow_failure: bool = true) -> Dictionary:
	return {"target": target, "data": Abi.encode_call(signature, args), "allow_failure": allow_failure}


## Helper: decode one result, or null if it failed / is too short.
static func value(result: Dictionary, out_types: Array):
	if not result.get("ok", false):
		return null
	var d: String = result["data"]
	if Abi.strip0x(d).length() < 64 * out_types.size():
		return null
	return Abi.decode(out_types, d)
