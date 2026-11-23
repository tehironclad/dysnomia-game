extends Node
## Autoload "Session": who is playing. The connected wallet is the identity
## root (wallet → LAU → YUE). Holds the latest PlayerState and Readiness and
## refreshes them on connect, after every confirmed write, and every 60 s.

signal changed
## Leads won or lost since this wallet was last seen (known players; a floor).
signal lead_changed(lost: Array, gained: Array, block: int)

const REFRESH_S := 60.0
const LOCAL_PATH := "user://identity.cfg"

var wallet := ""
var player: PlayerState = null
var readiness: Readiness = null
var refreshing := false
## Bars across every territory (YUE.Bar(QING) for all of them, one Multicall):
## address → [hypobar, epibar] (PackedInt64Array), only where non-zero.
var bars := {}
var bars_block := -1
## Territories this player leads among known players (a floor: known players only).
var leading: Array = []
## Global ladder rank from the site accelerator (-1 = unknown; never guessed).
var ladder_rank := -1
## A LAU forged by this client but not yet registered with CHO (between steps).
var forged_lau := ""
## Streak, reactions and days from the wallet's YUE mint logs (PlayerRecord).
var record: PlayerRecord = null
var _record_at := -1000000
var _record_stale := true
var _timer: Timer


func _ready() -> void:
	_load_local()
	Wallet.connected.connect(func(addr): set_wallet(addr))
	Wallet.disconnected.connect(func(): set_wallet(""))
	Wallet.tx_stage.connect(func(_l, stage, _i): if stage == "confirmed": _record_stale = true)
	_timer = Timer.new()
	_timer.wait_time = REFRESH_S
	_timer.timeout.connect(func(): if wallet != "": refresh())
	add_child(_timer)
	_timer.start()


func set_wallet(addr: String) -> void:
	addr = addr.strip_edges().to_lower()
	if addr != "" and not (addr.begins_with("0x") and addr.length() == 42 and addr.substr(2).is_valid_hex_number()):
		push_warning("[Session] ignoring malformed address %s" % addr)
		return
	wallet = addr
	player = null
	readiness = null
	record = null
	_record_stale = true
	changed.emit()
	if wallet != "":
		refresh()


func refresh() -> void:
	if refreshing or wallet == "":
		return
	refreshing = true
	var ps: PlayerState = await PlayerState.read(wallet)
	var rd: Readiness = await Readiness.evaluate(ps)
	player = ps
	readiness = rd
	if ps.has_yue():
		Players.add_player(wallet, ps.yue)
		await _read_bars(ps)
		_compare_leads(ps.block)
		if _record_stale or Time.get_ticks_msec() - _record_at > 300000:
			_record_stale = false
			_record_at = Time.get_ticks_msec()
			refreshing = false
			changed.emit()
			refreshing = true
			record = await PlayerRecord.read(wallet, ps.yue)
	if ps.has_lau() and forged_lau != "":
		forged_lau = ""  # registered now
		_save_local()
	refreshing = false
	changed.emit()


func remember_forged(lau: String) -> void:
	forged_lau = lau.to_lower()
	_save_local()


func _load_local() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LOCAL_PATH) == OK:
		forged_lau = String(cfg.get_value("identity", "forged_lau", ""))


func _save_local() -> void:
	var cfg := ConfigFile.new()
	cfg.load(LOCAL_PATH)  # keep the other sections (head and body picks, leads)
	cfg.set_value("identity", "forged_lau", forged_lau)
	cfg.save(LOCAL_PATH)


## Leads gained/lost since the last time this wallet was read on this machine.
func _compare_leads(block: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(LOCAL_PATH)
	var prev: Array = cfg.get_value("leads", wallet, [])
	var lost: Array = prev.filter(func(a): return not leading.has(a))
	var gained: Array = leading.filter(func(a): return not prev.has(a))
	cfg.set_value("leads", wallet, leading.duplicate())
	cfg.save(LOCAL_PATH)
	if cfg.has_section_key("leads_seen", wallet) and (not lost.is_empty() or not gained.is_empty()):
		lead_changed.emit(lost, gained, block)
	cfg.set_value("leads_seen", wallet, true)
	cfg.save(LOCAL_PATH)


func _read_bars(ps: PlayerState) -> void:
	var all: Array = Registry.all()
	var calls: Array = []
	for q in all:
		calls.append(Multicall.make_call(ps.yue, "Bar(address)", [q["address"]]))
	var res: Array = await Chain.multicall.run(calls, "", ps.block)
	var found := {}
	for i in all.size():
		var v = Multicall.value(res[i], ["uint256", "uint256"])
		if v == null:
			continue
		var hb := BigInt.from_hex(v[0])
		var eb := BigInt.from_hex(v[1])
		if not BigInt.is_zero(hb) or not BigInt.is_zero(eb):
			found[String(all[i]["address"])] = [hb, eb]
	bars = found
	bars_block = ps.block
	# Leading: compare with every known player's Hypobar at each of these (cap 25).
	var lead: Array = []
	var targets: Array = found.keys().slice(0, 25)
	var others: Array = Players.all().filter(func(p): return p["wallet"] != wallet)
	if not targets.is_empty() and not others.is_empty():
		var c2: Array = []
		for t in targets:
			for o in others:
				c2.append(Multicall.make_call(o["yue"], "Bar(address)", [t]))
		var r2: Array = await Chain.multicall.run(c2, "", ps.block)
		for ti in targets.size():
			var mine: PackedInt64Array = found[targets[ti]][0]
			var best := true
			for oi in others.size():
				var v2 = Multicall.value(r2[ti * others.size() + oi], ["uint256", "uint256"])
				if v2 != null and BigInt.cmp(BigInt.from_hex(v2[0]), mine) > 0:
					best = false
					break
			if best and not BigInt.is_zero(mine):
				lead.append(targets[ti])
	leading = lead
	ladder_rank = -1
	var lr: Dictionary = await Chain.site.leaders("hypobar", 100)
	if lr.get("ok", false) and lr["data"] is Array:
		for i in lr["data"].size():
			if String(lr["data"][i].get("address", "")).to_lower() == wallet:
				ladder_rank = i + 1
				break
