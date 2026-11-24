class_name LauFinder
extends RefCounted
## Every LAU a wallet owns, and switching which one CHO knows it by.
##
## Finding (read-only):
##   1. eth_getLogs over the whole chain, no address, topics
##      [OwnershipUpdate(address indexed,bool indexed), wallet]: every contract that
##      ever named this wallet an owner (an LAU has no owner(); this is how the site
##      finds them too).
##   2. Each candidate is proven an LAU of this wallet by Saat(2) == wallet % the
##      Motzkin prime (the contract's own identity formula); anything else is dropped.
##   3. Username(), name(), symbol() for the proven ones (Multicall3, one block).
## Switching (a write): CHO.Enter(LAU) makes that LAU the wallet's current one.
## Measured live 2026-11-25: simulated Enter(kingg) from the owner's wallet, then
## CHO.GetUserTokenAddress(wallet) returned kingg (trace_callMany, same block).
## After the receipt the game re-reads GetUserTokenAddress at that block.

const FALLBACK_FROM := 22_000_000   ## before the first LAU OwnershipUpdate seen (22,815,864)
const SLICE := 2_000_000
const TOPIC_OWNERSHIP := "0x6bfa7e860c3e9bf67b810cb88276b19b27c972812bac04793d369b59a1183a83"


## Pure: the unique contract addresses in OwnershipUpdate logs, oldest first.
static func candidates(logs: Array) -> Array:
	var out: Array = []
	var seen := {}
	for lg in logs:
		var a := String(lg.get("address", "")).to_lower()
		if a.length() == 42 and not seen.has(a):
			seen[a] = true
			out.append(a)
	return out


## Pure: does a Saat(2) value (hex word) prove this LAU belongs to `wallet`?
static func proves(saat2_hex: String, wallet: String) -> bool:
	if saat2_hex == "" or wallet.length() != 42:
		return false
	var want := BigInt.mod_int(BigInt.from_hex(wallet), Contracts.MOTZKIN_PRIME)
	var got := BigInt.from_hex(saat2_hex)
	return BigInt.cmp(got, BigInt.from_int(want)) == 0


## Pure: a label for a picker row ("kingg · king gizard" / "chatlife" / "0x3a1e…1fe4").
static func label(l: Dictionary) -> String:
	var u := String(l.get("username", ""))
	var n := String(l.get("name", ""))
	if u != "" and n != "" and n != u:
		return "%s · %s" % [u, n]
	if u != "":
		return u
	if n != "":
		return n
	return ArcadeScores.short(String(l.get("address", "")))


## {ok, block, laus: [{address, username, name, symbol, current}], error}.
static func find(wallet: String) -> Dictionary:
	wallet = wallet.to_lower()
	if wallet.length() != 42:
		return {"ok": false, "error": "no wallet"}
	var head: int = await Chain.refresh_head()
	var topics := [TOPIC_OWNERSHIP, "0x" + wallet.substr(2).lpad(64, "0")]
	# The whole chain first (as the site does); a slow node can time out on it, so
	# retry, then read from FALLBACK_FROM in slices (no LAU's logs are older).
	var r: Dictionary = {}
	for attempt in 2:
		r = await Chain.rpc.request("eth_getLogs", [{"topics": topics, "fromBlock": "0x0", "toBlock": "0x%x" % head}])
		if r.get("ok", false) and r.get("result") is Array:
			break
	if not r.get("ok", false) or not (r.get("result") is Array):
		var all: Array = []
		var from := FALLBACK_FROM
		while from <= head:
			var to := mini(from + SLICE - 1, head)
			var part: Dictionary = await Chain.rpc.request("eth_getLogs", [{"topics": topics, "fromBlock": "0x%x" % from, "toBlock": "0x%x" % to}])
			if not part.get("ok", false) or not (part.get("result") is Array):
				return {"ok": false, "error": "the ownership logs could not be read"}
			all.append_array(part["result"])
			from = to + 1
		r = {"ok": true, "result": all}
	var cands := candidates(r["result"])
	if cands.is_empty():
		return {"ok": true, "block": head, "laus": []}
	var calls: Array = []
	for a in cands:
		calls.append(Multicall.make_call(a, "Saat(uint256)", [2]))
	var res: Array = await Chain.multicall.run(calls, "", head)
	if res.size() < cands.size():
		return {"ok": false, "error": "the LAU checks could not be read"}
	var laus: Array = []
	for i in cands.size():
		var v = Multicall.value(res[i], ["uint256"])
		if v != null and proves(String(v[0]), wallet):
			laus.append({"address": cands[i], "username": "", "name": "", "symbol": "", "current": false})
	if laus.is_empty():
		return {"ok": true, "block": head, "laus": []}
	calls = []
	for l in laus:
		calls.append(Multicall.make_call(l["address"], "Username()"))
		calls.append(Multicall.make_call(l["address"], "name()"))
		calls.append(Multicall.make_call(l["address"], "symbol()"))
	calls.append(Multicall.make_call(Contracts.CHO, "GetUserTokenAddress(address)", [wallet]))
	res = await Chain.multicall.run(calls, "", head)
	var current := ""
	if res.size() == calls.size():
		var cv = Multicall.value(res[calls.size() - 1], ["address"])
		current = String(cv[0]).to_lower() if cv != null else ""
		for i in laus.size():
			for j in 3:
				var sv = Multicall.value(res[i * 3 + j], ["string"])
				if sv != null:
					laus[i][["username", "name", "symbol"][j]] = String(sv[0])
	for l in laus:
		l["current"] = current != "" and l["address"] == current
	return {"ok": true, "block": head, "laus": laus, "current": current}


## CHO.Enter(lau) through the write pipeline, then the current LAU re-read at the
## receipt's block. {ok, block} or {ok:false, stage, message}.
static func switch_to(lau: String, title: String) -> Dictionary:
	var wallet := Wallet.address.to_lower()
	var data := Abi.encode_call("Enter(address)", [lau.to_lower()])
	var res: Dictionary = await Wallet.send("Use your LAU %s (CHO.Enter)" % title, Contracts.CHO, data)
	if not res.get("ok", false):
		return res
	var r: Dictionary = await Chain.rpc.call_decoded(Contracts.CHO, "GetUserTokenAddress(address)", [wallet], ["address"], "", "0x%x" % int(res["block"]))
	if not r.get("ok", false):
		return {"ok": false, "stage": "verify", "message": "Mined in block %d, but the current LAU could not be re-read." % int(res["block"])}
	if String(r["values"][0]).to_lower() != lau.to_lower():
		return {"ok": false, "stage": "verify", "message": "Mined in block %d, but CHO still names %s." % [int(res["block"]), String(r["values"][0])]}
	Session.refresh()
	return {"ok": true, "block": int(res["block"])}
