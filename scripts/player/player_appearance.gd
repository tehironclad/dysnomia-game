class_name PlayerAppearance
## Generates deterministic player appearance from LAU Saat values.
## Saat[0] (Soul) -> body proportions (height/radius)
## Saat[1] (Spirit) -> primary body color (hue)
## Saat[2] (Aura) -> accent/emission color and glow intensity

const MOTZKIN_PRIME: int = 953467954114363


static func generate(saat: Array[int]) -> Dictionary:
	## Returns appearance dictionary from Saat values.
	## Deterministic: same Saat always produces the same appearance.
	var soul: int = saat[0] if saat.size() > 0 else 0
	var spirit: int = saat[1] if saat.size() > 1 else 0
	var aura: int = saat[2] if saat.size() > 2 else 0

	# --- Body proportions from Soul ---
	# Height ranges from 1.6 to 2.1 meters
	var soul_norm: float = _normalize(soul)
	var height: float = 1.6 + soul_norm * 0.5
	# Radius scales proportionally with slight variation
	var radius: float = 0.25 + soul_norm * 0.1

	# --- Primary color from Spirit ---
	# Map spirit to warm brown range (hue 0.04-0.12 in HSV = orange-brown).
	# This keeps the teddy bear looking like a bear, not green/blue/red.
	# Different spirits produce different shades of brown: chocolate, caramel, honey, etc.
	var spirit_norm: float = _normalize(spirit)
	var hue: float = 0.04 + spirit_norm * 0.08  # Brown range: 0.04 (reddish-brown) to 0.12 (golden-brown)
	var saturation: float = 0.5 + fmod(_normalize_offset(spirit, 7), 0.3)  # Rich but earthy
	var value: float = 0.35 + fmod(_normalize_offset(spirit, 13), 0.3)     # Dark chocolate to light tan
	var body_color := Color.from_hsv(hue, saturation, value)

	# --- Accent/emission from Aura ---
	var aura_norm: float = _normalize(aura)
	var accent_hue: float = fmod(hue + 0.33 + aura_norm * 0.34, 1.0) # Complementary-ish
	var accent_sat: float = 0.5 + fmod(_normalize_offset(aura, 3), 0.4)
	var accent_val: float = 0.8 + fmod(_normalize_offset(aura, 11), 0.2)
	var accent_color := Color.from_hsv(accent_hue, accent_sat, accent_val)

	# Emission color — slightly shifted from accent, higher brightness
	var emission_hue: float = fmod(accent_hue + 0.05, 1.0)
	var emission_color := Color.from_hsv(emission_hue, 0.7, 1.0)

	# Emission intensity scales with aura magnitude
	var emission_intensity: float = 0.2 + aura_norm * 0.8

	return {
		"body_color": body_color,
		"accent_color": accent_color,
		"emission_color": emission_color,
		"emission_intensity": emission_intensity,
		"height": height,
		"radius": radius,
	}


static func generate_default() -> Dictionary:
	## Fallback appearance when no identity is loaded.
	## Ted-brown bear, white suit accents, warm amber eyes.
	return {
		"body_color": Color(0.45, 0.30, 0.18),
		"accent_color": Color(0.5, 0.55, 0.6),
		"emission_color": Color(0.4, 0.3, 0.2),
		"emission_intensity": 0.15,
		"height": 1.8,
		"radius": 0.3,
	}


static func _normalize(val: int) -> float:
	## Map a uint64 value to [0, 1) deterministically.
	if val == 0:
		return 0.0
	return float(val % MOTZKIN_PRIME) / float(MOTZKIN_PRIME)


static func _normalize_offset(val: int, offset: int) -> float:
	## Variation normalizer — same value produces different results with different offsets.
	if val == 0:
		return 0.0
	return float((val + offset * 127) % MOTZKIN_PRIME) / float(MOTZKIN_PRIME)
