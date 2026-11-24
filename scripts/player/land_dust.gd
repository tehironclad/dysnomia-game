class_name LandDust
extends CPUParticles3D
## A puff of regolith where feet touch down after a fall: a low ring of dust
## that spreads and settles slowly (low gravity), then frees itself.

static var _mat: StandardMaterial3D


static func spawn(parent: Node, at: Vector3, strength: float) -> void:
	if parent == null or strength <= 0.0 or DisplayServer.get_name() == "headless":
		return
	var d := LandDust.new()
	d.amount = int(lerpf(10.0, 28.0, strength))
	d.lifetime = lerpf(0.9, 1.6, strength)
	d.one_shot = true
	d.explosiveness = 0.95
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	d.emission_ring_axis = Vector3.UP
	d.emission_ring_radius = 0.35
	d.emission_ring_inner_radius = 0.15
	d.emission_ring_height = 0.05
	d.direction = Vector3(0, 0.35, 0)
	d.spread = 80.0
	d.flatness = 0.7
	d.initial_velocity_min = lerpf(0.8, 1.6, strength)
	d.initial_velocity_max = lerpf(1.6, 3.4, strength)
	d.gravity = Vector3(0, -0.6, 0)
	d.damping_min = 1.5
	d.damping_max = 2.5
	d.scale_amount_min = 0.5
	d.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 1.4))
	d.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.72, 0.7, 0.66, 0.55))
	grad.set_color(1, Color(0.72, 0.7, 0.66, 0.0))
	d.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	q.material = _material()
	d.mesh = q
	parent.add_child(d)
	d.global_position = at + Vector3(0, 0.05, 0)
	d.emitting = true
	d.finished.connect(d.queue_free)


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mat.vertex_color_use_as_albedo = true
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 32
		tex.height = 32
		_mat.albedo_texture = tex
	return _mat
