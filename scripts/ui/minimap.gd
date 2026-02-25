extends Control
## Circular mini-map showing nearby POIs, creatures, remote players, and terrain.
## Positioned in the bottom-right corner of the HUD. N key toggles visibility.

const TERRAIN_SIZE: float = 400.0
const MAP_RADIUS: float = 50.0  # Pixels
const MAP_VIEW_RANGE: float = 120.0  # World-space meters shown on map

enum POIType { MONUMENT, BEAT_STATION, PUB, VEHICLE, CREATURE, REMOTE_PLAYER, FLAG }

var _player_pos: Vector3 = Vector3.ZERO
var _player_heading: float = 0.0  # Radians

var _pois: Array[Dictionary] = []
var _creature_positions: Array[Vector3] = []
var _remote_positions: Dictionary = {}  # wallet -> Vector3

# Cached terrain heightmap for minimap background (low-res)
var _terrain_colors: PackedColorArray
var _terrain_res: int = 32
var _terrain_cached: bool = false
var _terrain_gen: Node3D


func initialize(terrain_gen: Node3D) -> void:
	_terrain_gen = terrain_gen
	_cache_terrain_colors()


func _ready() -> void:
	# Position bottom-right
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	custom_minimum_size = Vector2(MAP_RADIUS * 2 + 8, MAP_RADIUS * 2 + 8)
	size = custom_minimum_size
	position = Vector2(-(MAP_RADIUS * 2 + 24), -(MAP_RADIUS * 2 + 24))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = Config.minimap_enabled


func _cache_terrain_colors() -> void:
	_terrain_colors.resize(_terrain_res * _terrain_res)
	if not _terrain_gen or not _terrain_gen.has_method("get_height_at"):
		# Fallback: flat grey
		for i in range(_terrain_colors.size()):
			_terrain_colors[i] = Color(0.15, 0.15, 0.18, 1.0)
		_terrain_cached = true
		return

	# Sample terrain heights and convert to greyscale
	var half := TERRAIN_SIZE * 0.5
	var min_h: float = 999.0
	var max_h: float = -999.0
	var heights: PackedFloat32Array
	heights.resize(_terrain_res * _terrain_res)

	for gy in range(_terrain_res):
		for gx in range(_terrain_res):
			var wx := (float(gx) / float(_terrain_res) - 0.5) * TERRAIN_SIZE
			var wz := (float(gy) / float(_terrain_res) - 0.5) * TERRAIN_SIZE
			var h: float = _terrain_gen.get_height_at(wx, wz)
			heights[gy * _terrain_res + gx] = h
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)

	var range_h := maxf(max_h - min_h, 1.0)
	for i in range(heights.size()):
		var norm := (heights[i] - min_h) / range_h
		var c := lerpf(0.08, 0.30, norm)
		_terrain_colors[i] = Color(c, c, c * 1.1, 1.0)

	_terrain_cached = true


func update_player(pos: Vector3, heading: float) -> void:
	_player_pos = pos
	_player_heading = heading
	queue_redraw()


func add_poi(poi_name: String, world_pos: Vector3, color: Color, poi_type: int) -> void:
	_pois.append({
		"name": poi_name,
		"pos": world_pos,
		"color": color,
		"type": poi_type,
	})


func update_creatures(positions: Array[Vector3]) -> void:
	_creature_positions = positions
	queue_redraw()


func update_remote_players(positions: Dictionary) -> void:
	_remote_positions = positions
	queue_redraw()


func update_flags(positions: Array[Vector3]) -> void:
	## Update flag POIs on the minimap. Replaces existing flag POIs.
	# Remove old flag POIs
	var new_pois: Array[Dictionary] = []
	for poi in _pois:
		if poi["type"] != POIType.FLAG:
			new_pois.append(poi)
	_pois = new_pois

	# Add new flag POIs
	for i in range(positions.size()):
		_pois.append({
			"name": "Flag %d" % (i + 1),
			"pos": positions[i],
			"color": Color(0.9, 0.85, 0.3, 0.9),
			"type": POIType.FLAG,
		})
	queue_redraw()


func _draw() -> void:
	if not visible:
		return

	var cx := MAP_RADIUS + 4.0
	var cy := MAP_RADIUS + 4.0
	var center := Vector2(cx, cy)

	# ── Background circle (dark) ──
	draw_circle(center, MAP_RADIUS + 2.0, Color(0.02, 0.02, 0.04, 0.9))

	# ── Terrain heightmap ──
	if _terrain_cached:
		_draw_terrain(center)

	# ── Border ring ──
	_draw_arc_ring(center, MAP_RADIUS, Color(0.4, 0.3, 0.7, 0.5), 2.0)

	# ── Cardinal directions ──
	_draw_cardinals(center)

	# ── POIs ──
	for poi in _pois:
		var world_offset: Vector3 = poi["pos"] - _player_pos
		var map_pt := _world_to_map(world_offset, center)
		if _in_circle(map_pt, center, MAP_RADIUS - 4.0):
			if poi["type"] == POIType.FLAG:
				# Draw flags as small pennant markers
				_draw_flag_marker(map_pt, poi["color"])
			else:
				var dot_size: float = 4.0 if poi["type"] in [POIType.MONUMENT, POIType.BEAT_STATION, POIType.PUB] else 3.0
				draw_circle(map_pt, dot_size, poi["color"])

	# ── Creatures (red dots) ──
	for cpos in _creature_positions:
		var world_offset := cpos - _player_pos
		var map_pt := _world_to_map(world_offset, center)
		if _in_circle(map_pt, center, MAP_RADIUS - 4.0):
			draw_circle(map_pt, 2.0, Color(0.9, 0.2, 0.15, 0.8))

	# ── Remote players (blue dots) ──
	for wallet in _remote_positions:
		var rpos: Vector3 = _remote_positions[wallet]
		var world_offset := rpos - _player_pos
		var map_pt := _world_to_map(world_offset, center)
		if _in_circle(map_pt, center, MAP_RADIUS - 4.0):
			draw_circle(map_pt, 2.5, Color(0.3, 0.6, 1.0, 0.8))

	# ── Player arrow (always at center) ──
	_draw_player_arrow(center)

	# ── North indicator ──
	var north_offset := Vector2(0, -1).rotated(-_player_heading)
	var north_pt := center + north_offset * (MAP_RADIUS - 8.0)
	draw_circle(north_pt, 3.0, Color(0.9, 0.3, 0.3, 0.8))


func _draw_terrain(center: Vector2) -> void:
	## Draw low-res terrain heightmap as colored pixels.
	var pixel_size := (MAP_RADIUS * 2.0) / float(_terrain_res)
	for gy in range(_terrain_res):
		for gx in range(_terrain_res):
			# Map grid cell to world position
			var wx := (float(gx) / float(_terrain_res) - 0.5) * TERRAIN_SIZE
			var wz := (float(gy) / float(_terrain_res) - 0.5) * TERRAIN_SIZE

			# Convert to map-relative (accounting for player position and rotation)
			var world_offset := Vector3(wx - _player_pos.x, 0, wz - _player_pos.z)
			var map_pt := _world_to_map(world_offset, center)

			if _in_circle(map_pt, center, MAP_RADIUS - 1.0):
				var col: Color = _terrain_colors[gy * _terrain_res + gx]
				draw_rect(Rect2(map_pt - Vector2(pixel_size * 0.5, pixel_size * 0.5),
					Vector2(pixel_size, pixel_size)), col)


func _draw_cardinals(center: Vector2) -> void:
	## Draw N/S/E/W letters around the edge.
	var directions := {
		"N": Vector2(0, -1),
		"S": Vector2(0, 1),
		"E": Vector2(1, 0),
		"W": Vector2(-1, 0),
	}
	for dir_name in directions:
		var dir: Vector2 = directions[dir_name]
		var rotated := dir.rotated(-_player_heading)
		var pt := center + rotated * (MAP_RADIUS + 8.0)
		# Simple text (can't use draw_string easily, use draw_circle as indicator)
		if dir_name == "N":
			# North is shown as the red dot above
			pass


func _draw_flag_marker(pos: Vector2, color: Color) -> void:
	## Draw a small pennant shape for flag POIs.
	var s := 3.0  # Half-size
	# Pole line
	draw_line(pos + Vector2(0, s), pos + Vector2(0, -s), Color(0.7, 0.7, 0.7, 0.8), 1.0)
	# Flag triangle
	var flag_pts := PackedVector2Array([
		pos + Vector2(0, -s),
		pos + Vector2(s * 1.2, -s * 0.4),
		pos + Vector2(0, s * 0.2),
	])
	draw_colored_polygon(flag_pts, color)


func _draw_player_arrow(center: Vector2) -> void:
	## Draw a triangle at center pointing up (player facing direction).
	var arrow_size := 5.0
	var points := PackedVector2Array([
		center + Vector2(0, -arrow_size),
		center + Vector2(-arrow_size * 0.6, arrow_size * 0.5),
		center + Vector2(arrow_size * 0.6, arrow_size * 0.5),
	])
	draw_colored_polygon(points, Color(0.95, 0.95, 0.95, 0.9))


func _draw_arc_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	## Draw a circle ring.
	var segments := 48
	var prev := center + Vector2(radius, 0)
	for i in range(1, segments + 1):
		var angle := float(i) / float(segments) * TAU
		var pt := center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(prev, pt, color, width)
		prev = pt


func _world_to_map(world_offset: Vector3, center: Vector2) -> Vector2:
	## Convert a world-space offset (relative to player) to minimap coordinates.
	## Rotates by player heading so map always shows forward=up.
	var flat := Vector2(world_offset.x, world_offset.z)
	var rotated := flat.rotated(-_player_heading)
	var scale := MAP_RADIUS / MAP_VIEW_RANGE
	return center + rotated * scale


func _in_circle(pt: Vector2, center: Vector2, radius: float) -> bool:
	return pt.distance_to(center) <= radius
