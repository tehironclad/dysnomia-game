class_name DysnomiaLore
## Shared Dysnomia flavour for the Cantina games, the quest board and the to-do panel:
## contract cards, real QING names, house themes and the entropy byte helpers.
## Pure data + static helpers — safe to call from tests (no scene tree needed).

const PULSE := Color(0.62, 0.42, 1.0)        # PulseChain purple #9e6bff
const AFFECTION_PINK := Color(0.95, 0.42, 0.72)  # AFFECTION pink #f26bb8
const GOLD := Color(1.0, 0.84, 0.32)
const OK := Color(0.45, 0.95, 0.6)
const BAD := Color(1.0, 0.42, 0.4)
const DIM := Color(0.72, 0.72, 0.8)

const CHAIN_ID := 369
const MOTZKIN_PRIME_TEXT := "953467954114363"
const QING_COUNT_ON_MAP := 263

## One card per contract: role (a few words) and a one-line flavour.
const CONTRACTS := {
	"LAU": {"role": "identity", "color": Color(0.95, 0.62, 0.32),
		"flavour": "Your soul-bound teddy. Username plus Saat: Pole, Soul, Aura."},
	"QING": {"role": "territory", "color": Color(0.36, 0.72, 0.95),
		"flavour": "A patch of Eris with its own Waat, entropy and keeper."},
	"AFFECTION": {"role": "terraforming", "color": Color(0.95, 0.42, 0.72),
		"flavour": "Pi, Rho, Generate, Alpha, Beta, Upsilon. The bar menu is its ABI."},
	"YUE": {"role": "bridge token & bars", "color": Color(0.5, 0.92, 0.75),
		"flavour": "Your bridge token. Keeps your Hypobar and Epibar in every QING."},
	"META": {"role": "ecosystem routing", "color": Color(0.45, 0.9, 0.45),
		"flavour": "Beat(waat) aggregates the state. The Resonance Array shakes."},
	"GWAT": {"role": "territory establishment", "color": Color(0.85, 0.75, 0.45),
		"flavour": "Persistent structures. Phase 2: Firma."},
	"XIE": {"role": "power", "color": Color(1.0, 0.85, 0.3),
		"flavour": "Power(): a QING's charge, omicron and omega."},
	"HECKE": {"role": "coordinates", "color": Color(0.9, 0.6, 0.85),
		"flavour": "Compliment() turns a QING into longitude & latitude."},
	"MAP": {"role": "neighbour lookup", "color": Color(0.55, 0.8, 0.55),
		"flavour": "GetMapQing(lat, lon): who lives next door?"},
	"ZUO": {"role": "QING index", "color": Color(0.7, 0.7, 0.95),
		"flavour": "GetQing(n): the nth QING in the world."},
	"CHAN": {"role": "player to YUE", "color": Color(0.4, 0.85, 0.9),
		"flavour": "Yan(player) points a wallet at its YUE."},
	"CHO": {"role": "soul registry", "color": Color(0.95, 0.9, 0.4),
		"flavour": "GetAddressBySoul: find a LAU by its Soul (Saat 1)."},
	"VOID": {"role": "the root", "color": Color(0.62, 0.42, 1.0),
		"flavour": "Where it all hangs from. (LAU.Void resets a soul. No undo.)"},
	"RING": {"role": "ring mechanics", "color": Color(0.95, 0.55, 0.45),
		"flavour": "The orbit everything else runs in."},
	"PANG": {"role": "connected interactions", "color": Color(0.6, 0.95, 0.95),
		"flavour": "The handshake between contracts."},
}

## House themes for WAAT Slots, picked by the QING's Waat hex. "featured" is a SlotSymbol id.
const HOUSE_THEMES := [
	{"name": "Crystal Caverns", "featured": 3, "color": Color(0.4, 0.85, 1.0)},
	{"name": "Teddy Tavern", "featured": 4, "color": Color(1.0, 0.72, 0.35)},
	{"name": "Rocket Yard", "featured": 5, "color": Color(1.0, 0.5, 0.3)},
	{"name": "AFFECTION Lounge", "featured": 2, "color": Color(0.95, 0.42, 0.72)},
]

const _FAKE_A := ["Regolith", "Quasar", "Nebula", "Lunar", "Teddy", "Comet", "Orbit", "Gravity",
	"Plasma", "Ion", "Saturn", "Cosmic", "Stellar", "Photon", "Crater", "Dusty"]
const _FAKE_B := ["Barn", "Gardens", "Harbour", "Hollow", "Ranch", "Den", "Works", "Reach",
	"Plains", "Bay", "Spire", "Market", "Station", "Basin", "Yard", "Keep"]

static var _names_cache: Array = []


static func qing_names() -> Array:
	## Real QING names from assets/data/qing_names.json, filtered to text the UI font can draw.
	if not _names_cache.is_empty():
		return _names_cache
	var out: Array = []
	var f := FileAccess.open("res://assets/data/qing_names.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for v in d.values():
				var s := str(v).strip_edges()
				if _printable(s) and s.length() <= 28 and s.length() >= 6 and not out.has(s):
					out.append(s)
	out.sort()
	_names_cache = out
	return out


static func _printable(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or c > 0x24F:
			return false
	return true


static func fake_qing_name(rng: RandomNumberGenerator, real: Array) -> String:
	## A plausible QING name that is definitely not on chain.
	for _i in 40:
		var n := "%s %s QING" % [_FAKE_A[rng.randi() % _FAKE_A.size()], _FAKE_B[rng.randi() % _FAKE_B.size()]]
		if not real.has(n):
			return n
	return "Nowhere QING"


static func house_theme(waat_hex: String) -> Dictionary:
	var b := hex_bytes(waat_hex)
	var idx := 0
	if b.size() > 0:
		idx = int(b[b.size() - 1]) % HOUSE_THEMES.size()
	return HOUSE_THEMES[idx]


static func hex_bytes(hex: String) -> PackedByteArray:
	var h := hex.strip_edges().to_lower()
	if h.begins_with("0x"):
		h = h.substr(2)
	if h.length() % 2 == 1:
		h = "0" + h
	var out := PackedByteArray()
	for i in range(0, h.length(), 2):
		var pair := h.substr(i, 2)
		if not pair.is_valid_hex_number():
			return PackedByteArray()
		out.append(pair.hex_to_int())
	return out


static func short_hex(hex: String, keep: int = 6) -> String:
	var h := hex.strip_edges()
	if h.is_empty():
		return "(no entropy yet)"
	if not h.begins_with("0x"):
		h = "0x" + h
	if h.length() <= keep * 2 + 4:
		return h
	return h.left(keep + 2) + "…" + h.right(keep)


static func qing_label() -> String:
	var n: String = GameManager.territory_name
	if n.is_empty():
		var a: String = GameManager.territory_address
		return "this QING" if a.is_empty() or a == "0x0" else a.left(8) + "…"
	return n


static func qing_key() -> String:
	## Stable per-QING key for saves. Address when we have one, else the name, else "offline".
	var a: String = GameManager.territory_address.to_lower()
	if HexUtils.is_valid_address(a):
		return a
	if not GameManager.territory_name.is_empty():
		return GameManager.territory_name
	return "offline"


static func player_label() -> String:
	var p: String = GameManager.player_identity
	return "You" if p.is_empty() or p == "Anonymous" else p


static func styled_panel(border: Color, radius: int = 10, bg_alpha: float = 0.94) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.08, bg_alpha)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	return sb


static func color_hex(c: Color) -> String:
	return "#" + c.to_html(false)
