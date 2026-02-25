extends Node3D
## Meta Resonance Array — standalone Beat Station south of player spawn.
## 4 energy pylons in a square with a rotating scanning dish hovering above.
## Triggers the META.Beat() visual: dish spins up, pylons flash, shockwave ripples terrain.
## Built from Godot primitives, materials reuse monument + circle shaders.

signal player_entered_range
signal player_exited_range

const MONUMENT_SHADER = preload("res://assets/shaders/monument.gdshader")
const CIRCLE_SHADER = preload("res://assets/shaders/monument_circle.gdshader")

const INTERACTION_RADIUS: float = 12.0
const PYLON_HEIGHT: float = 12.0
const PYLON_BOTTOM_RADIUS: float = 0.8
const PYLON_TOP_RADIUS: float = 0.3
const PYLON_SPACING: float = 6.0  # Half-width of square formation
const DISH_HEIGHT: float = 10.0
const DISH_RADIUS: float = 3.0
const DISH_TUBE: float = 0.25
const CONDUIT_RADIUS: float = 0.06
const GROUND_RING_SIZE: float = 20.0

# ─── Materials ──────────────────────────────────────────────────────
var _pylon_material: ShaderMaterial
var _conduit_material: ShaderMaterial
var _circle_material: ShaderMaterial
var _dish_material: StandardMaterial3D

# ─── Animated nodes ────────────────────────────────────────────────
var _dish_mesh: MeshInstance3D
var _station_light: OmniLight3D
var _pylon_meshes: Array[MeshInstance3D] = []
var _pylon_mats: Array[StandardMaterial3D] = []  # Per-pylon emissive material for flash

# ─── Animation state ───────────────────────────────────────────────
var _dish_angle: float = 0.0
var _dish_speed: float = 0.5  # Radians per second (normal)
var _beat_effect_timer: float = 0.0  # >0 while beat effect is active
const BEAT_EFFECT_DURATION: float = 3.0
const BEAT_DISH_SPEED: float = 4.0  # 4x spin during beat

var _player_in_range: bool = false
var _params: Dictionary = {}


func initialize(seed_value: int) -> void:
	## Build the entire beat station from the territory seed.
	_params = MonumentGenerator.get_monument_params(seed_value)

	_create_materials()
	_build_pylons()
	_build_dish()
	_build_conduits()
	_build_ground_circle()
	_build_light()
	_build_interaction_area()


func update_territory_state() -> void:
	## Sync shader parameters with on-chain territory state.
	var power := clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
	var bar_sum: int = GameManager.territory_hypobar + GameManager.territory_epibar
	var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)

	var scalars: Dictionary = GameManager.faung_scalars
	var tint_r := clampf(float(scalars.get("phi", 0)) / 1e15, 0.0, 0.3)
	var tint_g := clampf(float(scalars.get("eta", 0)) / 1e15, 0.0, 0.3)
	var tint_b := clampf(float(scalars.get("mu", 0)) / 1e15, 0.0, 0.3)
	var tint := Vector3(tint_r, tint_g, tint_b)

	if _pylon_material:
		_pylon_material.set_shader_parameter("territory_power", power)
		_pylon_material.set_shader_parameter("territory_activity", activity)
		_pylon_material.set_shader_parameter("power_tint", tint)

	if _conduit_material:
		_conduit_material.set_shader_parameter("territory_power", power)
		_conduit_material.set_shader_parameter("territory_activity", activity)

	if _circle_material:
		_circle_material.set_shader_parameter("territory_power", power)

	if _station_light:
		_station_light.light_energy = 2.0 * (0.3 + power * 0.7)


func trigger_beat_effect() -> void:
	## Called when META.Beat() tx confirms — spin up dish, flash pylons, boost light.
	_beat_effect_timer = BEAT_EFFECT_DURATION

	# Instant flash: boost light
	if _station_light:
		_station_light.light_energy = 12.0

	# Flash pylon emissive materials
	for mat in _pylon_mats:
		mat.emission_energy_multiplier = 8.0

	# Boost dish glow
	if _dish_material:
		_dish_material.emission_energy_multiplier = 6.0


func _process(delta: float) -> void:
	if _params.is_empty():
		return

	# ── Dish rotation ──
	var current_speed := _dish_speed
	if _beat_effect_timer > 0.0:
		# Spin faster during beat effect, decelerating toward normal
		var effect_progress := _beat_effect_timer / BEAT_EFFECT_DURATION
		current_speed = lerpf(_dish_speed, BEAT_DISH_SPEED, effect_progress * effect_progress)
	_dish_angle += current_speed * delta
	if _dish_mesh:
		_dish_mesh.rotation.y = _dish_angle

	# ── Beat effect decay ──
	if _beat_effect_timer > 0.0:
		_beat_effect_timer -= delta
		var decay := clampf(_beat_effect_timer / BEAT_EFFECT_DURATION, 0.0, 1.0)

		# Fade pylon flash
		for mat in _pylon_mats:
			mat.emission_energy_multiplier = lerpf(0.5, 8.0, decay * decay)

		# Fade dish glow
		if _dish_material:
			_dish_material.emission_energy_multiplier = lerpf(1.5, 6.0, decay * decay)

		# Fade light
		if _station_light:
			var base_energy := 2.0
			_station_light.light_energy = lerpf(base_energy, 12.0, decay * decay)

		if _beat_effect_timer <= 0.0:
			_beat_effect_timer = 0.0

	# ── Ambient light pulse ──
	if _beat_effect_timer <= 0.0 and _station_light:
		var t := Time.get_ticks_msec() * 0.001
		var pulse := sin(t * 1.2) * 0.2 + 0.8
		_station_light.light_energy = 2.0 * pulse

	# ── Dish bob ──
	if _dish_mesh:
		var t := Time.get_ticks_msec() * 0.001
		_dish_mesh.position.y = DISH_HEIGHT + sin(t * 0.6) * 0.3


# ─── Build Methods ────────────────────────────────────────────────────

func _create_materials() -> void:
	var accent: Color = _params.get("accent_color", Color.CYAN)

	# Pylon material — uses monument shader (energy lines, fresnel)
	_pylon_material = ShaderMaterial.new()
	_pylon_material.shader = MONUMENT_SHADER
	_pylon_material.set_shader_parameter("accent_color", Vector3(accent.r, accent.g, accent.b))
	_pylon_material.set_shader_parameter("glow_intensity", 1.2)
	_pylon_material.set_shader_parameter("wall_darken", 0.0)

	# Conduit material — monument shader, bright thin beams
	_conduit_material = ShaderMaterial.new()
	_conduit_material.shader = MONUMENT_SHADER
	_conduit_material.set_shader_parameter("accent_color", Vector3(accent.r * 0.8, accent.g * 0.9, accent.b))
	_conduit_material.set_shader_parameter("glow_intensity", 1.8)
	_conduit_material.set_shader_parameter("wall_darken", 0.0)

	# Circle material — ground ring shader
	_circle_material = ShaderMaterial.new()
	_circle_material.shader = CIRCLE_SHADER
	_circle_material.set_shader_parameter("accent_color", Vector3(accent.r, accent.g, accent.b))

	# Dish material — StandardMaterial3D with emissive glow (not monument shader, needs transparency)
	_dish_material = StandardMaterial3D.new()
	_dish_material.albedo_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.7)
	_dish_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dish_material.emission_enabled = true
	_dish_material.emission = accent
	_dish_material.emission_energy_multiplier = 1.5
	_dish_material.metallic = 0.6
	_dish_material.roughness = 0.15
	_dish_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL


func _build_pylons() -> void:
	## 4 tapered cylinders in a square formation.
	var accent: Color = _params.get("accent_color", Color.CYAN)
	var positions: Array[Vector3] = [
		Vector3(-PYLON_SPACING, 0.0, -PYLON_SPACING),
		Vector3(PYLON_SPACING, 0.0, -PYLON_SPACING),
		Vector3(-PYLON_SPACING, 0.0, PYLON_SPACING),
		Vector3(PYLON_SPACING, 0.0, PYLON_SPACING),
	]

	for i in positions.size():
		var pos: Vector3 = positions[i]

		# Main pylon body — uses monument shader
		var cyl := CylinderMesh.new()
		cyl.top_radius = PYLON_TOP_RADIUS
		cyl.bottom_radius = PYLON_BOTTOM_RADIUS
		cyl.height = PYLON_HEIGHT

		var inst := MeshInstance3D.new()
		inst.name = "Pylon_%d" % i
		inst.mesh = cyl
		inst.material_override = _pylon_material
		inst.position = pos + Vector3(0.0, PYLON_HEIGHT * 0.5, 0.0)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(inst)
		_pylon_meshes.append(inst)

		# Pylon cap — emissive sphere at top (flashes on beat)
		var cap_mat := StandardMaterial3D.new()
		cap_mat.albedo_color = Color(accent.r * 0.2, accent.g * 0.2, accent.b * 0.2)
		cap_mat.emission_enabled = true
		cap_mat.emission = accent
		cap_mat.emission_energy_multiplier = 0.5
		cap_mat.roughness = 0.1
		cap_mat.metallic = 0.5

		var cap_mesh := SphereMesh.new()
		cap_mesh.radius = PYLON_TOP_RADIUS * 1.5
		cap_mesh.height = PYLON_TOP_RADIUS * 3.0

		var cap_inst := MeshInstance3D.new()
		cap_inst.name = "PylonCap_%d" % i
		cap_inst.mesh = cap_mesh
		cap_inst.material_override = cap_mat
		cap_inst.position = pos + Vector3(0.0, PYLON_HEIGHT + PYLON_TOP_RADIUS * 0.5, 0.0)
		add_child(cap_inst)
		_pylon_mats.append(cap_mat)


func _build_dish() -> void:
	## Hovering parabolic dish at center-top. Rotates continuously.
	## Uses SurfaceTool to generate a concave dish shape instead of a torus.
	_dish_mesh = MeshInstance3D.new()
	_dish_mesh.name = "ScanningDish"
	_dish_mesh.mesh = _create_parabolic_dish(DISH_RADIUS, 1.2, 24, 8)
	_dish_mesh.material_override = _dish_material
	_dish_mesh.position = Vector3(0.0, DISH_HEIGHT, 0.0)
	_dish_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_dish_mesh)

	# Inner ring — slightly smaller, brighter torus nested inside
	var accent: Color = _params.get("accent_color", Color.CYAN)
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5)
	inner_mat.emission_enabled = true
	inner_mat.emission = accent
	inner_mat.emission_energy_multiplier = 2.5
	inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var inner_torus := TorusMesh.new()
	inner_torus.inner_radius = DISH_RADIUS * 0.6
	inner_torus.outer_radius = DISH_RADIUS * 0.6 + DISH_TUBE

	var inner_inst := MeshInstance3D.new()
	inner_inst.name = "InnerRing"
	inner_inst.mesh = inner_torus
	inner_inst.material_override = inner_mat
	# Child of dish so it rotates with it
	_dish_mesh.add_child(inner_inst)

	# Runic ring: hovering glow ring above the dish
	var runic_mat := StandardMaterial3D.new()
	runic_mat.albedo_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.5)
	runic_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	runic_mat.emission_enabled = true
	runic_mat.emission = accent
	runic_mat.emission_energy_multiplier = 3.0
	runic_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var runic_torus := TorusMesh.new()
	runic_torus.inner_radius = DISH_RADIUS * 1.3
	runic_torus.outer_radius = DISH_RADIUS * 1.3 + 0.08

	var runic_inst := MeshInstance3D.new()
	runic_inst.name = "RunicRing"
	runic_inst.mesh = runic_torus
	runic_inst.material_override = runic_mat
	runic_inst.position.y = 1.5  # Above dish
	# Counter-rotate (child of dish, but we'll offset rotation in _process)
	_dish_mesh.add_child(runic_inst)


func _build_conduits() -> void:
	## 4 thin cylinders connecting pylon tops to the dish center.
	var pylon_positions: Array[Vector3] = [
		Vector3(-PYLON_SPACING, PYLON_HEIGHT, -PYLON_SPACING),
		Vector3(PYLON_SPACING, PYLON_HEIGHT, -PYLON_SPACING),
		Vector3(-PYLON_SPACING, PYLON_HEIGHT, PYLON_SPACING),
		Vector3(PYLON_SPACING, PYLON_HEIGHT, PYLON_SPACING),
	]
	var dish_center := Vector3(0.0, DISH_HEIGHT, 0.0)

	for i in pylon_positions.size():
		var start: Vector3 = pylon_positions[i]
		var midpoint := (start + dish_center) * 0.5
		var length := start.distance_to(dish_center)
		var direction := (dish_center - start).normalized()

		var cyl := CylinderMesh.new()
		cyl.top_radius = CONDUIT_RADIUS
		cyl.bottom_radius = CONDUIT_RADIUS
		cyl.height = length

		var inst := MeshInstance3D.new()
		inst.name = "Conduit_%d" % i
		inst.mesh = cyl
		inst.material_override = _conduit_material
		inst.position = midpoint

		# Orient cylinder from pylon top to dish center
		if direction.length() > 0.01:
			inst.look_at(dish_center)
			inst.rotate_object_local(Vector3.RIGHT, PI * 0.5)

		add_child(inst)


func _create_parabolic_dish(radius: float, depth: float, radial_segs: int, ring_segs: int) -> ArrayMesh:
	## Generate a concave parabolic dish via SurfaceTool.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for ring in range(ring_segs + 1):
		var v: float = float(ring) / float(ring_segs)
		var r: float = v * radius
		# Parabolic height: deeper at center, zero at rim
		var y: float = -depth * (1.0 - v * v)

		for seg in range(radial_segs + 1):
			var u: float = float(seg) / float(radial_segs)
			var angle: float = u * TAU
			var px: float = cos(angle) * r
			var pz: float = sin(angle) * r

			# Normal: derivative of paraboloid
			var slope: float = 2.0 * depth * v / radius
			var nr: float = slope
			var ny: float = 1.0
			var normal := Vector3(cos(angle) * nr, ny, sin(angle) * nr).normalized()

			st.set_normal(normal)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(px, y, pz))

	for ring in range(ring_segs):
		for seg in range(radial_segs):
			var current: int = ring * (radial_segs + 1) + seg
			var next_ring: int = current + radial_segs + 1
			st.add_index(current)
			st.add_index(next_ring)
			st.add_index(current + 1)
			st.add_index(current + 1)
			st.add_index(next_ring)
			st.add_index(next_ring + 1)

	st.generate_tangents()
	return st.commit()


func _build_ground_circle() -> void:
	## Flat quad on ground with the circle shader — concentric rings + radials.
	var quad := QuadMesh.new()
	quad.size = Vector2(GROUND_RING_SIZE, GROUND_RING_SIZE)

	var inst := MeshInstance3D.new()
	inst.name = "GroundCircle"
	inst.mesh = quad
	inst.material_override = _circle_material
	inst.position = Vector3(0.0, 0.05, 0.0)  # Slightly above ground to avoid z-fighting
	inst.rotation_degrees.x = -90.0  # Flat on ground
	add_child(inst)


func _build_light() -> void:
	## OmniLight3D at dish height, accent-colored.
	var accent: Color = _params.get("accent_color", Color.CYAN)

	_station_light = OmniLight3D.new()
	_station_light.name = "StationLight"
	_station_light.light_color = accent
	_station_light.light_energy = 2.0
	_station_light.omni_range = 25.0
	_station_light.omni_attenuation = 1.5
	_station_light.shadow_enabled = false
	_station_light.position = Vector3(0.0, DISH_HEIGHT, 0.0)
	add_child(_station_light)


func _build_interaction_area() -> void:
	## Area3D for detecting player proximity.
	var area := Area3D.new()
	area.name = "InteractionArea"

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = INTERACTION_RADIUS
	shape.shape = sphere

	area.add_child(shape)
	area.position = Vector3(0.0, PYLON_HEIGHT * 0.5, 0.0)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and not _player_in_range:
		_player_in_range = true
		player_entered_range.emit()


func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D and _player_in_range:
		_player_in_range = false
		player_exited_range.emit()
