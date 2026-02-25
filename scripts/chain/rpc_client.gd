extends Node
## Low-level Ethereum JSON-RPC 2.0 client using HTTPRequest.
## Single-request-at-a-time with FIFO queue for sequential calls.

signal call_completed(request_id: int, result_hex: String)
signal call_failed(request_id: int, error_msg: String)

const REQUEST_TIMEOUT: float = 10.0
const RETRY_DELAY: float = 0.15  # Seconds between queued requests (150ms = ~6.6 req/s)
const RATE_LIMIT_DELAY: float = 2.0  # Extra wait when RPC rate-limits us (HTTP 429)

var rpc_url: String = "https://rpc.pulsechain.com"

var _http: HTTPRequest
var _timeout_timer: Timer
var _retry_timer: Timer
var _request_id: int = 0
var _current_id: int = -1
var _current_callback_completed: Callable
var _current_callback_failed: Callable
var _current_request: Dictionary = {}  # Full request dict for retry on rate-limit
var _queue: Array[Dictionary] = []
var _busy: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	_http.request_completed.connect(_on_http_completed)
	add_child(_http)

	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.wait_time = REQUEST_TIMEOUT
	_timeout_timer.timeout.connect(_on_timeout)
	add_child(_timeout_timer)

	# Retry timer for when HTTPRequest reports ERR_BUSY
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.wait_time = RETRY_DELAY
	_retry_timer.timeout.connect(_try_process_queue)
	add_child(_retry_timer)


func eth_call(to: String, data: String, on_completed: Callable = Callable(), on_failed: Callable = Callable()) -> int:
	_request_id += 1
	var rid := _request_id
	_enqueue({
		"id": rid,
		"method": "eth_call",
		"params": [{"to": to, "data": data}, "latest"],
		"on_completed": on_completed,
		"on_failed": on_failed,
	})
	return rid


func eth_call_from(from: String, to: String, data: String, on_completed: Callable = Callable(), on_failed: Callable = Callable()) -> int:
	## eth_call with a 'from' field — needed for view functions that return per-user data.
	_request_id += 1
	var rid := _request_id
	_enqueue({
		"id": rid,
		"method": "eth_call",
		"params": [{"from": from, "to": to, "data": data}, "latest"],
		"on_completed": on_completed,
		"on_failed": on_failed,
	})
	return rid


func eth_get_storage_at(address: String, slot: int, on_completed: Callable = Callable(), on_failed: Callable = Callable()) -> int:
	_request_id += 1
	var rid := _request_id
	var slot_hex := "0x%x" % slot
	_enqueue({
		"id": rid,
		"method": "eth_getStorageAt",
		"params": [address, slot_hex, "latest"],
		"on_completed": on_completed,
		"on_failed": on_failed,
	})
	return rid


func eth_get_storage_at_hex(address: String, slot_hex: String, on_completed: Callable = Callable(), on_failed: Callable = Callable()) -> int:
	## Read storage at a hex-encoded slot key (for computed mapping keys).
	_request_id += 1
	var rid := _request_id
	_enqueue({
		"id": rid,
		"method": "eth_getStorageAt",
		"params": [address, slot_hex, "latest"],
		"on_completed": on_completed,
		"on_failed": on_failed,
	})
	return rid


func eth_call_create(data: String, on_completed: Callable = Callable(), on_failed: Callable = Callable()) -> int:
	## eth_call without a 'to' field — EVM treats data as contract creation init code.
	## Used to compute keccak256 on the RPC node without deploying anything.
	_request_id += 1
	var rid := _request_id
	_enqueue({
		"id": rid,
		"method": "eth_call",
		"params": [{"data": data}, "latest"],
		"on_completed": on_completed,
		"on_failed": on_failed,
	})
	return rid


func eth_get_logs(filter: Dictionary, on_completed: Callable = Callable(), on_failed: Callable = Callable()) -> int:
	## Fetch event logs matching the given filter.
	## The on_completed callback receives the raw JSON result string (an array).
	## Caller must parse it with JSON.parse_string().
	_request_id += 1
	var rid := _request_id
	_enqueue({
		"id": rid,
		"method": "eth_getLogs",
		"params": [filter],
		"on_completed": on_completed,
		"on_failed": on_failed,
	})
	return rid


func eth_get_transaction_receipt(tx_hash: String, on_completed: Callable = Callable(), on_failed: Callable = Callable()) -> int:
	## Query the receipt for a transaction by its hash.
	## Returns the raw JSON result string. Caller checks if result is null (pending) or has status.
	_request_id += 1
	var rid := _request_id
	_enqueue({
		"id": rid,
		"method": "eth_getTransactionReceipt",
		"params": [tx_hash],
		"on_completed": on_completed,
		"on_failed": on_failed,
	})
	return rid


func eth_chain_id(on_completed: Callable = Callable(), on_failed: Callable = Callable()) -> int:
	_request_id += 1
	var rid := _request_id
	_enqueue({
		"id": rid,
		"method": "eth_chainId",
		"params": [],
		"on_completed": on_completed,
		"on_failed": on_failed,
	})
	return rid


func is_busy() -> bool:
	return _busy


func _enqueue(request: Dictionary) -> void:
	if _busy:
		_queue.push_back(request)
	else:
		_send(request)


func _send(request: Dictionary) -> void:
	_busy = true
	_current_id = request["id"]
	_current_callback_completed = request.get("on_completed", Callable())
	_current_callback_failed = request.get("on_failed", Callable())
	_current_request = request

	var payload := {
		"jsonrpc": "2.0",
		"method": request["method"],
		"params": request["params"],
		"id": _current_id,
	}

	var json_body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])

	var err := _http.request(rpc_url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		if err == ERR_BUSY:
			# HTTPRequest hasn't fully reset yet — re-queue and retry after delay.
			# Don't call _finish_with_error to avoid recursive queue processing.
			_queue.push_front(request)
			_busy = false
			_current_id = -1
			_current_callback_completed = Callable()
			_current_callback_failed = Callable()
			if not _retry_timer.is_stopped():
				return  # Timer already pending
			_retry_timer.start()
			return
		_finish_with_error("HTTP request failed to start (error %d)" % err)
		return

	_timeout_timer.start()


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_timeout_timer.stop()

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_map := {
			HTTPRequest.RESULT_CANT_CONNECT: "Cannot connect to RPC endpoint",
			HTTPRequest.RESULT_CANT_RESOLVE: "Cannot resolve RPC hostname",
			HTTPRequest.RESULT_CONNECTION_ERROR: "Connection error",
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS handshake failed",
			HTTPRequest.RESULT_TIMEOUT: "Request timed out",
		}
		_finish_with_error(error_map.get(result, "HTTP error %d" % result))
		return

	if response_code == 429:
		# Rate limited — re-queue at front and retry after longer delay
		print("[RPCClient] Rate limited (HTTP 429), retrying after %.1fs..." % RATE_LIMIT_DELAY)
		var request := _current_request.duplicate()
		_reset_current()
		_queue.push_front(request)
		_retry_timer.wait_time = RATE_LIMIT_DELAY
		_retry_timer.start()
		return

	if response_code != 200:
		_finish_with_error("RPC returned HTTP %d" % response_code)
		return

	var body_str := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(body_str) != OK:
		_finish_with_error("Invalid JSON response")
		return

	var data: Dictionary = json.data
	if data.has("error"):
		var err_obj: Dictionary = data["error"]
		_finish_with_error("RPC error: %s" % err_obj.get("message", "Unknown"))
		return

	if not data.has("result"):
		_finish_with_error("No result in RPC response")
		return

	var raw_result = data["result"]
	if raw_result is Array or raw_result is Dictionary:
		# For eth_getLogs, eth_getTransactionReceipt, etc. — re-serialize as JSON string
		_finish_with_success(JSON.stringify(raw_result))
	elif raw_result == null:
		# Some RPC methods return null (e.g., pending tx receipt) — pass as "null"
		_finish_with_success("null")
	else:
		_finish_with_success(str(raw_result))


func _on_timeout() -> void:
	if not _busy:
		return  # Already handled by HTTPRequest's own timeout
	_http.cancel_request()
	_finish_with_error("Request timed out (manual)")


func _finish_with_success(result_hex: String) -> void:
	var rid := _current_id
	var cb := _current_callback_completed
	_reset_current()

	call_completed.emit(rid, result_hex)
	if cb.is_valid():
		cb.call(result_hex)

	# Use timer to process next queued request — ensures HTTPRequest
	# has fully reset before we call request() again.
	_schedule_next()


func _finish_with_error(error_msg: String) -> void:
	var rid := _current_id
	var cb := _current_callback_failed
	_reset_current()

	call_failed.emit(rid, error_msg)
	if cb.is_valid():
		cb.call(error_msg)

	_schedule_next()


func _reset_current() -> void:
	_busy = false
	_current_id = -1
	_current_callback_completed = Callable()
	_current_callback_failed = Callable()
	_current_request = {}


func _schedule_next() -> void:
	## Schedule the next queued request via the retry timer.
	## This guarantees HTTPRequest has fully completed before we re-use it.
	if _queue.is_empty():
		return
	if _busy:
		return  # Already processing something
	if not _retry_timer.is_stopped():
		return  # Timer already pending
	_retry_timer.wait_time = RETRY_DELAY  # Reset to normal delay (may have been raised by rate-limit)
	_retry_timer.start()


func _try_process_queue() -> void:
	## Called by retry timer — safely attempt to send the next queued request.
	if _busy:
		return
	if _queue.size() > 0:
		var next := _queue.pop_front() as Dictionary
		_send(next)


# ─── Batch RPC ───────────────────────────────────────────────────────────
# Sends multiple JSON-RPC calls in a single HTTP POST (JSON-RPC batch).
# Uses a separate HTTPRequest so it doesn't block the main queue.
# PulseChain RPC supports batch requests.

var _batch_http: HTTPRequest
var _batch_busy: bool = false
var _batch_queue: Array[Dictionary] = []  # [{calls: Array, callback: Callable}]

const BATCH_CHUNK_SIZE: int = 50  # Max calls per HTTP request (avoid oversized payloads)


func _ensure_batch_http() -> void:
	if _batch_http == null:
		_batch_http = HTTPRequest.new()
		_batch_http.timeout = 30.0  # Longer timeout for batch
		add_child(_batch_http)


func eth_call_batch(calls: Array, on_completed: Callable) -> void:
	## Send multiple eth_call requests in a single JSON-RPC batch.
	## calls: Array of {to: String, data: String}
	## on_completed(results: Array[Dictionary]) where each dict has:
	##   {index: int, success: bool, result: String}
	## Results are ordered by original index.
	_ensure_batch_http()

	if calls.is_empty():
		on_completed.call([])
		return

	# Split into chunks
	var chunks: Array = []
	for i in range(0, calls.size(), BATCH_CHUNK_SIZE):
		var end := mini(i + BATCH_CHUNK_SIZE, calls.size())
		chunks.append({"start": i, "calls": calls.slice(i, end)})

	# Process chunks sequentially
	var all_results: Array = []
	all_results.resize(calls.size())
	_process_batch_chunks(chunks, 0, all_results, on_completed)


func _process_batch_chunks(chunks: Array, chunk_idx: int, all_results: Array, final_callback: Callable) -> void:
	if chunk_idx >= chunks.size():
		# All chunks done
		final_callback.call(all_results)
		return

	if _batch_busy:
		# Queue this work for later
		_batch_queue.append({
			"chunks": chunks,
			"chunk_idx": chunk_idx,
			"all_results": all_results,
			"callback": final_callback,
		})
		return

	var chunk: Dictionary = chunks[chunk_idx]
	var start_idx: int = chunk.start
	var batch_calls: Array = chunk.calls

	# Build JSON-RPC batch payload
	var payload: Array = []
	for i in range(batch_calls.size()):
		var call_data: Dictionary = batch_calls[i]
		payload.append({
			"jsonrpc": "2.0",
			"method": "eth_call",
			"params": [{"to": call_data["to"], "data": call_data["data"]}, "latest"],
			"id": start_idx + i,
		})

	_batch_busy = true
	var json_body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])

	# Disconnect previous signal connections to avoid stacking
	if _batch_http.request_completed.is_connected(_on_batch_completed):
		_batch_http.request_completed.disconnect(_on_batch_completed)

	# Use a lambda to capture context
	var cb := func(result: int, response_code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
		_on_batch_http_done(result, response_code, body, start_idx, batch_calls.size(),
			all_results, chunks, chunk_idx, final_callback)
	_batch_http.request_completed.connect(cb, CONNECT_ONE_SHOT)

	var err := _batch_http.request(rpc_url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_batch_busy = false
		# Fill with errors
		for i in range(batch_calls.size()):
			all_results[start_idx + i] = {"index": start_idx + i, "success": false, "result": "HTTP error %d" % err}
		# Continue with next chunk
		_process_batch_chunks(chunks, chunk_idx + 1, all_results, final_callback)


func _on_batch_http_done(result: int, response_code: int, body: PackedByteArray,
		start_idx: int, count: int, all_results: Array,
		chunks: Array, chunk_idx: int, final_callback: Callable) -> void:
	_batch_busy = false
	print("[RPCClient] Batch response: result=%d code=%d body_size=%d chunk=%d/%d" % [
		result, response_code, body.size(), chunk_idx + 1, chunks.size()])

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var err_msg := "Batch HTTP error (result=%d, code=%d)" % [result, response_code]
		print("[RPCClient] Batch error: %s" % err_msg)
		for i in range(count):
			all_results[start_idx + i] = {"index": start_idx + i, "success": false, "result": err_msg}
		_process_batch_chunks(chunks, chunk_idx + 1, all_results, final_callback)
		_flush_batch_queue()
		return

	var body_str := body.get_string_from_utf8()
	var parsed = JSON.parse_string(body_str)
	if parsed == null or not (parsed is Array):
		print("[RPCClient] Batch parse failed: body_start='%s'" % body_str.left(100))
		for i in range(count):
			all_results[start_idx + i] = {"index": start_idx + i, "success": false, "result": "Invalid batch response"}
		_process_batch_chunks(chunks, chunk_idx + 1, all_results, final_callback)
		_flush_batch_queue()
		return

	# Map results by ID
	# Note: Godot's JSON parser returns numbers as float, so "id":0 becomes 0.0.
	# We must convert to int for dictionary key matching.
	var results_by_id: Dictionary = {}
	for item in parsed:
		if item is Dictionary:
			var resp_id: int = int(item.get("id", -1))
			results_by_id[resp_id] = item
	print("[RPCClient] Batch parsed: %d responses mapped for chunk starting at %d" % [
		results_by_id.size(), start_idx])

	for i in range(count):
		var idx := start_idx + i
		var resp: Dictionary = results_by_id.get(idx, {})
		if resp.has("error"):
			var err_val = resp.error
			var err_msg: String = err_val.get("message", "RPC error") if err_val is Dictionary else str(err_val)
			all_results[idx] = {"index": idx, "success": false, "result": err_msg}
		elif resp.has("result"):
			var raw = resp.result
			var result_str: String
			if raw is Array or raw is Dictionary:
				result_str = JSON.stringify(raw)
			elif raw == null:
				result_str = "null"
			else:
				result_str = str(raw)
			all_results[idx] = {"index": idx, "success": true, "result": result_str}
		else:
			all_results[idx] = {"index": idx, "success": false, "result": "Missing result for id %d" % idx}

	# Continue with next chunk
	_process_batch_chunks(chunks, chunk_idx + 1, all_results, final_callback)
	_flush_batch_queue()


func _on_batch_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	## Placeholder — actual handling done via one-shot lambda connections.
	pass


func _flush_batch_queue() -> void:
	## Process any queued batch work.
	if _batch_busy:
		return
	if _batch_queue.is_empty():
		return
	var next: Dictionary = _batch_queue.pop_front()
	_process_batch_chunks(next.chunks, next.chunk_idx, next.all_results, next.callback)
