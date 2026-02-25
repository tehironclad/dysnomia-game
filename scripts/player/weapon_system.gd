extends Node3D
## Player weapon system for Dysnomia.
## Manages weapons, firing, and damage dealing to creatures.
## Weapons are unlocked based on player level/achievements from entropy API.

signal weapon_fired(weapon_type: int)
signal weapon_switched(weapon_type: int)
signal health_changed(current: float, maximum: float)

enum WeaponType { FIST, MINING_LASER, PULSE_RIFLE, GRAVITY_HAMMER }

# ─── Player Health ──────────────────────────────────────────────────────
var max_health: float = 100.0
var health: float = 100.0
var health_regen_rate: float = 2.0  # HP per second out of combat
var _damage_cooldown: float = 0.0   # Invulnerability frames after taking damage
var _last_damage_time: float = 0.0
const DAMAGE_INVULN: float = 0.5    # 0.5s invulnerability after hit
const REGEN_DELAY: float = 5.0      # Seconds after last hit before regen starts

# ─── Weapon Stats ───────────────────────────────────────────────────────
var current_weapon: int = WeaponType.FIST
var _unlocked_weapons: Array[int] = [WeaponType.FIST, WeaponType.MINING_LASER, WeaponType.PULSE_RIFLE, WeaponType.GRAVITY_HAMMER]
var _fire_cooldown: float = 0.0
var _creature_spawner: Node3D

# Weapon definitions: {damage, range, cooldown, projectile}
const WEAPON_STATS: Dictionary = {
	WeaponType.FIST: {"name": "Fists", "damage": 15.0, "range": 4.5, "cooldown": 0.4, "aoe": 0.0},
	WeaponType.MINING_LASER: {"name": "Mining Laser", "damage": 25.0, "range": 20.0, "cooldown": 0.3, "aoe": 0.0},
	WeaponType.PULSE_RIFLE: {"name": "Pulse Rifle", "damage": 35.0, "range": 40.0, "cooldown": 0.8, "aoe": 2.0},
	WeaponType.GRAVITY_HAMMER: {"name": "Gravity Hammer", "damage": 60.0, "range": 5.0, "cooldown": 1.5, "aoe": 4.0},
}

# ─── Weapon Visuals ─────────────────────────────────────────────────────
var _muzzle_flash: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _fire_effect_gen: int = 0  # Generation counter — prevents stale timers hiding fresh effects

# Multi-layer laser beam (all children of a beam_root for easy cleanup)
var _beam_root: Node3D              # Root node for all beam parts
var _beam_core: MeshInstance3D      # Bright inner core
var _beam_glow: MeshInstance3D      # Wider outer glow
var _beam_flare: MeshInstance3D     # Source flare at turret lens
var _beam_impact: MeshInstance3D    # Impact flash at hit point
var _beam_core_mat: StandardMaterial3D
var _beam_glow_mat: StandardMaterial3D
var _beam_flare_mat: StandardMaterial3D
var _beam_impact_mat: StandardMaterial3D
var _beam_active: bool = false
var _beam_timer: float = 0.0
const BEAM_DURATION: float = 0.25   # How long beam stays visible
var _beam_origin: Vector3 = Vector3.ZERO
var _beam_end: Vector3 = Vector3.ZERO

# Impact spark particles (reusable, repositioned per shot)
var _impact_sparks: GPUParticles3D
var _impact_light: OmniLight3D
var _impact_light_tween: Tween


func initialize(creature_spawner: Node3D) -> void:
	_creature_spawner = creature_spawner
	health = max_health
	_build_weapon_visuals()
	_build_impact_particles()


func _build_weapon_visuals() -> void:
	# Muzzle flash — small emissive sphere that appears briefly on fire
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.8, 0.3)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1.0, 0.8, 0.3)
	_flash_mat.emission_energy_multiplier = 5.0
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.1
	flash_mesh.height = 0.2
	_muzzle_flash = MeshInstance3D.new()
	_muzzle_flash.name = "MuzzleFlash"
	_muzzle_flash.mesh = flash_mesh
	_muzzle_flash.material_override = _flash_mat
	_muzzle_flash.visible = false
	_muzzle_flash.position = Vector3(0.3, 1.2, 0.5)  # Near player's hand
	add_child(_muzzle_flash)

	# ─── Multi-Layer Laser Beam ──────────────────────────────────────
	# All beam parts are top-level nodes (not children of weapon_system)
	# so they can be positioned in world space without transform conflicts.

	# Core beam — bright white-blue center, thin
	_beam_core_mat = StandardMaterial3D.new()
	_beam_core_mat.albedo_color = Color(0.8, 0.95, 1.0)
	_beam_core_mat.emission_enabled = true
	_beam_core_mat.emission = Color(0.7, 0.9, 1.0)
	_beam_core_mat.emission_energy_multiplier = 12.0
	_beam_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_core_mat.no_depth_test = true

	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.012
	core_mesh.bottom_radius = 0.012
	core_mesh.height = 1.0
	_beam_core = MeshInstance3D.new()
	_beam_core.name = "BeamCore"
	_beam_core.mesh = core_mesh
	_beam_core.material_override = _beam_core_mat
	_beam_core.visible = false

	# Outer glow — wider, transparent, colored halo around core
	_beam_glow_mat = StandardMaterial3D.new()
	_beam_glow_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.35)
	_beam_glow_mat.emission_enabled = true
	_beam_glow_mat.emission = Color(0.3, 0.7, 1.0)
	_beam_glow_mat.emission_energy_multiplier = 6.0
	_beam_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_beam_glow_mat.no_depth_test = true

	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius = 0.06
	glow_mesh.bottom_radius = 0.06
	glow_mesh.height = 1.0
	_beam_glow = MeshInstance3D.new()
	_beam_glow.name = "BeamGlow"
	_beam_glow.mesh = glow_mesh
	_beam_glow.material_override = _beam_glow_mat
	_beam_glow.visible = false

	# Source flare — bright billboard sphere at the turret lens
	_beam_flare_mat = StandardMaterial3D.new()
	_beam_flare_mat.albedo_color = Color(0.7, 0.9, 1.0)
	_beam_flare_mat.emission_enabled = true
	_beam_flare_mat.emission = Color(0.6, 0.85, 1.0)
	_beam_flare_mat.emission_energy_multiplier = 15.0
	_beam_flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_beam_flare_mat.no_depth_test = true

	var flare_mesh := SphereMesh.new()
	flare_mesh.radius = 0.08
	flare_mesh.height = 0.16
	_beam_flare = MeshInstance3D.new()
	_beam_flare.name = "BeamFlare"
	_beam_flare.mesh = flare_mesh
	_beam_flare.material_override = _beam_flare_mat
	_beam_flare.visible = false

	# Impact flash — bright expanding sphere at hit point
	_beam_impact_mat = StandardMaterial3D.new()
	_beam_impact_mat.albedo_color = Color(0.5, 0.8, 1.0, 0.8)
	_beam_impact_mat.emission_enabled = true
	_beam_impact_mat.emission = Color(0.6, 0.9, 1.0)
	_beam_impact_mat.emission_energy_multiplier = 10.0
	_beam_impact_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_impact_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_beam_impact_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var impact_mesh := SphereMesh.new()
	impact_mesh.radius = 0.12
	impact_mesh.height = 0.24
	_beam_impact = MeshInstance3D.new()
	_beam_impact.name = "BeamImpact"
	_beam_impact.mesh = impact_mesh
	_beam_impact.material_override = _beam_impact_mat
	_beam_impact.visible = false


func _build_impact_particles() -> void:
	## Reusable spark burst at weapon impact points.
	_impact_sparks = GPUParticles3D.new()
	_impact_sparks.name = "ImpactSparks"
	_impact_sparks.one_shot = true
	_impact_sparks.explosiveness = 1.0
	_impact_sparks.amount = 24
	_impact_sparks.lifetime = 0.6
	_impact_sparks.emitting = false
	_impact_sparks.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.15
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 12.0
	mat.gravity = Vector3(0, -3.0, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	mat.damping_min = 2.0
	mat.damping_max = 5.0

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	color_ramp.add_point(0.3, Color(1.0, 0.6, 0.2, 0.9))
	color_ramp.add_point(0.7, Color(0.8, 0.3, 0.1, 0.5))
	color_ramp.set_color(1, Color(0.4, 0.15, 0.05, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex
	_impact_sparks.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_impact_sparks.draw_pass_1 = quad
	# Soft-circle shader for spark blobs (no hard square edges)
	var spark_shader_mat := ShaderMaterial.new()
	var spark_shader := Shader.new()
	spark_shader.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(vec3(0.0, 1.0, 0.0), 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c) * 2.0;
	float alpha = exp(-d * d * 6.0);
	float core = exp(-d * d * 20.0);
	ALBEDO = COLOR.rgb * (1.0 + core * 2.0);
	ALPHA = alpha * COLOR.a;
}
"""
	spark_shader_mat.shader = spark_shader
	quad.surface_set_material(0, spark_shader_mat)

	# Impact flash light — brief OmniLight at hit point
	_impact_light = OmniLight3D.new()
	_impact_light.name = "ImpactLight"
	_impact_light.light_energy = 0.0
	_impact_light.light_color = Color(1.0, 0.8, 0.4)
	_impact_light.omni_range = 6.0
	_impact_light.omni_attenuation = 1.5
	_impact_light.shadow_enabled = false


func _spawn_impact_at(pos: Vector3, color: Color) -> void:
	## Position and fire the impact spark burst at a world position.
	var root := get_tree().current_scene
	if not root:
		return

	# Ensure sparks are in scene
	if not _impact_sparks.is_inside_tree():
		root.add_child(_impact_sparks)
	if not _impact_light.is_inside_tree():
		root.add_child(_impact_light)

	_impact_sparks.global_position = pos
	_impact_sparks.emitting = false  # Reset
	_impact_sparks.emitting = true

	# Update spark color
	var mat: ParticleProcessMaterial = _impact_sparks.process_material as ParticleProcessMaterial
	if mat and mat.color_ramp:
		var grad: GradientTexture1D = mat.color_ramp as GradientTexture1D
		if grad and grad.gradient:
			grad.gradient.set_color(0, Color(color.r, color.g, color.b, 1.0))

	# Flash the impact light
	_impact_light.global_position = pos
	_impact_light.light_energy = 3.0
	_impact_light.light_color = color
	if _impact_light_tween and _impact_light_tween.is_valid():
		_impact_light_tween.kill()
	_impact_light_tween = create_tween()
	_impact_light_tween.tween_property(_impact_light, "light_energy", 0.0, 0.3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _process(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_damage_cooldown = maxf(0.0, _damage_cooldown - delta)

	# Health regeneration (out of combat)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_damage_time > REGEN_DELAY and health < max_health:
		health = minf(health + health_regen_rate * delta, max_health)
		health_changed.emit(health, max_health)

	# Animate active laser beam
	if _beam_active:
		_beam_timer -= delta
		_update_beam(delta)
		if _beam_timer <= 0.0:
			_hide_beam()


func _unhandled_input(event: InputEvent) -> void:
	# Fire weapon with left mouse button
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_fire()

	# Switch weapons with number keys
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1 and WeaponType.FIST in _unlocked_weapons:
			_switch_weapon(WeaponType.FIST)
		elif event.keycode == KEY_2 and WeaponType.MINING_LASER in _unlocked_weapons:
			_switch_weapon(WeaponType.MINING_LASER)
		elif event.keycode == KEY_3 and WeaponType.PULSE_RIFLE in _unlocked_weapons:
			_switch_weapon(WeaponType.PULSE_RIFLE)
		elif event.keycode == KEY_4 and WeaponType.GRAVITY_HAMMER in _unlocked_weapons:
			_switch_weapon(WeaponType.GRAVITY_HAMMER)

		# Mouse wheel weapon cycling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(-1)


func _fire() -> void:
	if _fire_cooldown > 0.0:
		return

	var stats: Dictionary = WEAPON_STATS[current_weapon]
	_fire_cooldown = stats.cooldown

	weapon_fired.emit(current_weapon)

	# Get camera for aim direction
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var aim_origin := camera.global_position
	var aim_dir := -camera.global_transform.basis.z

	# Fire effect
	_show_fire_effect(stats, aim_origin, aim_dir)

	# Find targets
	if not _creature_spawner or not _creature_spawner.has_method("get_nearby_creatures"):
		return

	var weapon_range: float = stats.range
	var aoe: float = stats.aoe
	var damage_amount: float = stats.damage

	if aoe > 0.0:
		# AoE weapon — damage all creatures in radius around hit point
		var hit_point := aim_origin + aim_dir * weapon_range * 0.5
		var targets: Array = _creature_spawner.get_nearby_creatures(hit_point, weapon_range)
		var did_hit := false
		for target: CharacterBody3D in targets:
			var knockback: Vector3 = (target.global_position - global_position).normalized()
			target.take_damage(damage_amount, knockback)
			did_hit = true
		if did_hit:
			var spark_color := Color(0.6, 0.2, 1.0) if current_weapon == WeaponType.GRAVITY_HAMMER else Color(1.0, 0.5, 0.1)
			_spawn_impact_at(hit_point, spark_color)
	else:
		# Single target — raycast or nearest in cone
		var best_target: CharacterBody3D = null
		# Fists use a wider aim cone (0.5 = ~60°) since you're punching nearby;
		# ranged weapons keep tighter cone (0.85 = ~32°)
		var is_melee := current_weapon == WeaponType.FIST
		var best_dot: float = 0.5 if is_melee else 0.85
		var best_dist: float = weapon_range

		# Melee searches from player position (not camera) for better close-range hit detection
		var search_origin := global_position if is_melee else aim_origin
		var targets: Array = _creature_spawner.get_nearby_creatures(search_origin, weapon_range)
		for target: CharacterBody3D in targets:
			var to_target: Vector3 = (target.global_position - search_origin).normalized()
			var dot := aim_dir.dot(to_target)
			var dist := search_origin.distance_to(target.global_position)
			if dot > best_dot and dist < best_dist:
				best_dot = dot
				best_dist = dist
				best_target = target

		if best_target:
			var knockback := (best_target.global_position - global_position).normalized()
			best_target.take_damage(damage_amount, knockback)
			# Spawn impact sparks at hit creature
			var spark_color := Color(1.0, 0.9, 0.5)
			if current_weapon == WeaponType.MINING_LASER:
				spark_color = Color(0.5, 0.85, 1.0)
			elif current_weapon == WeaponType.FIST:
				spark_color = Color(0.9, 0.7, 0.2)
			_spawn_impact_at(best_target.global_position + Vector3(0, 0.5, 0), spark_color)


func _show_fire_effect(stats: Dictionary, origin: Vector3, direction: Vector3) -> void:
	## Brief visual effect for weapon fire.
	## Uses a generation counter so rapid clicks don't cause stale timers
	## to hide effects that belong to a newer shot.
	_fire_effect_gen += 1
	var gen := _fire_effect_gen

	# Get player model for punch / laser flash
	var player_model: Node3D = null
	if get_parent():
		player_model = get_parent().get_node_or_null("PlayerModel")

	match current_weapon:
		WeaponType.FIST:
			# Trigger punch animation on the player model
			if player_model and player_model.has_method("trigger_punch"):
				player_model.trigger_punch()
			# Quick punch flash at impact point
			_muzzle_flash.visible = true
			_muzzle_flash.scale = Vector3(0.5, 0.5, 0.5)
			_flash_mat.emission = Color(0.9, 0.7, 0.2)  # Brass flash
			get_tree().create_timer(0.12).timeout.connect(func():
				if _fire_effect_gen == gen:
					_muzzle_flash.visible = false)

		WeaponType.MINING_LASER:
			# Flash the shoulder-mounted laser turret
			if player_model and player_model.has_method("flash_shoulder_laser"):
				player_model.flash_shoulder_laser()
			# Get beam origin from the shoulder turret lens
			var beam_start := origin  # Fallback to camera
			if player_model:
				var lens := player_model.get_node_or_null("LaserMountPivot/LaserLens")
				if lens:
					beam_start = lens.global_position
			var beam_end: Vector3 = beam_start + direction * float(stats.range)
			_fire_beam(beam_start, beam_end)

		WeaponType.PULSE_RIFLE:
			# Orange pulse flash
			_flash_mat.emission = Color(1.0, 0.5, 0.1)
			_muzzle_flash.visible = true
			_muzzle_flash.scale = Vector3(1.5, 1.5, 1.5)
			get_tree().create_timer(0.2).timeout.connect(func():
				if _fire_effect_gen == gen:
					_muzzle_flash.visible = false)
			# Energy bolt trail
			_spawn_pulse_bolt(origin + Vector3(0.3, 1.2, 0.5), direction, float(stats.range))

		WeaponType.GRAVITY_HAMMER:
			# Purple shockwave
			_flash_mat.emission = Color(0.6, 0.2, 1.0)
			_muzzle_flash.visible = true
			_muzzle_flash.scale = Vector3(3.0, 3.0, 3.0)
			get_tree().create_timer(0.3).timeout.connect(func():
				if _fire_effect_gen == gen:
					_muzzle_flash.visible = false)
			# Ground-pound shockwave ring
			_spawn_shockwave_ring(origin + direction * 3.0)


func _spawn_pulse_bolt(start: Vector3, direction: Vector3, weapon_range: float) -> void:
	## Fast-moving energy bolt for the pulse rifle with a glowing trail.
	var bolt := MeshInstance3D.new()
	bolt.name = "PulseBolt"
	var bolt_mesh := CapsuleMesh.new()
	bolt_mesh.radius = 0.06
	bolt_mesh.height = 0.8
	bolt.mesh = bolt_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bolt.material_override = mat

	# Orient capsule along flight direction
	bolt.global_position = start
	bolt.look_at(start + direction)
	bolt.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	# OmniLight for bolt glow
	var bolt_light := OmniLight3D.new()
	bolt_light.light_color = Color(1.0, 0.5, 0.15)
	bolt_light.light_energy = 2.0
	bolt_light.omni_range = 4.0
	bolt_light.shadow_enabled = false
	bolt.add_child(bolt_light)

	var root := get_tree().current_scene
	if not root:
		return
	root.add_child(bolt)

	# Tween bolt to fly to endpoint
	var end := start + direction * weapon_range
	var fly_time := weapon_range / 60.0  # 60 m/s
	var tween := create_tween()
	tween.tween_property(bolt, "global_position", end, fly_time)
	tween.tween_callback(func():
		if is_instance_valid(bolt):
			bolt.queue_free()
	)


func _spawn_shockwave_ring(pos: Vector3) -> void:
	## Expanding torus ring at impact point for gravity hammer ground-pound.
	var ring := MeshInstance3D.new()
	ring.name = "ShockwaveRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.8
	torus.rings = 16
	torus.ring_segments = 16
	ring.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.2, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.15, 0.9)
	mat.emission_energy_multiplier = 6.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat

	ring.global_position = pos
	ring.scale = Vector3(0.5, 0.2, 0.5)

	var root := get_tree().current_scene
	if root:
		root.add_child(ring)

	# Expand ring outward and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(5.0, 0.3, 5.0), 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.5)

	# Clean up after animation
	get_tree().create_timer(0.7).timeout.connect(func():
		if is_instance_valid(ring):
			ring.queue_free()
	)


func _fire_beam(start: Vector3, end: Vector3) -> void:
	## Activate the multi-layer laser beam from start to end.
	_beam_origin = start
	_beam_end = end
	_beam_active = true
	_beam_timer = BEAM_DURATION

	# Ensure beam nodes are in the scene tree (add to root so they use world coords)
	_ensure_beam_in_tree()

	# Position all beam parts
	_position_beam(start, end, 1.0)

	# Show all parts
	_beam_core.visible = true
	_beam_glow.visible = true
	_beam_flare.visible = true
	_beam_impact.visible = true


func _ensure_beam_in_tree() -> void:
	## Add beam nodes to the scene root if not already parented.
	var root := get_tree().current_scene
	if not root:
		return
	if _beam_core and not _beam_core.is_inside_tree():
		root.add_child(_beam_core)
	if _beam_glow and not _beam_glow.is_inside_tree():
		root.add_child(_beam_glow)
	if _beam_flare and not _beam_flare.is_inside_tree():
		root.add_child(_beam_flare)
	if _beam_impact and not _beam_impact.is_inside_tree():
		root.add_child(_beam_impact)


func _position_beam(start: Vector3, end: Vector3, intensity: float) -> void:
	## Position and orient beam cylinders between start and end points.
	var midpoint := (start + end) * 0.5
	var beam_length := start.distance_to(end)
	if beam_length < 0.1:
		return  # Too short to render

	# Orient a cylinder from midpoint toward end, then rotate so Y-axis aligns with beam
	var orient_cylinder := func(cyl: MeshInstance3D) -> void:
		cyl.global_position = midpoint
		cyl.scale = Vector3(1.0, beam_length, 1.0)
		cyl.look_at(end)
		cyl.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	# Core beam — thin bright center
	if _beam_core:
		orient_cylinder.call(_beam_core)
		_beam_core_mat.emission_energy_multiplier = 12.0 * intensity

	# Outer glow — wider colored halo
	if _beam_glow:
		orient_cylinder.call(_beam_glow)
		_beam_glow_mat.emission_energy_multiplier = 6.0 * intensity
		_beam_glow_mat.albedo_color.a = 0.35 * intensity

	# Source flare at turret
	if _beam_flare:
		_beam_flare.global_position = start
		var flare_scale := 0.8 + sin(Time.get_ticks_msec() * 0.02) * 0.3  # Pulsing
		_beam_flare.scale = Vector3.ONE * flare_scale * intensity
		_beam_flare_mat.emission_energy_multiplier = 15.0 * intensity

	# Impact flash at endpoint
	if _beam_impact:
		_beam_impact.global_position = end
		var impact_scale := 0.6 + sin(Time.get_ticks_msec() * 0.03 + 1.0) * 0.2
		_beam_impact.scale = Vector3.ONE * impact_scale * intensity
		_beam_impact_mat.emission_energy_multiplier = 10.0 * intensity
		_beam_impact_mat.albedo_color.a = 0.8 * intensity


func _update_beam(_delta: float) -> void:
	## Called each frame while beam is active. Updates origin from turret, fades out.
	if not _beam_active:
		return

	# Update beam origin from turret lens (it may have moved)
	var player_model: Node3D = null
	if get_parent():
		player_model = get_parent().get_node_or_null("PlayerModel")
	if player_model:
		var lens := player_model.get_node_or_null("LaserMountPivot/LaserLens")
		if lens:
			_beam_origin = lens.global_position

	# Fade intensity as beam expires
	var intensity := clampf(_beam_timer / BEAM_DURATION, 0.0, 1.0)
	# Smooth fade: fast start, slow tail
	intensity = intensity * intensity

	_position_beam(_beam_origin, _beam_end, intensity)


func _hide_beam() -> void:
	## Hide all beam visuals.
	_beam_active = false
	if _beam_core:
		_beam_core.visible = false
	if _beam_glow:
		_beam_glow.visible = false
	if _beam_flare:
		_beam_flare.visible = false
	if _beam_impact:
		_beam_impact.visible = false


func _switch_weapon(type: int) -> void:
	if type == current_weapon:
		return
	if type not in _unlocked_weapons:
		return
	current_weapon = type
	_fire_cooldown = 0.0
	weapon_switched.emit(type)


func _cycle_weapon(direction: int) -> void:
	if _unlocked_weapons.size() <= 1:
		return
	var idx := _unlocked_weapons.find(current_weapon)
	idx = (idx + direction) % _unlocked_weapons.size()
	_switch_weapon(_unlocked_weapons[idx])


func take_damage(amount: float) -> void:
	## Player takes damage from a creature.
	if _damage_cooldown > 0.0:
		return

	health -= amount
	health = maxf(health, 0.0)
	_damage_cooldown = DAMAGE_INVULN
	_last_damage_time = Time.get_ticks_msec() / 1000.0
	health_changed.emit(health, max_health)

	if health <= 0:
		_on_death()


func _on_death() -> void:
	## Player died — respawn at center of territory.
	health = max_health
	health_changed.emit(health, max_health)
	# Teleport to spawn (parent is the player CharacterBody3D)
	if get_parent() is CharacterBody3D:
		var player := get_parent() as CharacterBody3D
		player.position = Vector3(0.0, 10.0, 0.0)
		player.velocity = Vector3.ZERO


func unlock_weapon(type: int) -> void:
	## Unlock a new weapon (called when player meets requirements).
	if type not in _unlocked_weapons:
		_unlocked_weapons.append(type)
		_unlocked_weapons.sort()


func get_weapon_name() -> String:
	return WEAPON_STATS[current_weapon].name


func get_health_percent() -> float:
	return health / max_health if max_health > 0 else 0.0


func is_weapon_unlocked(type: int) -> bool:
	return type in _unlocked_weapons
