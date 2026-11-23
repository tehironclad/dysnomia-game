extends Node
## AFFECTION economy for in-territory attractions (pub drinks, funfair rides).
## Lives under ChainManager as `ChainManager.economy`.
##
## buy(item) settles an AttractionCatalog item on-chain:
##   ticket → AFFECTION.transfer(QING keeper, price)   — paid by the visitor to the QING's owner
##   op     → AFFECTION.<Pi|Rho|Generate|Alpha|Beta|Upsilon>(...) — the visitor's own call
## Either way, once the tx confirms we re-read the territory state and emit bar_report with
## the visitor's measured Hypobar/Epibar before and after. No numbers are invented.
##
## Without a connected wallet a ticket is granted as a free "preview" (marked unpaid) so the
## ride can still be tried; ops always need a wallet. The keeper rides their own QING free.

signal balance_updated(display: String)
signal purchase_pending(purchase_id: int, item: Dictionary, tx_id: int)
signal purchase_granted(purchase_id: int, item: Dictionary, mode: String)  # mode: "paid" | "keeper" | "preview" | "op"
signal purchase_failed(purchase_id: int, item: Dictionary, error: String)
signal bar_report(report: Dictionary)

const BAR_REPORT_TIMEOUT := 45.0

var balance_display: String = "—"
var decimals: int = 18
var _next_purchase_id: int = 1
var _pending: Dictionary = {}       # tx_id -> {purchase_id, item, hypo, epi}
var _awaiting_bars: Array = []      # [{item, hypo, epi, deadline}] waiting for a state refresh
var _tx_hashes: Dictionary = {}     # purchase_id -> confirmed tx hash (media boards cite it)


func _ready() -> void:
	var cm := get_parent()
	cm.tx_confirmed.connect(_on_tx_confirmed)
	cm.tx_failed.connect(_on_tx_failed)
	cm.token_balances_updated.connect(_on_balances)
	cm.wallet_connected.connect(func(_a: String) -> void: refresh_balance())
	GameManager.territory_state_changed.connect(_on_territory_state_changed)


func _process(_delta: float) -> void:
	# Expire bar reports that never got a fresh state read
	if _awaiting_bars.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for w in _awaiting_bars.duplicate():
		if now > w["deadline"]:
			_awaiting_bars.erase(w)


# ─── Queries ────────────────────────────────────────────────────────────

func wallet_ready() -> bool:
	return ChainManager.is_wallet_connected()


func keeper_address() -> String:
	## The QING's keeper — where ticket AFFECTION goes.
	return GameManager.territory_owner


func keeper_label() -> String:
	var name := GameManager.territory_name
	if name.is_empty():
		var k := keeper_address()
		return k.left(6) + "…" + k.right(4) if k.length() > 10 else "this QING"
	return name


func is_keeper() -> bool:
	var me := ChainManager.get_wallet_address().to_lower()
	if me.is_empty():
		me = GameManager.lau_owner.to_lower()
	return not me.is_empty() and me == keeper_address().to_lower()


func describe_cost(item: Dictionary) -> String:
	## One line telling the visitor exactly what pressing "pay" will do.
	if item.get("kind", "") == AttractionCatalog.KIND_OP:
		if not wallet_ready():
			return "Connect a wallet (W) to order — this is your own AFFECTION.%s call." % _op_fn(item.get("op", ""))
		return "Sends AFFECTION.%s() from your wallet. Gas only." % _op_fn(item.get("op", ""))
	if is_keeper():
		return "You keep this QING — you ride free."
	if not wallet_ready():
		return "No wallet connected — free preview ride (nothing is paid or recorded)."
	if keeper_address().is_empty() or not HexUtils.is_valid_address(keeper_address()):
		return "This QING's keeper is unknown — preview ride only."
	return "Pays %s to %s (the QING keeper)." % [AttractionCatalog.price_label(item), keeper_label()]


func refresh_balance() -> void:
	var w := ChainManager.get_wallet_address()
	if w.is_empty():
		w = GameManager.lau_wallet
	if w.is_empty():
		return
	ChainManager.read_affection_balance(w)


# ─── Purchase ───────────────────────────────────────────────────────────

func buy(item: Dictionary) -> int:
	## Start a purchase. Returns a purchase id; watch purchase_* signals for the outcome.
	var pid := _next_purchase_id
	_next_purchase_id += 1

	if item.get("kind", "") == AttractionCatalog.KIND_OP:
		_buy_op(pid, item)
		return pid

	# Ticket
	if is_keeper():
		purchase_granted.emit.call_deferred(pid, item, "keeper")
		return pid
	var keeper := keeper_address()
	if not wallet_ready() or keeper.is_empty() or not HexUtils.is_valid_address(keeper):
		purchase_granted.emit.call_deferred(pid, item, "preview")
		return pid

	var amount := to_base_units(str(item.get("price", "0")), decimals)
	var tx_id: int = ChainManager.send_affection_transfer(keeper, amount)
	if tx_id < 0:
		purchase_failed.emit.call_deferred(pid, item, "Wallet refused to send the ticket transaction")
		return pid
	_track(tx_id, pid, item)
	return pid


func _buy_op(pid: int, item: Dictionary) -> void:
	if not wallet_ready():
		purchase_failed.emit.call_deferred(pid, item, "Connect a wallet first (press W)")
		return
	var seed_val := randi() % 1_000_000 + 1
	var tx_id := -1
	match item.get("op", ""):
		"pi": tx_id = ChainManager.terraform_pi()
		"rho": tx_id = ChainManager.terraform_rho()
		"generate": tx_id = ChainManager.terraform_generate()
		"alpha": tx_id = ChainManager.terraform_alpha(seed_val)
		"beta": tx_id = ChainManager.terraform_beta(seed_val)
		"upsilon": tx_id = ChainManager.terraform_upsilon(seed_val, randi() % 2 == 0)
	if tx_id < 0:
		purchase_failed.emit.call_deferred(pid, item, "Could not send AFFECTION.%s" % _op_fn(item.get("op", "")))
		return
	_track(tx_id, pid, item)


func _track(tx_id: int, pid: int, item: Dictionary) -> void:
	_pending[tx_id] = {
		"purchase_id": pid, "item": item,
		"hypo": GameManager.territory_hypobar, "epi": GameManager.territory_epibar,
		"had_state": GameManager.has_territory_state,
	}
	purchase_pending.emit(pid, item, tx_id)


func _on_tx_confirmed(tx_id: int, tx_hash: String) -> void:
	if not _pending.has(tx_id):
		return
	var p: Dictionary = _pending[tx_id]
	_pending.erase(tx_id)
	_tx_hashes[p["purchase_id"]] = tx_hash
	var item: Dictionary = p["item"]
	var mode := "op" if item.get("kind", "") == AttractionCatalog.KIND_OP else "paid"
	purchase_granted.emit(p["purchase_id"], item, mode)
	_awaiting_bars.append({
		"item": item, "hypo": p["hypo"], "epi": p["epi"], "had_state": p["had_state"],
		"deadline": Time.get_ticks_msec() / 1000.0 + BAR_REPORT_TIMEOUT,
	})
	# Terraform ops refresh state on their own; tickets need an explicit re-read.
	if mode == "paid":
		ChainManager.refresh_territory_state()
	refresh_balance()


func tx_hash_for(purchase_id: int) -> String:
	return _tx_hashes.get(purchase_id, "")


func _on_tx_failed(tx_id: int, error: String) -> void:
	if not _pending.has(tx_id):
		return
	var p: Dictionary = _pending[tx_id]
	_pending.erase(tx_id)
	purchase_failed.emit(p["purchase_id"], p["item"], _friendly_error(error))


func _on_territory_state_changed(_data: Dictionary) -> void:
	if _awaiting_bars.is_empty():
		return
	var w: Dictionary = _awaiting_bars.pop_front()
	var hypo := GameManager.territory_hypobar
	var epi := GameManager.territory_epibar
	bar_report.emit({
		"item": w["item"],
		"hypo_before": w["hypo"], "epi_before": w["epi"],
		"hypo_after": hypo, "epi_after": epi,
		"d_hypo": hypo - int(w["hypo"]), "d_epi": epi - int(w["epi"]),
		"baseline_known": w["had_state"],
	})


func _on_balances(balances: Dictionary) -> void:
	var key := ChainManager.AFFECTION_TOKEN_ADDRESS.to_lower()
	if balances.has(key):
		var b: Dictionary = balances[key]
		decimals = int(b.get("decimals", 18))
		balance_display = str(b.get("display", "—"))
		balance_updated.emit(balance_display)


# ─── Helpers ────────────────────────────────────────────────────────────

static func to_base_units(amount: String, token_decimals: int) -> String:
	## "2.5" with 18 decimals → "2500000000000000000". Pure string math, no float rounding,
	## and no int64 overflow (ethers parses the decimal string as uint256).
	var s := amount.strip_edges()
	if s.is_empty() or not s.replace(".", "").is_valid_int():
		return "0"
	var whole := s
	var frac := ""
	var dot := s.find(".")
	if dot >= 0:
		whole = s.left(dot)
		frac = s.substr(dot + 1)
	frac = frac.left(token_decimals)
	while frac.length() < token_decimals:
		frac += "0"
	var out := (whole + frac).lstrip("0")
	return out if not out.is_empty() else "0"


static func _op_fn(op: String) -> String:
	match op:
		"pi": return "Pi"
		"rho": return "Rho"
		"generate": return "Generate"
		"alpha": return "Alpha"
		"beta": return "Beta"
		"upsilon": return "Upsilon"
	return op


static func _friendly_error(error: String) -> String:
	var e := error.to_lower()
	if e.contains("rejected") or e.contains("denied") or e.contains("4001"):
		return "You declined the transaction in your wallet"
	if e.contains("insufficient") or e.contains("exceeds balance"):
		return "Not enough AFFECTION (or PLS for gas)"
	if e.contains("reverted"):
		return "The contract rejected it (simulation reverted)"
	return error.left(120)
