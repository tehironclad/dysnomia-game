extends Node
## Autoload "World" (WP 6.1): is WORLD deployed? Read from the chain only.
##
## Every Dysnomia core contract came from one EOA, the deployer. A contract an
## EOA creates lands at keccak256(rlp([sender, nonce])), so its next addresses
## are known in advance (assets/data/deployer_creates.json, made with the
## site's keccak by tools/golden/creates.js). Each check, pinned to one block:
##   1. the deployer's nonce; 712 = nothing new since 2026-10-15;
##   2. for each nonce used past the baseline: code at that CREATE address?
##   3. code → classified by its dispatcher's PUSH4 selectors (WORLD needs
##      Code(int256,int256,address) + Vitus(); WAR Faa + Water(); GWAT Gwat + War());
##   4. a WORLD is "wired" only if Cheon()/Meta()/Map() return the real CHEON,
##      META and MAP. Only then does the status read "live".
## The site's /api/world-watch is shown beside it as corroboration, never as proof.
##
## status: "unknown" | "latent" | "stirring" (the deployer moved, no WORLD code)
##         | "unverified" (WORLD-shaped code that is not wired to the system) | "live"

signal changed
signal launched(addresses: Dictionary)

const CHECK_S := 600.0
const CREATES_PATH := "res://assets/data/deployer_creates.json"
const KINDS := {
	"WORLD": ["Code(int256,int256,address)", "Vitus()"],
	"WAR": ["Faa(address,uint256)", "Water()"],
	"GWAT": ["Gwat(address,uint256)", "War()"],
}

var status := "unknown"
var nonce: Fact = Fact.loading("eth_getTransactionCount(deployer)")
var site: Fact = Fact.loading("site /api/world-watch")
var block := -1
## kind → {address, nonce, wired: bool|null, points: {}} verified on-chain.
var found := {}
var evidence: PackedStringArray = []
var checking := false
var _creates := {}
var _table_to := -1


var _timer: Timer


func _ready() -> void:
	_load_creates()


## Starts watching (the front door and territories call this; autoloads do no
## network on their own, so tests and tools stay offline).
func start() -> void:
	if _timer != null:
		return
	_timer = Timer.new()
	_timer.wait_time = CHECK_S
	_timer.timeout.connect(check)
	add_child(_timer)
	_timer.start()
	check()


func _load_creates() -> void:
	var f := FileAccess.open(CREATES_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_creates = d.get("creates", {})
		_table_to = int(d.get("to", -1))


func is_live() -> bool:
	return status == "live"


## The verified address of a kind ("" unless found on-chain and, for WORLD, wired).
func address_of(kind: String) -> String:
	if not found.has(kind):
		return ""
	if kind == "WORLD" and found[kind].get("wired") != true:
		return ""
	return String(found[kind]["address"])


## Pure: which WORLD-family class a runtime bytecode is ("" if none).
static func classify(code_hex: String) -> String:
	var hex := code_hex.to_lower()
	if hex.length() <= 2:
		return ""
	for kind in KINDS:
		var all := true
		for sig in KINDS[kind]:
			if not hex.contains("63" + Contracts.selector(sig).substr(2)):
				all = false
				break
		if all:
			return kind
	return ""


func check() -> void:
	if checking:
		return
	checking = true
	var was_live := is_live()
	var head := await Chain.refresh_head()
	if head < 0:
		_finish("unknown", ["the chain head could not be read"], was_live)
		return
	block = head
	var nr := await Chain.rpc.get_transaction_count(Contracts.DYSNOMIA_DEPLOYER, head)
	if not nr["ok"]:
		nonce = Fact.unavailable(nonce.source, "read failed")
		_finish("unknown", ["the deployer's nonce could not be read"], was_live)
		await _read_site()
		return
	var n := String(nr["result"]).hex_to_int()
	nonce = Fact.ok(n, "eth_getTransactionCount(%s)" % Contracts.DYSNOMIA_DEPLOYER, head)
	var ev: PackedStringArray = ["Deployer %s nonce %d at block %d (baseline %d)." % [Contracts.DYSNOMIA_DEPLOYER, n, head, Contracts.DEPLOYER_NONCE_BASELINE]]
	var new_found := {}
	var unread := 0
	for k in range(Contracts.DEPLOYER_NONCE_BASELINE, n):
		var addr := String(_creates.get(str(k), ""))
		if addr == "":
			ev.append("Nonce %d is beyond the shipped CREATE table (to %d): regenerate it (tools/golden/creates.js)." % [k, _table_to])
			unread += 1
			continue
		var cr := await Chain.rpc.get_code(addr, head)
		if not cr["ok"]:
			ev.append("Nonce %d → %s: code unreadable (retry next check)." % [k, addr])
			unread += 1
			continue
		var code := String(cr["result"])
		if code.length() <= 2:
			ev.append("Nonce %d → %s: no code (a plain transaction)." % [k, addr])
			continue
		var kind := classify(code)
		ev.append("Nonce %d → %s: contract, %s." % [k, addr, ("classified " + kind) if kind != "" else "not WORLD-family"])
		if kind != "" and not new_found.has(kind):
			new_found[kind] = {"address": addr, "nonce": k, "wired": null, "points": {}}
	if new_found.has("WORLD"):
		await _inspect_world(new_found["WORLD"], head)
		ev.append("WORLD Cheon/Meta/Map → %s" % ("the real CHEON, META, MAP (wired)" if new_found["WORLD"]["wired"] == true else "NOT the live system (unverified)"))
	found = new_found
	var st := "latent"
	if n > Contracts.DEPLOYER_NONCE_BASELINE:
		st = "stirring"
	if found.has("WORLD"):
		st = "live" if found["WORLD"]["wired"] == true else "unverified"
	elif unread > 0 and n > Contracts.DEPLOYER_NONCE_BASELINE:
		st = "unknown"
	await _read_site()
	_finish(st, ev, was_live)


func _inspect_world(w: Dictionary, head: int) -> void:
	var a: String = w["address"]
	var res: Array = await Chain.multicall.run([
		Multicall.make_call(a, "Cheon()"), Multicall.make_call(a, "Meta()"),
		Multicall.make_call(a, "Map()"), Multicall.make_call(a, "Vitus()")], "", head)
	var pts := {}
	var keys := ["cheon", "meta", "map", "vitus"]
	for i in 4:
		var v = Multicall.value(res[i], ["address"])
		pts[keys[i]] = String(v[0]).to_lower() if v != null else ""
	w["points"] = pts
	if pts["cheon"] == "" or pts["meta"] == "" or pts["map"] == "":
		w["wired"] = null
	else:
		w["wired"] = pts["cheon"] == Contracts.CHEON and pts["meta"] == Contracts.META and pts["map"] == Contracts.MAP


func _read_site() -> void:
	var r: Dictionary = await Chain.site.world_watch()
	if r["ok"]:
		site = Fact.ok(String(r["data"].get("status", "?")), "site /api/world-watch (corroboration only)")
	else:
		site = Fact.unavailable(site.source, String(r.get("error", "")))


func _finish(st: String, ev: PackedStringArray, was_live: bool) -> void:
	status = st
	evidence = ev
	checking = false
	changed.emit()
	if is_live() and not was_live:
		launched.emit({"WORLD": address_of("WORLD"), "WAR": address_of("WAR"), "GWAT": address_of("GWAT")})


func headline() -> String:
	match status:
		"latent": return "WORLD: not deployed (deployer nonce %s, block %d)" % [nonce.display(), block]
		"stirring": return "WORLD: the deployer moved (nonce %s) but no WORLD code yet (block %d)" % [nonce.display(), block]
		"unverified": return "WORLD-shaped code at %s, NOT wired to CHEON/META/MAP: not trusted" % found["WORLD"]["address"]
		"live": return "WORLD LIVE at %s (verified on-chain at block %d)" % [address_of("WORLD"), block]
	return "WORLD: unknown (—)"
