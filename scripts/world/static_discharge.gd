extends Node3D
## Static discharge event — lightning arcs flash between world structures.
## Uses ImmediateMesh to draw jagged arc lines with OmniLight3D flashes.
## Arcs fire periodically (every 2-4s) between random structure positions.
## Spawned and managed by WeatherSystem.

signal discharge_flash(position: Vector3)

const ARC_COUNT: int = 4                # Number of arc channels
const ARC_INTERVAL_MIN: float = 2.0     # Min seconds between arc flashes
const ARC_INTERVAL_MAX: float = 4.0     # Max seconds between arc flashes
const ARC_FLASH_DURATION: float = 0.15  # How long a single arc flash is visible
const ARC_SEGMENTS: int = 8             # Line segments per arc (jaggedness)
const ARC_JITTER: float = 3.0           # Max displacement per segment
const LIGHT_ENERGY: float = 12.0        # OmniLight flash intensity
const LIGHT_RANGE: float = 40.0

var _player: Node3D
var _structure_positions: Array[Vector3] = []
var _duration: float = 60.0
var _elapsed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Per-arc state: each arc has its own timer, mesh, and light
var _arc_timers: Array[float] = []
var _arc_flash_timers: Array[float] = []  # -1 = not flashing
var _arc_meshes: Array[MeshInstance3D] = []
var _arc_lights: Array[OmniLight3D] = []


func set_duration(d: float) -> void:
	_duration = maxf(d, 10.0)


func initialize(player: Node3D, structure_positions: Array[Vector3]) -> void:
	_player = player
	_structure_positions = structure_positions
	_rng.seed = Time.get_ticks_msec()

	# Need at least 2 positions for arcs
	if _structure_positions.size() < 2:
		_structure_positions.append(Vector3(-20.0, 10.0, -20.0))
		_structure_positions.append(Vector3(20.0, 12.0, 20.0))

	# Initialize arc channels
	var arc_count := mini(ARC_COUNT, _structure_positions.size() - 1)
	for i in range(arc_count):
		# Stagger initial timers so arcs don't all fire at once
		_arc_timers.append(_rng.randf_range(0.5, ARC_INTERVAL_MAX))
		_arc_flash_timers.append(-1.0)

		# Create mesh instance for the arc line (hidden initially)
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "ArcMesh_%d" % i
		mesh_inst.visible = false
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mesh_inst)
		_arc_meshes.append(mesh_inst)

		# Create light for flash
		var light := OmniLight3D.new()
		light.name = "ArcLight_%d" % i
		light.light_color = Color(0.7, 0.8, 1.0)
		light.light_energy = 0.0  # Off until flash
		light.omni_range = LIGHT_RANGE
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_arc_lights.append(light)


func _process(delta: float) -> void:
	_elapsed += delta

	var fade := _get_fade_factor()

	for i in range(_arc_timers.size()):
		# Count down to next arc flash
		_arc_timers[i] -= delta

		if _arc_timers[i] <= 0.0 and _arc_flash_timers[i] < 0.0:
			# Trigger a new flash
			_fire_arc(i, fade)
			_arc_timers[i] = _rng.randf_range(ARC_INTERVAL_MIN, ARC_INTERVAL_MAX)

		# Animate active flash
		if _arc_flash_timers[i] >= 0.0:
			_arc_flash_timers[i] += delta
			_update_arc_flash(i)


func _fire_arc(arc_index: int, fade: float) -> void:
	## Select two random structure positions and build a jagged arc between them.
	if _structure_positions.size() < 2:
		return

	var idx_a := _rng.randi_range(0, _structure_positions.size() - 1)
	var idx_b := idx_a
	while idx_b == idx_a:
		idx_b = _rng.randi_range(0, _structure_positions.size() - 1)

	var pos_a := _structure_positions[idx_a]
	var pos_b := _structure_positions[idx_b]

	# Build jagged arc mesh using ImmediateMesh
	var im := ImmediateMesh.new()
	_build_arc_geometry(im, pos_a, pos_b)

	# Apply material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.85, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.8, 1.0)
	mat.emission_energy_multiplier = 5.0 * fade
	mat.no_depth_test = true
	im.surface_set_material(0, mat)

	_arc_meshes[arc_index].mesh = im
	_arc_meshes[arc_index].visible = true

	# Position light at midpoint of the arc
	var midpoint := (pos_a + pos_b) * 0.5
	_arc_lights[arc_index].global_position = midpoint
	_arc_lights[arc_index].light_energy = LIGHT_ENERGY * fade
	_arc_lights[arc_index].visible = true

	_arc_flash_timers[arc_index] = 0.0

	# Emit signal for screen shake
	discharge_flash.emit(midpoint)


func _build_arc_geometry(im: ImmediateMesh, from: Vector3, to: Vector3) -> void:
	## Draw a jagged line from `from` to `to` using ARC_SEGMENTS line segments.
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var direction := to - from
	var length := direction.length()
	var step := direction / float(ARC_SEGMENTS)

	# Build a local perpendicular basis for jitter
	var forward := direction.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = forward.cross(Vector3.RIGHT).normalized()
	var up := right.cross(forward).normalized()

	for i in range(ARC_SEGMENTS + 1):
		var t := float(i) / float(ARC_SEGMENTS)
		var base_point := from + step * float(i)

		# Add jitter perpendicular to the arc direction (not at endpoints)
		if i > 0 and i < ARC_SEGMENTS:
			var jitter_amount := ARC_JITTER * sin(t * PI)  # More jitter in middle
			base_point += right * _rng.randf_range(-jitter_amount, jitter_amount)
			base_point += up * _rng.randf_range(-jitter_amount, jitter_amount)

		im.surface_add_vertex(base_point)

	im.surface_end()


func _update_arc_flash(arc_index: int) -> void:
	## Animate the arc flash — bright start, quick fade.
	var t := _arc_flash_timers[arc_index]

	if t >= ARC_FLASH_DURATION:
		# Flash is over — hide arc and light
		_arc_meshes[arc_index].visible = false
		_arc_lights[arc_index].visible = false
		_arc_lights[arc_index].light_energy = 0.0
		_arc_flash_timers[arc_index] = -1.0
		return

	# Intensity curve: bright flash then rapid decay
	var progress := t / ARC_FLASH_DURATION
	var intensity := (1.0 - progress) * (1.0 - progress)  # Quadratic falloff

	if _arc_lights[arc_index]:
		_arc_lights[arc_index].light_energy = LIGHT_ENERGY * intensity


func _get_fade_factor() -> float:
	## Global fade envelope: ramp up first 2s, ramp down last 2s.
	var fade := 1.0
	if _elapsed < 2.0:
		fade = _elapsed / 2.0
	elif _elapsed > _duration - 2.0:
		fade = (_duration - _elapsed) / 2.0
	return clampf(fade, 0.0, 1.0)


func cleanup() -> void:
	## Hide all arcs and lights immediately.
	for mesh in _arc_meshes:
		if is_instance_valid(mesh):
			mesh.visible = false
	for light in _arc_lights:
		if is_instance_valid(light):
			light.visible = false
			light.light_energy = 0.0
