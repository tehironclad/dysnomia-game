class_name LogScanner
extends RefCounted
## Windowed eth_getLogs: 500k-block windows, halving on refusal down to a 2k
## floor, remembering the smallest refused size for the rest of the session.
## Logs are returned in chain order; de-duplicate on (transactionHash, logIndex).

const DEFAULT_WINDOW := 500000
const MIN_WINDOW := 2000

## Shared across scanners: the node's learned limit.
static var max_window := DEFAULT_WINDOW

var rpc: Rpc


func _init(p_rpc: Rpc) -> void:
	rpc = p_rpc


## Returns {ok, logs: Array, scanned_to: int}. On failure, `logs` holds what
## was read so far and `scanned_to` the last fully scanned block (a floor).
func scan(address: String, topics: Array, from_block: int, to_block: int) -> Dictionary:
	var logs: Array = []
	var cursor := from_block
	var window := max_window
	while cursor <= to_block:
		var end := mini(cursor + window - 1, to_block)
		var r := await rpc.get_logs(address, topics, cursor, end)
		if r["ok"]:
			logs.append_array(r["result"])
			cursor = end + 1
			continue
		# Range/size refusals come back as JSON-RPC errors; halve and retry.
		if r["kind"] == "rpc" and window > MIN_WINDOW:
			window = maxi(MIN_WINDOW, window / 2)
			max_window = mini(max_window, window)
			continue
		return {"ok": false, "logs": logs, "scanned_to": cursor - 1, "error": r}
	return {"ok": true, "logs": logs, "scanned_to": to_block}


static func log_key(log: Dictionary) -> String:
	return "%s:%s" % [String(log.get("transactionHash", "")), String(log.get("logIndex", ""))]
