extends Node3D
## Utility pipe network connecting territory structures (Monument, Pub, Beat Station).
## CylinderMesh pipes laid along terrain with torus elbow joints at turns,
## and valve wheels at midpoints. Emissive accent glow that scales with
## territory power via update_territory_state().
##
## Routes:
##   Monument (0, -40) -> Pub (60, 0)
##   Pub (60, 0) -> Beat Station (0, 60)

const PIPE_RADIUS: float = 0.15
const GLOW_STRIP_HEIGHT: float = 0.04
const GLOW_STRIP_WIDTH: float = 0.08
const ELBOW_INNER: float = 0.25
const ELBOW_OUTER: float = 0.35
const VALVE_RADIUS: float = 0.3
const VALVE_TUBE: float = 0.03

# Structure positions (XZ)
const MONUMENT_POS := Vector2(0.0, -40.0)
const PUB_POS := Vector2(60.0, 0.0)
const BEAT_STATION_POS := Vector2(0.0, 60.0)

var _pipe_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _valve_material: StandardMaterial3D
var _elbow_material: StandardMaterial3D
var _glow_meshes: Array[MeshInstance3D] = []
var _current_power: float = 0.0


func initialize(terrain_gen: Node3D, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 6100

	_create_materials(rng)

	# Route 1: Monument -> Pub
	var route1: Array[Vector2] = _build_route(MONUMENT_POS, PUB_POS, rng)
	_lay_pipe_route(route1, terrain_gen, "Route1")

	# Route 2: Pub -> Beat Station
	var route2: Array[Vector2] = _build_route(PUB_POS, BEAT_STATION_POS, rng)
	_lay_pipe_route(route2, terrain_gen, "Route2")


func update_territory_state() -> void:
	## Sync glow intensity with on-chain territory power.
	var power: float = 0.0
	if GameManager.has_territory_state:
		power = clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
	_current_power = power

	if _glow_material:
		var energy: float = 0.2 + power * 3.5
		_glow_material.emission_energy_multiplier = energy
		var alpha: float = 0.3 + power * 0.7
		_glow_material.albedo_color.a = alpha


func _create_materials(rng: RandomNumberGenerator) -> void:
	# Dark metallic pipe
	_pipe_material = StandardMaterial3D.new()
	_pipe_material.albedo_color = Color(0.18, 0.17, 0.16)
	_pipe_material.roughness = 0.55
	_pipe_material.metallic = 0.7
	_pipe_material.specular = 0.5

	# Accent glow strip — emissive, scales with power
	var hue: float = rng.randf_range(0.45, 0.65)  # Cyan-to-blue range
	var glow_color := Color.from_hsv(hue, 0.8, 0.9)
	_glow_material = StandardMaterial3D.new()
	_glow_material.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.3)
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.emission_enabled = true
	_glow_material.emission = glow_color
	_glow_material.emission_energy_multiplier = 0.2
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Elbow joint — slightly lighter metal
	_elbow_material = StandardMaterial3D.new()
	_elbow_material.albedo_color = Color(0.25, 0.24, 0.23)
	_elbow_material.roughness = 0.5
	_elbow_material.metallic = 0.65
	_elbow_material.specular = 0.4

	# Valve wheel — rust-red accent
	_valve_material = StandardMaterial3D.new()
	_valve_material.albedo_color = Color(0.5, 0.18, 0.1)
	_valve_material.roughness = 0.7
	_valve_material.metallic = 0.3
	_valve_material.specular = 0.3


func _build_route(from: Vector2, to: Vector2, rng: RandomNumberGenerator) -> Array[Vector2]:
	## Build a multi-segment route with 4-6 waypoints between two structures.
	## Pipes follow L-shaped and zigzag paths, not straight lines.
	var waypoints: Array[Vector2] = [from]
	var seg_count: int = rng.randi_range(4, 6)

	for i in range(1, seg_count):
		var t: float = float(i) / float(seg_count)
		var base: Vector2 = from.lerp(to, t)
		# Add lateral deviation for zigzag routing
		var perp := Vector2(-(to.y - from.y), to.x - from.x).normalized()
		var deviation: float = rng.randf_range(-8.0, 8.0)
		var wp: Vector2 = base + perp * deviation
		waypoints.append(wp)

	waypoints.append(to)
	return waypoints


func _lay_pipe_route(waypoints: Array[Vector2], terrain_gen: Node3D, route_name: String) -> void:
	## Lay pipe segments between consecutive waypoints. Add elbows at turns
	## and valve wheels at midpoints.
	var valve_placed: bool = false
	var mid_segment: int = waypoints.size() / 2

	for i in range(waypoints.size() - 1):
		var p0: Vector2 = waypoints[i]
		var p1: Vector2 = waypoints[i + 1]

		# Query terrain height at start and end
		var y0: float = 0.5  # Default above ground
		var y1: float = 0.5
		if terrain_gen.has_method("get_height_at"):
			y0 = terrain_gen.get_height_at(p0.x, p0.y) + 0.3
			y1 = terrain_gen.get_height_at(p1.x, p1.y) + 0.3

		var start := Vector3(p0.x, y0, p0.y)
		var end := Vector3(p1.x, y1, p1.y)
		var midpoint: Vector3 = (start + end) * 0.5
		var length: float = start.distance_to(end)
		var direction: Vector3 = (end - start).normalized()

		if length < 0.5:
			continue

		# Pipe segment — horizontal cylinder
		var cyl := CylinderMesh.new()
		cyl.top_radius = PIPE_RADIUS
		cyl.bottom_radius = PIPE_RADIUS
		cyl.height = length
		cyl.radial_segments = 8

		var inst := MeshInstance3D.new()
		inst.name = "%s_Pipe_%d" % [route_name, i]
		inst.mesh = cyl
		inst.material_override = _pipe_material
		inst.position = midpoint
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		# Orient cylinder along the segment direction
		if direction.length() > 0.01:
			inst.look_at(inst.position + direction)
			inst.rotate_object_local(Vector3.RIGHT, PI * 0.5)

		add_child(inst)

		# Glow strip on top of pipe
		var strip := BoxMesh.new()
		strip.size = Vector3(GLOW_STRIP_WIDTH, GLOW_STRIP_HEIGHT, length * 0.9)

		var strip_inst := MeshInstance3D.new()
		strip_inst.name = "%s_Glow_%d" % [route_name, i]
		strip_inst.mesh = strip
		strip_inst.material_override = _glow_material
		strip_inst.position = midpoint + Vector3(0.0, PIPE_RADIUS + GLOW_STRIP_HEIGHT * 0.5, 0.0)

		# Match pipe orientation
		if direction.length() > 0.01:
			strip_inst.look_at(strip_inst.position + direction)

		add_child(strip_inst)
		_glow_meshes.append(strip_inst)

		# Elbow joint at each waypoint (not at start/end structures)
		if i > 0 and i < waypoints.size() - 1:
			_add_elbow(start, terrain_gen)

		# Valve wheel at the midpoint segment
		if i == mid_segment and not valve_placed:
			_add_valve(midpoint, direction)
			valve_placed = true


func _add_elbow(pos: Vector3, terrain_gen: Node3D) -> void:
	## Torus elbow joint at a pipe waypoint.
	var torus := TorusMesh.new()
	torus.inner_radius = ELBOW_INNER
	torus.outer_radius = ELBOW_OUTER
	torus.ring_segments = 12
	torus.rings = 8

	var inst := MeshInstance3D.new()
	inst.mesh = torus
	inst.material_override = _elbow_material
	inst.position = pos
	inst.scale = Vector3(1.0, 0.6, 1.0)  # Flatten slightly for pipe junction look
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(inst)


func _add_valve(pos: Vector3, pipe_dir: Vector3) -> void:
	## Valve wheel assembly at a pipe midpoint.
	## Torus wheel + CylinderMesh handle stem.

	# Valve wheel (torus)
	var wheel := TorusMesh.new()
	wheel.inner_radius = VALVE_RADIUS
	wheel.outer_radius = VALVE_RADIUS + VALVE_TUBE
	wheel.ring_segments = 16
	wheel.rings = 8

	var wheel_inst := MeshInstance3D.new()
	wheel_inst.name = "ValveWheel"
	wheel_inst.mesh = wheel
	wheel_inst.material_override = _valve_material
	# Position above pipe, rotated perpendicular to pipe direction
	wheel_inst.position = pos + Vector3(0.0, PIPE_RADIUS + VALVE_RADIUS + 0.1, 0.0)
	wheel_inst.rotation_degrees.x = 90.0  # Stand upright
	wheel_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(wheel_inst)

	# Handle stem connecting wheel to pipe
	var stem := CylinderMesh.new()
	stem.top_radius = 0.02
	stem.bottom_radius = 0.02
	stem.height = VALVE_RADIUS + 0.1
	stem.radial_segments = 6

	var stem_inst := MeshInstance3D.new()
	stem_inst.name = "ValveStem"
	stem_inst.mesh = stem
	stem_inst.material_override = _valve_material
	stem_inst.position = pos + Vector3(0.0, PIPE_RADIUS + (VALVE_RADIUS + 0.1) * 0.5, 0.0)
	add_child(stem_inst)

	# Cross handle through the wheel center
	var handle := CylinderMesh.new()
	handle.top_radius = 0.015
	handle.bottom_radius = 0.015
	handle.height = VALVE_RADIUS * 1.6
	handle.radial_segments = 4

	var handle_inst := MeshInstance3D.new()
	handle_inst.name = "ValveHandle"
	handle_inst.mesh = handle
	handle_inst.material_override = _valve_material
	handle_inst.position = wheel_inst.position
	handle_inst.rotation_degrees.z = 90.0  # Horizontal cross
	add_child(handle_inst)
