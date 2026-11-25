class_name RaveStyle
extends RefCounted
## How a territory's arcade parties: the blacklight palette, the track (tempo, key, groove) and the
## people (the DJ's head, the crowd's looks), all from the territory's own state (its address and
## entropy through its Deep Field emblem). Never from the viewer: everyone who walks in sees and hears
## the same party. Pure: no network, no nodes.

## UV blacklight violet: the light the paint glows under.
const BLACKLIGHT := Color(0.42, 0.16, 1.0)
const FLOOR_PATTERNS := ["checker", "ripple", "sparkle", "bars"]
const WALL_PATTERNS := ["stripes", "splatter", "hypobar", "circuit"]
const DJ_HEADS := ["fox", "cat", "robot", "alien", "frog", "bird", "skull", "ape", "rat", "dog", "bear", "hamster", "pig"]
const CROWD_HEADS := ["bear", "rat", "alien", "frog", "dog", "cat", "robot", "hamster", "fox", "pig", "ape", "bird", "skull", "human"]


## The style for a Registry territory record ({address, entropy, name…}); a fixed fallback for {}.
static func for_territory(territory: Dictionary) -> Dictionary:
	var addr := String(territory.get("address", "")).to_lower()
	if addr == "" or not territory.has("entropy"):
		return make(Color(0.3, 0.85, 1.0), Color(1.0, 0.3, 0.75), 0x5EED)
	var p := DeepField.for_territory(territory)
	return make(DeepField.to_color(p["color"]), DeepField.to_color(p["color2"]), Outfits.hash32(addr), int(p.get("arms", 3)))


## The style from the emblem's two colours and a 32-bit seed (the address hash).
static func make(c1: Color, c2: Color, seed_value: int, arms: int = 3) -> Dictionary:
	var h := seed_value & 0xffffffff
	var uv1 := fluoro(c1)
	var uv2 := fluoro(c2)
	# A third paint opposite the first, unless it lands on the second's hue.
	var h3 := fposmod(uv1.h + 0.5, 1.0)
	if absf(wrapf(h3 - uv2.h, -0.5, 0.5)) < 0.12:
		h3 = fposmod(h3 + 0.25, 1.0)
	var uv3 := Color.from_hsv(h3, 0.9, 1.0)
	return {
		"uv": [uv1, uv2, uv3],
		"blacklight": BLACKLIGHT,
		"bpm": 120 + (h % 9),  ## 120–128: a club tempo
		"root": (h >> 4) % 12,  ## the key's root, semitones above A
		"groove": (h >> 8) % 4,  ## which arp and bass patterns
		"floor": FLOOR_PATTERNS[(h >> 12) % FLOOR_PATTERNS.size()],
		"wall": WALL_PATTERNS[(h >> 14) % WALL_PATTERNS.size()],
		"lasers": 6 + 2 * (clampi(arms, 2, 9) % 4),  ## 6–12 beams: the emblem's arms
		"dj_head": DJ_HEADS[(h >> 16) % DJ_HEADS.size()],
		"crowd_seed": (h >> 6) & 0xffffff,
	}


## A colour as fluorescent paint under blacklight: its hue, saturated and bright.
static func fluoro(c: Color) -> Color:
	return Color.from_hsv(c.h, clampf(maxf(c.s, 0.75), 0.0, 0.95), 1.0)


## The crowd's people (n of them): [{head, outfit: {kind, seed}, body}], from the style's seed.
static func crowd(style: Dictionary, n: int) -> Array:
	var out: Array = []
	var s := int(style.get("crowd_seed", 1))
	for i in n:
		var h := Outfits.hash32("rave:%d:%d" % [s, i])
		out.append({
			"head": CROWD_HEADS[h % CROWD_HEADS.size()],
			"outfit": Outfits.for_npc(s + i * 7919),
			"body": "female" if (h >> 9) & 1 else "male",
			"phase": float((h >> 12) % 1000) / 1000.0,
		})
	return out
