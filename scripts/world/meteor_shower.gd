extends Node3D
## Meteor shower event — spawns falling meteor objects across the territory.
## Each meteor is a tapered cylinder with an orange OmniLight3D and trail particles.
## Meteors that reach ground level trigger screen shake via signal + explosion particles.
## Spawned and managed by WeatherSystem.

signal meteor_impact(position: Vector3)

const SPAWN_HEIGHT_MIN: float = 80.0
const SPAWN_HEIGHT_MAX: float = 120.0
const FALL_SPEED_MIN: float = 30.0
const FALL_SPEED_MAX: float = 55.0
const TERRITORY_HALF: float = 200.0
const GROUND_HIT_Y: float = -5.0       # Below this = definitely hit ground
const EXPLOSION_LIFETIME: float = 1.5   # How long explosion particles persist

var _player: Node3D
var _meteors: Array[Node3D] = []
var _spawn_timer: float = 0.0
var _spawn_count: int = 0
var _max_meteors: int = 12
var _duration: float = 60.0
var _elapsed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func set_duration(d: float) -> void:
	_duration = maxf(d, 10.0)
	# Scale meteor count with duration
	_max_meteors = clampi(int(d / 8.0), 5, 15)


func initialize(player: Node3D) -> void:
	_player = player
	_rng.seed = Time.get_ticks_msec()
	# First meteor spawns quickly
	_spawn_timer = _rng.randf_range(0.5, 2.0)


func _process(delta: float) -> void:
	_elapsed += delta

	# Spawn new meteors on timer
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _spawn_count < _max_meteors:
		_spawn_meteor()
		var interval := _duration / float(_max_meteors)
		_spawn_timer = _rng.randf_range(interval * 0.5, interval * 1.5)

	# Update existing meteors — move downward, check ground impact
	var to_remove: Array[int] = []
	for i in range(_meteors.size()):
		var m: Node3D = _meteors[i]
		if not is_instance_valid(m):
			to_remove.append(i)
			continue

		var speed: float = m.get_meta("fall_speed", FALL_SPEED_MIN)
		var angle: float = m.get_meta("fall_angle", 0.0)

		# Move: primarily downward with slight lateral drift
		m.global_position.y -= speed * delta
		m.global_position.x += sin(angle) * speed * 0.15 * delta
		m.global_position.z += cos(angle) * speed * 0.1 * delta

		# Check ground impact
		if m.global_position.y <= GROUND_HIT_Y:
			_on_meteor_hit_ground(m)
			to_remove.append(i)

	# Remove impacted/freed meteors (reverse order for safe index removal)
	for i in range(to_remove.size() - 1, -1, -1):
		if to_remove[i] < _meteors.size():
			var m: Node3D = _meteors[to_remove[i]]
			if is_instance_valid(m):
				m.queue_free()
			_meteors.remove_at(to_remove[i])


func _spawn_meteor() -> void:
	_spawn_count += 1

	# Random XZ position within territory, biased toward player vicinity
	var base_x := 0.0
	var base_z := 0.0
	if _player and is_instance_valid(_player):
		base_x = _player.global_position.x
		base_z = _player.global_position.z

	var spawn_x := clampf(
		base_x + _rng.randf_range(-120.0, 120.0),
		-TERRITORY_HALF * 0.9, TERRITORY_HALF * 0.9
	)
	var spawn_z := clampf(
		base_z + _rng.randf_range(-120.0, 120.0),
		-TERRITORY_HALF * 0.9, TERRITORY_HALF * 0.9
	)
	var spawn_y := _rng.randf_range(SPAWN_HEIGHT_MIN, SPAWN_HEIGHT_MAX)

	var meteor := Node3D.new()
	meteor.name = "Meteor_%d" % _spawn_count
	add_child(meteor)
	meteor.global_position = Vector3(spawn_x, spawn_y, spawn_z)

	# Store fall parameters as metadata
	var fall_speed := _rng.randf_range(FALL_SPEED_MIN, FALL_SPEED_MAX)
	var fall_angle := _rng.randf() * TAU
	meteor.set_meta("fall_speed", fall_speed)
	meteor.set_meta("fall_angle", fall_angle)

	# Rotate to look like it's streaking downward at an angle
	meteor.rotation.x = -PI * 0.35 + _rng.randf_range(-0.2, 0.2)
	meteor.rotation.y = fall_angle

	# ─── Mesh: tapered cylinder (meteor body) ────────────────────────
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.25
	cyl.height = 2.0
	cyl.radial_segments = 6
	cyl.rings = 1
	mesh_inst.mesh = cyl

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.9, 0.5, 0.2, 1.0)
	body_mat.emission_enabled = true
	body_mat.emission = Color(1.0, 0.6, 0.15)
	body_mat.emission_energy_multiplier = 3.0
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.surface_set_material(0, body_mat)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	meteor.add_child(mesh_inst)

	# ─── Light: orange point light ───────────────────────────────────
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 4.0
	light.omni_range = 15.0
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	meteor.add_child(light)

	# ─── Trail: GPUParticles3D for fiery tail ────────────────────────
	var trail := GPUParticles3D.new()
	trail.amount = 30
	trail.lifetime = 0.8
	trail.explosiveness = 0.0
	trail.randomness = 0.3
	trail.fixed_fps = 30
	trail.emitting = true
	trail.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var trail_mat := ParticleProcessMaterial.new()
	trail_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	trail_mat.direction = Vector3(0.0, 1.0, 0.0)  # Trail goes up (meteor falls down)
	trail_mat.spread = 15.0
	trail_mat.initial_velocity_min = 1.0
	trail_mat.initial_velocity_max = 3.0
	trail_mat.gravity = Vector3(0.0, 0.5, 0.0)
	trail_mat.scale_min = 0.1
	trail_mat.scale_max = 0.4
	trail_mat.damping_min = 1.0
	trail_mat.damping_max = 2.0

	# Orange → red → dark color ramp
	var trail_ramp := Gradient.new()
	trail_ramp.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
	trail_ramp.add_point(0.3, Color(1.0, 0.5, 0.1, 0.7))
	trail_ramp.add_point(0.7, Color(0.8, 0.2, 0.05, 0.3))
	trail_ramp.set_color(1, Color(0.3, 0.1, 0.05, 0.0))
	var trail_tex := GradientTexture1D.new()
	trail_tex.gradient = trail_ramp
	trail_mat.color_ramp = trail_tex

	trail.process_material = trail_mat

	var trail_quad := QuadMesh.new()
	trail_quad.size = Vector2(0.5, 0.5)
	trail.draw_pass_1 = trail_quad
	var trail_draw_mat := StandardMaterial3D.new()
	trail_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_draw_mat.vertex_color_use_as_albedo = true
	trail_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	trail_draw_mat.no_depth_test = true
	trail_quad.surface_set_material(0, trail_draw_mat)

	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	meteor.add_child(trail)

	_meteors.append(meteor)


func _on_meteor_hit_ground(meteor: Node3D) -> void:
	var impact_pos := meteor.global_position
	impact_pos.y = 0.0  # Snap to approximate ground level

	# Emit impact signal (for screen shake in main.gd or camera controller)
	meteor_impact.emit(impact_pos)

	# Spawn explosion particles at impact point
	_spawn_explosion(impact_pos)


func _spawn_explosion(pos: Vector3) -> void:
	var explosion := GPUParticles3D.new()
	explosion.name = "MeteorExplosion"
	add_child(explosion)
	explosion.global_position = pos

	explosion.amount = 40
	explosion.lifetime = EXPLOSION_LIFETIME
	explosion.explosiveness = 0.95  # All at once — burst
	explosion.one_shot = true
	explosion.emitting = true
	explosion.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 15, 20))

	var exp_mat := ParticleProcessMaterial.new()
	exp_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	exp_mat.emission_sphere_radius = 0.5
	exp_mat.direction = Vector3(0.0, 1.0, 0.0)
	exp_mat.spread = 90.0
	exp_mat.initial_velocity_min = 5.0
	exp_mat.initial_velocity_max = 15.0
	exp_mat.gravity = Vector3(0.0, -4.0, 0.0)
	exp_mat.scale_min = 0.3
	exp_mat.scale_max = 1.0
	exp_mat.damping_min = 2.0
	exp_mat.damping_max = 4.0

	var exp_ramp := Gradient.new()
	exp_ramp.set_color(0, Color(1.0, 0.9, 0.4, 1.0))
	exp_ramp.add_point(0.2, Color(1.0, 0.5, 0.1, 0.8))
	exp_ramp.add_point(0.6, Color(0.6, 0.3, 0.1, 0.4))
	exp_ramp.set_color(1, Color(0.3, 0.2, 0.1, 0.0))
	var exp_tex := GradientTexture1D.new()
	exp_tex.gradient = exp_ramp
	exp_mat.color_ramp = exp_tex

	explosion.process_material = exp_mat

	var exp_quad := QuadMesh.new()
	exp_quad.size = Vector2(0.8, 0.8)
	explosion.draw_pass_1 = exp_quad
	var exp_draw_mat := StandardMaterial3D.new()
	exp_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	exp_draw_mat.vertex_color_use_as_albedo = true
	exp_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	exp_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	exp_draw_mat.no_depth_test = true
	exp_quad.surface_set_material(0, exp_draw_mat)

	explosion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	explosion.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	# Flash light at impact
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.light_energy = 8.0
	flash.omni_range = 25.0
	flash.omni_attenuation = 2.0
	flash.shadow_enabled = false
	explosion.add_child(flash)

	# Auto-cleanup after explosion finishes
	var cleanup_timer := Timer.new()
	cleanup_timer.wait_time = EXPLOSION_LIFETIME + 0.5
	cleanup_timer.one_shot = true
	cleanup_timer.autostart = true
	explosion.add_child(cleanup_timer)
	cleanup_timer.timeout.connect(explosion.queue_free)


func cleanup() -> void:
	# Free all active meteors
	for m in _meteors:
		if is_instance_valid(m):
			m.queue_free()
	_meteors.clear()
