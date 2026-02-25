extends Node3D
## Octagonal landing pad with sequential perimeter lighting and runway markings.
## Placed at approximately (0, 100) in the territory.
## The 8 amber spotlights cycle sequentially around the perimeter
## to guide incoming craft. Central "H" helipad marking in white emissive.
## Deterministic from territory seed.

const PAD_RADIUS: float = 8.0
const PAD_HEIGHT: float = 0.15
const PAD_SEGMENTS: int = 8  # Octagonal
const LIGHT_COUNT: int = 8
const LIGHT_CYCLE_SPEED: float = 0.3  # Seconds per light step
const STRIPE_COUNT: int = 6

var _pad_material: StandardMaterial3D
var _marking_material: StandardMaterial3D
var _light_material: StandardMaterial3D
var _perimeter_lights: Array[SpotLight3D] = []
var _light_meshes: Array[MeshInstance3D] = []
var _light_materials: Array[StandardMaterial3D] = []
var _active_light_index: int = 0
var _light_timer: float = 0.0


func initialize(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 8800

	_create_materials()
	_build_pad_base()
	_build_runway_stripes()
	_build_h_marking()
	_build_perimeter_lights()
	_build_edge_trim()


func _process(delta: float) -> void:
	# Sequential light animation — one light active at a time, cycles around
	_light_timer += delta
	if _light_timer >= LIGHT_CYCLE_SPEED:
		_light_timer -= LIGHT_CYCLE_SPEED

		# Turn off current light
		if _active_light_index < _perimeter_lights.size():
			_perimeter_lights[_active_light_index].light_energy = 0.3
			if _active_light_index < _light_materials.size():
				_light_materials[_active_light_index].emission_energy_multiplier = 0.2

		# Advance to next
		_active_light_index = (_active_light_index + 1) % LIGHT_COUNT

		# Turn on new light
		if _active_light_index < _perimeter_lights.size():
			_perimeter_lights[_active_light_index].light_energy = 4.0
			if _active_light_index < _light_materials.size():
				_light_materials[_active_light_index].emission_energy_multiplier = 3.0


func _create_materials() -> void:
	# Landing pad surface — dark concrete
	_pad_material = StandardMaterial3D.new()
	_pad_material.albedo_color = Color(0.15, 0.14, 0.13)
	_pad_material.roughness = 0.85
	_pad_material.metallic = 0.1
	_pad_material.specular = 0.2

	# White emissive markings
	_marking_material = StandardMaterial3D.new()
	_marking_material.albedo_color = Color(0.9, 0.9, 0.9)
	_marking_material.roughness = 0.5
	_marking_material.metallic = 0.0
	_marking_material.emission_enabled = true
	_marking_material.emission = Color(0.85, 0.85, 0.85)
	_marking_material.emission_energy_multiplier = 0.8

	# Light fixture base material (amber)
	_light_material = StandardMaterial3D.new()
	_light_material.albedo_color = Color(0.8, 0.55, 0.1)
	_light_material.roughness = 0.3
	_light_material.metallic = 0.2
	_light_material.emission_enabled = true
	_light_material.emission = Color(1.0, 0.7, 0.15)
	_light_material.emission_energy_multiplier = 0.2


func _build_pad_base() -> void:
	## Flat octagonal platform. CylinderMesh with 8 radial segments = octagon.
	var cyl := CylinderMesh.new()
	cyl.top_radius = PAD_RADIUS
	cyl.bottom_radius = PAD_RADIUS + 0.2
	cyl.height = PAD_HEIGHT
	cyl.radial_segments = PAD_SEGMENTS

	var inst := MeshInstance3D.new()
	inst.name = "PadBase"
	inst.mesh = cyl
	inst.material_override = _pad_material
	inst.position = Vector3(0.0, PAD_HEIGHT * 0.5, 0.0)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(inst)

	# Slightly raised inner circle for visual depth
	var inner := CylinderMesh.new()
	inner.top_radius = PAD_RADIUS * 0.85
	inner.bottom_radius = PAD_RADIUS * 0.85
	inner.height = 0.02
	inner.radial_segments = PAD_SEGMENTS

	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = Color(0.18, 0.17, 0.16)
	inner_mat.roughness = 0.8
	inner_mat.metallic = 0.1

	var inner_inst := MeshInstance3D.new()
	inner_inst.name = "PadInner"
	inner_inst.mesh = inner
	inner_inst.material_override = inner_mat
	inner_inst.position = Vector3(0.0, PAD_HEIGHT + 0.01, 0.0)
	add_child(inner_inst)


func _build_runway_stripes() -> void:
	## 6 white stripes arranged as parallel runway markings across the pad.
	var stripe_spacing: float = PAD_RADIUS * 1.2 / float(STRIPE_COUNT)
	var stripe_start_x: float = -float(STRIPE_COUNT - 1) * stripe_spacing * 0.5

	for i in range(STRIPE_COUNT):
		var sx: float = stripe_start_x + float(i) * stripe_spacing
		# Stripe length varies — shorter at edges
		var edge_factor: float = 1.0 - absf(sx) / (PAD_RADIUS * 0.7)
		edge_factor = clampf(edge_factor, 0.3, 1.0)
		var stripe_len: float = PAD_RADIUS * 0.8 * edge_factor

		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 0.01, stripe_len)

		var inst := MeshInstance3D.new()
		inst.name = "Stripe_%d" % i
		inst.mesh = mesh
		inst.material_override = _marking_material
		inst.position = Vector3(sx, PAD_HEIGHT + 0.02, 0.0)
		add_child(inst)


func _build_h_marking() -> void:
	## Central "H" helipad marking using two vertical bars and one horizontal crossbar.
	var h_size: float = 2.0
	var bar_width: float = 0.2
	var bar_height: float = 0.01
	var mark_y: float = PAD_HEIGHT + 0.025

	# Left vertical bar of H
	var left_bar := BoxMesh.new()
	left_bar.size = Vector3(bar_width, bar_height, h_size)
	var left_inst := MeshInstance3D.new()
	left_inst.name = "H_Left"
	left_inst.mesh = left_bar
	left_inst.material_override = _marking_material
	left_inst.position = Vector3(-h_size * 0.3, mark_y, 0.0)
	add_child(left_inst)

	# Right vertical bar of H
	var right_bar := BoxMesh.new()
	right_bar.size = Vector3(bar_width, bar_height, h_size)
	var right_inst := MeshInstance3D.new()
	right_inst.name = "H_Right"
	right_inst.mesh = right_bar
	right_inst.material_override = _marking_material
	right_inst.position = Vector3(h_size * 0.3, mark_y, 0.0)
	add_child(right_inst)

	# Horizontal crossbar of H
	var cross_bar := BoxMesh.new()
	cross_bar.size = Vector3(h_size * 0.6 + bar_width, bar_height, bar_width)
	var cross_inst := MeshInstance3D.new()
	cross_inst.name = "H_Cross"
	cross_inst.mesh = cross_bar
	cross_inst.material_override = _marking_material
	cross_inst.position = Vector3(0.0, mark_y, 0.0)
	add_child(cross_inst)


func _build_perimeter_lights() -> void:
	## 8 amber SpotLight3Ds evenly spaced around the octagonal perimeter.
	## Each has a small box "fixture" mesh and its own material for glow control.
	for i in range(LIGHT_COUNT):
		var angle: float = float(i) / float(LIGHT_COUNT) * TAU
		var lx: float = cos(angle) * (PAD_RADIUS - 0.5)
		var lz: float = sin(angle) * (PAD_RADIUS - 0.5)

		# Light fixture mesh (small box)
		var fixture_mat := StandardMaterial3D.new()
		fixture_mat.albedo_color = Color(0.6, 0.42, 0.08)
		fixture_mat.roughness = 0.3
		fixture_mat.metallic = 0.4
		fixture_mat.emission_enabled = true
		fixture_mat.emission = Color(1.0, 0.7, 0.15)
		fixture_mat.emission_energy_multiplier = 0.2
		_light_materials.append(fixture_mat)

		var fixture_mesh := BoxMesh.new()
		fixture_mesh.size = Vector3(0.2, 0.15, 0.2)
		var fixture_inst := MeshInstance3D.new()
		fixture_inst.name = "LightFixture_%d" % i
		fixture_inst.mesh = fixture_mesh
		fixture_inst.material_override = fixture_mat
		fixture_inst.position = Vector3(lx, PAD_HEIGHT + 0.1, lz)
		add_child(fixture_inst)
		_light_meshes.append(fixture_inst)

		# SpotLight pointing upward (runway approach lighting)
		var light := SpotLight3D.new()
		light.name = "PerimeterLight_%d" % i
		light.light_color = Color(1.0, 0.7, 0.15)
		light.light_energy = 0.3  # Dim by default, one is bright at a time
		light.spot_range = 12.0
		light.spot_angle = 35.0
		light.spot_attenuation = 1.5
		light.shadow_enabled = false
		light.position = Vector3(lx, PAD_HEIGHT + 0.2, lz)
		# Point light upward and slightly inward
		light.rotation_degrees.x = -70.0
		# Face toward center
		var to_center := Vector3(-lx, 0.0, -lz).normalized()
		if to_center.length() > 0.01:
			light.look_at(light.position + Vector3(0, 5, 0))
		add_child(light)
		_perimeter_lights.append(light)

	# Start with first light active
	if _perimeter_lights.size() > 0:
		_perimeter_lights[0].light_energy = 4.0
		if _light_materials.size() > 0:
			_light_materials[0].emission_energy_multiplier = 3.0


func _build_edge_trim() -> void:
	## Thin accent ring around the pad edge for visual definition.
	var torus := TorusMesh.new()
	torus.inner_radius = PAD_RADIUS - 0.1
	torus.outer_radius = PAD_RADIUS + 0.05
	torus.ring_segments = 32
	torus.rings = 8

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.4, 0.38, 0.35)
	trim_mat.roughness = 0.5
	trim_mat.metallic = 0.6

	var inst := MeshInstance3D.new()
	inst.name = "EdgeTrim"
	inst.mesh = torus
	inst.material_override = trim_mat
	inst.position = Vector3(0.0, PAD_HEIGHT + 0.02, 0.0)
	inst.scale = Vector3(1.0, 0.2, 1.0)  # Flatten the torus into a ring
	add_child(inst)
