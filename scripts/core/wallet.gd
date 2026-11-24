extends Node
## Autoload "Wallet" (WP 4.1): the browser wallet, through the local relay page
## (assets/web/wallet.html, authenticated by a session token).
##
## Every write goes through send():
##   1. precondition: connected, wallet on chain 369;
##   2. simulate: eth_call from the wallet; a revert is decoded and returned;
##   3. sign: the page relays {from,to,data,value} to the browser wallet;
##   4. verify: the receipt is read from the chain here (never trusted from the page);
##   5. the caller re-reads state.
## Nothing reports success before step 4 finds status 0x1.

signal connected(address: String)
signal disconnected
signal tx_stage(label: String, stage: String, info: Dictionary)

const SIGN_TIMEOUT_S := 300.0
const RECEIPT_TIMEOUT_S := 360.0
const RECEIPT_POLL_S := 4.0

var address := ""
var chain_id := 0
var bridge: Node
var _results := {}  # request id → {hash} | {error}


func _ready() -> void:
	bridge = load("res://scripts/chain/wallet_bridge.gd").new()
	bridge.name = "Bridge"
	add_child(bridge)
	# Last-resort chain reads through the browser window (after every autoload is up)
	(func() -> void:
		if Chain and Chain.rpc:
			Chain.rpc.relay = bridge.relay_rpc).call_deferred()
	bridge.wallet_connected.connect(_on_connected)
	bridge.wallet_disconnected.connect(_on_disconnected)
	bridge.tx_result.connect(func(id, hash): _results[id] = {"hash": hash})
	bridge.tx_failed.connect(func(id, err): _results[id] = {"error": err})


func is_connected_to_chain() -> bool:
	return address != "" and chain_id == Contracts.CHAIN_ID


## Starts the local relay and opens the wallet page in the browser.
func connect_wallet() -> bool:
	if bridge.is_server_running():
		bridge.open_wallet_page()
		return true
	if bridge.start_server(Config.wallet_bridge_port):
		bridge.open_wallet_page()
		return true
	return false


func disconnect_wallet() -> void:
	bridge.stop_server()
	_on_disconnected()


func _on_connected(addr: String, cid: int) -> void:
	address = addr.to_lower()
	chain_id = cid
	connected.emit(address)


func _on_disconnected() -> void:
	address = ""
	chain_id = 0
	disconnected.emit()


## eth_call from the connected wallet (or `from`), with `value_wei` for payable
## calls. {ok, result} or the Rpc failure.
func simulate(to: String, data: String, from: String = "", value_wei: String = "") -> Dictionary:
	return await Chain.rpc.eth_call(to, data, from if from != "" else address, "latest", value_wei)


## The full write pipeline. Returns:
##   {ok: true, hash, receipt, block, simulated}
##   {ok: false, stage: "precondition"|"simulate"|"sign"|"receipt", message, revert?}
func send(label: String, to: String, data: String, value_wei: String = "0x0") -> Dictionary:
	if address == "":
		return _fail(label, "precondition", "No wallet connected.")
	if chain_id != Contracts.CHAIN_ID:
		return _fail(label, "precondition", "The wallet is on chain %d; switch it to PulseChain (369)." % chain_id)
	tx_stage.emit(label, "simulate", {})
	var sim := await simulate(to, data, "", value_wei)
	if not sim["ok"]:
		var msg: String = sim["revert"]["message"] if sim.get("kind") == "revert" else String(sim.get("error", {}).get("message", "simulation failed"))
		var out := _fail(label, "simulate", "Simulation says this would fail: " + msg)
		if sim.get("kind") == "revert":
			out["revert"] = sim["revert"]
		return out
	tx_stage.emit(label, "sign", {"simulated": sim["result"]})
	var id: int = bridge.send_raw({"from": address, "to": to, "data": data, "value": value_wei})
	if id < 0:
		return _fail(label, "sign", "The wallet page is not linked; reopen it.")
	# The approval opens from the wallet window; if the game is in front (fullscreen),
	# the wallet's popup would sit hidden behind it. Raise the wallet window now,
	# and again every 12 s while we wait.
	if bridge.has_method("focus_wallet_page"):
		bridge.focus_wallet_page()
	var t0 := Time.get_ticks_msec()
	var next_nudge := 12000
	while not _results.has(id) and Time.get_ticks_msec() - t0 < SIGN_TIMEOUT_S * 1000.0:
		await get_tree().create_timer(0.25).timeout
		if Time.get_ticks_msec() - t0 > next_nudge and bridge.has_method("focus_wallet_page"):
			next_nudge += 12000
			bridge.focus_wallet_page()
	# Signed or refused: bring the game back in front
	DisplayServer.window_move_to_foreground()
	var res: Dictionary = _results.get(id, {"error": "no answer from the wallet within %d s" % int(SIGN_TIMEOUT_S)})
	_results.erase(id)
	if res.has("error"):
		return _fail(label, "sign", String(res["error"]))
	var hash := String(res["hash"])
	tx_stage.emit(label, "pending", {"hash": hash})
	var rec := await wait_receipt(hash)
	if rec.is_empty():
		return _fail(label, "receipt", "Sent (%s) but no receipt within %d s; check the explorer." % [hash, int(RECEIPT_TIMEOUT_S)])
	var block := String(rec.get("blockNumber", "0x0")).hex_to_int()
	if String(rec.get("status", "")) != "0x1":
		return _fail(label, "receipt", "Mined in block %d but reverted (status %s)." % [block, rec.get("status", "?")])
	var ok := {"ok": true, "hash": hash, "receipt": rec, "block": block, "simulated": sim["result"]}
	tx_stage.emit(label, "confirmed", ok)
	return ok


## Polls eth_getTransactionReceipt; {} on timeout.
func wait_receipt(hash: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < RECEIPT_TIMEOUT_S * 1000.0:
		var r := await Chain.rpc.get_receipt(hash)
		if r["ok"] and r["result"] is Dictionary:
			return r["result"]
		await get_tree().create_timer(RECEIPT_POLL_S).timeout
	return {}


func _fail(label: String, stage: String, message: String) -> Dictionary:
	var out := {"ok": false, "stage": stage, "message": message}
	tx_stage.emit(label, "failed", out)
	return out
