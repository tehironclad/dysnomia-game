class_name PubGenerator
## Static utility for deterministic pub building parameters from territory seed.
## Same pattern as MonumentGenerator — pure function, no state. Same seed → same cantina.

# Exterior paint jobs for the container-steel shell (tints over the PBR albedo)
const SHELL_TINTS := [
	Color(0.78, 0.36, 0.26),  # Oxide red
	Color(0.32, 0.55, 0.58),  # Habitat teal
	Color(0.80, 0.62, 0.30),  # Ochre
	Color(0.40, 0.45, 0.60),  # Slate blue
	Color(0.52, 0.56, 0.38),  # Olive drab
	Color(0.85, 0.84, 0.80),  # Bleached white
]

const NEON_COLORS := [
	Color(1.0, 0.25, 0.55),   # Hot pink
	Color(0.2, 0.85, 1.0),    # Cyan
	Color(1.0, 0.55, 0.12),   # Amber
	Color(0.55, 1.0, 0.3),    # Lime
	Color(0.7, 0.35, 1.0),    # Violet
]


static func get_pub_params(seed_value: int) -> Dictionary:
	var s := absi(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = s * 7919 + 1337

	# Room dimensions (interior). Building + porch must fit the 40 × 30 m flattened site.
	var room_width: float = 15.0 + float(s % 4) * 1.0         # 15-18 m
	var room_depth: float = 11.0 + float((s / 7) % 3) * 1.0   # 11-13 m
	var wall_height: float = 4.4 + float((s / 31) % 3) * 0.3  # 4.4-5.0 m

	# Bar counter
	var bar_length: float = room_width * 0.5 + 0.4
	var bar_height: float = 1.08

	# Furniture
	var stool_count: int = 5 + (s / 97) % 3         # 5-7 stools
	var table_count: int = 3 + (s / 53) % 2         # 3-4 high-top tables
	var game_table_count: int = 2 + (s / 137) % 3  # 2-4 game tables

	# Roof: 0 = barrel vault, 1 = gable, 2 = skillion (mono-pitch)
	var roof_style: int = (s / 199) % 3
	var roof_rise: float = [2.1, 2.4, 1.7][roof_style] + rng.randf_range(-0.2, 0.3)

	# Colors
	var hue: float = fmod(float(s % 953) / 953.0, 1.0)
	var accent_color := Color.from_hsv(hue, 0.6, 0.85)
	var accent_dark := accent_color.darkened(0.4)
	var sign_color := Color.from_hsv(fmod(hue + 0.15, 1.0), 0.7, 0.95)
	var shell_tint: Color = SHELL_TINTS[(s / 11) % SHELL_TINTS.size()]
	var neon_a: Color = NEON_COLORS[(s / 3) % NEON_COLORS.size()]
	var neon_b: Color = NEON_COLORS[((s / 3) + 2) % NEON_COLORS.size()]

	# Window count (side walls)
	var window_count: int = 2 + (s / 313) % 3  # 2-4

	# People: bartender + 5..7 patrons (AmbientNPC is ~90 meshes each, so stay ≤ 8)
	var patron_count: int = 5 + (s / 17) % 3

	return {
		"room_width": room_width,
		"room_depth": room_depth,
		"wall_height": wall_height,
		"bar_length": bar_length,
		"bar_height": bar_height,
		"stool_count": stool_count,
		"table_count": table_count,
		"game_table_count": game_table_count,
		"roof_style": roof_style,
		"roof_rise": roof_rise,
		"accent_color": accent_color,
		"accent_dark": accent_dark,
		"sign_color": sign_color,
		"shell_tint": shell_tint,
		"neon_a": neon_a,
		"neon_b": neon_b,
		"window_count": window_count,
		"patron_count": patron_count,
		"detail_seed": rng.randi(),
	}
