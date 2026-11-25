class_name KnockWorld
extends Node
## Bumping into things, for one scene: one per scene, made on first use by
## KnockWorld.of(node) and freed with the scene. Every physics frame it reads
## where the bumpers are (the "player" group and the "knock_bumper" group:
## vehicles, other players' avatars), and:
##   - a Knockable they touch gets a RigidBody3D and the bumper's push
##     (BumpMath.contact_impulse), plays its knock, wakes what stood on it;
##     its body goes when it lies still (it stays where it fell, bodiless), and
##     it goes home later, out of view (BumpMath.may_reset);
##   - a character (Stumble) they run into nudges, stumbles or falls
##     (BumpMath.reaction) and the player staggers a little on a hard hit.
## Costs nothing while nobody moves: resting props sit in a 4 m grid and only
## the cells around a moving bumper are looked at; bodies exist only while
## something is moving (at most MAX_ACTIVE).
##
## Bumpers may carry meta: bump_radius (m, 0.35), bump_height (m, 1.8),
## bump_mass (kg, 80). Knocked bodies are on DEBRIS_LAYER, which the player,
## the camera and vehicles don't collide with: you never trip on the mess.

signal character_bumped(stumble: Node, level: int, dir: Vector3, bumper: Node3D)
signal prop_knocked(k: Knockable, impulse: float, bumper: Node3D)
signal prop_reset(k: Knockable)

const DEBRIS_LAYER := 1 << 9
const CELL := 4.0
const MAX_PROP_R := 1.6
const MAX_ACTIVE := 32
const MIN_BUMP_SPEED := 0.8
const MAX_KICK_SPEED := 6.5     ## m/s a kick gives a prop at most
const STILL_SPEED := 0.15
const STILL_SPIN := 0.6
const STILL_S := 0.6            ## lying still this long: the body goes
const ACTIVE_MAX_S := 6.0       ## still rolling after this long: it stops where it is
const MAX_RISE_SPEED := 3.0     ## m/s upwards at most (a hop, not a launch)
const TELEPORT_SPEED := 70.0    ## faster than this between frames is a jump cut, not a bump
const GRAVITY_SCALE := 0.5      ## a low-g moon, like the player's own fall
const VIEW_M := 70.0
const CHAR_R := 0.32
const CHAR_H := 1.75
const CHECK_S := 0.5

var _props: Array = []
var _pending: Array = []
var _grid := {}       # Vector2i → Array[Knockable] (resting or lying, no body)
var _active: Array = []  # Knockable with a body, oldest first
var _lying: Array = []   # knocked, still, waiting to go home
var _chars: Array = []   # Stumble
var _last := {}       # bumper instance id → Vector3
var _bumpers: Array = []  # this frame's
var _check_t := 0.0
var _now := 0.0
var _phys_mat: PhysicsMaterial
## Tests and probes: count of knocks and resets since the scene began.
var knocks := 0
var resets := 0
## Seconds a knocked prop waits before it may go home (probes shorten it).
var reset_min_s := BumpMath.RESET_MIN_S
## Prints every knock and bump (tools/probe_bump.gd --debug).
var debug := false


## The KnockWorld of the scene `n` is in (made on first use).
static func of(n: Node) -> KnockWorld:
	if n == null or not n.is_inside_tree():
		return null
	var top := n
	while top.get_parent() != null and top.get_parent() != n.get_tree().root:
		top = top.get_parent()
	if top.has_meta("knock_world"):
		var w = top.get_meta("knock_world")
		if is_instance_valid(w):
			return w
	var kw := KnockWorld.new()
	kw.name = "KnockWorld"
	top.set_meta("knock_world", kw)
	top.add_child.call_deferred(kw)
	return kw


func _init() -> void:
	_phys_mat = PhysicsMaterial.new()
	_phys_mat.friction = 0.75
	_phys_mat.bounce = 0.12


func enlist(k: Knockable) -> void:
	if not _props.has(k):
		_props.append(k)
		_pending.append(k)


func forget(k: Knockable) -> void:
	_props.erase(k)
	_pending.erase(k)
	_active.erase(k)
	_lying.erase(k)
	_grid_remove(k)
	if k.body and is_instance_valid(k.body):
		k.body.queue_free()
	k.body = null
	if k.ghost and is_instance_valid(k.ghost):
		k.ghost.queue_free()
	k.ghost = null


func add_character(s: Node) -> void:
	if not _chars.has(s):
		_chars.append(s)


func remove_character(s: Node) -> void:
	_chars.erase(s)


func prop_count() -> int:
	return _props.size()


func active_count() -> int:
	return _active.size()


func lying_count() -> int:
	return _lying.size()


# --- the grid ---------------------------------------------------------------------

func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _grid_add(k: Knockable) -> void:
	k.cell = _cell_of(k.centre_g)
	if not _grid.has(k.cell):
		_grid[k.cell] = []
	_grid[k.cell].append(k)


func _grid_remove(k: Knockable) -> void:
	var a: Array = _grid.get(k.cell, [])
	a.erase(k)
	if a.is_empty():
		_grid.erase(k.cell)
	k.cell = Vector2i(1 << 30, 0)


## Resting or lying props whose cell is within `r` of p.
func _near(p: Vector3, r: float) -> Array:
	var out: Array = []
	var c0 := _cell_of(p - Vector3(r, 0, r))
	var c1 := _cell_of(p + Vector3(r, 0, r))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			var a = _grid.get(Vector2i(x, z))
			if a:
				out.append_array(a)
	return out


# --- the frame -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_now += delta
	if not _pending.is_empty():
		_enlist_pending()
	_bumpers = get_tree().get_nodes_in_group("player")
	_bumpers.append_array(get_tree().get_nodes_in_group("knock_bumper"))
	for b in _bumpers:
		_bumper(b as Node3D, delta)
	if not _active.is_empty():
		_step_active(delta)
	_check_t -= delta
	if _check_t <= 0.0 and not _lying.is_empty():
		_check_t = CHECK_S
		_check_resets()


func _enlist_pending() -> void:
	var keep: Array = []
	for k: Knockable in _pending:
		if not is_instance_valid(k):
			continue
		if not k.ready_to_enlist():
			keep.append(k)
			continue
		k.home = k.get_xf()
		k.home_known = true
		k.update_bounds(k.home)
		_grid_add(k)
	_pending = keep


func _bumper(b: Node3D, delta: float) -> void:
	if b == null or not b.is_inside_tree():
		return
	var id := b.get_instance_id()
	var pos := b.global_position
	var prev = _last.get(id)
	_last[id] = pos
	if prev == null or not b.is_visible_in_tree():
		return
	if b is CharacterBody3D and not b.is_physics_processing():
		return  # the player while seated in a vehicle or on a ride: the vehicle bumps
	var v: Vector3 = (pos - (prev as Vector3)) / maxf(delta, 1e-4)
	var speed := v.length()
	if speed < MIN_BUMP_SPEED or speed > TELEPORT_SPEED:
		return
	var rb := float(b.get_meta("bump_radius", 0.35))
	var hb := float(b.get_meta("bump_height", 1.8))
	var mb := float(b.get_meta("bump_mass", 80.0))
	for k: Knockable in _near(pos, rb + MAX_PROP_R):
		if not k.body and BumpMath.touches(pos, rb, hb, k.centre_g, k.radius, k.half_h):  # (woken by one before it: skip)
			var n := BumpMath.flat_normal(pos, k.centre_g, v)
			_hit(k, v, n, mb, b)
	for k: Knockable in _active.duplicate():
		if k.body and BumpMath.touches(pos, rb, hb, k.body.global_position, k.radius, k.half_h):
			var n2 := BumpMath.flat_normal(pos, k.body.global_position, v)
			var j := BumpMath.kick(v, k.body.linear_velocity, n2, mb, k.mass, MAX_KICK_SPEED, 0.0, 0.0)
			if j != Vector3.ZERO:
				k.body.apply_impulse(j, Vector3(0, k.half_h * 0.4, 0))
				k.still_t = 0.0
	for s in _chars:
		_touch_character(s, b, pos, v, rb, hb, mb)


## `k` (resting or lying) is touched by a bumper moving at v along n.
func _hit(k: Knockable, v: Vector3, n: Vector3, mb: float, bumper: Node3D) -> void:
	var j := BumpMath.kick(v, Vector3.ZERO, n, mb, k.mass, MAX_KICK_SPEED)
	if j == Vector3.ZERO:
		return
	if not _activate(k):
		return
	# Pushed above its middle: it topples the way it was pushed.
	k.body.apply_impulse(j, Vector3(0, k.half_h * 0.45, 0))
	k.body.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * j.length() * 0.02)
	knocks += 1
	if debug:
		print("[Knock] %s knocked at %s: impulse %.1f N·s (%.1f kg)" % [k.get_parent().name, k.centre_g, j.length(), k.mass])
	BumpSfx.play_at(self, k.centre_g, k.sound, clampf(j.length() / (k.mass * 4.0), 0.2, 1.0))
	prop_knocked.emit(k, j.length(), bumper)
	if bumper and bumper.has_method("bump_stagger") and bumper.is_in_group("player"):
		var s := BumpMath.stagger_seconds(BumpMath.NONE, j.length())
		# The bumper gives what the prop took (momentum), lightly.
		bumper.bump_stagger(s, -Vector3(j.x, 0, j.z) / mb * 0.6)


## Gives `k` a body where it stands. False when it can't (too many moving).
func _activate(k: Knockable) -> bool:
	if k.body:
		return true
	if _active.size() >= MAX_ACTIVE:
		_settle(_active[0])  # the oldest stops where it is
	_grid_remove(k)
	_lying.erase(k)
	if k.ghost and is_instance_valid(k.ghost):
		k.ghost.queue_free()
	k.ghost = null
	var g := k.get_xf()
	var body := RigidBody3D.new()
	body.name = "Knocked"
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = 1 | DEBRIS_LAYER
	body.mass = k.mass
	body.gravity_scale = GRAVITY_SCALE
	body.physics_material_override = _phys_mat
	body.angular_damp = 2.6 if k.shape_cyl else 1.6  # a lying bin or stool would roll for ever
	body.linear_damp = 0.2
	body.continuous_cd = k.mass < 2.0
	var cs := CollisionShape3D.new()
	var e := k.global_size()
	if k.shape_cyl:
		var cy := CylinderShape3D.new()
		cy.radius = maxf(e.x * 0.5, 0.02)
		cy.height = maxf(e.y, 0.04)
		cs.shape = cy
	else:
		var bx := BoxShape3D.new()
		bx.size = Vector3(maxf(e.x, 0.04), maxf(e.y, 0.04), maxf(e.z, 0.04))
		cs.shape = bx
	body.add_child(cs)
	# The player and vehicles stand on layer 1 too: they push through the mess by
	# KnockWorld's impulses alone, never by the solver shoving a body out of a capsule.
	for b in _bumpers:
		if b is PhysicsBody3D and is_instance_valid(b):
			body.add_collision_exception_with(b)
	add_child(body)
	body.global_transform = k.body_xf(g)
	k.body = body
	k.still_t = 0.0
	k.moving_since = _now
	if k.knocked_at < 0.0:
		k.knocked_at = _now
	k.lying = false
	if k.collider and is_instance_valid(k.collider):
		k.collider.process_mode = Node.PROCESS_MODE_DISABLED
	_active.append(k)
	_wake_above(k)
	_support_below(k)
	return true


## Whatever stood or lay on `k` falls with it.
func _wake_above(k: Knockable) -> void:
	var top := k.centre_g.y + k.half_h
	for o: Knockable in _near(k.centre_g, k.radius + MAX_PROP_R):
		if o == k or o.body:
			continue
		var dx: float = o.centre_g.x - k.centre_g.x
		var dz: float = o.centre_g.z - k.centre_g.z
		if dx * dx + dz * dz > k.radius * k.radius * 1.4:
			continue
		var bottom: float = o.centre_g.y - o.half_h
		if bottom > top - 0.15 and bottom < top + 0.25:
			_activate(o)


## If `k` stood on a resting prop, that prop holds it up (a stand-in collider)
## until it is knocked itself.
func _support_below(k: Knockable) -> void:
	var bottom := k.centre_g.y - k.half_h
	for o: Knockable in _near(k.centre_g, MAX_PROP_R):
		if o == k or o.body or o.ghost:
			continue
		var dx: float = o.centre_g.x - k.centre_g.x
		var dz: float = o.centre_g.z - k.centre_g.z
		if dx * dx + dz * dz > o.radius * o.radius:
			continue
		var top: float = o.centre_g.y + o.half_h
		if absf(top - bottom) > 0.2:
			continue
		var sb := StaticBody3D.new()
		sb.name = "Support"
		sb.collision_layer = DEBRIS_LAYER
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		var e: Vector3 = o.global_size()
		bx.size = Vector3(maxf(e.x, 0.04), maxf(e.y, 0.04), maxf(e.z, 0.04))
		cs.shape = bx
		sb.add_child(cs)
		add_child(sb)
		sb.global_transform = o.body_xf(o.get_xf())
		o.ghost = sb


func _step_active(delta: float) -> void:
	for k: Knockable in _active.duplicate():
		if not is_instance_valid(k) or k.body == null:
			_active.erase(k)
			continue
		var body: RigidBody3D = k.body
		var bx := body.global_transform
		k.set_xf(k.mesh_xf(bx))
		k.centre_g = bx.origin
		if bx.origin.y < k.home.origin.y - 40.0:
			_reset(k)  # fell out of the world
			continue
		# No launches: a body that starts touching the ground or a wall is pushed
		# out by the solver, sometimes hard. Nothing knocked goes faster than a kick.
		var lv := body.linear_velocity
		var flat := Vector2(lv.x, lv.z)
		if flat.length() > MAX_KICK_SPEED * 1.3 or lv.y > MAX_RISE_SPEED:
			flat = flat.limit_length(MAX_KICK_SPEED * 1.3)
			body.linear_velocity = Vector3(flat.x, minf(lv.y, MAX_RISE_SPEED), flat.y)
		# Other props it runs into fall too.
		var sp := body.linear_velocity.length()
		if sp > 1.5:
			for o: Knockable in _near(bx.origin, k.radius + MAX_PROP_R):
				if o != k and not o.body and BumpMath.touches(bx.origin - Vector3(0, k.half_h, 0), k.radius, k.half_h * 2.0, o.centre_g, o.radius, o.half_h):
					_hit(o, body.linear_velocity, BumpMath.flat_normal(bx.origin, o.centre_g, body.linear_velocity), k.mass, null)
					if k.body == null:
						break
		if _now - k.moving_since > ACTIVE_MAX_S:
			_settle(k)
		elif body.sleeping or (sp < STILL_SPEED and body.angular_velocity.length() < STILL_SPIN):
			k.still_t += delta
			if k.still_t >= STILL_S:
				_settle(k)
		else:
			k.still_t = 0.0


## The body goes; the prop stays where it lies (bodiless) until it goes home.
func _settle(k: Knockable) -> void:
	_active.erase(k)
	if k.body and is_instance_valid(k.body):
		var g := k.mesh_xf(k.body.global_transform)
		k.set_xf(g)
		k.body.queue_free()
	k.body = null
	var now_xf := k.get_xf()
	k.update_bounds(now_xf)
	k.lying = true
	_lying.append(k)
	_grid_add(k)


func _check_resets() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	for k: Knockable in _lying.duplicate():
		var age: float = _now - k.knocked_at
		var seen := _seen(cam, k.centre_g)
		var home_seen := _seen(cam, k.home * k.center)
		if BumpMath.may_reset(age, true, seen, home_seen, reset_min_s):
			_reset(k)


func _seen(cam: Camera3D, p: Vector3) -> bool:
	if cam == null:
		return false
	return cam.global_position.distance_to(p) < VIEW_M and cam.is_position_in_frustum(p)


## Home, quietly.
func _reset(k: Knockable) -> void:
	_active.erase(k)
	_lying.erase(k)
	_grid_remove(k)
	if k.body and is_instance_valid(k.body):
		k.body.queue_free()
	k.body = null
	if k.ghost and is_instance_valid(k.ghost):
		k.ghost.queue_free()
	k.ghost = null
	k.set_xf(k.home)
	k.update_bounds(k.home)
	k.lying = false
	k.knocked_at = -1.0
	if k.collider and is_instance_valid(k.collider):
		k.collider.process_mode = Node.PROCESS_MODE_INHERIT
	_grid_add(k)
	resets += 1
	prop_reset.emit(k)


## Sends everything home now (tests, probes, a scene that wants it tidy).
func reset_all() -> void:
	for k: Knockable in _active.duplicate() + _lying.duplicate():
		_reset(k)


## Probes: the prop knocked as if hit at `v` from `from`.
func knock(k: Knockable, v: Vector3, from: Vector3, mb: float = 80.0) -> void:
	_hit(k, v, BumpMath.flat_normal(from, k.centre_g, v), mb, null)


# --- characters ------------------------------------------------------------------

func _touch_character(s: Node, b: Node3D, pos: Vector3, v: Vector3, rb: float, hb: float, mb: float) -> void:
	if not is_instance_valid(s) or not s.is_inside_tree():
		return
	var av: Node3D = s.avatar
	if av == null or av == b or not av.is_visible_in_tree() or b.is_ancestor_of(av):
		return
	var cp := av.global_position
	if not BumpMath.touches(pos, rb, hb, cp + Vector3(0, CHAR_H * 0.5, 0), CHAR_R, CHAR_H * 0.5):
		return
	var n := BumpMath.flat_normal(pos, cp, v)
	var closing: float = (v - (s.velocity() as Vector3)).dot(n)
	var level := BumpMath.reaction(BumpMath.effective_speed(closing, mb), s.can_fall())
	if debug:
		print("[Knock] %s bumps %s: v %.1f closing %.1f can_fall %s → level %d" % [b.name, av.name, v.length(), closing, s.can_fall(), level])
	if level == BumpMath.NONE or not s.ready_for(level):
		return
	s.bump(n, level, b)
	character_bumped.emit(s, level, n, b)
	if b.has_method("bump_stagger") and b.is_in_group("player") and level >= BumpMath.STUMBLE:
		b.bump_stagger(BumpMath.stagger_seconds(level), -n * (1.5 if level == BumpMath.FALL else 0.8))
