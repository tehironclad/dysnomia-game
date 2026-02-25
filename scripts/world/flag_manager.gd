extends Node3D
## Manages territory flags — up to 20 visible flags from API data.
## Spawns FlagMarker instances for each flag entry.
## Supports planting new flags at the player's position.

const FlagMarkerScript = preload("res://scripts/world/flag_marker.gd")
const MAX_FLAGS: int = 20

signal flag_count_changed(count: int)

var _flags: Array[Node3D] = []
var _terrain_gen: Node3D


func initialize(terrain_gen: Node3D) -> void:
	_terrain_gen = terrain_gen


func load_flags(flag_data: Array) -> void:
	## Load flags from API response array.
	## Each entry: {wallet, username, message, position: {x,y,z}, timestamp}
	_clear_flags()

	var count: int = 0
	for entry in flag_data:
		if count >= MAX_FLAGS:
			break
		if not entry is Dictionary:
			continue

		var flag := Node3D.new()
		flag.set_script(FlagMarkerScript)
		flag.name = "Flag_%d" % count
		add_child(flag)
		flag.initialize(entry)

		# Snap Y to terrain height if terrain is available
		if _terrain_gen and _terrain_gen.has_method("get_height_at"):
			var h: float = _terrain_gen.get_height_at(flag.position.x, flag.position.z)
			flag.position.y = h

		_flags.append(flag)
		count += 1

	flag_count_changed.emit(_flags.size())
	print("[FlagManager] Loaded %d flags" % _flags.size())


func plant_flag_at(pos: Vector3, data: Dictionary) -> void:
	## Add a local flag immediately (before API confirms).
	if _flags.size() >= MAX_FLAGS:
		# Remove oldest flag to make room
		var oldest: Node3D = _flags.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	# Snap Y to terrain
	var snap_y := pos.y
	if _terrain_gen and _terrain_gen.has_method("get_height_at"):
		snap_y = _terrain_gen.get_height_at(pos.x, pos.z)

	data["position"] = {"x": pos.x, "y": snap_y, "z": pos.z}

	var flag := Node3D.new()
	flag.set_script(FlagMarkerScript)
	flag.name = "Flag_%d" % _flags.size()
	add_child(flag)
	flag.initialize(data)
	flag.position.y = snap_y

	_flags.append(flag)
	flag_count_changed.emit(_flags.size())


func get_flag_count() -> int:
	return _flags.size()


func get_flag_positions() -> Array[Vector3]:
	## Return all flag positions for minimap rendering.
	var positions: Array[Vector3] = []
	for f in _flags:
		if is_instance_valid(f):
			positions.append(f.position)
	return positions


func _clear_flags() -> void:
	for f in _flags:
		if is_instance_valid(f):
			f.queue_free()
	_flags.clear()
