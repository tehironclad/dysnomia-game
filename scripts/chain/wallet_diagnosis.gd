class_name WalletDiagnosis
extends RefCounted
## "Test my wallet" (Settings, F2): the payment path checked step by step, so the
## player can see which step fails and why. Reusable (AccessSteps shows the same):
##
##   var steps: Array = await WalletDiagnosis.run({open = true, sign = false, qing = "0x…"})
##   # → [{id, step, ok, why}, …]; ok is true, false, or null (skipped)
##
## Read-only: nothing is sent to the chain. With `open`, the relay is started and the
## wallet window opened if needed; with `sign`, a free personal_sign round trip is
## asked (a popup in the wallet; the signature is checked here by ecrecover).
## Every chain number comes from a read at a named block; a failed read is a ✗ with
## its reason, never a guessed value.

const TICKET_WEI := "1000000000000000001"  # 1 Ⓐ + a 1-wei code, like a fair ticket
const LINK_WAIT_S := 30.0


static func run(opts: Dictionary = {}) -> Array:
	var out: Array = []
	var bridge = Wallet.bridge
	# 1. the local relay
	if not bridge.is_server_running() and bool(opts.get("open", false)):
		Wallet.connect_wallet()
	if bridge.is_server_running():
		_add(out, "relay", "Local wallet relay", true, "listening on %s" % bridge.page_url())
	else:
		_add(out, "relay", "Local wallet relay", false, "not started: press Connect wallet (front door) or click the wallet chip")
	# 2. the wallet window linked
	if bridge.is_server_running() and not bridge.is_linked() and bool(opts.get("open", false)):
		bridge.focus_wallet_page()
		var t0 := Time.get_ticks_msec()
		while not bridge.is_linked() and Time.get_ticks_msec() - t0 < LINK_WAIT_S * 1000.0:
			await Wallet.get_tree().create_timer(0.25).timeout
	var st := {}
	if bridge.is_linked():
		_add(out, "window", "Wallet window linked", true, "opened as %s" % (bridge.browser_used if bridge.browser_used != "" else "?"))
		st = await bridge.query_status()
	elif bridge.is_server_running():
		_add(out, "window", "Wallet window linked", false, "no wallet window is linked (opened as %s). Close any old Dysnomia wallet windows and click the wallet chip." % (bridge.browser_used if bridge.browser_used != "" else "not opened yet"))
	else:
		_add(out, "window", "Wallet window linked", null, "skipped: the relay is not running")
	# 3. a browser wallet in that window
	if st.is_empty():
		_add(out, "provider", "Browser wallet in that window", null, "skipped: no linked window")
	elif not st.get("ok", false):
		_add(out, "provider", "Browser wallet in that window", false, String(st.get("error", "no answer")))
	elif not bool(st.get("hasProvider", false)):
		_add(out, "provider", "Browser wallet in that window", false, "that browser has no wallet extension (the window opened as %s). In Settings set \"Wallet browser\" to the browser where your wallet is (e.g. brave.exe)." % bridge.browser_used)
	else:
		var others: Array = st.get("wallets", [])
		_add(out, "provider", "Browser wallet in that window", true, "%s%s" % [st.get("wallet", "?"), (" (also there: %s)" % ", ".join(PackedStringArray(others))) if others.size() > 1 else ""])
	# 4. the account
	var accounts: Array = st.get("accounts", []) if st.get("ok", false) else []
	var wallet := Wallet.address
	if st.get("ok", false) and bool(st.get("hasProvider", false)):
		if accounts.is_empty():
			var why := "the wallet has not approved this page yet: click Connect wallet in the wallet window and approve"
			if bridge.connect_error != "":
				why += " (last answer: %s)" % bridge.connect_error
			_add(out, "account", "Account connected", false, why)
		elif wallet != "" and String(accounts[0]) != wallet:
			_add(out, "account", "Account connected", false, "the wallet shows %s but the game has %s: switch account in the wallet or reconnect" % [accounts[0], wallet])
		else:
			if wallet == "":
				wallet = String(accounts[0])
			_add(out, "account", "Account connected", true, wallet)
	elif wallet != "":
		_add(out, "account", "Account connected", null, "the game remembers %s, but the wallet window couldn't be asked" % wallet)
	else:
		_add(out, "account", "Account connected", null, "skipped: no wallet in a linked window")
	# 5. the chain
	if st.get("ok", false) and bool(st.get("hasProvider", false)):
		var cid := int(st.get("chainId", 0))
		if cid == Contracts.CHAIN_ID:
			_add(out, "chain", "Wallet on PulseChain (369)", true, "eth_chainId = 0x171")
		else:
			_add(out, "chain", "Wallet on PulseChain (369)", false, "the wallet is on chain %d. Paying asks it to switch; you can also switch to PulseChain in the wallet now." % cid)
	else:
		_add(out, "chain", "Wallet on PulseChain (369)", null, "skipped: no wallet in a linked window")
	if wallet == "":
		for s in [["balance", "Ⓐ in this wallet"], ["gas", "PLS for gas"], ["simulate", "A 1 Ⓐ ticket simulates"]]:
			_add(out, s[0], s[1], null, "skipped: no account")
	else:
		await _chain_checks(out, wallet, String(opts.get("qing", "")))
	# 9. optional: a free signature round trip
	if bool(opts.get("sign", false)):
		if wallet == "" or not bridge.is_linked():
			_add(out, "sign", "Free signature round trip", null, "skipped: needs a linked window and an account")
		else:
			var msg := "Dysnomia wallet test (free, not a transaction)\nwallet: %s\ntime: %d" % [wallet, int(Time.get_unix_time_from_system())]
			var r: Dictionary = await Wallet.sign_message(msg)
			if not r["ok"]:
				_add(out, "sign", "Free signature round trip", false, "stopped at %s: %s" % [Wallet.stage_text(String(r.get("stage", "sign"))), r.get("error", "?")])
			else:
				var who := EthSign.recover_personal(msg, String(r["signature"]))
				if who == wallet:
					_add(out, "sign", "Free signature round trip", true, "the wallet signed and the signature recovers to %s" % who)
				else:
					_add(out, "sign", "Free signature round trip", false, "the signature recovers to %s, not %s" % [who if who != "" else "(invalid)", wallet])
	for s in out:
		print("[Pay] wallet test · %s %s · %s" % ["✓" if s["ok"] == true else ("✗" if s["ok"] == false else "–"), s["step"], s["why"]])
	return out


static func _chain_checks(out: Array, wallet: String, qing: String) -> void:
	var head: Dictionary = await Chain.rpc.block_number()
	if not head["ok"]:
		var why := "the chain could not be read (%s)" % String(head.get("error", {}).get("message", "?"))
		for s in [["balance", "Ⓐ in this wallet"], ["gas", "PLS for gas"], ["simulate", "A 1 Ⓐ ticket simulates"]]:
			_add(out, s[0], s[1], false, why)
		return
	var block: int = head["block"]
	var fee := BigInt.from_decimal(TICKET_WEI)
	var bal: Dictionary = await ArcadePay.read_balance(wallet, block)
	if not bal["ok"]:
		_add(out, "balance", "Ⓐ in this wallet", false, "AFFECTION.balanceOf could not be read at block %d" % block)
	elif BigInt.cmp(bal["balance"], fee) >= 0:
		_add(out, "balance", "Ⓐ in this wallet", true, "%s · AFFECTION.balanceOf · block %d" % [ArcadePay.fmt(bal["balance"]), block])
	else:
		var why := "%s · block %d: a ticket needs 1 Ⓐ in the wallet itself" % [ArcadePay.fmt(bal["balance"]), block]
		var ps = Session.player
		if ps != null and ps.has_lau():
			why += " (Ⓐ on your LAU is moved over with LAU.Withdraw when you pay)"
		_add(out, "balance", "Ⓐ in this wallet", false, why)
	if qing == "":
		qing = _default_qing()
	if qing == "":
		_add(out, "gas", "PLS for gas", null, "skipped: no territory known yet")
		_add(out, "simulate", "A 1 Ⓐ ticket simulates", null, "skipped: no territory known yet")
		return
	var data := Abi.encode_call("transfer(address,uint256)", [qing, TICKET_WEI])
	var gas: Dictionary = await Chain.rpc.estimate_gas(wallet, Contracts.AFFECTION, data)
	var price: Dictionary = await Chain.rpc.gas_price()
	var pls: Dictionary = await Chain.rpc.request("eth_getBalance", [wallet, Rpc.block_param(block)])
	if not pls["ok"] or not price["ok"]:
		_add(out, "gas", "PLS for gas", false, "eth_getBalance / eth_gasPrice could not be read at block %d" % block)
	else:
		var have := BigInt.from_hex(String(pls["result"]))
		var units: int = gas["gas"] if gas["ok"] else 100000
		var need := BigInt.mul(price["wei"], BigInt.from_int(units))
		var line := "%s PLS; a ticket's gas ≈ %s PLS (%d gas%s) · block %d" % [TokenFormat.wei_to_tokens(have), TokenFormat.wei_to_tokens(need), units, "" if gas["ok"] else ", assumed", block]
		_add(out, "gas", "PLS for gas", BigInt.cmp(have, need) >= 0, line)
	var sim: Dictionary = await Chain.rpc.eth_call(Contracts.AFFECTION, data, wallet, block)
	var what := "AFFECTION.transfer(%s, 1 Ⓐ + 1 wei) from %s at block %d" % [_short(qing), _short(wallet), block]
	if sim["ok"]:
		_add(out, "simulate", "A 1 Ⓐ ticket simulates", true, what + ": would succeed")
	elif sim.get("kind") == "revert":
		_add(out, "simulate", "A 1 Ⓐ ticket simulates", false, what + ": reverts — " + String(sim["revert"]["message"]))
	else:
		_add(out, "simulate", "A 1 Ⓐ ticket simulates", false, what + ": could not run (%s)" % String(sim.get("error", {}).get("message", "?")))


static func _short(a: String) -> String:
	return "%s…%s" % [a.left(6), a.right(4)] if a.length() > 12 else a


## The territory the player stands in, else the first known one (a real QING either way).
static func _default_qing() -> String:
	var scene := Wallet.get_tree().current_scene
	if scene != null:
		var t = scene.get("territory")
		if t is Dictionary and String(t.get("address", "")) != "":
			return String(t["address"]).to_lower()
		var q = scene.get("qing")
		if q is String and q != "":
			return q.to_lower()
	var all: Array = Registry.all()
	return String(all[0]["address"]).to_lower() if not all.is_empty() else ""


static func _add(out: Array, id: String, step: String, ok, why: String) -> void:
	out.append({"id": id, "step": step, "ok": ok, "why": why})


## Pure: one line per step ("✓ step — why"), for the console and the panel.
static func lines(steps: Array) -> PackedStringArray:
	var l: PackedStringArray = []
	for s in steps:
		l.append("%s %s — %s" % ["✓" if s.get("ok") == true else ("✗" if s.get("ok") == false else "–"), s.get("step", "?"), s.get("why", "")])
	return l


## Pure: the first failed step ({} when none failed).
static func first_failure(steps: Array) -> Dictionary:
	for s in steps:
		if s.get("ok") == false:
			return s
	return {}
