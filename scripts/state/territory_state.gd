class_name TerritoryState
extends Node
## Shared, viewer-independent state of one territory (WP 2.5), read from the
## chain and pinned to one block per refresh:
## - reservoirs: Fornax, Eris, Tethys held by the QING (balanceOf(QING));
## - Ω: Hypobar added per Su here = ⌊Fornax(QING) / Entropy(QING)⌋ (same for everyone);
## - Dione-ish: Tethys(QING) / Entropy is what a future Code pays in VITUS;
## - the board: YUE.Bar(QING) for every known player → totals, reactors, ranks;
## - the door: CoverCharge(), Asset().
## Every value is a Fact. The board and totals are FLOORS (known players only).

signal changed
signal bars_moved(delta_hypobar: PackedInt64Array, block: int)

const REFRESH_S := 10.0  # about one PulseChain block

var address := ""
var entropy := PackedInt64Array()
var block := -1
var fornax: Fact = Fact.loading("Fornax.balanceOf(QING)")
var eris: Fact = Fact.loading("Eris.balanceOf(QING)")
var tethys: Fact = Fact.loading("Tethys.balanceOf(QING)")
var omega: Fact = Fact.loading("⌊Fornax(QING) / QING.Entropy()⌋")
var cover_charge: Fact = Fact.loading("QING.CoverCharge()")
var asset: Fact = Fact.loading("QING.Asset()")
var total_hypobar: Fact = Fact.loading("Σ YUE.Bar(QING).Hypobar")
var total_epibar: Fact = Fact.loading("Σ YUE.Bar(QING).Epibar")
var reactors: Fact = Fact.loading("players with bars here")
## [{wallet, yue, hypobar: PackedInt64Array, epibar: PackedInt64Array}] by Hypobar, desc.
var board: Array = []
var _timer: Timer
var _refreshing := false


func setup(q: Dictionary) -> void:
	address = String(q["address"]).to_lower()
	entropy = BigInt.from_decimal(String(q["entropy"]))
	_timer = Timer.new()
	_timer.wait_time = REFRESH_S
	_timer.timeout.connect(refresh)
	add_child(_timer)
	_timer.start()
	refresh()


func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var head := await Chain.refresh_head()
	if head < 0:
		_mark_unavailable("chain head unavailable")
		_refreshing = false
		return
	if head == block:  # nothing new since the last read
		_refreshing = false
		return
	var calls: Array = [
		Multicall.make_call(Contracts.FORNAX, "balanceOf(address)", [address]),
		Multicall.make_call(Contracts.ERIS, "balanceOf(address)", [address]),
		Multicall.make_call(Contracts.TETHYS, "balanceOf(address)", [address]),
		Multicall.make_call(address, "CoverCharge()"),
		Multicall.make_call(address, "Asset()"),
	]
	var players: Array = Players.all()
	for p in players:
		calls.append(Multicall.make_call(p["yue"], "Bar(address)", [address]))
	var res: Array = await Chain.multicall.run(calls, "", head)
	var src := "block %d" % head
	fornax = _bal(res[0], "Fornax.balanceOf(QING)", head)
	eris = _bal(res[1], "Eris.balanceOf(QING)", head)
	tethys = _bal(res[2], "Tethys.balanceOf(QING)", head)
	var cv = Multicall.value(res[3], ["uint256"])
	cover_charge = Fact.ok(cv[0], "QING.CoverCharge()", head) if cv != null else Fact.unavailable("QING.CoverCharge()", "read failed")
	var av = Multicall.value(res[4], ["address"])
	asset = Fact.ok(av[0], "QING.Asset()", head) if av != null else Fact.unavailable("QING.Asset()", "read failed")
	omega = Fact.ok("0x" + BigInt.to_hex(BigInt.div(BigInt.coerce(fornax.value), entropy)), omega.source, head) \
		if fornax.has_value() else Fact.unavailable(omega.source, "Fornax read failed")
	# The board.
	var prev_total := BigInt.coerce(total_hypobar.value) if total_hypobar.has_value() else PackedInt64Array()
	var rows: Array = []
	var th := PackedInt64Array()
	var te := PackedInt64Array()
	var failed := 0
	for i in players.size():
		var v = Multicall.value(res[5 + i], ["uint256", "uint256"])
		if v == null:
			failed += 1
			continue
		var hb := BigInt.from_hex(v[0])
		var eb := BigInt.from_hex(v[1])
		th = BigInt.add(th, hb)
		te = BigInt.add(te, eb)
		if not BigInt.is_zero(hb) or not BigInt.is_zero(eb):
			rows.append({"wallet": players[i]["wallet"], "yue": players[i]["yue"], "hypobar": hb, "epibar": eb})
	rows.sort_custom(func(x, y): return BigInt.cmp(x["hypobar"], y["hypobar"]) > 0)
	board = rows
	var why := "%d known players (snapshot block %d)%s" % [players.size(), Players.snapshot_block,
		", %d reads failed" % failed if failed > 0 else ""]
	total_hypobar = Fact.floor_of("0x" + BigInt.to_hex(th), "Σ YUE.Bar(QING).Hypobar", why, head)
	total_epibar = Fact.floor_of("0x" + BigInt.to_hex(te), "Σ YUE.Bar(QING).Epibar", why, head)
	reactors = Fact.floor_of(rows.size(), "players with bars here", why, head)
	var moved := not prev_total.is_empty() and BigInt.cmp(th, prev_total) > 0
	block = head
	_refreshing = false
	changed.emit()
	if moved:
		bars_moved.emit(BigInt.sub(th, prev_total), head)


func _bal(r: Dictionary, src: String, head: int) -> Fact:
	var v = Multicall.value(r, ["uint256"])
	return Fact.ok(v[0], src, head) if v != null else Fact.unavailable(src, "read failed")


func _mark_unavailable(why: String) -> void:
	for f in [fornax, eris, tethys, omega, cover_charge, asset, total_hypobar, total_epibar, reactors]:
		if not f.has_value():
			f.state = Fact.State.UNAVAILABLE
			f.note = why
	changed.emit()


## Escape bands to light on the ground: one per order of magnitude of the
## shared Hypobar total (only grows, so the land only brightens).
func lit_bands() -> float:
	if not total_hypobar.has_value():
		return 0.0
	var lg := BigInt.log10(BigInt.coerce(total_hypobar.value))
	return 0.0 if is_inf(lg) else floorf(lg)
