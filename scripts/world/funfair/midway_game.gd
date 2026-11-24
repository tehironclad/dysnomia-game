class_name MidwayGame
extends RefCounted
## The Affection Fair's midway games: titles, how to play, seeding and prizes. The rules
## themselves are MidwaySim (pure, integer, replayable); the 3D is MidwayStage. No network here.
##
## A paid round is seeded by its own ticket: the AFFECTION.transfer tx hash that
## ArcadePay verified in the receipt, so the targets, numbers and wheel come from
## the chain, not from this computer. A practice round (no wallet) is seeded
## locally and says so. Scores go on this computer's board (ArcadeScores) and, if the player
## posts them, on the room's verified board (FairBoard). One button plus the mouse; prizes
## are bragging rights.

const GAMES := {
	"striker": {"title": "TEST YOUR AFFECTION", "mech": "striker",
		"how": "Swing at the top of the meter: the puck rings the bell. Five swings, each meter faster. Bells in a row multiply; the last swing is a FRENZY (×2).",
		"tips": ["Click at the TOP of the meter", "Ring it in a row: ×2, ×3", "Dead top = PERFECT (150)"]},
	"entropy": {"title": "ENTROPY TOSS", "mech": "toss",
		"how": "Aim with the mouse, toss when the power meter is right; the drift pushes every puck sideways. From the third puck the rings slide. Bullseye = 150.",
		"tips": ["Mouse: aim · the meter sets distance", "Allow for the drift arrow", "Lead the sliding rings"]},
	"regolith": {"title": "REGOLITH RING TOSS", "mech": "rings",
		"how": "Aim at a peg; your hand sways more every ring, so throw when the sight sits on it. The GOLD peg pays double. Six rings.",
		"tips": ["Mouse / WASD: aim at a peg", "Throw when the sight is still", "The gold peg pays double"]},
	"crystal": {"title": "CRYSTAL SHY", "mech": "shy",
		"how": "Crystals slide along two rails, faster with every one you smash. Aim (up: the high rail) and lead them. Gold crystals pay 250. Eight balls.",
		"tips": ["Mouse up: the high rail", "Lead them: the ball takes a moment", "Gold crystals: 250"]},
	"motzkin": {"title": "MOTZKIN PRIME SHOOTER", "mech": "primes",
		"how": "Numbers pop up for 30 seconds. Shoot only the primes: a chain of primes multiplies (up to ×4), a non-prime costs 50 and breaks it. Mersenne primes (3, 7, 31) pay 250. The last 8 s are a FRENZY.",
		"tips": ["Shoot PRIMES only", "Chain them: up to ×4", "Gold 3 · 7 · 31 = 250"]},
	"waat": {"title": "WAAT WHEEL OF FORTUNE", "mech": "wheel",
		"how": "The wheel spins faster every time. Brake: it always slows the same way, so time it to land the 500. Five spins; 100+ in a row multiplies.",
		"tips": ["Click to brake", "It always slows the same way", "Land 500 for the JACKPOT"]},
	"saat": {"title": "SAAT FORTUNE TELLER", "mech": "fortune",
		"how": "Higher or lower? The teller lays a card from your ticket; guess the next one. Seven guesses, right ones in a row multiply (up to ×5). Then she reads your fortune.",
		"tips": ["Mouse left: LOWER · right: HIGHER", "Right in a row: up to ×5", "Ace low, King high"]},
}

## Prize tiers: [fraction of the game's par, kind (FairPrizes), text]. A score of 0 wins nothing.
const PRIZES := [
	[1.0, "trophy", "GRAND PRIZE · a crystal trophy"],
	[0.65, "rocket", "a toy Upsilon rocket"],
	[0.35, "moon", "a plush moon"],
	[0.0, "pennant", "a paper Dysnomia pennant"],
]

const FORTUNES := [
	"A Su you skip today becomes a tower you never climb.",
	"Your Hypobar is a floor, never a ceiling.",
	"The QING remembers every Ⓐ; so should you.",
	"A neighbour across the force field is waiting for your Join.",
	"Entropy favours the one who reacts first.",
	"The Void answers those who speak in it.",
	"Your next block is closer than your last.",
	"What the chain records, no one can take away.",
	"Bars never shrink. Neither should you.",
	"Fornax rises for the patient.",
	"The Capital was a Wild lot once.",
	"Somewhere a Motzkin prime has your name on it.",
]


static func has_game(id: String) -> bool:
	return GAMES.has(id)


static func title(id: String) -> String:
	return String(GAMES.get(id, {}).get("title", id.to_upper()))


## A 31-bit seed from a tx hash ("0x…64 hex"); 0 if it isn't one.
static func seed_from_tx(tx: String) -> int:
	var h := tx.to_lower().trim_prefix("0x")
	if h.length() < 8 or not h.is_valid_hex_number():
		return 0
	return h.right(8).hex_to_int() & 0x7fffffff


static func is_prime(n: int) -> bool:
	return MidwaySim.is_prime(n)


## The best score a game allows (the rules' bound).
static func max_score(id: String) -> int:
	return MidwaySim.max_score(id)


## The prize tier for a score: [fraction, kind, text], or [] for none (a score of 0).
static func prize_tier(id: String, score: int) -> Array:
	var par := MidwaySim.par(id)
	if par <= 0 or score <= 0:
		return []
	var f := float(score) / par
	for p in PRIZES:
		if f >= float(p[0]):
			return p
	return PRIZES[-1]


static func prize(id: String, score: int) -> String:
	var t := prize_tier(id, score)
	return String(t[2]) if not t.is_empty() else ""


static func prize_kind(id: String, score: int) -> String:
	var t := prize_tier(id, score)
	return String(t[1]) if not t.is_empty() else ""


static func fortune(seed_v: int) -> String:
	return FORTUNES[absi(seed_v) % FORTUNES.size()]
