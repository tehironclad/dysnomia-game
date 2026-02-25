class_name PubGenerator
## Static utility for deterministic pub building parameters from territory seed.
## Same pattern as MonumentGenerator — pure function, no state.


static func get_pub_params(seed_value: int) -> Dictionary:
	var s := absi(seed_value)

	# Room dimensions
	var room_width: float = 14.0 + float(s % 5) * 1.0       # 14-18m
	var room_depth: float = 10.0 + float((s / 7) % 4) * 1.0  # 10-13m
	var wall_height: float = 5.0 + float((s / 31) % 3) * 0.5 # 5-6m

	# Bar counter
	var bar_length: float = room_width * 0.6
	var bar_height: float = 1.1

	# Furniture
	var stool_count: int = 4 + (s / 97) % 5   # 4-8 stools
	var table_count: int = 2 + (s / 53) % 3   # 2-4 tables
	var game_table_count: int = 2 + (s / 137) % 3  # 2-4 game tables

	# Roof style
	var roof_style: int = (s / 199) % 3  # 0=flat, 1=dome, 2=vault

	# Colors
	var hue: float = fmod(float(s % 953) / 953.0, 1.0)
	var accent_color := Color.from_hsv(hue, 0.6, 0.85)
	var accent_dark := accent_color.darkened(0.4)
	var sign_color := Color.from_hsv(fmod(hue + 0.15, 1.0), 0.7, 0.95)

	# Window count
	var window_count: int = 2 + (s / 313) % 3  # 2-4 per side wall

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
		"accent_color": accent_color,
		"accent_dark": accent_dark,
		"sign_color": sign_color,
		"window_count": window_count,
	}
