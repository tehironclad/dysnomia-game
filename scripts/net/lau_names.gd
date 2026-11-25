class_name LauNames
extends Node
## The chain's names for other players' wallets (read-only), for name tags, free
## chat and the activity feed: CHO.GetUserTokenAddress(wallet) → LAU.Username(),
## name(), symbol(). Wallets asked for within a frame are read together (two
## Multicall3 rounds pinned to one block, never a JSON-RPC batch) and cached
## (LauNames.TTL_OK_S; a failed read is retried after TTL_FAIL_S). NetNames
## decides what to show from a record. A child of the Net autoload (Net.names).
##
##   record(wallet) -> {state: "ok"|"none"|"failed"|"reading", username, lau_name, lau_symbol, lau, head, block}
##   display(wallet) -> the name to show (NetNames.shown)
##   refresh(wallet)  -> re-read now (a player switched LAU: their profile changed)
##   signal resolved(wallet)

signal resolved(wallet: String)

const TTL_OK_S := 600.0
const TTL_FAIL_S := 60.0
const REFRESH_MIN_S := 15.0   ## a forced re-read of one wallet at most this often
const BATCH := 40
const ZERO := "0x0000000000000000000000000000000000000000"

var _cache := {}      # wallet → record (+ "at": s)
var _queue := {}      # wallet → true
var _busy := false
var _forced_at := {}  # wallet → s
## Debug builds only (--net-lau-of=<test wallet>=<real wallet>, screenshots): read the
## real wallet's LAU for a throwaway test wallet. Its names are marked "(test)".
var test_alias := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-lau-of="):
			if not OS.is_debug_build():
				push_warning("[Net] --net-lau-of is ignored outside debug builds.")
				continue
			var kv := a.substr(13).split("=")
			if kv.size() == 2 and NetProto.clean_wallet(kv[0]) != "" and NetProto.clean_wallet(kv[1]) != "":
				test_alias[kv[0].to_lower()] = kv[1].to_lower()
				print("[Net] TEST MODE (--net-lau-of): %s is shown with %s's LAU name, marked (test)." % [kv[0], kv[1]])


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The cached record for `wallet` ({} or {state: "reading"} until read); asks for a
## read when there is none or it is stale.
func record(wallet: String) -> Dictionary:
	wallet = NetProto.clean_wallet(wallet)
	if wallet == "":
		return {}
	var r: Dictionary = _cache.get(wallet, {})
	var ttl := TTL_OK_S if String(r.get("state", "")) in ["ok", "none"] else TTL_FAIL_S
	if r.is_empty() or (String(r.get("state", "")) != "reading" and _now() - float(r.get("at", 0.0)) > ttl):
		_ask(wallet)
	return _cache.get(wallet, {})


func display(wallet: String) -> String:
	return NetNames.shown(wallet, record(wallet))


## Re-read now (rate-limited per wallet): their profile changed (a LAU switch).
func refresh(wallet: String) -> void:
	wallet = NetProto.clean_wallet(wallet)
	if wallet == "" or _now() - float(_forced_at.get(wallet, -1000.0)) < REFRESH_MIN_S:
		return
	_forced_at[wallet] = _now()
	_ask(wallet)


## Tests and tools: a record put in by hand (never by the game itself).
func put(wallet: String, rec: Dictionary) -> void:
	rec = rec.duplicate()
	rec["at"] = _now()
	_cache[wallet.to_lower()] = rec
	resolved.emit(wallet.to_lower())


func _ask(wallet: String) -> void:
	if not _cache.has(wallet):
		_cache[wallet] = {"state": "reading", "at": _now()}
	_queue[wallet] = true
	if not _busy:
		_pump.call_deferred()


func _pump() -> void:
	if _busy:
		return
	_busy = true
	while not _queue.is_empty():
		var batch: Array = _queue.keys().slice(0, BATCH)
		for w in batch:
			_queue.erase(w)
		await _read(batch)
	_busy = false


func _read(wallets: Array) -> void:
	var chain := get_node_or_null("/root/Chain")
	if chain == null:
		return
	var head: int = await chain.refresh_head()
	if head < 0:
		_fail(wallets)
		return
	var calls: Array = []
	for w in wallets:
		calls.append(Multicall.make_call(Contracts.CHO, "GetUserTokenAddress(address)", [String(test_alias.get(w, w))]))
	var r1: Array = await chain.multicall.run(calls, "", head)
	var laus := {}  # wallet → lau
	for i in wallets.size():
		var w: String = wallets[i]
		if not r1[i].get("ok", false):
			_store(w, {"state": "failed", "block": head})
			continue
		var v = Multicall.value(r1[i], ["address"])
		var lau := String(v[0]).to_lower() if v != null else ""
		if v == null:
			_store(w, {"state": "failed", "block": head})
		elif lau == "" or lau == ZERO:
			_store(w, {"state": "none", "block": head})
		else:
			laus[w] = lau
	if laus.is_empty():
		return
	var calls2: Array = []
	var order: Array = laus.keys()
	for w in order:
		calls2.append(Multicall.make_call(laus[w], "Username()"))
		calls2.append(Multicall.make_call(laus[w], "name()"))
		calls2.append(Multicall.make_call(laus[w], "symbol()"))
	var r2: Array = await chain.multicall.run(calls2, "", head)
	for i in order.size():
		var w: String = order[i]
		var un = Multicall.value(r2[i * 3], ["string"])
		var nm = Multicall.value(r2[i * 3 + 1], ["string"])
		var sy = Multicall.value(r2[i * 3 + 2], ["string"])
		if un == null and nm == null:
			_store(w, {"state": "failed", "block": head, "lau": laus[w]})
			continue
		var u := String(un[0]) if un != null else ""
		var n := String(nm[0]) if nm != null else ""
		var s := String(sy[0]) if sy != null else ""
		if test_alias.has(w):
			u = (u + " (test)") if u != "" else u
			n = (n + " (test)") if n != "" else n
		_store(w, {"state": "ok", "username": u, "lau_name": n, "lau_symbol": s, "lau": laus[w], "block": head,
			"head": AvatarHeads.kind_for(String(un[0]) if un != null else "", String(nm[0]) if nm != null else "", s),
			"acc": AvatarHeads.accessories_for(String(un[0]) if un != null else "", String(nm[0]) if nm != null else "", s)})


func _fail(wallets: Array) -> void:
	for w in wallets:
		_store(w, {"state": "failed", "block": -1})


func _store(w: String, rec: Dictionary) -> void:
	var old: Dictionary = _cache.get(w, {})
	# A failed re-read keeps the name read before (it is still the last fact), marked by its block.
	if rec["state"] == "failed" and String(old.get("state", "")) == "ok":
		old["at"] = _now() - TTL_OK_S + TTL_FAIL_S
		return
	rec["at"] = _now()
	_cache[w] = rec
	resolved.emit(w)
