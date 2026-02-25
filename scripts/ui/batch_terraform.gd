extends Node
## Batch terraform controller — chains multiple terraform calls sequentially.
## Waits for each tx to confirm before sending the next one.
## Only available at the monument interaction station.

signal batch_progress(op_name: String, current: int, total: int)
signal batch_completed(op_name: String, total: int)
signal batch_failed(op_name: String, error: String, completed: int)

const DEFAULT_BATCH_COUNT: int = 3
const MAX_BATCH_COUNT: int = 100
const TX_TIMEOUT: float = 360.0  # 6 minutes max wait per tx

var _batch_count: int = DEFAULT_BATCH_COUNT
var _is_running: bool = false
var _current_op: String = ""
var _current_index: int = 0
var _total_count: int = DEFAULT_BATCH_COUNT
var _op_callable: Callable
var _op_needs_seed: bool = false
var _op_extra_args: Array = []
var _pending_tx_id: int = -1
var _tx_sent_time: float = 0.0  # When the current tx was submitted


func is_running() -> bool:
	return _is_running


func set_batch_count(count: int) -> void:
	## Set how many operations to run in each batch (1–100).
	_batch_count = clampi(count, 1, MAX_BATCH_COUNT)
	print("[BatchTerraform] Batch count set to %d" % _batch_count)


func get_batch_count() -> int:
	return _batch_count


func _process(_delta: float) -> void:
	# Safety timeout — if we've been waiting too long for a tx, abort the batch
	if _is_running and _pending_tx_id >= 0 and _tx_sent_time > 0.0:
		var elapsed := Time.get_unix_time_from_system() - _tx_sent_time
		if elapsed > TX_TIMEOUT:
			print("[BatchTerraform] Tx %d timed out after %.0fs" % [_pending_tx_id, elapsed])
			var completed := _current_index - 1
			var op := _current_op
			_cleanup()
			batch_failed.emit(op, "Transaction confirmation timed out", completed)


func start_batch(op_name: String, op_callable: Callable, needs_seed: bool, extra_args: Array = []) -> void:
	## Start a batch of terraform operations.
	## op_callable: The ChainManager.terraform_* function to call.
	## needs_seed: If true, generates a fresh random seed for each iteration.
	## extra_args: Additional arguments (e.g., [phi_bool] for Upsilon).
	if _is_running:
		print("[BatchTerraform] Already running, ignoring start_batch")
		return

	_is_running = true
	_current_op = op_name
	_current_index = 0
	_total_count = _batch_count
	_op_callable = op_callable
	_op_needs_seed = needs_seed
	_op_extra_args = extra_args
	_pending_tx_id = -1
	_tx_sent_time = 0.0

	print("[BatchTerraform] Starting batch: %s x%d (needs_seed=%s, extra_args=%s)" % [
		op_name, _total_count, str(needs_seed), str(extra_args)])

	# Connect chain signals
	if not ChainManager.tx_confirmed.is_connected(_on_tx_confirmed):
		ChainManager.tx_confirmed.connect(_on_tx_confirmed)
	if not ChainManager.tx_failed.is_connected(_on_tx_failed):
		ChainManager.tx_failed.connect(_on_tx_failed)

	# Send first operation
	_send_next()


func cancel() -> void:
	## Cancel the current batch (doesn't revert already-confirmed txs).
	if not _is_running:
		return
	var completed := _current_index
	print("[BatchTerraform] Cancelled at %d/%d" % [completed, _total_count])
	_cleanup()
	batch_failed.emit(_current_op, "Cancelled by user", completed)


func _send_next() -> void:
	## Send the next terraform operation in the batch.
	if _current_index >= _total_count:
		# All done
		var op := _current_op
		var total := _total_count
		print("[BatchTerraform] Batch complete: %s x%d" % [op, total])
		_cleanup()
		batch_completed.emit(op, total)
		return

	_current_index += 1

	# Build arguments
	var args: Array = []
	if _op_needs_seed:
		var seed_val: int = randi() % 1_000_000_000 + 1
		args.append(seed_val)
	args.append_array(_op_extra_args)

	# Call the terraform function
	print("[BatchTerraform] Sending %s %d/%d with args %s" % [
		_current_op, _current_index, _total_count, str(args)])
	var tx_id: int = _op_callable.callv(args)
	if tx_id < 0:
		# Failed to even submit
		var completed := _current_index - 1
		var op := _current_op
		print("[BatchTerraform] Failed to submit tx %d/%d (tx_id=%d)" % [
			_current_index, _total_count, tx_id])
		_cleanup()
		batch_failed.emit(op, "Failed to submit transaction %d/%d" % [_current_index, _total_count], completed)
		return

	_pending_tx_id = tx_id
	_tx_sent_time = Time.get_unix_time_from_system()
	print("[BatchTerraform] Tx submitted, pending tx_id=%d" % tx_id)

	# Emit progress AFTER tx is submitted (so focus_wallet_page happens after tx is sent)
	batch_progress.emit(_current_op, _current_index, _total_count)


func _on_tx_confirmed(id: int, _hash: String) -> void:
	if not _is_running:
		return
	if id != _pending_tx_id:
		print("[BatchTerraform] Ignoring tx_confirmed id=%d (pending=%d)" % [id, _pending_tx_id])
		return  # Not our transaction

	print("[BatchTerraform] Tx %d confirmed (%d/%d done)" % [id, _current_index, _total_count])
	_pending_tx_id = -1
	_tx_sent_time = 0.0

	# Delay before next tx — wallet extensions need time to be ready for the next popup
	await get_tree().create_timer(1.5).timeout

	# Guard: batch may have been cancelled during the await
	if not _is_running:
		return

	# Send next in chain
	_send_next()


func _on_tx_failed(id: int, error: String) -> void:
	if not _is_running:
		return
	if id != _pending_tx_id:
		return  # Not our transaction

	print("[BatchTerraform] Tx %d failed: %s (%d/%d)" % [id, error, _current_index, _total_count])
	var completed := _current_index - 1
	var op := _current_op
	_cleanup()
	batch_failed.emit(op, error, completed)


func _cleanup() -> void:
	_is_running = false
	_pending_tx_id = -1
	_tx_sent_time = 0.0

	# Disconnect signals
	if ChainManager.tx_confirmed.is_connected(_on_tx_confirmed):
		ChainManager.tx_confirmed.disconnect(_on_tx_confirmed)
	if ChainManager.tx_failed.is_connected(_on_tx_failed):
		ChainManager.tx_failed.disconnect(_on_tx_failed)
