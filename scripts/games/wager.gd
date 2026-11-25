class_name Wager
extends RefCounted
## The honour-bound stake of a head-to-head game, as each player sees it. Pure.
## There is no escrow: when a game with an agreed stake ends, the loser owes the
## stake in Ⓐ and pays it with a plain AFFECTION.transfer to the winner (the write
## pipeline: simulate → sign → receipt → re-read). A debt counts as paid only when
## an AFFECTION Transfer(loser → winner) log at or after the game's end block is
## read from the chain (TableBook.allocate); otherwise it is unpaid, and an
## unread or failed check is "—", never a guess.
##
## m: a TableBook-shaped match (NetMatch.m or a room-line match).
## Pure (no autoloads).
## code: none | proposed | agreed | dropped | push | owed | paid | unpaid

static func code(m: Dictionary) -> String:
	if m.is_empty():
		return "none"
	var state := String(m.get("stake_state", "agreed" if not BigInt.is_zero(m.get("stake", BigInt.zero())) else "none"))
	if state == "none" or state == "dropped":
		return state
	if m["status"] == "confirm":
		return "proposed"
	if m["status"] != "over":
		return "agreed"
	if m.get("push", false):
		return "push"
	match m.get("paid"):
		true: return "paid"
		false: return "unpaid"
	return "owed"


## The debt of a finished game with an agreed stake: {loser, winner, stake, end_block} or {}.
static func debt(m: Dictionary) -> Dictionary:
	var c := code(m)
	if not c in ["owed", "paid", "unpaid"]:
		return {}
	return {"match": m, "loser": m["loser"], "winner": m["winner"], "stake": m["stake"], "end_block": int(m.get("end_block", -1))}


## One line for the panel and the table, from `me`'s side.
static func text(m: Dictionary, me: String, display: Callable = Callable()) -> String:
	var nm := func(w: String) -> String:
		if w == me:
			return "you"
		return String(display.call(w)) if display.is_valid() else NetMatch.short(w)
	var amt := NetMatch.fmt(m.get("stake", BigInt.zero()))
	match code(m):
		"none":
			return "no stake"
		"dropped":
			return "played without a stake"
		"proposed":
			var ok: Array = m.get("stake_ok", [false, false])
			var waiting: Array = []
			for i in 2:
				if not ok[i]:
					waiting.append(nm.call(m["players"][i]))
			return "stake %s proposed · waiting for %s to confirm" % [amt, " and ".join(waiting)]
		"agreed":
			return "stake %s agreed (honour-bound: the loser pays the winner)" % amt
		"push":
			return "push: nobody owes the %s stake" % amt
		"owed":
			return "%s owes %s %s · checking the chain for the payment…" % [nm.call(m["loser"]), nm.call(m["winner"]), amt]
		"paid":
			return "✓ paid: %s → %s %s, Transfer in block %d" % [nm.call(m["loser"]), nm.call(m["winner"]), amt, int(m.get("paid_block", -1))]
		"unpaid":
			return "⚠ unpaid: %s owes %s %s (no Transfer on chain since block %s)" % [nm.call(m["loser"]), nm.call(m["winner"]), amt,
				str(m["end_block"]) if int(m.get("end_block", -1)) >= 0 else "—"]
	return "—"


## True when `me` lost a game with an agreed stake that the chain does not show paid.
static func i_owe(m: Dictionary, me: String) -> bool:
	return code(m) == "unpaid" and String(m["loser"]) == me
