class_name BiomeSystem
## Derives biome properties from a seed value.
## Dysnomia is a moon of Eris — terrain is lunar regolith, not earthlike.
## Biome types affect terrain shape and shade variation but all are grey/brown regolith.
## Terraforming (territory_power) gradually introduces color and life.

const MOTZKIN_PRIME: int = 953467954114363

# Biome type names for debug display
const BIOME_NAMES: Array[String] = ["Cratered Highlands", "Mare Basin", "Rift Valley", "Impact Shelf"]


static func get_biome(seed_value: int) -> Dictionary:
	var normalized: int = absi(seed_value) % MOTZKIN_PRIME if seed_value != 0 else 42
	var biome_type: int = normalized % 4

	# Derive shade palette from seed bits
	var color_seed: int = (normalized / 4) % 10000

	# Lunar regolith base colors — greys, browns, dusty tans
	# Each biome type has a distinct shade palette but all are monochromatic/desaturated
	var regolith_color: Color       # Primary surface (replaces grass)
	var regolith_color_2: Color     # Secondary surface variation
	var rock_color: Color           # Exposed bedrock on slopes
	var rock_color_2: Color         # Rock variation
	var dust_color: Color           # Fine dust in valleys (replaces soil)
	var frost_color: Color = Color(0.72, 0.74, 0.78)  # Nitrogen frost — icy bright
	var shadow_color: Color = Color(0.06, 0.06, 0.08) # Deep crater shadow — very dark

	# Subtle shade shift from seed — keeps it monochromatic
	var shade_shift: float = (color_seed % 100) / 1250.0 - 0.04  # -0.04 to +0.04

	match biome_type:
		0: # Cratered Highlands — anorthositic, lighter grey (brightest biome)
			regolith_color = Color(0.48 + shade_shift, 0.46 + shade_shift, 0.44 + shade_shift)
			regolith_color_2 = Color(0.42 + shade_shift, 0.40 + shade_shift, 0.38 + shade_shift)
			rock_color = Color(0.35, 0.33, 0.31)
			rock_color_2 = Color(0.38, 0.36, 0.34)
			dust_color = Color(0.50, 0.48, 0.45)
		1: # Mare Basin — dark basaltic plains (darkest biome)
			regolith_color = Color(0.32 + shade_shift, 0.31 + shade_shift, 0.30 + shade_shift)
			regolith_color_2 = Color(0.36 + shade_shift, 0.34 + shade_shift, 0.33 + shade_shift)
			rock_color = Color(0.25, 0.24, 0.23)
			rock_color_2 = Color(0.28, 0.27, 0.26)
			dust_color = Color(0.38, 0.36, 0.34)
		2: # Rift Valley — iron-rich, slightly warmer brown
			regolith_color = Color(0.42 + shade_shift, 0.38 + shade_shift, 0.34 + shade_shift)
			regolith_color_2 = Color(0.46 + shade_shift, 0.41 + shade_shift, 0.36 + shade_shift)
			rock_color = Color(0.33, 0.29, 0.25)
			rock_color_2 = Color(0.36, 0.32, 0.28)
			dust_color = Color(0.48, 0.42, 0.36)
		3: # Impact Shelf — freshest ejecta, bright pale grey
			regolith_color = Color(0.52 + shade_shift, 0.50 + shade_shift, 0.48 + shade_shift)
			regolith_color_2 = Color(0.46 + shade_shift, 0.44 + shade_shift, 0.42 + shade_shift)
			rock_color = Color(0.38, 0.36, 0.34)
			rock_color_2 = Color(0.42, 0.40, 0.38)
			dust_color = Color(0.55, 0.52, 0.49)
		_:
			regolith_color = Color(0.44, 0.42, 0.40)
			regolith_color_2 = Color(0.38, 0.36, 0.34)
			rock_color = Color(0.30, 0.28, 0.26)
			rock_color_2 = Color(0.34, 0.32, 0.30)
			dust_color = Color(0.46, 0.44, 0.41)

	# Terrain thresholds for a cold airless moon
	var frost_line: float   # Nitrogen/methane frost appears at high elevations
	var crater_floor: float # Deep crater shadow threshold (replaces water level)
	match biome_type:
		0: frost_line = 32.0; crater_floor = -8.0   # Highland craters are deep
		1: frost_line = 45.0; crater_floor = -3.0    # Mare are flat, frost only on peaks
		2: frost_line = 38.0; crater_floor = -6.0    # Rifts go deep
		3: frost_line = 28.0; crater_floor = -4.0    # Impact shelves, frost at moderate height
		_: frost_line = 35.0; crater_floor = -5.0

	return {
		"biome_type": biome_type,
		"biome_name": BIOME_NAMES[biome_type],
		# Keep original key names so existing code doesn't break
		"grass_color": regolith_color,
		"grass_color_2": regolith_color_2,
		"rock_color": rock_color,
		"rock_color_2": rock_color_2,
		"soil_color": dust_color,
		"snow_color": frost_color,
		"water_color": shadow_color,
		"snow_line": frost_line,
		"water_level": crater_floor,
	}


static func apply_latitude_shift(biome: Dictionary, latitude: float) -> Dictionary:
	## Nudge biome parameters based on HECKE latitude.
	## High latitude (polar): more frost, cooler grey tones.
	## Low latitude (equatorial): less frost, slightly warmer brown tones.
	var result := biome.duplicate()
	var abs_lat := absf(latitude)

	if abs_lat > 60.0:
		# Polar: more frost coverage, cooler surface
		result["snow_line"] = biome.get("snow_line", 35.0) - 8.0
		var gc: Color = biome.get("grass_color", Color(0.44, 0.42, 0.40))
		result["grass_color"] = Color(gc.r - 0.02, gc.g - 0.01, gc.b + 0.01)
		var gc2: Color = biome.get("grass_color_2", Color(0.38, 0.36, 0.34))
		result["grass_color_2"] = Color(gc2.r - 0.02, gc2.g - 0.01, gc2.b + 0.01)
	elif abs_lat < 30.0:
		# Equatorial: warmer tones, less frost
		result["snow_line"] = biome.get("snow_line", 35.0) + 8.0
		var gc: Color = biome.get("grass_color", Color(0.44, 0.42, 0.40))
		result["grass_color"] = Color(gc.r + 0.02, gc.g + 0.01, gc.b - 0.01)
		var gc2: Color = biome.get("grass_color_2", Color(0.38, 0.36, 0.34))
		result["grass_color_2"] = Color(gc2.r + 0.02, gc2.g + 0.01, gc2.b - 0.01)

	return result
