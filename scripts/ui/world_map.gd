extends Control
## World map overlay — shows all ~263 QINGs as colored dots.
## Two views: 2D flat map and 3D globe projection.
## M key toggles the map. Click a dot to inspect, click again to travel/join.
## Color scheme matches entropy-ai's map.html (meridian-based 15-color palette).

signal territory_selected(qing_address: String)
signal map_closed
signal name_requested(qing_address: String)

# ─── Entropy-style meridian color palette (15 colors) ───────────────────
const MERIDIAN_COLORS: Array[Color] = [
	Color(0.831, 0.325, 0.467),  # #d45377 - rose
	Color(0.976, 0.451, 0.086),  # #f97316 - orange
	Color(0.831, 0.659, 0.325),  # #d4a853 - gold
	Color(0.918, 0.702, 0.031),  # #eab308 - yellow
	Color(0.518, 0.800, 0.086),  # #84cc16 - lime
	Color(0.133, 0.773, 0.369),  # #22c55e - green
	Color(0.078, 0.722, 0.651),  # #14b8a6 - teal
	Color(0.325, 0.831, 0.780),  # #53d4c7 - cyan
	Color(0.055, 0.647, 0.914),  # #0ea5e9 - sky
	Color(0.231, 0.510, 0.965),  # #3b82f6 - blue
	Color(0.388, 0.400, 0.945),  # #6366f1 - indigo
	Color(0.545, 0.478, 0.831),  # #8b7ad4 - lavender
	Color(0.659, 0.333, 0.969),  # #a855f7 - purple
	Color(0.851, 0.275, 0.937),  # #d946ef - fuchsia
	Color(0.925, 0.282, 0.600),  # #ec4899 - pink
]

# Entropy-style theme colors
const COLOR_BG := Color(0.016, 0.024, 0.043, 0.95)       # #04060b
const COLOR_CURRENT := Color(0.133, 0.773, 0.369)         # #22c55e green (member)
const COLOR_SELECTED := Color(0.325, 0.831, 0.780)        # #53d4c7 cyan
const COLOR_GRID := Color(0.15, 0.18, 0.25, 0.4)
const COLOR_TEXT := Color(0.75, 0.82, 0.92)
const COLOR_TEXT_DIM := Color(0.45, 0.50, 0.58)
const COLOR_PANEL_BG := Color(0.06, 0.07, 0.12, 0.95)
const COLOR_PANEL_BORDER := Color(0.325, 0.831, 0.780, 0.4)

const DOT_RADIUS: float = 5.0
const HOVER_RADIUS: float = 7.0
const SELECTED_RADIUS: float = 9.0
const CURRENT_RADIUS: float = 8.0
const MAP_MARGIN: float = 50.0
const HIT_THRESHOLD: float = 14.0

# Pre-processed QING data for rendering
var _map_qings: Array[Dictionary] = []
var _selected_idx: int = -1
var _hovered_idx: int = -1
var _current_territory: String = ""
var _current_idx: int = -1  # Cache index of current territory for pulsing
var _is_initialized: bool = false
var _is_globe: bool = false  # Toggle between flat map and globe
var _pulse_time: float = 0.0  # For pulsing animation on current territory

# Name cache: address → name string (populated on-demand)
var _name_cache: Dictionary = {}

# Globe view parameters
var _globe_rotation: float = 0.0  # Y-axis rotation in radians
var _globe_tilt: float = 0.3      # X-axis tilt
var _globe_dragging: bool = false
var _globe_drag_start: Vector2 = Vector2.ZERO
var _globe_rot_start: float = 0.0
var _globe_tilt_start: float = 0.0

# Search
var _search_input: LineEdit = null
var _search_results: Array[int] = []  # Indices into _map_qings matching search
var _search_active: bool = false
var _search_selected: int = -1  # Index within _search_results for keyboard nav


func _ready() -> void:
	# Under CanvasLayer, anchors don't work — set size to viewport manually
	size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)

	# Create search input
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search QINGs... (S)"
	_search_input.custom_minimum_size = Vector2(250, 30)
	_search_input.position = Vector2(MAP_MARGIN, 50)
	_search_input.visible = false
	_search_input.add_theme_color_override("font_color", COLOR_TEXT)
	_search_input.add_theme_color_override("font_placeholder_color", COLOR_TEXT_DIM)
	_search_input.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL_BG
	sb.border_color = COLOR_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	_search_input.add_theme_stylebox_override("normal", sb)
	var sb_focus := sb.duplicate()
	sb_focus.border_color = COLOR_SELECTED
	sb_focus.set_border_width_all(2)
	_search_input.add_theme_stylebox_override("focus", sb_focus)
	add_child(_search_input)
	_search_input.text_changed.connect(_on_search_text_changed)
	_search_input.text_submitted.connect(_on_search_submitted)
	_search_input.gui_input.connect(_on_search_input_gui_input)


func _on_viewport_resized() -> void:
	size = get_viewport().get_visible_rect().size
	queue_redraw()


func _load_bundled_names() -> void:
	## Territory names come from the Registry (read from each QING's name()).
	for q in Registry.all():
		if String(q.get("name", "")) != "":
			_name_cache[q["address"]] = q["name"]


func set_qing_name(address: String, qing_name: String) -> void:
	## Called externally when a QING name is resolved.
	_name_cache[address.to_lower()] = qing_name
	queue_redraw()


func _process(delta: float) -> void:
	if not visible or not _is_initialized:
		return
	_pulse_time += delta
	# Only redraw for pulse effect (every ~50ms = 20fps for the pulse)
	if fmod(_pulse_time, 0.05) < delta:
		queue_redraw()


func initialize(raw_qings: Array[Dictionary], current_territory_address: String) -> void:
	# Ensure size is set (anchors don't work under CanvasLayer)
	var vp_size := get_viewport().get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		size = vp_size
	_current_territory = current_territory_address.to_lower()
	_map_qings.clear()
	_selected_idx = -1
	_hovered_idx = -1
	_current_idx = -1
	_pulse_time = 0.0
	_is_globe = false  # Always start in flat map view
	# Close search if it was open from a previous session
	if _search_active:
		_close_search()

	# Load bundled QING names if not already cached
	if _name_cache.is_empty():
		_load_bundled_names()

	for q in raw_qings:
		if not (q is Dictionary):
			continue
		var addr: String = q.get("address", "").to_lower()
		if addr.is_empty():
			continue

		var lat_hex: String = q.get("lat_hex", "")
		var lon_hex: String = q.get("lon_hex", "")
		var waat_hex: String = q.get("waat_hex", "0x0")

		# Display degrees: the site's projection of HECKE.Compliment words
		# (Coords.project). Map adjacency is meaningless on chain.
		var lat: float
		var lon: float
		if q.has("lat") and q.has("lon"):
			lat = float(q["lat"])
			lon = float(q["lon"])
		else:
			var p := Coords.project(lon_hex, lat_hex)
			lat = p[0]
			lon = p[1]

		# Meridian-based color (matching entropy's 15-color palette)
		var meridian_idx := _lon_to_meridian_color_idx(lon)
		var dot_color: Color = MERIDIAN_COLORS[meridian_idx]

		var entry := {
			"address": addr,
			"waat_hex": waat_hex,
			"lat": lat,
			"lon": lon,
			"meridian_idx": meridian_idx,
			"dot_color": dot_color,
			"screen_pos": Vector2.ZERO,
		}

		_map_qings.append(entry)
		if addr == _current_territory:
			_current_idx = _map_qings.size() - 1

	# If current territory not found by exact match, try without 0x prefix normalization
	if _current_idx < 0 and not _current_territory.is_empty():
		for i in range(_map_qings.size()):
			if _map_qings[i].address.ends_with(_current_territory.right(40)):
				_current_idx = i
				break

	# Center globe on current territory if found
	if _current_idx >= 0:
		_globe_rotation = -deg_to_rad(_map_qings[_current_idx].lon)

	_is_initialized = true
	# Grab keyboard focus so _gui_input receives key events (S for search, etc.)
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	queue_redraw()


func _int256_hex_to_lat(hex64: String) -> float:
	## Convert a 64-char int256 hex to latitude in [-90, 90] range.
	## Uses HexUtils.hex_mod() for overflow-safe modular arithmetic on the
	## raw hex string, then applies sign from the int256 top nibble.
	return _hex_to_coordinate(hex64, 90_000_000)


func _int256_hex_to_lon(hex64: String) -> float:
	## Convert a 64-char int256 hex to longitude in [-180, 180] range.
	return _hex_to_coordinate(hex64, 180_000_000)


func _hex_to_coordinate(hex64: String, modulus: int) -> float:
	## Convert a 64-char int256 hex to a coordinate via overflow-safe hex_mod.
	## HexUtils.hex_mod processes hex digits one at a time (no int overflow).
	## Sign is determined from the int256 top nibble (two's complement).
	if hex64.is_empty():
		return 0.0

	var h := hex64.to_lower()
	while h.length() < 64:
		h = "0" + h

	# Determine sign from int256 top nibble (>= 8 means negative)
	var is_negative: bool = HexUtils.hex_char_to_int(h[0]) >= 8

	# Use hex_mod for overflow-safe modular reduction on the raw hex
	# This operates digit-by-digit, never exceeding GDScript int64 range
	var remainder: int = HexUtils.hex_mod(h, modulus)

	# Apply sign and convert to degrees
	var deg: float = float(remainder) / 1000000.0
	return -deg if is_negative else deg


func _lon_to_meridian_color_idx(lon: float) -> int:
	## Map longitude to one of 15 meridian color buckets (matching entropy).
	## Entropy uses 90 meridians mapped to 15 colors.
	# Normalize lon to 0..360
	var norm_lon := fmod(lon + 180.0, 360.0)
	if norm_lon < 0:
		norm_lon += 360.0
	# 360 degrees / 15 colors = 24 degrees per color
	var idx := int(norm_lon / 24.0)
	return clampi(idx, 0, 14)


func _lat_lon_to_screen(lat: float, lon: float) -> Vector2:
	var map_rect := _get_map_rect()
	# Coordinates are already wrapped to valid ranges during initialization
	var norm_x: float = (lon + 180.0) / 360.0
	var norm_y: float = 1.0 - (lat + 90.0) / 180.0
	return Vector2(
		map_rect.position.x + norm_x * map_rect.size.x,
		map_rect.position.y + norm_y * map_rect.size.y
	)


func _lat_lon_to_globe(lat: float, lon: float, center: Vector2, globe_radius: float) -> Vector2:
	## Project lat/lon onto a 3D sphere viewed from the front.
	## Returns screen position; points on the back of the globe return (-1, -1).
	var lat_rad := deg_to_rad(lat)
	var lon_rad := deg_to_rad(lon) + _globe_rotation

	# 3D sphere coordinates
	var x := cos(lat_rad) * sin(lon_rad)
	var y := sin(lat_rad)
	var z := cos(lat_rad) * cos(lon_rad)

	# Apply tilt (rotation around X axis)
	var y2 := y * cos(_globe_tilt) - z * sin(_globe_tilt)
	var z2 := y * sin(_globe_tilt) + z * cos(_globe_tilt)

	# Back-face culling: if z2 < 0, point is on the far side
	if z2 < -0.05:
		return Vector2(-1, -1)

	# Orthographic projection
	return Vector2(
		center.x + x * globe_radius,
		center.y - y2 * globe_radius  # Y inverted for screen
	)


func _get_map_rect() -> Rect2:
	return Rect2(MAP_MARGIN, MAP_MARGIN + 20, size.x - MAP_MARGIN * 2, size.y - MAP_MARGIN * 2 - 20)


func _draw() -> void:
	if not _is_initialized or _map_qings.is_empty():
		return

	# Safety: re-acquire viewport size if our size is zero
	if size.x < 1.0 or size.y < 1.0:
		size = get_viewport().get_visible_rect().size
		if size.x < 1.0:
			return  # Still no size — skip draw

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)

	if _is_globe:
		_draw_globe()
	else:
		_draw_flat_map()

	# Header bar
	_draw_header()

	# Info panel for selected QING
	if _selected_idx >= 0 and _selected_idx < _map_qings.size():
		_draw_info_panel(_map_qings[_selected_idx])

	# Search results overlay
	_draw_search_results()


func _draw_header() -> void:
	## Draw the top header with title and view toggle.
	# Title
	draw_string(ThemeDB.fallback_font, Vector2(MAP_MARGIN, 32),
		"QING Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR_SELECTED)
	draw_string(ThemeDB.fallback_font, Vector2(MAP_MARGIN + 120, 32),
		"— %d territories" % _map_qings.size(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_TEXT_DIM)

	# View toggle buttons
	var btn_y: float = 14.0
	var flat_x: float = size.x - MAP_MARGIN - 160
	var globe_x: float = size.x - MAP_MARGIN - 80

	# Flat map button
	var flat_color := COLOR_SELECTED if not _is_globe else COLOR_TEXT_DIM
	draw_rect(Rect2(flat_x, btn_y, 70, 24), COLOR_PANEL_BG)
	draw_rect(Rect2(flat_x, btn_y, 70, 24), flat_color.darkened(0.5) if not _is_globe else Color(0.2, 0.2, 0.3, 0.3), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(flat_x + 14, btn_y + 17),
		"Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, flat_color)

	# Globe button
	var globe_color := COLOR_SELECTED if _is_globe else COLOR_TEXT_DIM
	draw_rect(Rect2(globe_x, btn_y, 70, 24), COLOR_PANEL_BG)
	draw_rect(Rect2(globe_x, btn_y, 70, 24), globe_color.darkened(0.5) if _is_globe else Color(0.2, 0.2, 0.3, 0.3), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(globe_x + 10, btn_y + 17),
		"Globe", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, globe_color)

	# Controls hint
	var hint := "S: search | Click: inspect | Click again: join | ESC: close"
	if _is_globe:
		hint = "S: search | Drag: rotate | Click: inspect | ESC: close"
	if _search_active:
		hint = "↑↓: navigate | Enter: select | ESC: close search"
	draw_string(ThemeDB.fallback_font, Vector2(size.x / 2 - 180, size.y - 15),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_TEXT_DIM)


func _draw_flat_map() -> void:
	var map_rect := _get_map_rect()

	# Grid lines
	for lon_val in range(-180, 181, 30):
		var x: float = map_rect.position.x + (float(lon_val + 180) / 360.0) * map_rect.size.x
		draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), COLOR_GRID, 1.0)
		if lon_val % 90 == 0:
			draw_string(ThemeDB.fallback_font, Vector2(x - 10, map_rect.end.y + 14),
				"%d" % lon_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)
	for lat_val in range(-90, 91, 30):
		var y: float = map_rect.position.y + (1.0 - float(lat_val + 90) / 180.0) * map_rect.size.y
		draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), COLOR_GRID, 1.0)
		if lat_val % 30 == 0:
			draw_string(ThemeDB.fallback_font, Vector2(map_rect.position.x - 28, y + 4),
				"%d" % lat_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)

	# Border
	draw_rect(map_rect, Color(0.2, 0.25, 0.35, 0.5), false, 1.0)

	# Draw all dots (non-current first, then current on top)
	for i in range(_map_qings.size()):
		if i == _current_idx:
			continue  # Draw current last (on top)
		var q: Dictionary = _map_qings[i]
		var screen_pos := _lat_lon_to_screen(q.lat, q.lon)
		q["screen_pos"] = screen_pos
		_draw_dot(i, q, screen_pos)

	# Draw current territory last (on top of everything)
	if _current_idx >= 0:
		var q: Dictionary = _map_qings[_current_idx]
		var screen_pos := _lat_lon_to_screen(q.lat, q.lon)
		q["screen_pos"] = screen_pos
		_draw_dot(_current_idx, q, screen_pos)


func _draw_globe() -> void:
	var center := Vector2(size.x / 2, size.y / 2 + 10)
	var globe_radius: float = minf(size.x, size.y) * 0.35

	# Draw globe outline
	draw_arc(center, globe_radius, 0, TAU, 64, Color(0.2, 0.25, 0.35, 0.5), 1.5)

	# Draw latitude/longitude grid on globe
	for lat_val in range(-60, 61, 30):
		var prev_pos := Vector2(-1, -1)
		for lon_step in range(0, 361, 5):
			var lon_val: float = float(lon_step) - 180.0
			var pos := _lat_lon_to_globe(float(lat_val), lon_val, center, globe_radius)
			if pos.x >= 0 and prev_pos.x >= 0:
				draw_line(prev_pos, pos, COLOR_GRID, 1.0)
			prev_pos = pos

	for lon_val in range(-180, 181, 30):
		var prev_pos := Vector2(-1, -1)
		for lat_step in range(-90, 91, 5):
			var pos := _lat_lon_to_globe(float(lat_step), float(lon_val), center, globe_radius)
			if pos.x >= 0 and prev_pos.x >= 0:
				draw_line(prev_pos, pos, COLOR_GRID, 1.0)
			prev_pos = pos

	# Draw equator slightly brighter
	var eq_prev := Vector2(-1, -1)
	for lon_step in range(0, 361, 3):
		var lon_val: float = float(lon_step) - 180.0
		var pos := _lat_lon_to_globe(0.0, lon_val, center, globe_radius)
		if pos.x >= 0 and eq_prev.x >= 0:
			draw_line(eq_prev, pos, Color(0.25, 0.30, 0.4, 0.5), 1.5)
		eq_prev = pos

	# Draw all dots
	for i in range(_map_qings.size()):
		if i == _current_idx:
			continue
		var q: Dictionary = _map_qings[i]
		var screen_pos := _lat_lon_to_globe(q.lat, q.lon, center, globe_radius)
		q["screen_pos"] = screen_pos
		if screen_pos.x >= 0:
			_draw_dot(i, q, screen_pos)

	# Draw current territory last
	if _current_idx >= 0:
		var q: Dictionary = _map_qings[_current_idx]
		var screen_pos := _lat_lon_to_globe(q.lat, q.lon, center, globe_radius)
		q["screen_pos"] = screen_pos
		if screen_pos.x >= 0:
			_draw_dot(_current_idx, q, screen_pos)


func _draw_hex_outline(center: Vector2, hex_radius: float, color: Color, width: float) -> void:
	## Draw a hexagonal outline (6-sided polygon) around a point.
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(7):
		var angle := float(i) / 6.0 * TAU - PI / 6.0  # Flat-top hex
		points.append(center + Vector2(cos(angle), sin(angle)) * hex_radius)
	for i in range(6):
		draw_line(points[i], points[i + 1], color, width)


func _draw_dot(idx: int, q: Dictionary, screen_pos: Vector2) -> void:
	## Draw a single QING dot with hex outline and glow effects.
	var is_current: bool = idx == _current_idx
	var is_selected: bool = idx == _selected_idx
	var is_hovered: bool = idx == _hovered_idx

	var dot_color: Color = q.dot_color
	var radius: float = DOT_RADIUS

	# Hex outline for all dots (subtle territory boundary indicator)
	if not is_current:
		var hex_alpha: float = 0.2
		if is_selected:
			hex_alpha = 0.7
		elif is_hovered:
			hex_alpha = 0.5
		var hex_color := Color(dot_color.r, dot_color.g, dot_color.b, hex_alpha)
		var hex_radius: float = radius + 4.0
		if is_selected:
			hex_radius = radius + 6.0
		elif is_hovered:
			hex_radius = radius + 5.0
		_draw_hex_outline(screen_pos, hex_radius, hex_color, 1.0 if not is_selected else 1.5)

	# Glow halo on hover/select
	if is_hovered and not is_selected and not is_current:
		var glow_col := Color(dot_color.r, dot_color.g, dot_color.b, 0.12)
		draw_circle(screen_pos, radius + 8.0, glow_col)

	if is_current:
		# Current territory: very prominent "YOU ARE HERE" beacon
		var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 2.5)
		var fast_pulse: float = 0.5 + 0.5 * sin(_pulse_time * 5.0)
		radius = 12.0  # Much larger than normal dots

		# Outer pulsing glow ring (large, fading)
		var glow_radius: float = radius + 12.0 + 6.0 * pulse
		draw_arc(screen_pos, glow_radius, 0, TAU, 32,
			Color(COLOR_CURRENT.r, COLOR_CURRENT.g, COLOR_CURRENT.b, 0.15 * pulse), 4.0)

		# Middle pulsing ring
		draw_arc(screen_pos, radius + 7, 0, TAU, 32,
			Color(COLOR_CURRENT.r, COLOR_CURRENT.g, COLOR_CURRENT.b, 0.35 * pulse), 3.0)

		# Inner solid ring
		draw_arc(screen_pos, radius + 3, 0, TAU, 32,
			Color(COLOR_CURRENT.r, COLOR_CURRENT.g, COLOR_CURRENT.b, 0.7), 2.5)

		# Crosshair lines extending from the dot
		var ch_len: float = 20.0 + 5.0 * fast_pulse
		var ch_color := Color(COLOR_CURRENT.r, COLOR_CURRENT.g, COLOR_CURRENT.b, 0.4 * pulse)
		draw_line(Vector2(screen_pos.x - ch_len, screen_pos.y),
			Vector2(screen_pos.x - radius - 4, screen_pos.y), ch_color, 1.5)
		draw_line(Vector2(screen_pos.x + radius + 4, screen_pos.y),
			Vector2(screen_pos.x + ch_len, screen_pos.y), ch_color, 1.5)
		draw_line(Vector2(screen_pos.x, screen_pos.y - ch_len),
			Vector2(screen_pos.x, screen_pos.y - radius - 4), ch_color, 1.5)
		draw_line(Vector2(screen_pos.x, screen_pos.y + radius + 4),
			Vector2(screen_pos.x, screen_pos.y + ch_len), ch_color, 1.5)

		# "YOU ARE HERE" label above the dot (always visible)
		var label_text := "YOU ARE HERE"
		draw_string(ThemeDB.fallback_font,
			Vector2(screen_pos.x - 38, screen_pos.y - radius - 14),
			label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(COLOR_CURRENT.r, COLOR_CURRENT.g, COLOR_CURRENT.b, 0.7 + 0.3 * pulse))

		dot_color = COLOR_CURRENT.lightened(0.2 * fast_pulse)
	elif is_selected:
		radius = SELECTED_RADIUS
		# Cyan selection ring (matching entropy's selected style)
		draw_arc(screen_pos, radius + 3, 0, TAU, 20, COLOR_SELECTED, 2.0)
		dot_color = COLOR_SELECTED
	elif is_hovered:
		radius = HOVER_RADIUS
		dot_color = dot_color.lightened(0.4)

	draw_circle(screen_pos, radius, dot_color)

	# Draw name label next to dot (if cached)
	var addr: String = q.address
	var qing_name: String = _name_cache.get(addr, "")
	if not qing_name.is_empty():
		# Strip " QING" suffix for brevity
		if qing_name.ends_with(" QING"):
			qing_name = qing_name.left(qing_name.length() - 5)
		var label_color := COLOR_TEXT
		if is_current:
			label_color = COLOR_CURRENT
		elif is_selected:
			label_color = COLOR_SELECTED
		elif is_hovered:
			label_color = COLOR_TEXT
		else:
			label_color = Color(dot_color.r, dot_color.g, dot_color.b, 0.85)
		var font_size: int = 10
		if is_current:
			font_size = 14
		elif is_selected or is_hovered:
			font_size = 12
		draw_string(ThemeDB.fallback_font,
			Vector2(screen_pos.x + radius + 4, screen_pos.y + 4),
			qing_name, HORIZONTAL_ALIGNMENT_LEFT, 150, font_size, label_color)


func _draw_info_panel(q: Dictionary) -> void:
	var pos: Vector2 = q.screen_pos
	if pos.x < 0:
		return  # Behind the globe
	var is_current: bool = q.address == _current_territory
	var addr: String = q.address
	var qing_name: String = _name_cache.get(addr, "")
	var has_name: bool = not qing_name.is_empty()

	var panel_w: float = 300.0
	var panel_h: float = 125.0 if has_name else 105.0
	var panel_x: float = pos.x + 18
	var panel_y: float = pos.y - panel_h / 2

	if panel_x + panel_w > size.x - MAP_MARGIN:
		panel_x = pos.x - panel_w - 18
	panel_y = clampf(panel_y, MAP_MARGIN + 20, size.y - MAP_MARGIN - panel_h)

	# Panel background + border (entropy style)
	var panel_rect := Rect2(panel_x, panel_y, panel_w, panel_h)
	draw_rect(panel_rect, COLOR_PANEL_BG)
	draw_rect(panel_rect, COLOR_PANEL_BORDER, false, 1.0)

	var text_x: float = panel_x + 12
	var text_y: float = panel_y + 20

	# Name in large white text (if available)
	if has_name:
		draw_string(ThemeDB.fallback_font, Vector2(text_x, text_y),
			qing_name, HORIZONTAL_ALIGNMENT_LEFT, int(panel_w - 24), 16, COLOR_TEXT)
		text_y += 20

	# Address in cyan
	var short_addr: String = addr.left(6) + "..." + addr.right(4)
	draw_string(ThemeDB.fallback_font, Vector2(text_x, text_y),
		short_addr, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_SELECTED)

	# Current territory badge
	if is_current:
		draw_string(ThemeDB.fallback_font, Vector2(text_x + 160, text_y),
			"YOU ARE HERE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_CURRENT)

	# Coordinates
	text_y += 18
	draw_string(ThemeDB.fallback_font, Vector2(text_x, text_y),
		"Lat: %.4f  Lon: %.4f" % [q.lat, q.lon],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_DIM)

	# Meridian color indicator
	text_y += 18
	var meridian_color: Color = MERIDIAN_COLORS[q.meridian_idx]
	draw_circle(Vector2(text_x + 5, text_y - 3), 4, meridian_color)
	draw_string(ThemeDB.fallback_font, Vector2(text_x + 14, text_y),
		"Meridian %d" % (q.meridian_idx + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_DIM)

	# Action hint
	text_y += 20
	if is_current:
		draw_string(ThemeDB.fallback_font, Vector2(text_x, text_y),
			"Current territory", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_CURRENT)
	elif not has_name:
		draw_string(ThemeDB.fallback_font, Vector2(text_x, text_y),
			"Loading name...", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_DIM)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(text_x, text_y),
			"Click again to travel here",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.8, 0.5))


func _gui_input(event: InputEvent) -> void:
	if not _is_initialized:
		return

	if event is InputEventMouseMotion:
		if _is_globe and _globe_dragging:
			# Rotate globe by dragging
			var delta: Vector2 = event.position - _globe_drag_start
			_globe_rotation = _globe_rot_start + delta.x * 0.005
			_globe_tilt = clampf(_globe_tilt_start - delta.y * 0.005, -1.2, 1.2)
			queue_redraw()
			accept_event()
		else:
			var old_hover := _hovered_idx
			_hovered_idx = _find_nearest_qing(event.position)
			if _hovered_idx != old_hover:
				queue_redraw()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check view toggle buttons first
				var btn_y_range := Rect2(size.x - MAP_MARGIN - 160, 14, 70, 24)
				if btn_y_range.has_point(event.position):
					_is_globe = false
					queue_redraw()
					accept_event()
					return
				var globe_range := Rect2(size.x - MAP_MARGIN - 80, 14, 70, 24)
				if globe_range.has_point(event.position):
					_is_globe = true
					queue_redraw()
					accept_event()
					return

				# Globe drag start
				if _is_globe:
					var globe_clicked := _find_nearest_qing(event.position)
					if globe_clicked < 0:
						# Start dragging globe
						_globe_dragging = true
						_globe_drag_start = event.position
						_globe_rot_start = _globe_rotation
						_globe_tilt_start = _globe_tilt
						accept_event()
						return

				# Click on dot
				var clicked := _find_nearest_qing(event.position)
				if clicked >= 0:
					if clicked == _selected_idx:
						var addr: String = _map_qings[clicked].address
						if addr != _current_territory:
							territory_selected.emit(addr)
					else:
						_selected_idx = clicked
						# Request name if not cached yet
						var sel_addr: String = _map_qings[clicked].address
						if not _name_cache.has(sel_addr):
							name_requested.emit(sel_addr)
						queue_redraw()
				else:
					_selected_idx = -1
					queue_redraw()
				accept_event()
			else:
				# Mouse release — stop globe drag
				_globe_dragging = false

		# Scroll to rotate globe
		elif _is_globe and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if event.pressed:
				var dir := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				_globe_rotation += dir * 0.1
				queue_redraw()
				accept_event()

	elif event is InputEventKey and event.pressed:
		# When search is active, keys go to the LineEdit — skip map key handling
		if _search_active:
			return

		if event.keycode == KEY_ESCAPE or event.keycode == KEY_M:
			map_closed.emit()
			accept_event()
		elif event.keycode == KEY_TAB:
			# Toggle between flat and globe
			_is_globe = not _is_globe
			queue_redraw()
			accept_event()
		elif event.keycode == KEY_S or event.keycode == KEY_SLASH:
			_open_search()
			accept_event()


func _find_nearest_qing(mouse_pos: Vector2) -> int:
	var best_idx: int = -1
	var best_dist: float = HIT_THRESHOLD

	for i in range(_map_qings.size()):
		var screen_pos: Vector2 = _map_qings[i].screen_pos
		if screen_pos.x < 0:
			continue  # Behind globe or not computed
		var dist: float = mouse_pos.distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best_idx = i

	return best_idx


# ─── Search ──────────────────────────────────────────────────────────────

func _open_search() -> void:
	_search_active = true
	_search_input.visible = true
	_search_input.text = ""
	_search_results.clear()
	_search_selected = -1
	_search_input.grab_focus()
	queue_redraw()


func _close_search() -> void:
	_search_active = false
	_search_input.visible = false
	_search_input.release_focus()
	_search_results.clear()
	_search_selected = -1
	# Re-grab focus so _gui_input receives key events again
	grab_focus()
	queue_redraw()


func _on_search_input_gui_input(event: InputEvent) -> void:
	## Intercept special keys while the search LineEdit has focus.
	## LineEdit captures all key input when focused, so we handle
	## Escape, Up, Down here rather than in _gui_input.
	if not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		_close_search()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DOWN:
		if _search_results.size() > 0:
			_search_selected = mini(_search_selected + 1, _search_results.size() - 1)
			_jump_to_search_result(_search_selected)
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_UP:
		if _search_results.size() > 0:
			_search_selected = maxi(_search_selected - 1, 0)
			_jump_to_search_result(_search_selected)
			queue_redraw()
		get_viewport().set_input_as_handled()


func _on_search_text_changed(new_text: String) -> void:
	var query := new_text.strip_edges().to_lower()
	_search_results.clear()
	_search_selected = -1

	if query.length() < 1:
		queue_redraw()
		return

	# Search by name and address
	for i in range(_map_qings.size()):
		var addr: String = _map_qings[i].address
		var qing_name: String = _name_cache.get(addr, "").to_lower()
		if qing_name.contains(query) or addr.contains(query):
			_search_results.append(i)
		if _search_results.size() >= 12:
			break  # Limit results to 12

	# Auto-select first result
	if _search_results.size() > 0:
		_search_selected = 0
		_jump_to_search_result(0)

	queue_redraw()


func _on_search_submitted(_text: String) -> void:
	## Enter pressed in search — travel to the selected result.
	if _search_selected >= 0 and _search_selected < _search_results.size():
		var idx: int = _search_results[_search_selected]
		_selected_idx = idx
		_close_search()
		queue_redraw()


func _jump_to_search_result(result_idx: int) -> void:
	## Center the view on the search result (for globe: rotate to show it).
	if result_idx < 0 or result_idx >= _search_results.size():
		return
	var idx: int = _search_results[result_idx]
	var q: Dictionary = _map_qings[idx]
	_selected_idx = idx

	# Request name if not cached
	if not _name_cache.has(q.address):
		name_requested.emit(q.address)

	if _is_globe:
		# Rotate globe to center on this QING
		_globe_rotation = -deg_to_rad(q.lon)
		_globe_tilt = clampf(deg_to_rad(q.lat) * 0.5, -1.2, 1.2)


func _draw_search_results() -> void:
	## Draw search results list below the search input.
	if not _search_active or _search_results.is_empty():
		return

	var panel_x: float = MAP_MARGIN
	var panel_y: float = 85.0  # Below search input
	var item_h: float = 24.0
	var panel_w: float = 300.0
	var panel_h: float = item_h * _search_results.size() + 8.0

	# Panel background
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), COLOR_PANEL_BG)
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), COLOR_PANEL_BORDER, false, 1.0)

	for ri in range(_search_results.size()):
		var idx: int = _search_results[ri]
		var q: Dictionary = _map_qings[idx]
		var addr: String = q.address
		var qing_name: String = _name_cache.get(addr, "")
		var display_name: String = qing_name if not qing_name.is_empty() else addr.left(6) + "..." + addr.right(4)

		var item_y: float = panel_y + 4.0 + ri * item_h
		var is_sel: bool = ri == _search_selected
		var is_cur: bool = idx == _current_idx

		# Highlight selected row
		if is_sel:
			draw_rect(Rect2(panel_x + 2, item_y, panel_w - 4, item_h - 2),
				Color(COLOR_SELECTED.r, COLOR_SELECTED.g, COLOR_SELECTED.b, 0.15))

		# Dot color indicator
		var dot_color: Color = q.dot_color
		draw_circle(Vector2(panel_x + 14, item_y + item_h / 2 - 1), 4.0, dot_color)

		# Name text
		var text_color := COLOR_TEXT
		if is_cur:
			text_color = COLOR_CURRENT
		elif is_sel:
			text_color = COLOR_SELECTED

		draw_string(ThemeDB.fallback_font,
			Vector2(panel_x + 24, item_y + item_h - 7),
			display_name, HORIZONTAL_ALIGNMENT_LEFT, int(panel_w - 36), 12, text_color)

		# "HERE" tag for current territory
		if is_cur:
			draw_string(ThemeDB.fallback_font,
				Vector2(panel_x + panel_w - 42, item_y + item_h - 7),
				"HERE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_CURRENT)
