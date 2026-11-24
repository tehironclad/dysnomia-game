class_name ArcadeCatalog
extends RefCounted
## Everything an arcade cabinet can run.
##
## Each entry: {id, title, blurb, script, kind: "game" | "cartridge", playable, [cart, cart_type], [world]}.
##   - world: the ArcadeWorld you dive into (scripts/arcade/dive/); without one the dive shows the
##     cabinet's own screen full-size in a CRT bezel (every cartridge).
##   - kind "game": `load(script).new()` is a ready ArcadeGame.
##   - kind "cartridge": script is folklore_cart.gd; the cabinet MUST call `load_cart(cart)` on the
##     new node before `start(seed)` / `attract()`. Sprite cartridges (cart_type "sprite") are art
##     pieces for attract mode only (`playable: false`); game cartridges are playable.
## Cartridge titles and themes come from assets/arcade/cartridges/manifest.json.

const CART_DIR := "res://assets/arcade/cartridges/"
const CART_SCRIPT := "res://scripts/arcade/folklore_cart.gd"

const GAMES := [
	{
		"id": "entropy_drift", "title": "Entropy Drift",
		"blurb": "Steer the probe, grab gold Fornax motes, dodge shards. Fire: pulse.",
		"script": "res://scripts/arcade/entropy_drift.gd",
		"world": "res://scripts/arcade/dive/entropy_drift_world.gd",
	},
	{
		"id": "void_lanes", "title": "Void Lanes",
		"blurb": "Catch true chat lines; dodge or flag the imposters. Fire: flag.",
		"script": "res://scripts/arcade/void_lanes.gd",
		"world": "res://scripts/arcade/dive/void_lanes_world.gd",
	},
	{
		"id": "bar_raiser", "title": "Bar Raiser",
		"blurb": "Hold fire to grow the Hypobar; release on the gold Epibar mark.",
		"script": "res://scripts/arcade/bar_raiser.gd",
		"world": "res://scripts/arcade/dive/bar_raiser_world.gd",
	},
]


## The three games, then every Folklore cartridge in the manifest (games before sprites).
static func games() -> Array:
	var out: Array = []
	for g in GAMES:
		var e: Dictionary = g.duplicate()
		e["kind"] = "game"
		e["playable"] = true
		out.append(e)
	var carts := cartridges()
	for want in ["game", "sprite"]:
		for c in carts:
			if c["cart_type"] == want:
				out.append(c)
	return out


## Only the entries a paid credit can start.
static func playable() -> Array:
	return games().filter(func(e): return e["playable"])


static func find(id: String) -> Dictionary:
	for e in games():
		if e["id"] == id:
			return e
	return {}


## Cartridge entries from the manifest (empty if it can't be read).
static func cartridges() -> Array:
	var out: Array = []
	var f := FileAccess.open(CART_DIR + "manifest.json", FileAccess.READ)
	if f == null:
		return out
	var j = JSON.parse_string(f.get_as_text())
	if not (j is Dictionary) or not (j.get("cartridges") is Array):
		return out
	for c in j["cartridges"]:
		if not (c is Dictionary) or not c.has("file"):
			continue
		var cart_type := String(c.get("type", "sprite"))
		out.append({
			"id": "cart_" + String(c.get("id", "")).replace("-", "_"),
			"title": String(c.get("title", c["file"])),
			"blurb": String(c.get("theme", "")),
			"script": CART_SCRIPT,
			"kind": "cartridge",
			"cart": CART_DIR + String(c["file"]),
			"cart_type": cart_type,
			"playable": cart_type == "game",
		})
	return out
