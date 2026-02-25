extends MeshInstance3D
## Heat shimmer / energy distortion effect near the ground surface.
## Only visible when territory is being actively terraformed.
## Follows the player and scales intensity with territory_power.

var _player: Node3D
var _shimmer_material: ShaderMaterial


func _ready() -> void:
	# Create a large horizontal plane that acts as the distortion surface
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	mesh = plane

	# Load and apply shimmer shader
	var shader := load("res://assets/shaders/heat_shimmer.gdshader") as Shader
	if shader:
		_shimmer_material = ShaderMaterial.new()
		_shimmer_material.shader = shader
		_shimmer_material.set_shader_parameter("shimmer_intensity", 0.0)
		_shimmer_material.set_shader_parameter("shimmer_speed", 1.5)
		_shimmer_material.set_shader_parameter("shimmer_scale", 15.0)
		mesh.surface_set_material(0, _shimmer_material)

	# Render settings — this is a transparent overlay
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Start hidden — only show when territory has power
	visible = false


func initialize(player: Node3D) -> void:
	_player = player


func set_power_level(power: float) -> void:
	## Shimmer intensity scales with terraform power.
	## Completely hidden when no terraform power to avoid white rectangle artifact.
	var effective: float = clampf((power - 0.1) / 0.9, 0.0, 1.0)
	visible = effective > 0.01
	if _shimmer_material:
		_shimmer_material.set_shader_parameter("shimmer_intensity", effective * 0.6)


func _process(_delta: float) -> void:
	# Follow the player, positioned at ground level
	if _player and is_instance_valid(_player):
		global_position = Vector3(
			_player.global_position.x,
			_player.global_position.y - 0.5,
			_player.global_position.z
		)
