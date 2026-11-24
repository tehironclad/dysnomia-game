class_name VehicleUnlocks
extends RefCounted
## Which garage vehicles a player may drive, from the player's REAL chain state
## (read by Session and TerritoryState; no new reads, nothing guessed):
##
##   rover      free for everyone (no wallet needed)
##   hoverbike  a Hypobar anywhere: YUE.Bar(QING) > 0 at any territory
##   skimmer    a Hypobar HERE: YUE.Bar(this QING) > 0
##   hopper     bars at 3+ territories (the creature gear's spark rule, LEARNINGS §11)
##   crawler    your tower here is in the skyline's top 3 (this territory's board,
##              ranked by Hypobar over known players: the towers everyone sees)
##
## A rule whose inputs are not read yet is UNKNOWN ("…"), one whose read failed
## is UNKNOWN ("—"), never "locked" and never "open". A rental (1 Ⓐ to this
## QING, receipt-verified by ArcadePay) opens one vehicle here for this session.

enum State { OPEN, LOCKED, UNKNOWN }

const TOP_N := 3
const HOPPER_TERRITORIES := 3

const RULES := {
	"rover": "free for everyone",
	"hoverbike": "a Hypobar anywhere",
	"skimmer": "a Hypobar in this territory",
	"hopper": "bars at %d+ territories" % HOPPER_TERRITORIES,
	"crawler": "a top-%d tower here" % TOP_N,
}

## Rentals this session: "wallet@qing:kind" → {tx, block}. Never saved: a rental
## is for one session, and the payment itself is on the chain.
static var rentals := {}
## The last complete bars pass seen per wallet: Session re-reads bars after the
## identity each minute; bars only grow, so the previous pass stays a true floor.
static var _bars_seen := {}


## The facts the rules read. Build it with gather() in the game, or by hand in tests.
##   wallet        "" = no wallet connected
##   identity      "loading" | "failed" | "ok"
##   has_yue       bool (only meaningful when identity == "ok")
##   bars          {qing → [hypobar, epibar]} non-zero bars across territories, or null (not read yet)
##   bars_block    block of that read (-1 unknown)
##   territories   how many territories the bars pass covered
##   qing          this territory (lower case)
##   board         this territory's board [{wallet, hypobar…}] sorted desc, or null (not read / failed)
##   board_note    "…" while loading, "—" if failed
##   board_block   block of the board
static func evaluate(kind: String, f: Dictionary) -> Dictionary:
	var wallet := String(f.get("wallet", "")).to_lower()
	var qing := String(f.get("qing", "")).to_lower()
	if kind == "rover":
		return _r(State.OPEN, "free for everyone")
	if wallet != "" and rentals.has(rental_key(wallet, qing, kind)):
		var rent: Dictionary = rentals[rental_key(wallet, qing, kind)]
		return _r(State.OPEN, "rented this session · tx %s · block %d" % [String(rent["tx"]).left(10), int(rent["block"])])
	if not RULES.has(kind):
		return _r(State.LOCKED, "unknown vehicle")
	if wallet == "":
		return _r(State.LOCKED, "needs %s · connect a wallet" % RULES[kind])
	match String(f.get("identity", "loading")):
		"loading":
			return _r(State.UNKNOWN, "… reading your identity")
		"failed":
			return _r(State.UNKNOWN, "— identity read failed")
	if not bool(f.get("has_yue", false)):
		return _r(State.LOCKED, "needs %s · no YUE yet (Su anywhere starts your bars)" % RULES[kind])
	if kind == "crawler":
		return _crawler(wallet, f)
	var bars = f.get("bars", null)
	if kind == "skimmer" and _on_board(wallet, f.get("board", null)):
		return _r(State.OPEN, "your tower stands here · board block %d" % int(f.get("board_block", -1)))
	if bars == null:
		return _r(State.UNKNOWN, "… reading your bars")
	var src := "YUE.Bar(QING) × %d territories · block %d" % [int(f.get("territories", 0)), int(f.get("bars_block", -1))]
	match kind:
		"hoverbike":
			var n := _count_hypobar(bars)
			return _r(State.OPEN, "Hypobar at %d territories · %s" % [n, src]) if n > 0 \
				else _r(State.LOCKED, "needs a Hypobar anywhere · none found · %s" % src)
		"skimmer":
			var here: bool = _hypobar_at(bars, qing)
			return _r(State.OPEN, "your Hypobar here · %s" % src) if here \
				else _r(State.LOCKED, "needs a Hypobar here · none yet (Su here) · %s" % src)
		"hopper":
			var n2 := _count_hypobar(bars)
			return _r(State.OPEN, "bars at %d territories · %s" % [n2, src]) if n2 >= HOPPER_TERRITORIES \
				else _r(State.LOCKED, "needs bars at %d+ territories · you have %d · %s" % [HOPPER_TERRITORIES, n2, src])
	return _r(State.LOCKED, "unknown vehicle")


static func _crawler(wallet: String, f: Dictionary) -> Dictionary:
	var board = f.get("board", null)
	if board == null:
		var note := String(f.get("board_note", "…"))
		return _r(State.UNKNOWN, "%s this territory's board %s" % [note, "unavailable" if note == "—" else "loading"])
	var rank := rank_on(wallet, board)
	var src := "board of %d towers · block %d" % [(board as Array).size(), int(f.get("board_block", -1))]
	if rank < 0:
		return _r(State.LOCKED, "needs a top-%d tower here · you have no tower here · %s" % [TOP_N, src])
	if rank <= TOP_N:
		return _r(State.OPEN, "your tower is #%d here · %s" % [rank, src])
	return _r(State.LOCKED, "needs a top-%d tower here · yours is #%d · %s" % [TOP_N, rank, src])


## 1-based rank of `wallet` on a board sorted by Hypobar (ties share the better
## rank), or -1 if it has no row or a zero Hypobar.
static func rank_on(wallet: String, board: Array) -> int:
	wallet = wallet.to_lower()
	var mine = null
	for row in board:
		if String(row.get("wallet", "")).to_lower() == wallet:
			mine = BigInt.coerce(row.get("hypobar", PackedInt64Array()))
			break
	if mine == null or BigInt.is_zero(mine):
		return -1
	var above := 0
	for row in board:
		if BigInt.cmp(BigInt.coerce(row.get("hypobar", PackedInt64Array())), mine) > 0:
			above += 1
	return above + 1


static func _on_board(wallet: String, board) -> bool:
	return board != null and rank_on(wallet, board) > 0


static func _hypobar_at(bars: Dictionary, qing: String) -> bool:
	for a in bars:
		if String(a).to_lower() == qing:
			return not BigInt.is_zero(BigInt.coerce(bars[a][0]))
	return false


static func _count_hypobar(bars: Dictionary) -> int:
	var n := 0
	for a in bars:
		if not BigInt.is_zero(BigInt.coerce(bars[a][0])):
			n += 1
	return n


static func _r(state: State, why: String) -> Dictionary:
	return {"state": state, "why": why}


static func rental_key(wallet: String, qing: String, kind: String) -> String:
	return "%s@%s:%s" % [wallet.to_lower(), qing.to_lower(), kind]


static func add_rental(wallet: String, qing: String, kind: String, tx: String, block: int) -> void:
	rentals[rental_key(wallet, qing, kind)] = {"tx": tx, "block": block}


static func status_word(state: State) -> String:
	return ["OPEN", "LOCKED", "…"][state]


## The facts, from what the game has already read (Session + this territory's state).
static func gather(qing: String, state: TerritoryState) -> Dictionary:
	var f := {"wallet": Session.wallet, "qing": qing.to_lower(), "identity": "loading", "has_yue": false,
		"bars": null, "bars_block": -1, "territories": Registry.all().size(), "board": null, "board_note": "…", "board_block": -1}
	var ps: PlayerState = Session.player
	if ps != null:
		f["identity"] = "ok" if ps.ok else "failed"
		f["has_yue"] = ps.has_yue()
		if ps.ok and ps.has_yue() and Session.bars_block >= 0 and Session.bars_block >= ps.block and ps.wallet == Session.wallet:
			_bars_seen[ps.wallet] = {"bars": Session.bars, "block": Session.bars_block}
		if ps.ok and ps.has_yue() and _bars_seen.has(ps.wallet):
			f["bars"] = _bars_seen[ps.wallet]["bars"]
			f["bars_block"] = _bars_seen[ps.wallet]["block"]
	if state != null:
		if state.total_hypobar.has_value():
			f["board"] = state.board
			f["board_block"] = state.block
		elif state.total_hypobar.state == Fact.State.UNAVAILABLE:
			f["board_note"] = "—"
	return f
