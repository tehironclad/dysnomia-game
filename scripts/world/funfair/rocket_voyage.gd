class_name RocketVoyage
extends Node3D
## The Upsilon Rocket, piloted. A few seconds after liftoff the player takes the
## controls: W thrust, S brake, mouse or A/D to steer, Shift to burn harder. The
## rocket climbs slowly toward light speed (this game's c, C_MS); past 0.97 c a
## wormhole opens ahead, and flying into it leaves the territory for the Field
## (the globe of every QING), to pick the next one. Esc aborts: the rocket goes
## home to its pad and the rider is set down.
##
## Nothing here touches the chain; the ticket was paid (or the preview labelled)
## by FairSite before the ride started.

signal ended(to_field: bool)

const C_MS := 1500.0            ## "light speed" in this world, m/s (the streaks and FOV sell the rest)
const WORMHOLE_BETA := 0.97
const WORMHOLE_DIST := 9000.0   ## about 6 s ahead at light speed
const WORMHOLE_R := 320.0
const MIN_CLEAR := 8.0          ## metres above the ground the rocket can't go below
const STARS := 420
const MILESTONES := [[0.1, "0.1 c · the territory falls away"], [0.25, "0.25 c"], [0.5, "HALF LIGHT SPEED"],
	[0.75, "0.75 c · the stars stretch"], [0.9, "0.9 c · space is folding ahead"]]

var _ride: RocketRide
var _rocket: Node3D
var _player: Node3D
var _hud: Node
var _ground: Callable
var _cam: Camera3D
var _prev_cam: Camera3D
var _beta := 0.0
var _yaw := 0.0
var _pitch := PI * 0.5
var _roll := 0.0
var _t := 0.0
var _pos := Vector3.ZERO
var _stars: MultiMeshInstance3D
var _star_pos: PackedVector3Array = []
var _star_mat: StandardMaterial3D
var _wormhole: Node3D
var _worm_disc: MeshInstance3D
var _flash: ColorRect
var _leaving := -1.0
var _milestone := 0
var _hud_t := 0.0
var _done := false
var _prev_pos := Vector3.ZERO


func begin(ride: RocketRide, player: Node3D, hud: Node, ground: Callable) -> void:
	_ride = ride
	_player = player
	_hud = hud
	_ground = ground
	_rocket = ride.rocket_node()
	_pos = _rocket.global_position
	_beta = 18.0 / C_MS   # liftoff speed after the scripted burn
	_yaw = ride.global_rotation.y
	_rocket.reparent(self, true)
	if _player:
		_player.visible = false
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.far = 20000.0
	_cam.fov = 70.0
	add_child(_cam)
	_cam.global_position = _pos - Vector3(0, 0, -40) + Vector3.UP * 20.0
	_cam.make_current()
	_build_stars()
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
	if _hud:
		_hud.ticker("YOU HAVE THE CONTROLS · %s thrust · %s brake · mouse / %s %s steer · %s burn harder · Esc abort" % [
			ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_back"), ControlsHelp.key_of("move_left"),
			ControlsHelp.key_of("move_right"), ControlsHelp.key_of("sprint")], Color("#ffd27a"), 12.0)
	_place(0.0)


## Pure: heading for yaw/pitch (pitch 0 = level toward −Z turned by yaw, PI/2 = straight up).
static func heading(yaw: float, pitch: float) -> Vector3:
	return -(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)).z


## Pure: how β grows per second under thrust (slow at first, then faster), or falls on the brake.
static func beta_rate(beta: float, thrust: bool, boost: bool, brake: bool) -> float:
	if brake:
		return -(0.01 + 0.3 * beta)
	if thrust:
		return (0.012 + 0.05 * beta) * (2.0 if boost else 1.0)
	return 0.0


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _leaving >= 0.0:
		_leaving += delta
		_flash.color.a = clampf(_leaving / 0.9, 0.0, 1.0)
		_beta = minf(1.0, _beta + delta * 0.2)
		_move(delta)
		if _leaving >= 1.1:
			_finish(true)
		return
	var thrust := Input.is_action_pressed("move_forward")
	var brake := Input.is_action_pressed("move_back")
	var boost := Input.is_action_pressed("sprint")
	_beta = clampf(_beta + beta_rate(_beta, thrust, boost, brake) * delta, 0.002, 0.995)
	var steer := Input.get_axis("move_right", "move_left")
	_yaw += steer * 1.1 * delta
	_roll = lerpf(_roll, -steer * 0.6, minf(1.0, delta * 4.0))
	_move(delta)
	_ride.set_engine(0.35 + 0.65 * float(thrust) + 0.3 * float(boost and thrust), _t)
	while _milestone < MILESTONES.size() and _beta >= float(MILESTONES[_milestone][0]):
		if _hud:
			_hud.ticker(String(MILESTONES[_milestone][1]), DeepFieldTheme.ICE, 6.0)
		_milestone += 1
	if _wormhole == null and _beta >= WORMHOLE_BETA:
		_open_wormhole()
	if _wormhole:
		_wormhole.rotate_object_local(Vector3.UP, delta * 0.6)
		if _through(_prev_pos, _pos):
			_leaving = 0.0
			if _hud:
				_hud.ticker("THROUGH THE WORMHOLE · to the Field", Color("#ffd27a"), 6.0)
	_hud_t -= delta
	if _hud_t <= 0.0 and _hud:
		_hud_t = 0.1
		_hud.show_prompt(_readout())


func _move(delta: float) -> void:
	var f := heading(_yaw, _pitch)
	_prev_pos = _pos
	_pos += f * _beta * C_MS * delta
	var g := float(_ground.call(_pos.x, _pos.z)) if _ground.is_valid() else -INF
	if _pos.y < g + MIN_CLEAR:
		_pos.y = g + MIN_CLEAR
		_pitch = maxf(_pitch, 0.25)
	_place(delta)
	_update_stars(f, delta)


func _place(delta: float) -> void:
	var look := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var f := -look.z
	var b := Basis(f, _roll) * look * Basis(Vector3.RIGHT, -PI * 0.5)
	_rocket.global_transform = Transform3D(b.scaled(Vector3.ONE * RocketRide.SCALE), _pos)
	# Chase camera: behind and above the rocket, pulled back and widened with speed
	var back := 34.0 + 10.0 * _beta
	var want := _pos - f * back + look.y * (9.0 + 4.0 * _beta) + f * 22.0
	_cam.global_position = want if delta <= 0.0 else _cam.global_position.lerp(want, minf(1.0, delta * 6.0))
	_cam.look_at(_pos + f * (60.0 + 200.0 * _beta), look.y)
	_cam.fov = 70.0 + 38.0 * _beta * _beta


func _input(event: InputEvent) -> void:
	if _done or _leaving >= 0.0:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.2, PI * 0.5)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _hud:
			_hud.ticker("Voyage aborted · back to the pad", DeepFieldTheme.ICE, 6.0)
		_finish(false)


## Did the segment a→b cross the wormhole's mouth (its disc plane, inside the ring)?
## Works however long the frame was.
func _through(a: Vector3, b: Vector3) -> bool:
	return crosses_disc(a, b, _wormhole.global_position, _wormhole.global_transform.basis.y.normalized(), WORMHOLE_R)


static func crosses_disc(a: Vector3, b: Vector3, c: Vector3, n: Vector3, r: float) -> bool:
	var da := (a - c).dot(n)
	var db := (b - c).dot(n)
	if da * db > 0.0 or is_equal_approx(da, db):
		return (b - c).length() < r * 0.5
	var p := a + (b - a) * (da / (da - db))
	return (p - c).length() < r


func _readout() -> String:
	var alt := _pos.y - (float(_ground.call(_pos.x, _pos.z)) if _ground.is_valid() else 0.0)
	var s := "VELOCITY %.3f c · %s m/s · ALT %s m" % [_beta, ArcadeScores.grouped(int(_beta * C_MS)), ArcadeScores.grouped(int(alt))]
	if _wormhole:
		var d := _wormhole.global_position - _pos
		s += " · WORMHOLE %s m %s" % [ArcadeScores.grouped(int(d.length())), _bearing(d)]
	elif _beta < WORMHOLE_BETA:
		s += " · wormhole at %.2f c" % WORMHOLE_BETA
	return s


## "ahead" / "left" / "above"… for a world offset, from the camera's point of view.
func _bearing(d: Vector3) -> String:
	var local := _cam.global_transform.basis.inverse() * d.normalized()
	if local.z < -0.85:
		return "ahead"
	if local.z > 0.3:
		return "behind"
	if absf(local.x) > absf(local.y):
		return "right" if local.x > 0.0 else "left"
	return "above" if local.y > 0.0 else "below"


# --- Effects ----------------------------------------------------------------------

func _build_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.35, 1.0)
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_star_mat.albedo_color = Color(0.8, 0.9, 1.0, 0.0)
	box.material = _star_mat
	mm.mesh = box
	mm.instance_count = STARS
	_stars = MultiMeshInstance3D.new()
	_stars.multimesh = mm
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.top_level = true
	add_child(_stars)
	var rng := RandomNumberGenerator.new()
	rng.seed = 369
	_star_pos.resize(STARS)
	for i in STARS:
		_star_pos[i] = _pos + _star_offset(rng, heading(_yaw, _pitch), rng.randf_range(-200.0, 1800.0))


func _star_offset(rng: RandomNumberGenerator, f: Vector3, along: float) -> Vector3:
	var side := f.cross(Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(f).normalized()
	var a := rng.randf() * TAU
	var r := rng.randf_range(40.0, 520.0)
	return f * along + (side * cos(a) + up * sin(a)) * r


var _rng := RandomNumberGenerator.new()


func _update_stars(f: Vector3, _delta: float) -> void:
	var len := 1.0 + 160.0 * _beta * _beta
	_star_mat.albedo_color = Color(0.85, 0.9, 1.0).lerp(Color(0.45, 0.7, 1.0), _beta) * Color(1, 1, 1, clampf((_beta - 0.04) * 3.0, 0.0, 0.9))
	var mm := _stars.multimesh
	var basis := Basis.looking_at(f, Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT).scaled(Vector3(1.0, 1.0, len))
	for i in STARS:
		var rel := _star_pos[i] - _pos
		if rel.dot(f) < -120.0 or rel.length() > 2600.0:
			_star_pos[i] = _pos + _star_offset(_rng, f, _rng.randf_range(900.0, 1900.0))
		mm.set_instance_transform(i, Transform3D(basis, _star_pos[i]))


func _open_wormhole() -> void:
	var f := heading(_yaw, _pitch)
	_wormhole = Node3D.new()
	_wormhole.name = "Wormhole"
	_wormhole.top_level = true
	add_child(_wormhole)
	_wormhole.global_position = _pos + f * WORMHOLE_DIST   # on the flight line: hold course and you go through
	# Face the rocket: the ring's axis (local Y) points back along the approach
	_wormhole.global_transform.basis = Basis.looking_at(-f, Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI * 0.5)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = WORMHOLE_R
	torus.outer_radius = WORMHOLE_R + 26.0
	torus.rings = 48
	torus.ring_segments = 16
	ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.75, 0.45, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.7, 0.4, 1.0)
	rm.emission_energy_multiplier = 4.0
	ring.material_override = rm
	_wormhole.add_child(ring)
	_worm_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = WORMHOLE_R
	disc.bottom_radius = WORMHOLE_R
	disc.height = 0.5
	disc.radial_segments = 64
	_worm_disc.mesh = disc
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/wormhole.gdshader")
	sm.set_shader_parameter("radius", WORMHOLE_R)
	_worm_disc.material_override = sm
	_wormhole.add_child(_worm_disc)
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.5, 1.0)
	light.light_energy = 8.0
	light.omni_range = 900.0
	_wormhole.add_child(light)
	if _hud:
		_hud.ticker("A WORMHOLE OPENS ahead · fly into it to reach the Field and pick another QING", Color("#ffd27a"), 14.0)


func _finish(to_field: bool) -> void:
	if _done:
		return
	_done = true
	if _hud:
		_hud.hide_prompt()
	ended.emit(to_field)
	if to_field:
		Travel.field(get_tree())
		return
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if _player:
		_player.visible = true
	_ride.voyage_returned()
	queue_free()
