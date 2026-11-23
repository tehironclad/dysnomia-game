class_name AttractionCatalog
## Everything a visitor can spend on inside a QING, in one place.
##
## Two kinds of purchase, both settled on-chain through AffectionEconomy:
##   "ticket" — an AFFECTION (ERC-20) transfer from the visitor to the QING's keeper
##              (the territory owner). This is "paying affection to the QING".
##   "op"     — the visitor's own AFFECTION contract call (Pi/Rho/Generate/Alpha/Beta/Upsilon),
##              the same calls the Monument terraform panel sends. These are what move
##              the visitor's per-QING YUE bars (Hypobar/Epibar); the game re-reads the
##              bars after confirmation and reports the measured change, never a guess.
##
## Prices are AFFECTION in whole or decimal units (strings, converted with the token's
## on-chain decimals). Tune them here — nothing else hardcodes a price.

const KIND_TICKET := "ticket"
const KIND_OP := "op"

const RIDES := {
	"rocket": {
		"id": "rocket", "kind": KIND_TICKET, "price": "1",
		"name": "Upsilon Rocket",
		"blurb": "Strapped into a glass capsule and fired 400 m straight up. Free-fall view of the whole QING, then a parachute ride home.",
		"duration": 55.0,
	},
	"wheel": {
		"id": "wheel", "kind": KIND_TICKET, "price": "1",
		"name": "Rho Wheel",
		"blurb": "A slow orbit in a lantern gondola, 30 m over the fairground. Best at dusk.",
		"duration": 48.0,
	},
	"drop": {
		"id": "drop", "kind": KIND_TICKET, "price": "1",
		"name": "Pi Drop Tower",
		"blurb": "Hauled 51 m up the 55 m tower, held at the top for a heartbeat, then dropped in low gravity.",
		"duration": 30.0,
	},
	"carousel": {
		"id": "carousel", "kind": KIND_TICKET, "price": "1",
		"name": "Orbital Carousel",
		"blurb": "Ride a rocket-sled round the orrery while the planets turn overhead.",
		"duration": 32.0,
	},
}

## Community media boards — one at each wing of a QING. A post stays up 24 h.
const BOARD := {
	"id": "board", "kind": KIND_TICKET, "price": "1",
	"name": "Media Board · 24 h",
	"blurb": "Put your picture and a caption on this wing's board for 24 hours. Paid to the QING keeper; verified on-chain by every visitor.",
}

## The bar menu. Every "op" drink is a real AFFECTION call made by the visitor.
const DRINKS := [
	{"id": "pi_shot", "kind": KIND_OP, "op": "pi", "price": "0",
		"name": "Pi Shot", "blurb": "AFFECTION.Pi() — neat. Irrational, never ends."},
	{"id": "rho_rocks", "kind": KIND_OP, "op": "rho", "price": "0",
		"name": "Rho on the Rocks", "blurb": "AFFECTION.Rho() over regolith ice."},
	{"id": "generator_lager", "kind": KIND_OP, "op": "generate", "price": "0",
		"name": "Generator Lager", "blurb": "AFFECTION.Generate() — the house pour."},
	{"id": "alpha_sour", "kind": KIND_OP, "op": "alpha", "price": "0",
		"name": "Alpha Sour", "blurb": "AFFECTION.Alpha(seed) — shaken with your lucky number."},
	{"id": "beta_blocker", "kind": KIND_OP, "op": "beta", "price": "0",
		"name": "Beta Blocker", "blurb": "AFFECTION.Beta(seed) — steadies the bars."},
	{"id": "upsilon_fizz", "kind": KIND_OP, "op": "upsilon", "price": "0",
		"name": "Upsilon Fizz", "blurb": "AFFECTION.Upsilon(seed, phi) — served with a twist of phi."},
	{"id": "house_round", "kind": KIND_TICKET, "price": "1",
		"name": "Round for the House", "blurb": "Tip 1 AFFECTION to this QING's keeper. Everyone in the bar cheers."},
]


static func ride(id: String) -> Dictionary:
	return RIDES.get(id, {})


static func drink(id: String) -> Dictionary:
	for d in DRINKS:
		if d["id"] == id:
			return d
	return {}


static func price_label(item: Dictionary) -> String:
	if item.get("kind", "") == KIND_OP:
		return "gas only"
	return "%s AFFECTION" % item.get("price", "0")
