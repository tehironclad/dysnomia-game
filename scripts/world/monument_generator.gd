class_name MonumentGenerator
## Static utility that converts a territory seed into mausoleum visual parameters.
## Works like BiomeSystem — pure functions, no state, deterministic output.
## Each QING territory gets a unique mausoleum inspired by Chinese Qing dynasty architecture.

## Mausoleum architectural styles
enum MausoleumStyle { IMPERIAL, PAGODA, FORTRESS, SPIRIT }

## Guardian statue types flanking the entrance
enum GuardianType { PILLAR, OBELISK, LANTERN, STELE }


static func get_monument_params(seed_value: int) -> Dictionary:
	## Generate all mausoleum visual parameters from a single seed.
	## Mausoleum is large — ~50m wide, ~55m deep total with back room.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Style determined by seed mod 4
	var style: int = absi(seed_value) % 4

	# Guardian type (independent of style)
	var guardian_type: int = (absi(seed_value) / 4) % 4

	# Main hall dimensions (the front room you enter)
	var chamber_width: float = rng.randf_range(40.0, 60.0)
	var chamber_depth: float = rng.randf_range(30.0, 40.0)

	# Wall parameters
	var wall_height: float = rng.randf_range(25.0, 40.0)
	var wall_thickness: float = rng.randf_range(3.0, 5.0)

	# Roof
	var roof_height: float = rng.randf_range(10.0, 20.0)

	# Platform
	var platform_steps: int = rng.randi_range(2, 4)
	var platform_step_height: float = rng.randf_range(1.5, 2.5)

	# Pillars
	var pillar_count: int = rng.randi_range(4, 8)
	var pillar_radius: float = rng.randf_range(1.0, 2.0)

	# Entrance
	var entrance_width: float = rng.randf_range(12.0, 20.0)

	# Accent color — seed-derived hue, moderate saturation, bright value
	var hue: float = fmod(float(absi(seed_value)) / 953467.0, 1.0)
	var accent_color := Color.from_hsv(hue, 0.6, 0.85)
	# Darker wall color — same hue, lower saturation and value
	var accent_color_dark := Color.from_hsv(hue, 0.35, 0.35)

	# Back room (inner sanctum) — where the tesseract hides
	var back_room_width: float = chamber_width * rng.randf_range(0.4, 0.6)
	var back_room_depth: float = rng.randf_range(15.0, 22.0)
	var back_room_entrance_width: float = rng.randf_range(5.0, 8.0)

	# Tesseract (larger for the bigger space)
	var tesseract_size: float = rng.randf_range(5.0, 8.0)
	var tesseract_speed: float = rng.randf_range(0.3, 0.8)

	# Light (larger ranges for bigger building)
	var glow_range: float = rng.randf_range(50.0, 80.0)
	var glow_energy: float = rng.randf_range(1.5, 3.0)

	# Spirit way pillars
	var spirit_way_count: int = rng.randi_range(3, 6)

	return {
		"style": style,
		"guardian_type": guardian_type,
		"chamber_width": chamber_width,
		"chamber_depth": chamber_depth,
		"wall_height": wall_height,
		"wall_thickness": wall_thickness,
		"roof_height": roof_height,
		"platform_steps": platform_steps,
		"platform_step_height": platform_step_height,
		"pillar_count": pillar_count,
		"pillar_radius": pillar_radius,
		"entrance_width": entrance_width,
		"accent_color": accent_color,
		"accent_color_dark": accent_color_dark,
		"back_room_width": back_room_width,
		"back_room_depth": back_room_depth,
		"back_room_entrance_width": back_room_entrance_width,
		"tesseract_size": tesseract_size,
		"tesseract_speed": tesseract_speed,
		"glow_range": glow_range,
		"glow_energy": glow_energy,
		"spirit_way_count": spirit_way_count,
	}


static func get_style_name(style: int) -> String:
	match style:
		MausoleumStyle.IMPERIAL: return "Imperial"
		MausoleumStyle.PAGODA: return "Pagoda"
		MausoleumStyle.FORTRESS: return "Fortress"
		MausoleumStyle.SPIRIT: return "Spirit"
		_: return "Unknown"
