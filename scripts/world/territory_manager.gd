extends Node3D
## Manages the center territory plus up to 4 neighbors (N/S/E/W).
## Each neighbor is separated by a force field wall.
## Joining a territory (on-chain tx or offline) dissolves the wall.

const MOTZKIN_PRIME: int = 953467954114363
const TERRAIN_SIZE: float = 400.0
const BORDER_HEIGHT: float = 40.0
const INTERACT_DISTANCE: float = 15.0  # How close to border to show prompt

# Direction enum
enum Direction { NORTH, SOUTH, EAST, WEST }

# Primes for deterministic neighbor seed derivation
const NEIGHBOR_PRIMES: Array[int] = [7919, 7927, 7933, 7937]

# Offsets per direction (where to place neighbor terrain origin)
const DIRECTION_OFFSETS: Dictionary = {
	Direction.NORTH: Vector3(0.0, 0.0, -TERRAIN_SIZE),
	Direction.SOUTH: Vector3(0.0, 0.0, TERRAIN_SIZE),
	Direction.EAST: Vector3(TERRAIN_SIZE, 0.0, 0.0),
	Direction.WEST: Vector3(-TERRAIN_SIZE, 0.0, 0.0),
}

# Where force field walls sit (at territory edge, between center and neighbor)
const WALL_POSITIONS: Dictionary = {
	Direction.NORTH: Vector3(0.0, 0.0, -TERRAIN_SIZE / 2.0),
	Direction.SOUTH: Vector3(0.0, 0.0, TERRAIN_SIZE / 2.0),
	Direction.EAST: Vector3(TERRAIN_SIZE / 2.0, 0.0, 0.0),
	Direction.WEST: Vector3(-TERRAIN_SIZE / 2.0, 0.0, 0.0),
}

# Rotation for walls (face inward toward center)
const WALL_ROTATIONS: Dictionary = {
	Direction.NORTH: 0.0,         # Faces +Z (toward center)
	Direction.SOUTH: PI,          # Faces -Z (toward center)
	Direction.EAST: -PI / 2.0,    # Faces -X (toward center)
	Direction.WEST: PI / 2.0,     # Faces +X (toward center)
}

const DIRECTION_NAMES: Dictionary = {
	Direction.NORTH: "North",
	Direction.SOUTH: "South",
	Direction.EAST: "East",
	Direction.WEST: "West",
}

# Scene to instance for each neighbor terrain
var _territory_scene: PackedScene

# Center territory reference (from main scene)
var _center_terrain: Node3D
var _center_seed: int = 0
var _center_address: String = ""

# Neighbor data
var _neighbors: Dictionary = {}  # Direction -> {terrain, force_field, seed, address, name, is_joined}

# Current territory tracking (-1 = center, 0-3 = neighbor direction)
var _current_territory: int = -1

# Signals
signal neighbor_join_prompt(direction: int, name: String)
signal neighbor_join_prompt_hide()
signal join_started(direction: int)
signal join_completed(direction: int)
signal territory_entered(direction: int, name: String, address: String)  # -1 = center


func _ready() -> void:
	_territory_scene = load("res://scenes/world/territory.tscn") as PackedScene


func initialize(center_terrain: Node3D, center_seed: int, center_address: String, terrain_material: ShaderMaterial) -> void:
	## Set up center and spawn all neighbors + force fields.
	_center_terrain = center_terrain
	_center_seed = center_seed
	_center_address = center_address

	for dir in [Direction.NORTH, Direction.SOUTH, Direction.EAST, Direction.WEST]:
		_spawn_neighbor(dir, terrain_material)


func _spawn_neighbor(direction: int, center_material: ShaderMaterial) -> void:
	## Create a neighbor terrain and force field for one direction.
	var n_seed := neighbor_seed(_center_seed, direction)
	var n_params := GameManager.seed_to_params(n_seed)
	var offset: Vector3 = DIRECTION_OFFSETS[direction]

	# Instance and generate neighbor terrain at half resolution
	var terrain: Node3D = _territory_scene.instantiate()
	terrain.name = "Neighbor_%s" % DIRECTION_NAMES[direction]
	terrain.position = offset
	add_child(terrain)

	# Build neighbor-specific material from their biome
	var biome := BiomeSystem.get_biome(n_seed)
	var shader := load("res://assets/shaders/terrain.gdshader") as Shader
	var n_material := ShaderMaterial.new()
	n_material.shader = shader
	n_material.set_shader_parameter("grass_color", biome.grass_color)
	n_material.set_shader_parameter("grass_color_2", biome.grass_color_2)
	n_material.set_shader_parameter("rock_color", biome.rock_color)
	n_material.set_shader_parameter("rock_color_2", biome.rock_color_2)
	n_material.set_shader_parameter("soil_color", biome.soil_color)
	n_material.set_shader_parameter("snow_color", biome.snow_color)
	n_material.set_shader_parameter("water_color", biome.water_color)
	n_material.set_shader_parameter("snow_line", biome.snow_line)
	n_material.set_shader_parameter("water_level", biome.water_level)

	terrain.set_shader_material(n_material)
	terrain.generate(n_seed, n_params, 128)  # Half resolution for LOD

	# Disable neighbor collision until joined (visual only)
	_set_terrain_collision_enabled(terrain, false)

	# Create force field wall
	var ff := Node3D.new()
	ff.set_script(load("res://scripts/world/force_field.gd"))
	ff.name = "ForceField_%s" % DIRECTION_NAMES[direction]
	ff.position = WALL_POSITIONS[direction]
	ff.rotation.y = WALL_ROTATIONS[direction]
	add_child(ff)
	ff.setup(direction, TERRAIN_SIZE, BORDER_HEIGHT, n_seed)
	ff.dissolved.connect(_on_force_field_dissolved)

	# Spawn beacon pillar at neighbor's monument position
	var beacon := _spawn_neighbor_beacon(direction, offset, n_seed, terrain)

	_neighbors[direction] = {
		"terrain": terrain,
		"force_field": ff,
		"beacon": beacon,
		"monument": null,   # Spawned when joined
		"seed": n_seed,
		"address": "",  # Unknown until chain lookup
		"name": "",     # QING name from chain (e.g. "AFFECTION™ QING")
		"is_joined": false,
		"cover_charge": -1,  # -1 = unknown, 0 = free (auto-join), >0 = requires Join tx
	}


func _set_terrain_collision_enabled(terrain: Node3D, enabled: bool) -> void:
	## Enable/disable collision on a terrain's StaticBody3D.
	for child in terrain.get_children():
		if child is StaticBody3D:
			child.set_collision_layer_value(1, enabled)
			child.set_collision_mask_value(1, enabled)


# ─── Neighbor Beacon Pillars ─────────────────────────────────────────────

func _spawn_neighbor_beacon(direction: int, offset: Vector3, n_seed: int, terrain: Node3D) -> MeshInstance3D:
	## Spawn a tall beacon pillar at the neighbor's monument position.
	## Visible from center as a colored light pillar on the horizon.
	var MonumentClass = preload("res://scripts/world/monument.gd")
	var params := MonumentGenerator.get_monument_params(n_seed)
	var accent: Color = params.get("accent_color", Color.CYAN)

	var beacon := MonumentClass.create_beacon_pillar(accent, 80.0)

	# Position at neighbor's monument location (0, terrain_height, -40) relative to their origin
	var monument_local_x: float = 0.0
	var monument_local_z: float = -40.0
	var monument_world_x: float = offset.x + monument_local_x
	var monument_world_z: float = offset.z + monument_local_z

	# Get terrain height at beacon position (local to the neighbor terrain)
	var beacon_y: float = 0.0
	if terrain and terrain.has_method("get_height_at"):
		beacon_y = terrain.get_height_at(monument_local_x, monument_local_z)

	beacon.position = Vector3(monument_world_x, beacon_y + 40.0, monument_world_z)
	add_child(beacon)

	return beacon


func _update_neighbor_beacon(direction: int, new_seed: int) -> void:
	## Update beacon color when real neighbor seed is discovered.
	if not _neighbors.has(direction):
		return
	var n: Dictionary = _neighbors[direction]
	var old_beacon: MeshInstance3D = n.get("beacon", null)
	if old_beacon:
		old_beacon.queue_free()

	var offset: Vector3 = DIRECTION_OFFSETS[direction]
	var terrain: Node3D = n.terrain
	var beacon := _spawn_neighbor_beacon(direction, offset, new_seed, terrain)
	n.beacon = beacon


# ─── Neighbor Seed ───────────────────────────────────────────────────────

static func neighbor_seed(center_seed: int, direction: int) -> int:
	## Deterministic neighbor seed. Same center + direction = same neighbor always.
	var prime: int = NEIGHBOR_PRIMES[direction] if direction < NEIGHBOR_PRIMES.size() else 7919
	return (center_seed * prime + direction + 1) % MOTZKIN_PRIME


# ─── Player Interaction ──────────────────────────────────────────────────

func get_nearest_border_direction(player_pos: Vector3) -> int:
	## Returns the Direction enum if player is within INTERACT_DISTANCE of a border.
	## Returns -1 if not near any border.
	var half := TERRAIN_SIZE / 2.0

	# Check each edge
	if player_pos.z < -half + INTERACT_DISTANCE:
		if _is_neighbor_joinable(Direction.NORTH):
			return Direction.NORTH
	if player_pos.z > half - INTERACT_DISTANCE:
		if _is_neighbor_joinable(Direction.SOUTH):
			return Direction.SOUTH
	if player_pos.x > half - INTERACT_DISTANCE:
		if _is_neighbor_joinable(Direction.EAST):
			return Direction.EAST
	if player_pos.x < -half + INTERACT_DISTANCE:
		if _is_neighbor_joinable(Direction.WEST):
			return Direction.WEST

	return -1


var _joinable_debug_logged: Dictionary = {}  # direction -> bool, log once per direction

func _is_neighbor_joinable(direction: int) -> bool:
	## Can the player E-key join this neighbor? Only for gated QINGs (CoverCharge > 0).
	## Free QINGs (CoverCharge == 0) auto-join via _check_free_neighbor_crossing().
	if not _neighbors.has(direction):
		return false
	var n: Dictionary = _neighbors[direction]

	# One-time debug log per direction so we can diagnose join failures
	if not _joinable_debug_logged.get(direction, false):
		_joinable_debug_logged[direction] = true
		var ff_active: bool = n.force_field != null and n.force_field.is_active()
		print("[TerritoryManager] _is_neighbor_joinable(%s): addr='%s' is_joined=%s ff_active=%s cover=%d" % [
			DIRECTION_NAMES.get(direction, "?"), n.address.left(14), str(n.is_joined),
			str(ff_active), n.get("cover_charge", -1)])

	if n.is_joined or n.address.is_empty():
		return false
	# Free QINGs don't need E-key — they auto-join on approach
	if n.get("cover_charge", -1) == 0:
		return false
	return n.force_field != null and n.force_field.is_active()


func get_direction_name(direction: int) -> String:
	return DIRECTION_NAMES.get(direction, "Unknown")


func is_direction_joined(direction: int) -> bool:
	## Returns true if the player has joined the neighbor in this direction.
	if not _neighbors.has(direction):
		return false
	return _neighbors[direction].is_joined


func get_neighbor_name(direction: int) -> String:
	## Returns QING name if discovered, otherwise falls back to direction name.
	if _neighbors.has(direction):
		var n: Dictionary = _neighbors[direction]
		if not n.name.is_empty():
			return n.name
	return DIRECTION_NAMES.get(direction, "Unknown") + " Territory"


signal join_rejected(reason: String)


var _pending_admitted_direction: int = -1


func request_join(direction: int) -> void:
	## Start the join flow for a neighbor territory.
	## First checks if user is already admitted (from cached scan or on-chain check).
	## If admitted, skips the wallet tx entirely. Otherwise sends QING.Join(LAU).
	if not _neighbors.has(direction):
		print("[TerritoryManager] request_join(%d): no neighbor data" % direction)
		return
	var n: Dictionary = _neighbors[direction]
	if n.is_joined:
		print("[TerritoryManager] request_join(%d): already joined" % direction)
		return

	print("[TerritoryManager] request_join(%d): addr=%s name=%s lau=%s" % [
		direction, n.address.left(12), n.name.left(20), GameManager.lau_address.left(12)])

	# Need a LAU address for any join flow
	if GameManager.lau_address.is_empty():
		join_rejected.emit("Load your identity first (main menu → Enter LAU Address)")
		return

	# Need a real on-chain address for this neighbor
	if n.address.is_empty():
		join_rejected.emit("Neighbor territory not yet discovered on-chain")
		return

	# Fast path: check if already admitted from cached scan
	if ChainManager.is_admitted_to(n.address):
		print("[TerritoryManager] Already admitted (cached) to %s — skipping join tx" % n.address.left(12))
		_complete_join(direction)
		return

	# Check on-chain Admitted() before requiring wallet tx
	print("[TerritoryManager] Checking on-chain Admitted() for %s on %s" % [
		GameManager.lau_address.left(12), n.address.left(12)])
	_pending_admitted_direction = direction
	join_started.emit(direction)
	ChainManager.check_admitted_for_join(n.address, _on_join_admitted_result)


func _on_join_admitted_result(qing_address: String, admitted: bool) -> void:
	## Handle admitted check result during join flow.
	print("[TerritoryManager] _on_join_admitted_result: qing=%s admitted=%s pending_dir=%d" % [
		qing_address.left(12), str(admitted), _pending_admitted_direction])
	if _pending_admitted_direction < 0:
		return  # Not waiting for a result

	var direction := _pending_admitted_direction
	_pending_admitted_direction = -1

	if admitted:
		# Already admitted — complete join without a tx
		print("[TerritoryManager] On-chain Admitted() confirmed — dissolving force field")
		_complete_join(direction)
		return

	# Not admitted — need wallet tx
	if not ChainManager.is_wallet_connected():
		join_rejected.emit("Not admitted yet — connect wallet to join (main menu)")
		return

	# Send QING.Join(lau_address) transaction via wallet
	var n: Dictionary = _neighbors[direction]
	print("[TerritoryManager] Not admitted — sending Join(%s) to QING %s" % [
		GameManager.lau_address.left(10), n.address.left(10)])
	var tx_id := ChainManager.join_territory(n.address)
	if tx_id >= 0:
		print("[TerritoryManager] Join tx sent: id=%d" % tx_id)
		ChainManager.focus_wallet_page()
	else:
		join_rejected.emit("Failed to send join transaction")


func _complete_join(direction: int) -> void:
	## Finalize joining: dissolve force field, enable collision, spawn monument, mark as joined.
	if not _neighbors.has(direction):
		return
	var n: Dictionary = _neighbors[direction]
	n.is_joined = true

	# Dissolve the force field
	if n.force_field and n.force_field.is_active():
		n.force_field.dissolve(1.5)

	# Enable collision on neighbor terrain
	_set_terrain_collision_enabled(n.terrain, true)

	# Spawn monument on the neighbor territory
	_spawn_neighbor_monument(direction)

	join_completed.emit(direction)
	var display_name := get_neighbor_name(direction)
	print("[TerritoryManager] Joined %s" % display_name)


func complete_join_for_address(qing_address: String) -> void:
	## Called when a join tx confirms — find which neighbor matches and complete.
	for dir in _neighbors:
		var n: Dictionary = _neighbors[dir]
		if n.address.to_lower() == qing_address.to_lower():
			_complete_join(dir)
			return
	# If no address match, might be an offline-generated neighbor — ignore


func _on_force_field_dissolved(direction: int) -> void:
	## Force field finished dissolving.
	pass  # Could trigger effects, sound, etc.


# ─── Real Neighbor Data (from Chain Discovery) ──────────────────────────

func set_neighbor_data(direction: int, data: Dictionary) -> void:
	## Update a neighbor with real on-chain data (address, name, seed from Waat).
	## Regenerates the neighbor terrain with the real seed and biome.
	## If the QING has no cover charge (CoverCharge=0), auto-dissolves force field.
	if not _neighbors.has(direction):
		return

	var n: Dictionary = _neighbors[direction]
	n.address = data.get("address", "")
	n.name = data.get("name", "")
	var cover_charge: int = data.get("cover_charge", -1)
	n.cover_charge = cover_charge

	# If we got a real seed from Waat, regenerate terrain with correct biome
	var real_seed: int = data.get("seed", 0)
	if real_seed > 0 and real_seed != n.seed:
		n.seed = real_seed
		_regenerate_neighbor_terrain(direction, n, real_seed)

	# Update beacon with real seed color
	if real_seed > 0:
		_update_neighbor_beacon(direction, n.seed)

	print("[TerritoryManager] Discovered %s neighbor: %s (%s) cover_charge=%d" % [
		DIRECTION_NAMES[direction], n.name, n.address.left(10) + "...", cover_charge])

	# Free QINGs (CoverCharge == 0) are auto-joinable but we defer the actual join
	# until the player approaches the border. See _check_free_neighbor_crossing().


func _regenerate_neighbor_terrain(direction: int, n: Dictionary, new_seed: int) -> void:
	## Regenerate a neighbor's terrain mesh with a new seed and biome.
	var terrain: Node3D = n.terrain
	if not terrain:
		return

	var new_params := GameManager.seed_to_params(new_seed)

	# Build new material from real biome
	var biome := BiomeSystem.get_biome(new_seed)
	var shader := load("res://assets/shaders/terrain.gdshader") as Shader
	var n_material := ShaderMaterial.new()
	n_material.shader = shader
	n_material.set_shader_parameter("grass_color", biome.grass_color)
	n_material.set_shader_parameter("grass_color_2", biome.grass_color_2)
	n_material.set_shader_parameter("rock_color", biome.rock_color)
	n_material.set_shader_parameter("rock_color_2", biome.rock_color_2)
	n_material.set_shader_parameter("soil_color", biome.soil_color)
	n_material.set_shader_parameter("snow_color", biome.snow_color)
	n_material.set_shader_parameter("water_color", biome.water_color)
	n_material.set_shader_parameter("snow_line", biome.snow_line)
	n_material.set_shader_parameter("water_level", biome.water_level)

	terrain.set_shader_material(n_material)
	terrain.generate(new_seed, new_params, 128)  # Half resolution for LOD

	# Keep collision disabled until joined
	if not n.is_joined:
		_set_terrain_collision_enabled(terrain, false)


# ─── Terrain Height Queries ──────────────────────────────────────────────

func get_terrain_at(world_pos: Vector3) -> Node3D:
	## Returns the correct terrain generator for a given world position.
	## Checks if position is within a joined neighbor territory.
	var half := TERRAIN_SIZE / 2.0

	# Check if player is outside center territory bounds
	if world_pos.x < -half or world_pos.x > half or world_pos.z < -half or world_pos.z > half:
		# Find which neighbor they're in
		for dir in _neighbors:
			var n: Dictionary = _neighbors[dir]
			if not n.is_joined:
				continue
			var offset: Vector3 = DIRECTION_OFFSETS[dir]
			var local_pos := world_pos - offset
			if absf(local_pos.x) <= half and absf(local_pos.z) <= half:
				return n.terrain

	# Default to center terrain
	return _center_terrain


func get_height_at(world_x: float, world_z: float) -> float:
	## Get terrain height at any world position, checking neighbors.
	var terrain := get_terrain_at(Vector3(world_x, 0.0, world_z))
	if terrain and terrain.has_method("get_height_at"):
		# Convert world coords to terrain-local coords
		var local_x := world_x - terrain.position.x
		var local_z := world_z - terrain.position.z
		return terrain.get_height_at(local_x, local_z)
	return 0.0


# ─── Player Territory Tracking ──────────────────────────────────────────

func update_player_territory(player_pos: Vector3) -> void:
	## Check which territory the player is in and emit signal on change.
	## Also auto-joins free neighbors when the player approaches the border.
	## Call from main scene _process() with player position.

	# Auto-join free neighbors when player is near the border
	_check_free_neighbor_crossing(player_pos)

	var new_territory: int = _detect_territory(player_pos)
	if new_territory != _current_territory:
		_current_territory = new_territory
		var tname: String
		var taddr: String
		if new_territory < 0:
			tname = GameManager.territory_name if not GameManager.territory_name.is_empty() else "Home Territory"
			taddr = GameManager.territory_address
		else:
			tname = get_neighbor_name(new_territory)
			taddr = _neighbors[new_territory].address if _neighbors.has(new_territory) else ""
		territory_entered.emit(new_territory, tname, taddr)


func _check_free_neighbor_crossing(player_pos: Vector3) -> void:
	## When the player approaches a border with a free QING (CoverCharge=0),
	## auto-join it — dissolve force field, enable collision, spawn monument.
	## No E-key needed for free territories.
	var half := TERRAIN_SIZE / 2.0
	var threshold := half - INTERACT_DISTANCE  # Same distance as the E-key prompt

	for dir in _neighbors:
		var n: Dictionary = _neighbors[dir]
		if n.is_joined or n.address.is_empty():
			continue
		if n.get("cover_charge", -1) != 0:
			continue  # Not free, or unknown — skip

		# Check if player is near this border
		var near := false
		match dir:
			Direction.NORTH:
				near = player_pos.z < -threshold
			Direction.SOUTH:
				near = player_pos.z > threshold
			Direction.EAST:
				near = player_pos.x > threshold
			Direction.WEST:
				near = player_pos.x < -threshold

		if near:
			print("[TerritoryManager] Player approaching free %s QING %s — auto-joining" % [
				DIRECTION_NAMES[dir], n.name])
			_complete_join(dir)


func _detect_territory(world_pos: Vector3) -> int:
	## Returns -1 for center territory, or Direction enum for a neighbor.
	var half := TERRAIN_SIZE / 2.0
	if world_pos.x >= -half and world_pos.x <= half and world_pos.z >= -half and world_pos.z <= half:
		return -1  # Center territory
	# Check joined neighbors
	for dir in _neighbors:
		var n: Dictionary = _neighbors[dir]
		if not n.is_joined:
			continue
		var offset: Vector3 = DIRECTION_OFFSETS[dir]
		var local_pos := world_pos - offset
		if absf(local_pos.x) <= half and absf(local_pos.z) <= half:
			return dir
	return -1  # Outside all known territories — keep current


func get_current_territory_direction() -> int:
	## Returns current territory direction (-1 = center, 0-3 = neighbor).
	return _current_territory


# ─── Neighbor Monuments ─────────────────────────────────────────────────

const MonumentScript = preload("res://scripts/world/monument.gd")

func _spawn_neighbor_monument(direction: int) -> void:
	## Spawn a mausoleum monument on a joined neighbor territory.
	## Flattens the terrain and places the monument at the same relative
	## position as the center monument (0, height, -40 local to terrain).
	if not _neighbors.has(direction):
		return
	var n: Dictionary = _neighbors[direction]
	if n.get("monument") != null:
		return  # Already spawned

	var terrain: Node3D = n.terrain
	if not terrain:
		return

	var n_seed: int = n.seed
	var offset: Vector3 = DIRECTION_OFFSETS[direction]

	# Flatten terrain at monument site (same relative position as center)
	var monument_local_x: float = 0.0
	var monument_local_z: float = -40.0
	_flatten_neighbor_monument_site(terrain, n_seed, monument_local_x, monument_local_z)

	# Get height after flattening
	var monument_y: float = 0.0
	if terrain.has_method("get_height_at"):
		monument_y = terrain.get_height_at(monument_local_x, monument_local_z)

	# Create monument at world position (neighbor offset + local position)
	var monument := Node3D.new()
	monument.set_script(MonumentScript)
	monument.name = "Monument_%s" % DIRECTION_NAMES[direction]
	monument.position = Vector3(
		offset.x + monument_local_x,
		monument_y,
		offset.z + monument_local_z
	)
	add_child(monument)
	monument.initialize(n_seed)

	n.monument = monument
	print("[TerritoryManager] Spawned monument for %s neighbor (seed=%d)" % [
		DIRECTION_NAMES[direction], n_seed])


func _flatten_neighbor_monument_site(terrain: Node3D, n_seed: int, mon_x: float, mon_z: float) -> void:
	## Flatten a neighbor terrain around the monument location.
	if not terrain.has_method("flatten_area"):
		return

	var params := MonumentGenerator.get_monument_params(n_seed)
	var cw: float = params.get("chamber_width", 50.0)
	var cd: float = params.get("chamber_depth", 35.0)
	var brd: float = params.get("back_room_depth", 18.0)
	var wt: float = params.get("wall_thickness", 4.0)

	var total_depth: float = cd + brd
	var site_center_z: float = mon_z - total_depth * 0.5
	var site_half_w: float = (cw + wt * 2.0) * 0.5 + 5.0
	var site_half_d: float = total_depth * 0.5 + 5.0

	# Flatten building site
	terrain.flatten_area(mon_x, site_center_z, site_half_w, site_half_d, 20.0)

	# Flatten approach path
	var approach_center_z: float = mon_z * 0.5
	var approach_half_w: float = 15.0
	var approach_half_d: float = absf(mon_z) * 0.5 + 5.0
	terrain.flatten_area(mon_x, approach_center_z, approach_half_w, approach_half_d, 15.0)
