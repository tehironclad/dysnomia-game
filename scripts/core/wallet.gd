extends Node
## Autoload "Wallet" (WP 4.1): the browser wallet, through the local relay page
## (assets/web/wallet.html, authenticated by a session token).
##
## Every write goes through send():
##   1. precondition: a wallet account, on chain 369 (the page is asked to switch);
##   2. simulate: eth_call from the wallet; a revert is decoded and returned;
##   3. link: the wallet window is linked (reopened and waited for if it was closed);
##   4. sign: the window is raised first, then the page relays {from,to,data,value}
##      to the browser wallet; the answer (hash or refusal) comes back by request id;
##   5. verify: the receipt is read from the chain here (never trusted from the
##      page), and must be from this wallet, to the contract asked for, with status
##      0x1; and the transaction itself (eth_getTransactionByHash) must carry exactly
##      the call data and value the game asked for (a wallet, extension or page that
##      altered it is caught and named, never reported as success);
##   6. the caller re-reads state.
## Refused before anything reaches the wallet: an approve / increaseAllowance above
## 2^128 (unlimited in all but name: the game approves exact amounts only) and any
## setApprovalForAll. sign_message signs only the game's own texts (SIGN_PREFIXES).
## Nothing reports success before step 5. Every failure is printed with [Pay] and
## emitted as tx_stage(label, "failed", {stage, message}) (WalletChip shows it).
## Tested end to end by tools/e2e_wallet.sh.

signal connected(address: String)
signal disconnected
signal tx_stage(label: String, stage: String, info: Dictionary)
## Anything the wallet chip shows changed (link, account, chain, page info).
signal status_changed

const SIGN_TIMEOUT_S := 300.0
const RECEIPT_TIMEOUT_S := 360.0
const RECEIPT_POLL_S := 4.0
## How long a request waits for the wallet window to (re)link before giving up.
const LINK_WAIT_S := 45.0
## A request whose window stays unlinked this long while waiting for the answer fails.
const LINK_LOST_S := 90.0
## How long send() waits for the wallet to switch to 369 after asking.
const CHAIN_WAIT_S := 60.0
## An approval above 2^APPROVE_MAX_BITS is "unlimited" in all but name: never sent.
const APPROVE_MAX_BITS := 128
const SEL_APPROVE := "0x095ea7b3"
const SEL_INCREASE_ALLOWANCE := "0x39509351"
const SEL_SET_APPROVAL_FOR_ALL := "0xa22cb465"
## The only texts sign_message signs: the game server's sign-in and the wallet test.
## Anything else (a login challenge for another site, an order, a permit) is refused
## before the wallet sees it, whoever asked for it.
const SIGN_PREFIXES := ["Dysnomia game server sign-in\n", "Dysnomia game server login\n", "Dysnomia wallet test (free, not a transaction)\n"]
const SIGN_MAX_CHARS := 600

var address := ""
var chain_id := 0
var bridge: Node
var _results := {}  # request id → {hash} | {error}
var _sigs := {}     # personal_sign request id → {signature} | {error}
## The last failure ({label, stage, message, at}) for the chip and the wallet test.
var last_failure := {}


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
	bridge.chain_changed.connect(func(cid):
		chain_id = cid
		status_changed.emit())
	bridge.link_changed.connect(func(_l): status_changed.emit())
	bridge.page_info_changed.connect(func(_i): status_changed.emit())
	bridge.connect_failed.connect(func(_e): status_changed.emit())
	bridge.tx_result.connect(func(id, hash): _results[id] = {"hash": hash})
	bridge.tx_failed.connect(func(id, err): _results[id] = {"error": err})
	bridge.sign_result.connect(func(id, sig): _sigs[id] = {"signature": sig})
	bridge.sign_failed.connect(func(id, err): _sigs[id] = {"error": err})
	# The HUD chip: wallet state + the last payment failure, in every scene (not headless).
	if DisplayServer.get_name() != "headless":
		var chip = load("res://scripts/ui/wallet_chip.gd").new()
		chip.name = "WalletChip"
		add_child(chip)


func is_connected_to_chain() -> bool:
	return address != "" and chain_id == Contracts.CHAIN_ID


## The wallet window is linked to the game right now.
func is_linked() -> bool:
	return bridge != null and bridge.is_linked()


## Starts the local relay and opens the wallet window (or raises the linked one).
func connect_wallet() -> bool:
	if bridge.is_server_running():
		if bridge.is_linked():
			bridge.request_accounts()
			bridge.reopen_wallet_page()
		else:
			bridge.open_wallet_page(true)
		status_changed.emit()
		return true
	if bridge.start_server(Config.wallet_bridge_port):
		bridge.open_wallet_page()
		status_changed.emit()
		return true
	return false


func disconnect_wallet() -> void:
	bridge.stop_server()
	_on_disconnected()


func _on_connected(addr: String, cid: int) -> void:
	addr = addr.to_lower()
	chain_id = cid
	if addr != address:
		address = addr
		print("[Pay] wallet %s connected (chain %d)" % [address, cid])
		connected.emit(address)
	status_changed.emit()


func _on_disconnected() -> void:
	var had := address != ""
	address = ""
	chain_id = 0
	if had:
		disconnected.emit()
	status_changed.emit()


## personal_sign of `message` by the connected wallet (free; not a transaction).
## {ok: true, signature} | {ok: false, stage, error}. Used for the game server's sign-in
## and the wallet test.
func sign_message(message: String) -> Dictionary:
	if address == "":
		return {"ok": false, "stage": "precondition", "error": "No wallet connected."}
	var refusal := sign_refusal(message)
	if refusal != "":
		print("[Pay] signature refused before the wallet: %s" % refusal)
		return {"ok": false, "stage": "precondition", "error": refusal}
	var linked := await _ensure_link("Free signature")
	if not linked["ok"]:
		return {"ok": false, "stage": "link", "error": linked["message"]}
	bridge.focus_wallet_page()
	var id: int = bridge.personal_sign(message, OS.get_name() == "Windows")
	if id < 0:
		return {"ok": false, "stage": "link", "error": "The wallet window is not linked; reopen it."}
	var waited := await _await_answer(_sigs, id)
	DisplayServer.window_move_to_foreground()
	var r: Dictionary = _sigs.get(id, {"error": waited})
	_sigs.erase(id)
	if r.has("error"):
		print("[Pay] signature refused: %s" % r["error"])
		return {"ok": false, "stage": "sign", "error": String(r["error"])}
	return {"ok": true, "signature": String(r["signature"])}


## eth_call from the connected wallet (or `from`), with `value_wei` for payable
## calls. {ok, result} or the Rpc failure.
func simulate(to: String, data: String, from: String = "", value_wei: String = "") -> Dictionary:
	return await Chain.rpc.eth_call(to, data, from if from != "" else address, "latest", value_wei)


## The full write pipeline. Returns:
##   {ok: true, hash, receipt, block, simulated}
##   {ok: false, stage: "precondition"|"chain"|"simulate"|"link"|"sign"|"receipt", message, revert?}
func send(label: String, to: String, data: String, value_wei: String = "0x0") -> Dictionary:
	var value := quantity(value_wei)
	if value == "":
		return _fail(label, "precondition", "Bad amount %s (the game's bug, not yours)." % value_wei)
	var refusal := call_refusal(data)
	if refusal != "":
		return _fail(label, "precondition", "Refused before your wallet saw it: %s (the game's bug, not yours)." % refusal)
	if address == "":
		if is_linked():
			return _fail(label, "precondition", "The wallet window is open but no account is connected: approve the connection in your wallet (or click the wallet chip).")
		return _fail(label, "precondition", "No wallet connected: use Connect wallet (front door) or click the wallet chip.")
	var from := address
	_log(label, "start", "to %s · value %s · data %s…" % [to, value, data.left(10)])
	if chain_id != Contracts.CHAIN_ID:
		tx_stage.emit(label, "chain", {})
		var sw := await _ensure_chain()
		if not sw["ok"]:
			return _fail(label, "chain", sw["message"])
	tx_stage.emit(label, "simulate", {})
	var sim := await simulate(to, data, from, value)
	if not sim["ok"]:
		var out: Dictionary
		if sim.get("kind") == "revert":
			out = _fail(label, "simulate", "The chain says this would fail, so nothing was sent: " + String(sim["revert"]["message"]))
			out["revert"] = sim["revert"]
		else:
			out = _fail(label, "simulate", "Could not check it on the chain first (%s); nothing was sent." % String(sim.get("error", {}).get("message", "no answer")))
		return out
	_log(label, "simulate", "ok")
	var linked := await _ensure_link(label)
	if not linked["ok"]:
		return _fail(label, "link", linked["message"])
	tx_stage.emit(label, "sign", {"simulated": sim["result"]})
	# Raise the wallet window FIRST: its approval popup must open in front of it,
	# not under a window raised later. The page waits (≤ 4 s) for the focus.
	bridge.focus_wallet_page()
	var tx := {"from": from, "to": to.to_lower(), "data": data, "value": value}
	var id: int = bridge.send_raw(tx, OS.get_name() == "Windows", label, call_summary(to, data, value))
	if id < 0:
		return _fail(label, "link", "The wallet window is not linked; click the wallet chip to reopen it.")
	_log(label, "sign", "request #%d sent to the wallet window; waiting for the wallet" % id)
	var waited := await _await_answer(_results, id)
	# Signed or refused: bring the game back in front
	DisplayServer.window_move_to_foreground()
	var res: Dictionary = _results.get(id, {"error": waited})
	_results.erase(id)
	if res.has("error"):
		return _fail(label, "sign", String(res["error"]))
	var hash := String(res["hash"]).to_lower()
	if not is_tx_hash(hash):
		return _fail(label, "sign", "The wallet answered without a transaction hash (%s)." % hash.left(80))
	_log(label, "pending", hash)
	tx_stage.emit(label, "pending", {"hash": hash})
	var rec := await wait_receipt(hash)
	if rec.is_empty():
		return _fail(label, "receipt", "Sent (%s) but no receipt within %d s; check the explorer." % [hash, int(RECEIPT_TIMEOUT_S)])
	var block := String(rec.get("blockNumber", "0x0")).hex_to_int()
	if String(rec.get("from", "")).to_lower() != from:
		return _fail(label, "receipt", "Transaction %s is from %s, not this wallet %s." % [hash, rec.get("from", "?"), from])
	var want := {"from": from, "to": tx["to"], "data": data, "value": value}
	var sent := await read_transaction(hash)
	if sent.is_empty():
		return _fail(label, "verify", "Mined in block %d (%s), but the transaction could not be read back to check it is the one asked for: —. Check it on the explorer." % [block, hash])
	var differs := tx_mismatch(sent, want)
	if differs == "" and String(rec.get("to", "")).to_lower() != want["to"]:
		differs = "its receipt says it went to %s, not %s" % [String(rec.get("to", "")).to_lower(), want["to"]]
	if differs != "":
		push_error("[Pay] %s: transaction %s is not the one the game asked for: %s" % [label, hash, differs])
		return _fail(label, "verify", "Transaction %s is NOT the one the game asked you to sign: %s. Something between the game and the chain changed it (an extension? the wallet page?). Check your wallet's activity, and don't sign again until you know why." % [hash, differs])
	if String(rec.get("status", "")) != "0x1":
		return _fail(label, "receipt", "Mined in block %d but reverted (status %s)." % [block, rec.get("status", "?")])
	var ok := {"ok": true, "hash": hash, "receipt": rec, "block": block, "simulated": sim["result"]}
	_log(label, "confirmed", "block %d · %s" % [block, hash])
	tx_stage.emit(label, "confirmed", ok)
	return ok


## Waits for request `id`'s answer in `box` (SIGN_TIMEOUT_S). Raises the wallet window
## again only while the GAME has the focus (the player came back without answering):
## raising it while they are in the wallet's popup would cover that popup.
## Returns "" when answered, else why not.
func _await_answer(box: Dictionary, id: int) -> String:
	var t0 := Time.get_ticks_msec()
	var next_nudge := t0 + 15000
	var unlinked_since := -1
	while not box.has(id):
		var now := Time.get_ticks_msec()
		if now - t0 > SIGN_TIMEOUT_S * 1000.0:
			return "no answer from the wallet within %d s (the request may still be open in your wallet)" % int(SIGN_TIMEOUT_S)
		if is_linked():
			unlinked_since = -1
		elif unlinked_since < 0:
			unlinked_since = now
		elif now - unlinked_since > LINK_LOST_S * 1000.0:
			return "the wallet window closed before answering; if you approved, check your wallet's activity before trying again"
		if now > next_nudge and DisplayServer.window_is_focused():
			next_nudge = now + 15000
			bridge.focus_wallet_page()
		await get_tree().create_timer(0.25).timeout
	return ""


## The wallet window linked, reopening it if needed. {ok} | {ok:false, message}.
func _ensure_link(label: String) -> Dictionary:
	if is_linked():
		return {"ok": true}
	if not bridge.is_server_running() and not bridge.start_server(Config.wallet_bridge_port):
		return {"ok": false, "message": "The local wallet relay could not start (ports %d+ busy?)." % Config.wallet_bridge_port}
	tx_stage.emit(label, "link", {})
	_log(label, "link", "the wallet window is not linked; opening it")
	bridge.focus_wallet_page()
	var t0 := Time.get_ticks_msec()
	while not is_linked() and Time.get_ticks_msec() - t0 < LINK_WAIT_S * 1000.0:
		await get_tree().create_timer(0.25).timeout
	if not is_linked():
		return {"ok": false, "message": "The wallet window did not link within %d s. Is it open (%s)? Click the wallet chip to reopen it." % [int(LINK_WAIT_S), bridge.browser_used]}
	# Its account must be the one this request is for
	var t1 := Time.get_ticks_msec()
	while bridge.get_wallet_address() == "" and Time.get_ticks_msec() - t1 < 15000:
		await get_tree().create_timer(0.25).timeout
	if bridge.get_wallet_address() != address:
		return {"ok": false, "message": "The wallet window is on account %s, not %s." % [bridge.get_wallet_address() if bridge.get_wallet_address() != "" else "(none)", address]}
	return {"ok": true}


## Chain 369, asking the page to switch the wallet. {ok} | {ok:false, message}.
func _ensure_chain() -> Dictionary:
	if chain_id == Contracts.CHAIN_ID:
		return {"ok": true}
	if not is_linked() or not bridge.request_switch_chain():
		return {"ok": false, "message": "The wallet is on chain %d; switch it to PulseChain (369)." % chain_id}
	print("[Pay] the wallet is on chain %d: asked it to switch to PulseChain (369)" % chain_id)
	bridge.focus_wallet_page()
	var t0 := Time.get_ticks_msec()
	while chain_id != Contracts.CHAIN_ID and Time.get_ticks_msec() - t0 < CHAIN_WAIT_S * 1000.0:
		await get_tree().create_timer(0.25).timeout
	DisplayServer.window_move_to_foreground()
	if chain_id != Contracts.CHAIN_ID:
		return {"ok": false, "message": "The wallet is still on chain %d; switch it to PulseChain (369) and try again." % chain_id}
	return {"ok": true}


## eth_getTransactionByHash, a few tries (a node can serve the receipt a moment
## before the transaction). {} if it can't be read.
func read_transaction(hash: String) -> Dictionary:
	for i in 4:
		var r: Dictionary = await Chain.rpc.request("eth_getTransactionByHash", [hash])
		if r["ok"] and r["result"] is Dictionary:
			return r["result"]
		await get_tree().create_timer(2.0).timeout
	return {}


## Pure: "" when the mined transaction `sent` (eth_getTransactionByHash) is exactly
## `want` ({from, to, data, value} as asked); else what differs, in words.
static func tx_mismatch(sent: Dictionary, want: Dictionary) -> String:
	var out: PackedStringArray = []
	var f := String(sent.get("from", "")).to_lower()
	var t := String(sent.get("to", "")).to_lower()
	var input := String(sent.get("input", sent.get("data", ""))).to_lower()
	var v := quantity(String(sent.get("value", "0x0")))
	if f != String(want["from"]).to_lower():
		out.append("it was sent from %s, not %s" % [f, want["from"]])
	if t != String(want["to"]).to_lower():
		out.append("it went to %s, not %s" % [t if t != "" else "(contract creation)", String(want["to"]).to_lower()])
	if input != String(want["data"]).to_lower():
		out.append("its call is %s…, not %s…" % [input.left(10), String(want["data"]).to_lower().left(10)] if input.left(10) != String(want["data"]).to_lower().left(10)
			else "its call's arguments differ from the ones asked for")
	if v != quantity(String(want["value"])):
		out.append("its value is %s wei, not %s" % [BigInt.to_decimal(BigInt.from_hex(v)) if v != "" else "?", BigInt.to_decimal(BigInt.from_hex(quantity(String(want["value"]))))])
	return "; ".join(out)


## Pure: "" when calldata `data` may go to the wallet; else why not. No unlimited
## approvals (approve / increaseAllowance above 2^APPROVE_MAX_BITS), no setApprovalForAll.
static func call_refusal(data: String) -> String:
	var d := data.strip_edges().to_lower()
	var sel := d.left(10)
	if sel == SEL_SET_APPROVAL_FOR_ALL:
		return "setApprovalForAll (it would hand over a whole collection) is never asked for"
	if sel == SEL_APPROVE or sel == SEL_INCREASE_ALLOWANCE:
		if d.length() < 10 + 128 or not d.substr(10, 128).is_valid_hex_number():
			return "a malformed approval"
		var amount := BigInt.from_hex("0x" + d.substr(74, 64))
		if BigInt.bit_length(amount) > APPROVE_MAX_BITS:
			return "an unlimited approval (%s wei) was asked for; the game only approves the exact amount it is about to spend" % BigInt.to_decimal(amount)
	return ""


## Pure: "" when `message` is one of the game's own texts (SIGN_PREFIXES, at most
## SIGN_MAX_CHARS); else why it is refused.
static func sign_refusal(message: String) -> String:
	if message.length() > SIGN_MAX_CHARS:
		return "the text to sign is too long (%d characters)" % message.length()
	for p in SIGN_PREFIXES:
		if message.begins_with(p):
			return ""
	return "the game only signs its own sign-in and wallet-test texts, not \"%s\"" % message.left(60).replace("\n", " ")


static var _names := {}

## Pure: the call in words for the wallet page ("AFFECTION.transfer(address,uint256)
## to 0x299c…35eb, 1000000000000000003 wei"). Unknown contracts and selectors say so.
static func call_summary(to: String, data: String, value: String = "0x0") -> String:
	if _names.is_empty():
		var consts: Dictionary = load("res://scripts/chain/contracts.gd").get_script_constant_map()
		for k in consts:
			var v = consts[k]
			if v is String and String(v).length() == 42 and String(v).begins_with("0x"):
				_names[String(v).to_lower()] = String(k)
	var d := data.to_lower()
	var sel := d.left(10)
	var fn := ""
	for sig in Contracts.SELECTORS:
		if Contracts.SELECTORS[sig] == sel:
			fn = sig
			break
	if fn == "" and sel == SEL_INCREASE_ALLOWANCE:
		fn = "increaseAllowance(address,uint256)"
	var who: String = _names.get(to.to_lower(), "contract %s" % to.to_lower())
	var out := "%s.%s" % [who, fn if fn != "" else "call %s" % sel]
	if fn in ["transfer(address,uint256)", "approve(address,uint256)"] and d.length() >= 138:
		var arg := "0x" + d.substr(34, 40)
		var amt := BigInt.from_hex("0x" + d.substr(74, 64))
		out += " %s %s, %s wei" % ["to" if fn.begins_with("transfer") else "for spender", arg, BigInt.to_decimal(amt)]
	if value != "" and value != "0x0":
		out += " · paying %s wei of PLS" % BigInt.to_decimal(BigInt.from_hex(value))
	return out


## Polls eth_getTransactionReceipt; {} on timeout.
func wait_receipt(hash: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < RECEIPT_TIMEOUT_S * 1000.0:
		var r := await Chain.rpc.get_receipt(hash)
		if r["ok"] and r["result"] is Dictionary:
			return r["result"]
		await get_tree().create_timer(RECEIPT_POLL_S).timeout
	return {}


## A failure found outside send() (ArcadePay's funds and receipt checks): printed
## and shown like every other payment failure.
func report_failure(label: String, stage: String, message: String) -> Dictionary:
	return _fail(label, stage, message)


func _fail(label: String, stage: String, message: String) -> Dictionary:
	var out := {"ok": false, "stage": stage, "message": message}
	last_failure = {"label": label, "stage": stage, "message": message, "at": Time.get_unix_time_from_system()}
	push_warning("[Pay] %s · stopped at %s: %s" % [label, stage, message])
	print("[Pay] %s · STOPPED at %s (%s): %s" % [label, stage, stage_text(stage), message])
	tx_stage.emit(label, "failed", out)
	return out


func _log(label: String, stage: String, what: String) -> void:
	print("[Pay] %s · %s · %s" % [label, stage, what])


## Plain words for a pipeline stage (what the player was waiting for).
static func stage_text(stage: String) -> String:
	var base := stage.get_slice(" · ", stage.get_slice_count(" · ") - 1) if stage.contains(" · ") else stage
	var words := {
		"precondition": "before starting",
		"chain": "switching the wallet to PulseChain",
		"funds": "checking your Ⓐ",
		"simulate": "the chain check (nothing was sent)",
		"link": "the wallet window",
		"sign": "your wallet's approval",
		"receipt": "the chain receipt",
		"verify": "checking the payment on the chain",
	}
	var t: String = words.get(base, base)
	return ("moving Ⓐ from your LAU: " + t) if stage.begins_with("funds · ") else t


## Pure: a JSON-RPC QUANTITY ("0x" + hex, no leading zeros) from "0x…" or a decimal
## string; "" if malformed. Never through a float.
static func quantity(v: String) -> String:
	var s := v.strip_edges()
	if s == "":
		return "0x0"
	if s.to_lower().begins_with("0x"):
		var h := s.substr(2)
		if h == "":
			return "0x0"
		if not h.is_valid_hex_number():
			return ""
		return "0x" + BigInt.to_hex(BigInt.from_hex(s))
	for c in s:
		if c < "0" or c > "9":
			return ""
	return "0x" + BigInt.to_hex(BigInt.from_decimal(s))


## Pure: "0x" + 64 hex digits.
static func is_tx_hash(h: String) -> bool:
	return h.length() == 66 and h.begins_with("0x") and h.substr(2).is_valid_hex_number()
