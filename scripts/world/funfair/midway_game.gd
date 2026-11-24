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
		"how": "The power meter swings. Swing the mallet at the top of it: the puck flies up the 7 m pole and rings the bell. Three swings."},
	"entropy": {"title": "ENTROPY TOSS", "mech": "toss",
		"how": "Aim with the mouse, toss when the power meter is right. The entropy drift pushes every puck sideways: allow for it. Three pucks onto the rings."},
	"regolith": {"title": "REGOLITH RING TOSS", "mech": "rings",
		"how": "Aim at a peg with the mouse; your hand sways, so throw when the sight sits on the peg. Five rings."},
	"crystal": {"title": "CRYSTAL SHY", "mech": "shy",
		"how": "Crystals slide along two rails. Aim (mouse up for the high rail) and lead them: the ball takes a moment to get there. Eight balls."},
	"motzkin": {"title": "MOTZKIN PRIME SHOOTER", "mech": "primes",
		"how": "Numbers pop up for 30 seconds. Shoot only the primes (+100); a number that isn't prime costs 50. Fifteen shots."},
	"waat": {"title": "WAAT WHEEL OF FORTUNE", "mech": "wheel",
		"how": "The wheel spins at a speed from your ticket. Brake: it always slows the same way, so time it. Three spins."},
	"saat": {"title": "SAAT FORTUNE TELLER", "mech": "fortune",
		"how": "The teller lays three cards from your ticket's transaction hash. Turn them one by one."},
}

const PRIZES := [
	[0.85, "GRAND PRIZE · an Upsilon toy rocket"],
	[0.6, "a crystal plush moon"],
	[0.35, "a glow-stick of Eris ice"],
	[0.0, "a paper Dysnomia pennant"],
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


## The best score a game allows (for the prize fraction).
static func max_score(id: String) -> int:
	return MidwaySim.max_score(id)


static func prize(id: String, score: int) -> String:
	var m := max_score(id)
	if m <= 0:
		return ""
	var f := clampf(float(score) / m, 0.0, 1.0)
	for p in PRIZES:
		if f >= float(p[0]):
			return String(p[1])
	return String(PRIZES[-1][1])


static func fortune(seed_v: int) -> String:
	return FORTUNES[absi(seed_v) % FORTUNES.size()]
