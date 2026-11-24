class_name Outfits
## What avatars wear: the outfit designs (garment parts from Quaternius'
## Modular Character Outfits – Fantasy, CC0, re-coloured for the Field by
## outfit.gdshader, plus tailored pieces from OutfitTailor) and the
## deterministic choice for an identity.
##
## Everyone sees the same outfit for a player: it comes from their wallet
## address alone (`for_identity`), never from the viewer. A player may pick
## another design for themselves on this machine (`local_choice`); that is
## their own choice and only their own screen shows it until the network
## carries it (HumanAvatar.set_outfit is the hook: call it with the synced
## kind instead of wear_identity).

const LOCAL_PATH := "user://identity.cfg"

const KINDS := ["pilot", "longcoat", "hoodie", "flightsuit", "robe", "street", "formal", "overalls"]
const LABELS := {
	"pilot": "Pilot jacket", "longcoat": "Long coat", "hoodie": "Hoodie and cargos", "flightsuit": "Flight suit",
	"robe": "Void robe", "street": "Street", "formal": "Formal suit", "overalls": "Work overalls",
}

## Garment parts per body: file stems in assets/characters/outfits/ (without
## the Male_/Female_ prefix). A part's role follows its name: *_Legs are worn
## below the waist, *_Feet* are footwear, *_Hood and *_Pauldron* take the
## accent colour; everything else is the top.
## `skip`: meshes left out (by a substring of their name).
## `extras`: tailored pieces (OutfitTailor): coat_long, coat_short, robe,
## collar, fur_collar, hood_down, tie, sash, bands, bib.
const DESIGNS := {
	"pilot": {
		"male": ["Ranger_Body", "Ranger_Arms", "Peasant_Legs", "Peasant_Feet"],
		"female": ["Ranger_Body", "Ranger_Arms", "Peasant_Legs", "Peasant_Feet"],
		"skip": ["Bracer"], "extras": ["fur_collar"],
	},
	"longcoat": {
		"male": ["Ranger_Body", "Ranger_Arms", "Ranger_Legs", "Peasant_Feet"],
		"female": ["Ranger_Body", "Ranger_Arms", "Ranger_Legs", "Peasant_Feet"],
		"skip": ["Bracer", "Belt_2"], "extras": ["coat_long", "collar"],
	},
	"hoodie": {
		"male": ["Peasant_Body", "Ranger_Arms", "Peasant_Legs", "Peasant_Feet"],
		"female": ["Peasant_Body", "Ranger_Arms", "Peasant_Legs", "Peasant_Feet"],
		"skip": ["Bracer"], "extras": ["hood_down"],
	},
	"flightsuit": {
		"male": ["Ranger_Body", "Ranger_Arms", "Ranger_Legs", "Ranger_Feet_Boots"],
		"female": ["Ranger_Body", "Ranger_Arms", "Ranger_Legs", "Ranger_Feet"],
		"skip": ["Bracer"], "extras": ["collar", "bands"],
	},
	"robe": {
		"male": ["Peasant_Body", "Ranger_Arms", "Peasant_Legs", "Peasant_Feet", "Ranger_Head_Hood"],
		"female": ["Peasant_Body", "Peasant_Arms", "Peasant_Legs", "Peasant_Feet", "Ranger_Head_Hood"],
		"skip": ["Bracer"], "extras": ["robe", "sash"],
	},
	"street": {
		"male": ["Peasant_Body", "Peasant_Arms", "Peasant_Legs", "Peasant_Feet"],
		"female": ["Peasant_Body", "Peasant_Arms", "Peasant_Legs", "Peasant_Feet"],
		"skip": [], "extras": [],
	},
	"formal": {
		"male": ["Ranger_Body", "Ranger_Arms", "Peasant_Legs", "Peasant_Feet"],
		"female": ["Ranger_Body", "Ranger_Arms", "Peasant_Legs", "Peasant_Feet"],
		"skip": ["Bracer", "Belt_1", "Belt_2"], "extras": ["coat_short", "collar", "tie"],
	},
	"overalls": {
		"male": ["Peasant_Body", "Peasant_Arms", "Peasant_Legs", "Ranger_Feet_Boots"],
		"female": ["Peasant_Body", "Peasant_Arms", "Peasant_Legs", "Ranger_Feet"],
		"skip": [], "extras": ["bib", "bands"],
	},
}

## Colour slots (outfit.gdshader): main (the top), light (shirts, linings),
## bottom (trousers), leather (straps, belts), boots, metal (buckles), accent
## (hoods, collars, coats' facings). Muted Deep Field tones with one accent each.
const PALETTES := {
	"pilot": [
		["#4a3a2a", "#d8cbb4", "#2b2e36", "#2a1f17", "#17171b", "#9aa0aa", "#e6dcc8"],
		["#2c3a2c", "#c9c2a8", "#23262d", "#3b2a1c", "#141417", "#a5a9b0", "#d9cfb6"],
		["#1c2333", "#b9c2d6", "#2a2a30", "#151820", "#101014", "#b8bcc6", "#cfd6e6"],
		["#3d1f22", "#d9c2b0", "#252529", "#24161a", "#121215", "#b39b6c", "#e8d8c0"],
	],
	"longcoat": [
		["#1d1e24", "#6a6f7c", "#22232a", "#141418", "#0f0f12", "#a7aab3", "#3b3f4b"],
		["#3a1e24", "#a3868a", "#1e1d22", "#24131a", "#120f11", "#b59a6a", "#55303a"],
		["#1b2438", "#8b98b4", "#1f222b", "#141a28", "#0f1015", "#9ba6bb", "#2b3754"],
		["#6b5236", "#d1bd9a", "#2a2621", "#3b2c1d", "#18130f", "#b8a27a", "#8a6b47"],
	],
	"hoodie": [
		["#3a3f4c", "#4a5060", "#3b4234", "#2a2a2a", "#d7d7d2", "#9aa0aa", "#3a3f4c"],
		["#5b2a6e", "#6e3a82", "#2c2d33", "#232323", "#e2e0dc", "#a0a4ae", "#5b2a6e"],
		["#1f5a5e", "#2b6e72", "#40382c", "#2a241e", "#1b1b1e", "#a0a4ae", "#1f5a5e"],
		["#8a2b2b", "#a03838", "#262a33", "#222222", "#e6e4df", "#a0a4ae", "#8a2b2b"],
		["#c9c5bd", "#dcd8d0", "#2f3440", "#2b2b2b", "#202024", "#a0a4ae", "#c9c5bd"],
	],
	"flightsuit": [
		["#c8581c", "#e0e0dc", "#c8581c", "#3a2b22", "#1c1c20", "#b9bcc4", "#e8e4dc"],
		["#d9dbe0", "#f0f0f2", "#d9dbe0", "#3d4250", "#26272d", "#9aa3b5", "#4a5a7a"],
		["#4b5537", "#b7b59a", "#4b5537", "#2c2a20", "#1a1a16", "#a2a29a", "#c9c6ae"],
		["#2b3f6b", "#c6cee0", "#2b3f6b", "#1c2030", "#15161b", "#b8bec9", "#d8dde8"],
		["#2a2b30", "#8f94a3", "#2a2b30", "#18191d", "#111114", "#c0c4cc", "#7c8496"],
	],
	"robe": [
		["#231635", "#3a2a55", "#1a1424", "#120c1a", "#0e0b12", "#a68ccf", "#2d1d45"],
		["#0e0f14", "#2a2c36", "#101116", "#0b0b0e", "#08080a", "#8f9bb8", "#16171f"],
		["#141c33", "#2b3a5e", "#11162a", "#0b0f1c", "#090b12", "#9fb0d8", "#1c2747"],
		["#cfcbc2", "#e8e4dc", "#b9b4aa", "#6b6458", "#3b3832", "#c9b98a", "#e0dbd0"],
	],
	"street": [
		["#2e3a55", "#e8e6e0", "#33415c", "#3a2c22", "#e9e7e2", "#a0a4ae", "#e8e6e0"],
		["#7a3b2e", "#e0c9a8", "#1f2633", "#2c211a", "#1d1d21", "#a0a4ae", "#e0c9a8"],
		["#2b2b30", "#d9476e", "#2e3440", "#1e1e22", "#e6e4df", "#a0a4ae", "#d9476e"],
		["#3f5b3a", "#efe6cf", "#7c6a4c", "#3a2c1f", "#2a2420", "#a0a4ae", "#efe6cf"],
		["#5a4a7a", "#c7f0e6", "#26262c", "#232026", "#d8d8d8", "#a0a4ae", "#c7f0e6"],
	],
	"formal": [
		["#18191e", "#ecebe6", "#18191e", "#101014", "#0b0b0d", "#c9a24a", "#7a1f2b"],
		["#1b2236", "#e9eaee", "#1b2236", "#11151f", "#0c0d10", "#b8bcc6", "#3b6fb6"],
		["#3a3d45", "#f0eee8", "#3a3d45", "#24262b", "#121214", "#c0c4cc", "#2d2f35"],
		["#3a1820", "#ece6dc", "#2a1a1e", "#22101a", "#100b0d", "#c9a24a", "#c9a24a"],
		["#e6e1d6", "#3a3a3e", "#e6e1d6", "#bdb6a6", "#2a2620", "#c9a24a", "#2a2a2e"],
	],
	"overalls": [
		["#d96a1c", "#cfd3d8", "#d96a1c", "#3a2c22", "#2a221c", "#b0b4bc", "#3a3c42"],
		["#d6c21e", "#3a3c42", "#d6c21e", "#2e2a20", "#262019", "#b0b4bc", "#2a2c30"],
		["#26406b", "#d8d2c2", "#26406b", "#3a2c22", "#2a221c", "#b0b4bc", "#d96a1c"],
		["#55595f", "#e0ddd5", "#55595f", "#2e2a26", "#1f1c19", "#b0b4bc", "#d6c21e"],
	],
}
const SLOTS := ["main", "light", "bottom", "leather", "boots", "metal", "accent"]

## Skin tones multiplied into the hands' texture (and the neck).
const SKIN_TONES := ["#f1d0b5", "#e0b391", "#c68e68", "#9c6a48", "#6e4a33", "#4a3124"]
## NPC crowds lean casual; players draw from every design equally.
const CROWD := ["street", "street", "hoodie", "hoodie", "overalls", "pilot", "longcoat", "formal", "flightsuit", "robe"]


## 32-bit FNV-1a of the lowercase key: the same on every machine and build.
static func hash32(key: String) -> int:
	var h := 0x811c9dc5
	for b in key.to_lower().strip_edges().to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & 0xffffffff
	return h


## The outfit an identity wears for everyone: {kind, seed}. `key` is the
## wallet address (the same key the Aura patch and Deep Field picture use).
static func for_identity(key: String) -> Dictionary:
	var h := hash32(key)
	return {"kind": KINDS[h % KINDS.size()], "seed": (h >> 8) & 0xffffff}


## An NPC's outfit from its seed (crowds lean casual).
static func for_npc(seed_value: int) -> Dictionary:
	var h := hash32("npc:%d" % seed_value)
	return {"kind": CROWD[h % CROWD.size()], "seed": (h >> 8) & 0xffffff}


## Slot colours for a design and seed: {main, light, …, skin}.
static func colors(kind: String, seed_value: int) -> Dictionary:
	var pals: Array = PALETTES.get(kind, PALETTES["street"])
	var p: Array = pals[absi(seed_value) % pals.size()]
	var out := {}
	for i in SLOTS.size():
		out[SLOTS[i]] = Color(p[i])
	out["skin"] = Color(SKIN_TONES[(absi(seed_value) >> 5) % SKIN_TONES.size()])
	return out


static func design(kind: String) -> Dictionary:
	return DESIGNS.get(kind, DESIGNS["street"])


## The player's own pick on this machine ("" = the identity's outfit).
static func local_choice(wallet: String) -> String:
	var c := ConfigFile.new()
	c.load(LOCAL_PATH)
	return String(c.get_value("outfits", wallet.to_lower(), ""))


static func set_local_choice(wallet: String, kind: String) -> void:
	var c := ConfigFile.new()
	c.load(LOCAL_PATH)
	c.set_value("outfits", wallet.to_lower(), kind)
	c.save(LOCAL_PATH)
