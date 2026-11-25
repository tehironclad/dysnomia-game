class_name Prices
extends RefCounted
## The price table: every Ⓐ price the game shows or charges, in ONE place (whole Ⓐ; AFFECTION
## has 18 decimals). Change a number here and every label, button and transfer follows. Pure.
##
## Measured 2026-11-25: 1 Ⓐ ≈ 26.5 PLS on PulseX and one approval's gas ≈ 21 PLS, so a single
## play spends nearly half its cost on gas. A strip buys STRIP_PLAYS plays with one approval.
## What a transfer says it bought (the low wei) is TicketCode; this file is what it costs.
##
## Verification (FairBoard, ArcadePay.buy) asks covers(): the transfer paid at least today's price
## for what its code says. Lowering a price is always safe; RAISING one would make the boards drop
## tickets bought before the change: then keep the old price as the floor for older blocks.

const SYMBOL := "Ⓐ"
const UNIT_WEI := "1000000000000000000"

const PLAY := 1           ## one play: a fair stall, an arcade cabinet, a vehicle rental, a base jump
const STRIP_PLAYS := 10   ## a ticket strip: this many plays…
const STRIP := 10         ## …for this many Ⓐ, one approval (gas once)
const RIDE := 1           ## a fair ride (carousel, wheel, drop tower)
const ROCKET := 5         ## an Upsilon Rocket flight (the practice flight stays free)
const ROUND := 1          ## Sunny's round for the house
## Sunny's drinks, by drink id (BarTab.DRINKS): whole Ⓐ, paid to the QING before the drink's own call.
const DRINKS := {"pi_shot": 1, "rho_rocks": 1, "generator_lager": 1, "alpha_sour": 2, "beta_blocker": 2,
	"upsilon_fizz": 2, "house_su": 2}
## Each drink's item code in the low wei (TicketCode): the round is 20, the drinks 21….
const DRINK_ITEMS := {"house_round": 20, "pi_shot": 21, "rho_rocks": 22, "generator_lager": 23, "alpha_sour": 24,
	"beta_blocker": 25, "upsilon_fizz": 26, "house_su": 27}
## Wagers are the players' own (honour-bound, LEARNINGS §14); this only bounds what the UI accepts.
const WAGER_MAX := 1000


## `whole` Ⓐ in wei, as a decimal string.
static func wei(whole: int) -> String:
	return BigInt.to_decimal(BigInt.mul_small(BigInt.from_decimal(UNIT_WEI), whole))


## "10 Ⓐ"
static func text(whole: int) -> String:
	return "%s %s" % [TokenFormat.group(str(whole)), SYMBOL]


## Whole Ⓐ for one play of `item` (TicketCode items).
static func single(item: int) -> int:
	match item:
		TicketCode.ROCKET: return ROCKET
		TicketCode.ROUND: return ROUND
	for id in DRINK_ITEMS:
		if int(DRINK_ITEMS[id]) == item and DRINKS.has(id):
			return int(DRINKS[id])
	return PLAY


## Whole Ⓐ for `plays` plays of `item` bought at once: one play at its single price, a strip
## at the strip's rate (STRIP for STRIP_PLAYS; other sizes pro rata, rounded down).
static func price(item: int, plays: int) -> int:
	if plays <= 1:
		return single(item)
	return STRIP * plays / STRIP_PLAYS


## The transfer amount (wei, decimal) for that purchase: the price + its code (TicketCode).
static func ticket_wei(item: int, plays: int = 1) -> String:
	return TicketCode.encode(item, plays, price(item, plays))


## Did the decoded transfer pay at least today's price for what its code says?
static func covers(d: Dictionary) -> bool:
	if not d.get("ok", false):
		return false
	var need := BigInt.from_decimal(wei(price(int(d["item"]), int(d["plays"]))))
	return BigInt.cmp(d["whole"], need) >= 0


## Labels used wherever a price is shown.
static func play_text() -> String:
	return text(PLAY)


static func strip_text() -> String:
	return text(STRIP)


static func play_button() -> String:
	return "Play 1 · %s" % play_text()


static func strip_button() -> String:
	return "Strip of %d · %s (gas once)" % [STRIP_PLAYS, strip_text()]


## "1 Ⓐ a play · strip of 10: 10 Ⓐ"
static func menu_line() -> String:
	return "%s a play · strip of %d: %s" % [play_text(), STRIP_PLAYS, strip_text()]


static func drink(id: String) -> int:
	if id == "house_round":
		return ROUND
	return int(DRINKS.get(id, 0))


static func drink_wei(id: String) -> String:
	var w := drink(id)
	return TicketCode.encode(int(DRINK_ITEMS.get(id, 0)), 1, w) if w > 0 else "0"


## A player's wager text ("5", "0.25", "2.5 Ⓐ") → {ok, wei (BigInt), why}. Up to 18 decimals,
## more than 0, at most WAGER_MAX. For the tables and invites (another module posts it).
static func wager_wei(s: String) -> Dictionary:
	var t := s.strip_edges().trim_suffix(SYMBOL).strip_edges()
	if t == "" or not t.is_valid_float() or t.begins_with("-") or t.contains("e") or t.contains("E"):
		return {"ok": false, "wei": BigInt.zero(), "why": "a wager is a number of %s, like 5 or 0.25" % SYMBOL}
	var parts := t.split(".")
	if parts.size() > 2 or (parts.size() == 2 and parts[1].length() > 18):
		return {"ok": false, "wei": BigInt.zero(), "why": "at most 18 decimals"}
	var digits := (parts[0] + (parts[1] if parts.size() > 1 else "").rpad(18, "0")).lstrip("0")
	var w := BigInt.from_decimal(digits if digits != "" else "0")
	if BigInt.is_zero(w):
		return {"ok": false, "wei": w, "why": "a wager is more than 0 %s" % SYMBOL}
	if BigInt.cmp(w, BigInt.from_decimal(wei(WAGER_MAX))) > 0:
		return {"ok": false, "wei": w, "why": "at most %s" % text(WAGER_MAX)}
	return {"ok": true, "wei": w, "why": ""}


## "2.5 Ⓐ"
static func wager_text(w: PackedInt64Array) -> String:
	return "%s %s" % [TokenFormat.wei_to_tokens(w, 18, 18), SYMBOL]
