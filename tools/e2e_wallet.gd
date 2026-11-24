extends SceneTree
## The Godot half of the wallet end-to-end harness (run it with tools/e2e_wallet.sh).
## The real Wallet autoload and WalletBridge serve the real wallet.html; Chromium
## (Playwright, tools/e2e_wallet.js) opens it with a mock EIP-1193 wallet. This
## script drives the game's real payment code and writes what came back:
##
##   godot --headless --path . -s res://tools/e2e_wallet.gd -- --port=N --ctl=<dir>
##       --wallet=0x… --qing=0x… --hash=0x…
##
## <dir> is the hand-off with the JS side: this writes ready, open_c, done
## (results.json); the JS writes go when its windows are set up.
## Chain reads are real (rpc.pulsechain.com): simulations, the receipt of --hash, balances.
## Nothing is broadcast: the mock wallet answers eth_sendTransaction with --hash, a real
## past AFFECTION transfer from --wallet to --qing, so wait_receipt and verify_receipt
## run against a real receipt.

var _ctl := ""
var _results: Array = []
var _W
var _AP
var _wallet := ""


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def


func _signal(name: String, text: String = "") -> void:
	var f := FileAccess.open(_ctl.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wait_file(name: String, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not FileAccess.file_exists(_ctl.path_join(name)):
		if Time.get_ticks_msec() - t0 > timeout_s * 1000.0:
			return false
		await create_timer(0.1).timeout
	return true


func _wait(cond: Callable, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout_s * 1000.0:
			return false
		await create_timer(0.1).timeout
	return true


func _record(name: String, ok: bool, detail: Dictionary) -> void:
	detail["name"] = name
	detail["ok"] = ok
	_results.append(detail)
	print("[E2E] %s %s %s" % ["PASS" if ok else "FAIL", name, JSON.stringify(detail)])


static func _plain(d: Dictionary) -> Dictionary:
	# JSON-safe: BigInts (PackedInt64Array) as decimal strings, no receipts
	var o := {}
	for k in d:
		var v = d[k]
		if v is PackedInt64Array:
			o[k] = BigInt.to_decimal(v)
		elif k == "receipt" or k == "simulated":
			continue
		elif v is Dictionary or v is Array or v is String or v is int or v is float or v is bool or v == null:
			o[k] = v
		else:
			o[k] = str(v)
	return o


func _run() -> void:
	_ctl = _arg("ctl")
	var port := int(_arg("port", "48420"))
	_wallet = _arg("wallet").to_lower()
	var qing := _arg("qing").to_lower()
	var hash := _arg("hash").to_lower()
	_W = root.get_node("Wallet")
	_AP = load("res://scripts/games/arcade_pay.gd")
	var bridge = _W.bridge
	bridge.launch_browser = false
	if not bridge.start_server(port):
		_finish("could not start the bridge")
		return
	bridge.open_wallet_page()  # not launched: the JS side opens the pages
	_signal("ready", str(bridge.get_port()))

	# 1. The connect handshake (a stale page reloads, a second window is turned away)
	var linked: bool = await _wait(func(): return _W.address != "", 60.0)
	_record("connect", linked and _W.address == _wallet, {"address": _W.address, "chain": _W.chain_id, "browser_used": bridge.browser_used})
	if not await _wait_file("go", 60.0):
		_finish("the JS side never said go")
		return
	_record("one window linked", bridge.is_linked(), {"page_info": bridge.page_info})

	# 2. A fair ticket: 1 Ⓐ + the game's code in the last wei. The wallet connected on
	#    chain 1 (it refused the first switch): Wallet.send asks it to switch again.
	var FP = load("res://scripts/world/funfair/fair_progress.gd")
	var fee: String = FP.fee_wei("regolith")
	var chain_before: int = _W.chain_id
	var r: Dictionary = await _AP.transfer_to_qing(qing, "E2E fair ticket", fee)
	_record("fair ticket", r.get("ok", false) and String(r.get("hash", "")) == hash, _plain(r).merged({"fee_wei": fee, "chain_before": chain_before, "chain_after": _W.chain_id}))

	# 3. An arcade credit (ArcadePay.pay: transfer, verify, local credit). The local
	#    ledger is put back afterwards (the hash is a past transfer, not a new play).
	var ledger := ConfigFile.new()
	var had_ledger := ledger.load(_AP.LEDGER) == OK
	if had_ledger and ledger.has_section_key("credits", "%s@%s" % [_wallet, qing]):
		var trimmed := ConfigFile.new()
		trimmed.load(_AP.LEDGER)
		trimmed.erase_section_key("credits", "%s@%s" % [_wallet, qing])
		trimmed.save(_AP.LEDGER)
	var credits_before: int = _AP.credits(_wallet, qing)
	r = await _AP.pay(qing, "E2E arcade")
	var credits_after: int = _AP.credits(_wallet, qing)
	if had_ledger:
		ledger.save(_AP.LEDGER)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_AP.LEDGER))
	_record("arcade credit", r.get("ok", false) and credits_after == credits_before + 1, _plain(r).merged({"credits_before": credits_before, "credits_after": credits_after}))

	# 4. personal_sign round trip (the mock signs with a fixed signature: bytes compared on the JS side)
	var msg := "Dysnomia e2e sign-in\nnonce: 42 · ünïcödé ✓"
	var s: Dictionary = await _W.sign_message(msg)
	_record("personal_sign", s.get("ok", false), {"message": msg, "signature": s.get("signature", ""), "error": s.get("error", "")})

	# 5. Rejected in the wallet (the mock answers 4001): stage sign, plain words
	r = await _AP.transfer_to_qing(qing, "E2E rejected ticket", fee)
	_record("rejection", not r.get("ok", true) and r.get("stage", "") == "sign" and String(r.get("message", "")).contains("rejected"), _plain(r))

	# 6. The link drops while the wallet is open (the mock answers after 3 s; the socket
	#    is closed at 1 s): the page relinks and re-sends the hash; the address stays.
	var drop_state := {"kept": false, "dropped": false}
	var drop := func(label: String, stage: String, _i: Dictionary) -> void:
		if label != "E2E ticket across a dropped link" or stage != "sign" or drop_state["dropped"]:
			return
		drop_state["dropped"] = true
		await create_timer(1.0).timeout
		if bridge._ws_peer:
			bridge._ws_peer.close()
		await create_timer(0.5).timeout
		drop_state["kept"] = _W.address == _wallet and not bridge.is_linked()
	_W.tx_stage.connect(drop)
	r = await _AP.transfer_to_qing(qing, "E2E ticket across a dropped link", fee)
	_W.tx_stage.disconnect(drop)
	_record("link drop during signing", r.get("ok", false) and drop_state["dropped"] and drop_state["kept"], _plain(r).merged({"dropped": drop_state["dropped"], "address_kept_while_unlinked": drop_state["kept"]}))

	# 7. A simulation revert: nothing reaches the wallet, the revert is named
	var big := Abi.encode_call("transfer(address,uint256)", [qing, "1000000000000000000000000000000"])
	r = await _W.send("E2E too-large transfer", Contracts.AFFECTION, big)
	_record("simulation revert", not r.get("ok", true) and r.get("stage", "") == "simulate" and r.has("revert"), _plain(r))

	# 8. The wallet test (read-only checks)
	var steps: Array = await load("res://scripts/chain/wallet_diagnosis.gd").run({"qing": qing})
	var all_ok := true
	for st in steps:
		if st["ok"] != true:
			all_ok = false
	_record("wallet test", all_ok, {"steps": steps})

	# 9. A scene change keeps the wallet
	var n := Node.new()
	n.name = "E2EScene"
	change_scene_to_node(n)
	await process_frame
	await process_frame
	_record("address after a scene change", _W.address == _wallet and _W.is_linked(), {"address": _W.address})

	# 10. The wallet window is closed; a payment reopens it and waits for the link
	_signal("close_a")
	var gone: bool = await _wait(func(): return not bridge.is_linked(), 20.0)
	_signal("open_c")
	r = await _AP.transfer_to_qing(qing, "E2E ticket after the window was closed", fee)
	_record("window closed, reopened by the payment", gone and r.get("ok", false), _plain(r))

	_finish("")


func _finish(error: String) -> void:
	var f := FileAccess.open(_ctl.path_join("results.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"error": error, "results": _results}, "  "))
	f.close()
	_signal("done")
	var failed := error != ""
	for x in _results:
		if not x["ok"]:
			failed = true
	print("[E2E] done: %s" % ("FAILED " + error if failed else "all passed"))
	quit(1 if failed else 0)
