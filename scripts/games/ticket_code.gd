class_name TicketCode
extends RefCounted
## What an AFFECTION.transfer to a QING bought, written in its own amount, so the chain says it
## (LEARNINGS §14 "Ticket strips"). Pure: no network.
##
##   value = A Ⓐ (the price, whole Ⓐ) + c wei,  c < MAX_CODE (10,000)
##   c = item                  c < 100: ONE play (every ticket sold before strips; unchanged)
##   c = plays × 100 + item    plays 2..99: a STRIP of that many plays, one transfer, gas once
##
## Items: 0 general (a plain N Ⓐ: arcade credit, ride, rental, jump), 1..7 the fair's games
## (MidwaySim.code: striker 1 … saat 7), 8 any fair game (strips), 9 the Upsilon Rocket flight,
## 10 arcade cabinets (strips), 20 a round for the house, 21.. Sunny's drinks (Prices.DRINK_ITEMS).
##   1 Ⓐ + 3 wei       one Regolith Ring Toss ticket (the coded ticket since 2026-11-24)
##   10 Ⓐ + 1003 wei   a strip of 10 Regolith Ring Toss plays
##   10 Ⓐ + 1008 wei   a strip of 10 plays of any fair game
##   10 Ⓐ + 1010 wei   a strip of 10 arcade plays
##   5 Ⓐ + 9 wei       an Upsilon Rocket flight
## What it must cost is Prices (Prices.covers); this file only reads and writes the code.
##
## Play i (0-based) of a strip is seeded by seed_tx(tx, i) = "0x" + SHA-256("<tx>#<i>") (tx in
## lower case), so every play replays from the chain; a single ticket is seeded by its own tx hash.

const GENERAL := 0
const FAIR_ANY := 8
const ROCKET := 9
const ARCADE := 10
const ROUND := 20
const MAX_CODE := 10000
const MAX_PLAYS := 99
const UNIT := "1000000000000000000"
## The fair games by code (MidwaySim.code; FairProgress.ORDER). Kept here so this pure class never
## pulls in a class that uses autoloads (tools parse it before the autoloads exist).
const FAIR_GAMES := ["striker", "entropy", "regolith", "crystal", "motzkin", "waat", "saat"]


## The wei for `whole` Ⓐ carrying item and plays: a decimal string (for Abi / ArcadePay).
static func encode(item: int, plays: int, whole: int) -> String:
	assert(item >= 0 and item < 100 and plays >= 1 and plays <= MAX_PLAYS and whole >= 0)
	var c := item if plays <= 1 else plays * 100 + item
	return BigInt.to_decimal(BigInt.add(BigInt.mul_small(BigInt.from_decimal(UNIT), whole), BigInt.from_int(c)))


## {ok, whole (BigInt wei of the whole-Ⓐ part), whole_n (int Ⓐ, -1 if huge), item, plays, code, strip}.
## ok false (item -1) when the low wei isn't a code (≥ MAX_CODE, or 100..199: one play is written c < 100).
static func decode(value: PackedInt64Array) -> Dictionary:
	var qr := BigInt.divmod(value, BigInt.from_decimal(UNIT))
	var low: PackedInt64Array = qr[1]
	var whole_wei := BigInt.sub(value, low)
	var whole_n := BigInt.to_int(qr[0]) if BigInt.fits_int(qr[0]) else -1
	var c := BigInt.to_int(low) if BigInt.fits_int(low) else MAX_CODE
	var out := {"ok": false, "whole": whole_wei, "whole_n": whole_n, "item": -1, "plays": 0, "code": c, "strip": false}
	if c >= MAX_CODE or (c >= 100 and c < 200):
		return out
	out["ok"] = true
	out["item"] = c % 100
	out["plays"] = 1 if c < 100 else c / 100
	out["strip"] = c >= 200
	return out


static func decode_decimal(wei: String) -> Dictionary:
	return decode(BigInt.from_decimal(wei))


## The fair game codes (1..7) a ticket item can be played at: its own game, or any for FAIR_ANY.
static func is_fair(item: int) -> bool:
	return item >= 1 and item <= FAIR_ANY


## May a play of ticket `item` be used at fair game `game_code`?
static func fits_game(item: int, game_code: int) -> bool:
	return item == game_code or item == FAIR_ANY


## The hex string a play is seeded from: the tx itself for a single ticket (index < 0), else
## "0x" + SHA-256("<tx lower case>#<index>"). Feed it to MidwayGame / ArcadeWorld.seed_from_tx.
static func seed_tx(tx: String, index: int = -1) -> String:
	if index < 0:
		return tx.to_lower()
	return "0x" + ("%s#%d" % [tx.to_lower(), index]).sha256_text()


## One play's identity: "<tx>#<index>" (index -1 = a single ticket). A play counts once.
static func play_key(tx: String, index: int) -> String:
	return "%s#%d" % [tx.to_lower(), index]


## Is `index` a valid play of a ticket with `plays` plays? Singles take no index (-1).
static func index_ok(plays: int, index: int) -> bool:
	if plays <= 1:
		return index == -1
	return index >= 0 and index < plays


static func item_text(item: int) -> String:
	match item:
		GENERAL: return "a play"
		FAIR_ANY: return "any fair game"
		ROCKET: return "the Upsilon Rocket"
		ARCADE: return "the arcade cabinets"
		ROUND: return "a round for the house"
	if item >= 1 and item <= 7:
		return MidwayGame.title(FAIR_GAMES[item - 1]).capitalize()
	if item > ROUND and item < 100:
		return "a drink"
	return "—"
