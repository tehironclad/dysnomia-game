class_name Landmark
extends Node3D
## The landmark supertall of a developed QING (LandmarkPlan has the numbers).
## Built from territory state only, so every viewer sees the same tower:
##   class and height  ← Development tier and the Hypobar total (YUE.Bar, a floor)
##   lit windows       ← Development energy (the Epibar total)
##   the signs         ← the QING's name; the top Hypobar holder's LAU.Username()
##                       when it reads (CHO.GetUserTokenAddress → LAU), else omitted
## Wild and Outpost QINGs get nothing: they stay moonscape.
##
## The glass lift is free: looking costs nothing (reads need no wallet). The
## jump from the sky deck is the act: a 1 Ⓐ jump ticket, AFFECTION.transfer to
## this QING through ArcadePay (simulated, signed, receipt-verified, the QING's
## balance re-read), exactly like a fair ride. No wallet, or no ticket: a
## practice jump, labelled as such, never recorded.

signal jump_requested(at: Vector3, dir: Vector3, source: String, ticket: Dictionary)
signal built

const SHADER := preload("res://assets/shaders/landmark.gdshader")

var spec: Dictionary = {}
var site: Dictionary = {}
var ring: Dictionary = {}
var plank_info: Dictionary = {}
var lift_info: Dictionary = {}
var energy := 0.0
var hypobar_text := "—"
var block := -1
var leader_name := ""   ## the top Hypobar holder's LAU username, "" when not read

var _qing := ""
var _qing_name := ""
var _hud: Node
var _player: CharacterBody3D
var _height_fn: Callable
var _tint := Color("#7fd3ff")
var _ground_mat: Material
var _tower: Node3D       ## rotated so +Z faces the Core
var _ring_node: Node3D
var _mat: ShaderMaterial
var _mat_round: ShaderMaterial  ## the same facade on round masses (the Burj's core)
var _car: Node3D
var _blinkers: Array = []
var _blink_mat: StandardMaterial3D
var _lobby_sign: Label3D
var _focus := ""         ## lift_up | lift_down | plank | ""
var _riding := false
var _ride_t := 0.0
var _ride_from := 0.0
var _ride_to := 0.0
var _paying := false
var _practice_ok := false
var _leader_wallet := ""
var _t := 0.0
var _pending := {}       ## a rebuild waiting for the lift to stop
## The YUE Exchange floor (scripts/world/exchange/yue_floor.gd): a stop of the glass
## lift at this height, set by whoever builds the floor after `built`; -1 = none.
var exchange_y := -1.0


func tower_node() -> Node3D:
	return _tower


func setup(qing: String, qing_name: String, hud: Node, player: CharacterBody3D, height_fn: Callable,
		tint: Color, ground_mat: Material, others: Array) -> void:
	_qing = qing.to_lower()
	_qing_name = qing_name
	_hud = hud
	_player = player
	_height_fn = height_fn
	_tint = tint
	_ground_mat = ground_mat
	site = LandmarkPlan.tower_site(height_fn, others)
	var at: Vector2 = site.get("at", LandmarkPlan.PREFER)
	position = Vector3(at.x, float(site.get("top", 0.0)) + 0.12, at.y)
	ring = LandmarkPlan.ring_site(height_fn, at, others)
	print("[Landmark] site %s (on land: %s) · landing ring %s (on land: %s)" % [str(at), site.get("ok"), str(ring.get("at")), ring.get("ok")])


## The ring's centre in this node's parent space (the Core's).
func ring_local() -> Vector3:
	var r: Vector2 = ring.get("at", Vector2(position.x, position.z) + Vector2(0, 150))
	return Vector3(r.x, float(ring.get("top", 0.0)) + 0.1, r.y)


## The ring's centre in world space.
func ring_global() -> Vector3:
	var p := get_parent() as Node3D
	return p.to_global(ring_local()) if p else ring_local()


func has_tower() -> bool:
	return not spec.is_empty()


## From territory state (same for every viewer).
func set_development(tier: int, hypobar_total: PackedInt64Array, p_energy: float, board: Array, p_block: int) -> void:
	energy = p_energy
	block = p_block
	hypobar_text = TokenFormat.group(BigInt.to_decimal(hypobar_total)) if not hypobar_total.is_empty() else "—"
	if _mat:
		_mat.set_shader_parameter("energy", energy)
		_mat_round.set_shader_parameter("energy", energy)
	var lg := BigInt.log10(hypobar_total) if not BigInt.is_zero(hypobar_total) else -INF
	var s := LandmarkPlan.spec(tier, lg)
	if not board.is_empty():
		var w := String(board[0].get("wallet", "")).to_lower()
		if w != "" and w != _leader_wallet:
			_leader_wallet = w
			_read_leader(w)
	if s.get("kind", "") == spec.get("kind", "") and s.get("floors", 0) == spec.get("floors", 0):
		_update_signs()
		return
	if _riding or _paying or _player_on_site():
		_pending = {"spec": s}
		return
	_rebuild(s)


func _rebuild(s: Dictionary) -> void:
	spec = s
	for c in get_children():
		c.queue_free()
	_tower = null
	_ring_node = null
	_car = null
	_blinkers.clear()
	_lobby_sign = null
	_focus = ""
	exchange_y = -1.0
	if spec.is_empty():
		return
	var ms := LandmarkPlan.masses(spec)
	lift_info = LandmarkPlan.lift(spec)
	# Turn the tower so its plank points at the landing ring and its front (lobby,
	# lift) faces the Core as nearly as that allows.
	var ring_xz := Vector2(ring_local().x, ring_local().z) - Vector2(position.x, position.z)
	var to_core := -Vector2(position.x, position.z)
	var yaw := LandmarkPlan.orient(spec, atan2(ring_xz.y, ring_xz.x), atan2(to_core.y, to_core.x))
	plank_info = LandmarkPlan.plank(spec, atan2(ring_xz.y, ring_xz.x) + yaw)
	_build_terrace(LandmarkPlan.PLAZA_R, position.y - float(site.get("low", position.y)) + 1.5, Vector3.ZERO)
	_tower = Node3D.new()
	_tower.name = "Tower"
	_tower.rotation.y = yaw
	add_child(_tower)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("tint", _tint)
	_mat.set_shader_parameter("energy", energy)
	_mat.set_shader_parameter("seed", float(_qing.right(6).hex_to_int() % 997))
	_mat.set_shader_parameter("base_y", 0.0)
	_mat.set_shader_parameter("crown_y", 1.0e6)
	_mat_round = _mat.duplicate()
	_mat_round.set_shader_parameter("curved", 1.0)
	for m in ms:
		_mass(m)
	_build_lift()
	_build_lobby()
	_build_deck(ms)
	_build_top()
	_build_ring()
	_update_signs()
	# base_y/crown_y need world heights: set once the tower is in the tree
	_mat.set_shader_parameter("base_y", global_position.y)
	_mat.set_shader_parameter("crown_y", global_position.y + float(spec["roof"]) - 16.0)
	for k in ["base_y", "crown_y"]:
		_mat_round.set_shader_parameter(k, _mat.get_shader_parameter(k))
	print("[Landmark] %s · %d floors · roof %d m · top %d m · plank toward %d°" % [spec["title"], spec["floors"], int(spec["roof"]), int(spec["top"]), int(rad_to_deg(plank_info["bearing"]))])
	built.emit()


# --- Geometry ------------------------------------------------------------------

func _mass(m: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	if m.has("cyl"):
		var c := CylinderMesh.new()
		c.top_radius = m["cyl"]
		c.bottom_radius = m["cyl"]
		c.height = m["h"]
		c.radial_segments = 12
		c.rings = 1
		mi.mesh = c
		Solid.cylinder(_tower, m["cyl"], m["h"], m["pos"] - Vector3(0, float(m["h"]) * 0.5, 0))
	else:
		var b := BoxMesh.new()
		b.size = m["size"]
		mi.mesh = b
		mi.rotation.y = m["yaw"]
		Solid.box(_tower, m["size"], m["pos"], m["yaw"])
	mi.position = m["pos"]
	mi.material_override = _mat_round if m.has("cyl") else _mat
	_tower.add_child(mi)


static func _glow(c: Color, e: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


static func _glass(alpha: float = 0.14) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.78, 1.0, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.6
	m.roughness = 0.05
	return m


static func _metal(c: Color = Color(0.2, 0.21, 0.24)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.85
	m.roughness = 0.3
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, yaw: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.rotation.y = yaw
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, text: String, at: Vector3, px: float, font_size: int, color: Color, billboard: bool = false, mono: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = DeepFieldTheme.mono_font() if mono else DeepFieldTheme.display_font()
	l.font_size = font_size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0 if not billboard else 10
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.double_sided = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.position = at
	parent.add_child(l)
	return l


func _build_lift() -> void:
	var lz: float = lift_info["z"]
	var h: float = spec["deck"]
	var half: float = lift_info["half"]
	var shaft := Node3D.new()
	shaft.name = "LiftShaft"
	shaft.position = Vector3(0, 0, lz)
	_tower.add_child(shaft)
	_box(shaft, Vector3(half * 2.0, h + 4.0, half * 2.0), Vector3(0, (h + 4.0) * 0.5, 0), _glass(0.08))
	var rail := _glow(_tint, 2.2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(shaft, Vector3(0.16, h + 4.0, 0.16), Vector3(sx * half, (h + 4.0) * 0.5, sz * half), rail)
	_box(shaft, Vector3(half * 2.0 + 0.6, 2.0, half * 2.0 + 0.6), Vector3(0, h + 5.0, 0), _metal())  # machine room
	# The glass car
	_car = Node3D.new()
	_car.name = "Car"
	shaft.add_child(_car)
	_box(_car, Vector3(3.3, 0.18, 3.3), Vector3(0, -0.09, 0), _metal(Color(0.32, 0.33, 0.36)))
	_box(_car, Vector3(3.3, 0.12, 3.3), Vector3(0, 3.0, 0), _metal(Color(0.32, 0.33, 0.36)))
	_box(_car, Vector3(3.2, 3.0, 3.2), Vector3(0, 1.5, 0), _glass(0.1))
	var edge := _glow(Color("#ffd27a"), 2.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(_car, Vector3(0.08, 3.0, 0.08), Vector3(sx * 1.6, 1.5, sz * 1.6), edge)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffe2b0")
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	lamp.position = Vector3(0, 2.6, 0)
	_car.add_child(lamp)
	_car.position.y = 0.12


func _build_lobby() -> void:
	## A glass pavilion around the lift's foot, its door facing the Core.
	var lz: float = lift_info["z"]
	var back := lz - float(lift_info["half"]) - LandmarkPlan.LIFT_GAP - 0.5
	var front := lz + 6.5
	var w := 13.0
	var h := 7.0
	var cz := (back + front) * 0.5
	var depth := front - back
	var lobby := Node3D.new()
	lobby.name = "Lobby"
	_tower.add_child(lobby)
	var glass := _glass(0.16)
	var frame := _glow(_tint, 1.6)
	# Sides, the front either side of a 4.5 m door, the roof
	for sx in [-1.0, 1.0]:
		_box(lobby, Vector3(0.2, h, depth), Vector3(sx * w * 0.5, h * 0.5, cz), glass)
		Solid.box(lobby, Vector3(0.4, h, depth), Vector3(sx * w * 0.5, h * 0.5, cz))
		var pw := (w - 4.5) * 0.5
		_box(lobby, Vector3(pw, h, 0.2), Vector3(sx * (2.25 + pw * 0.5), h * 0.5, front), glass)
		Solid.box(lobby, Vector3(pw, h, 0.4), Vector3(sx * (2.25 + pw * 0.5), h * 0.5, front))
		_box(lobby, Vector3(0.18, h, 0.18), Vector3(sx * 2.25, h * 0.5, front), frame)
		_box(lobby, Vector3(0.18, h, 0.18), Vector3(sx * w * 0.5, h * 0.5, front), frame)
	_box(lobby, Vector3(w + 0.6, 0.5, depth + 0.6), Vector3(0, h + 0.25, cz), _metal())
	_box(lobby, Vector3(w + 0.6, 0.12, 0.12), Vector3(0, h + 0.05, front + 0.3), frame)
	Solid.box(lobby, Vector3(w, 0.5, depth), Vector3(0, h + 0.25, cz))
	# Floor: polished stone, lit from inside
	var floor_m := _metal(Color(0.12, 0.12, 0.14))
	floor_m.metallic = 0.3
	floor_m.roughness = 0.12
	_box(lobby, Vector3(w, 0.1, depth), Vector3(0, 0.05, cz), floor_m)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffe2b0")
	lamp.light_energy = 2.0
	lamp.omni_range = 14.0
	lamp.position = Vector3(0, h - 1.0, cz + 1.0)
	lobby.add_child(lamp)
	# The sign over the door (facing out, toward the Core): chain numbers
	_lobby_sign = _label(lobby, "", Vector3(0, h + 2.4, front + 0.45), 0.012, 64, DeepFieldTheme.INK, false, true)
	_lobby_sign.outline_size = 8


func _build_deck(ms: Array) -> void:
	var y: float = spec["deck"]
	var r := LandmarkPlan.deck_radius(spec)
	var deck := Node3D.new()
	deck.name = "SkyDeck"
	deck.position.y = y
	_tower.add_child(deck)
	var slab := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r - 1.5
	c.height = 1.4
	c.radial_segments = 48
	c.rings = 1
	slab.mesh = c
	slab.material_override = _metal(Color(0.14, 0.15, 0.17))
	slab.position.y = -0.7
	deck.add_child(slab)
	Solid.cylinder(deck, r, 1.4, Vector3(0, -1.4, 0))
	# Under-glow ring and the helipad markings
	var glow := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r - 0.15
	t.outer_radius = r + 0.15
	t.rings = 96
	glow.mesh = t
	glow.material_override = _glow(_tint, 2.4)
	glow.position.y = -0.7
	glow.scale = Vector3(1, 0.5, 1)
	deck.add_child(glow)
	var pad := MeshInstance3D.new()
	var pt := TorusMesh.new()
	pt.inner_radius = 6.6
	pt.outer_radius = 7.0
	pt.rings = 64
	pad.mesh = pt
	pad.material_override = _glow(Color("#ffd27a"), 1.8)
	pad.scale = Vector3(1, 0.1, 1)
	pad.position = Vector3(0, 0.03, -r * 0.35) if spec["kind"] == "burj" else Vector3(0, 0.03, 0)
	deck.add_child(pad)
	if spec["kind"] != "burj":
		var hl := _label(deck, "H", pad.position + Vector3(0, 0.05, 0), 0.05, 128, Color("#ffd27a"))
		hl.rotation.x = -PI * 0.5
	# Glass balustrade around the edge, open where the plank leaves
	var b: float = plank_info["bearing"]
	var n := 32
	for i in n:
		var a := TAU * (i + 0.5) / n
		if absf(angle_difference(a, b)) < 2.0 / r + TAU / n * 0.5:
			continue
		var p := Vector2(cos(a), sin(a)) * (r - 0.3)
		var seg := TAU * r / n
		_box(deck, Vector3(seg, 1.2, 0.1), Vector3(p.x, 0.6, p.y), _glass(0.2), -a + PI * 0.5)
		Solid.box(deck, Vector3(seg, 1.4, 0.3), Vector3(p.x, 0.7, p.y), -a + PI * 0.5)
	var lamp := OmniLight3D.new()
	lamp.light_color = _tint.lerp(Color.WHITE, 0.4)
	lamp.light_energy = 1.6
	lamp.omni_range = r + 8.0
	lamp.position.y = 4.0
	deck.add_child(lamp)
	_build_plank(deck, r)


func _build_plank(deck: Node3D, r: float) -> void:
	var b: float = plank_info["bearing"]
	var r0: float = plank_info["from"]
	var r1: float = plank_info["to"]
	var length := r1 - r0
	var mid := Vector2(cos(b), sin(b)) * (r0 + r1) * 0.5
	var yaw := -b  # the plank's +X runs along the bearing
	var plank := Node3D.new()
	plank.name = "JumpPlank"
	plank.position = Vector3(mid.x, 0, mid.y)
	plank.rotation.y = yaw
	deck.add_child(plank)
	_box(plank, Vector3(length, 0.4, 2.6), Vector3(0, -0.2, 0), _metal(Color(0.24, 0.25, 0.28)))
	Solid.box(plank, Vector3(length, 0.4, 2.6), Vector3(0, -0.2, 0))
	var edge := _glow(Color("#ffd27a"), 2.2)
	for sz in [-1.0, 1.0]:
		_box(plank, Vector3(length, 0.06, 0.06), Vector3(0, 0.02, sz * 1.3), edge)
		_box(plank, Vector3(length, 1.1, 0.06), Vector3(0, 0.55, sz * 1.3), _glass(0.2))
		Solid.box(plank, Vector3(length, 1.4, 0.3), Vector3(0, 0.7, sz * 1.3))
	# The gate at the tip: a light bar (and an invisible wall until you launch)
	_box(plank, Vector3(0.1, 0.1, 2.6), Vector3(length * 0.5, 1.1, 0), _glow(Color("#ff8fa0"), 2.5))
	Solid.box(plank, Vector3(0.3, 1.6, 2.6), Vector3(length * 0.5, 0.8, 0))
	var arrow := _label(plank, "BASE JUMP ›", Vector3(length * 0.5 - 2.4, 0.03, 0), 0.006, 96, Color("#ffd27a"))
	arrow.rotation = Vector3(-PI * 0.5, -PI * 0.5, 0)  # flat, reading across, its top toward the tip
	# A sign at the plank's root (billboard), with the numbers that matter
	_label(deck, "BASE JUMP · %d m\nlanding ring %d m %s" % [int(spec["deck"]), int(_ring_dist()), _ring_dir()],
		Vector3(cos(b) * (r0 - 1.5), 2.6, sin(b) * (r0 - 1.5)), 0.01, 48, DeepFieldTheme.ICE, true, true)


func _build_top() -> void:
	var roof: float = spec["roof"]
	var top: float = spec["top"]
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1.0, 0.15, 0.12)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.1, 0.08)
	red.emission_energy_multiplier = 3.0
	_blink_mat = red
	match spec["kind"]:
		"burj":
			# The spire: a tapered needle from the deck, ringed with light
			var sp := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.bottom_radius = 4.0
			c.top_radius = 0.25
			c.height = top - roof
			c.radial_segments = 12
			sp.mesh = c
			sp.material_override = _metal(Color(0.62, 0.66, 0.72))
			sp.position = Vector3(0, roof + (top - roof) * 0.5, 0)
			_tower.add_child(sp)
			Solid.cylinder(_tower, 3.0, 12.0, Vector3(0, roof, 0))
			for k in 5:
				var f := 0.12 + 0.17 * k
				var rr := lerpf(4.0, 0.25, f)
				var ring_m := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = rr + 0.05
				tm.outer_radius = rr + 0.3
				ring_m.mesh = tm
				ring_m.material_override = _glow(_tint, 3.0)
				ring_m.position.y = roof + (top - roof) * f
				_tower.add_child(ring_m)
		"supertall":
			# The open crown: four fins and a halo
			var w := 26.0 * 0.65 * 0.5
			for k in 4:
				var a := deg_to_rad(45.0) + PI * 0.5 * k
				var p := Vector2(cos(a), sin(a)) * w * 1.2
				_box(_tower, Vector3(1.0, top - roof, 1.0), Vector3(p.x, roof + (top - roof) * 0.5, p.y), _glow(_tint, 2.6))
			var halo := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = w * 1.2
			tm.outer_radius = w * 1.2 + 0.5
			tm.rings = 64
			halo.mesh = tm
			halo.material_override = _glow(_tint, 2.6)
			halo.position.y = top - 1.0
			_tower.add_child(halo)
	# Aviation lights: red, blinking (the same rhythm for everyone: block-free, clock-free)
	var pts: Array = [Vector3(0, top + 0.6, 0)]
	var r := LandmarkPlan.deck_radius(spec)
	for k in 4:
		var a := PI * 0.5 * k + PI * 0.25
		pts.append(Vector3(cos(a) * (r - 0.5), roof + 1.5, sin(a) * (r - 0.5)))
	for p in pts:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		s.mesh = sm
		s.material_override = red
		s.position = p
		_tower.add_child(s)
		_blinkers.append(s)
	# The crown sign: the QING's name on the front face, near the top
	var ms := LandmarkPlan.masses(spec)
	var sy := roof - 14.0
	var fz := LandmarkPlan.front_at(ms, sy)
	var text := LandmarkPlan.sign_name(spec["kind"], _qing_name)
	var width := clampf(fz * 1.4, 12.0, 26.0)
	var px := width / maxf(6.0, text.length() * 0.62 * 128.0)
	var sign := _label(_tower, text, Vector3(0, sy, fz + 0.6), px, 128, _tint.lerp(Color.WHITE, 0.55))
	sign.outline_size = 0


func _build_ring() -> void:
	## The landing zone: a round terrace in the terrain's own material with three
	## lit rings (3, 8, 14 m) and a beam you can see from the deck.
	var rl := ring_local()
	_ring_node = Node3D.new()
	_ring_node.name = "LandingRing"
	_ring_node.position = rl - position
	add_child(_ring_node)
	_build_terrace(LandmarkPlan.RING_R, float(ring.get("top", 0.0)) - float(ring.get("low", 0.0)) + 1.0, _ring_node.position)
	for rr in [3.0, 8.0, 14.0]:
		var mi := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = rr - 0.18
		t.outer_radius = rr + 0.18
		t.rings = 64
		mi.mesh = t
		mi.material_override = _glow(Color("#ffd27a") if rr == 3.0 else _tint, 2.4)
		mi.scale = Vector3(1, 0.25, 1)
		mi.position.y = 0.05
		_ring_node.add_child(mi)
	var beam := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 1.6
	c.bottom_radius = 0.6
	c.height = 120.0
	c.cap_top = false
	c.cap_bottom = false
	beam.mesh = c
	var bm := _glow(Color("#ffd27a"), 1.6, 0.16)
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.material_override = bm
	beam.position.y = 60.0
	_ring_node.add_child(beam)
	_label(_ring_node, "LANDING RING · %s" % LandmarkPlan.sign_name(spec["kind"], _qing_name), Vector3(0, 4.0, 0), 0.012, 48, Color("#ffd27a"), true, true)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffd27a")
	lamp.light_energy = 1.2
	lamp.omni_range = 18.0
	lamp.position.y = 5.0
	_ring_node.add_child(lamp)


func _build_terrace(radius: float, depth: float, at: Vector3) -> void:
	## Like the fair's: a round regolith terrace whose sides slope out into the
	## ground, drawn with the terrain's own material (it colours by world XZ, so
	## the contours and glow run straight across), plus a faint rim of light.
	var slope := clampf(depth * 2.2, 3.0, 14.0)
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius + slope
	m.height = depth
	m.radial_segments = 64
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	if _ground_mat:
		mi.material_override = _ground_mat
	else:
		var rd := "res://assets/textures/polyhaven/moon_dusted_02/moon_dusted_02_"
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(rd + "diff_1k.jpg")
		mat.albedo_color = Color(0.55, 0.55, 0.58).lerp(_tint, 0.18)
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
		mi.material_override = mat
	mi.position = at + Vector3(0, -depth * 0.5 - 0.02, 0)
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = depth
	cs.shape = sh
	cs.position = mi.position
	body.add_child(cs)
	var rim := CollisionShape3D.new()
	rim.shape = m.create_convex_shape()
	rim.position = mi.position
	body.add_child(rim)
	add_child(body)
	var ring_m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius - 0.12
	t.outer_radius = radius + 0.12
	t.rings = 96
	ring_m.mesh = t
	ring_m.material_override = _glow(_tint, 1.4)
	ring_m.scale = Vector3(1, 0.25, 1)
	ring_m.position = at + Vector3(0, 0.03, 0)
	add_child(ring_m)


# --- Signs from chain data -----------------------------------------------------

func _update_signs() -> void:
	if _lobby_sign == null or spec.is_empty():
		return
	var lines := [LandmarkPlan.sign_name(spec["kind"], _qing_name),
		"%d m · %d floors · from Σ Hypobar %s (YUE.Bar · block %s)" % [int(spec["roof"]), int(spec["floors"]), hypobar_text, str(block) if block >= 0 else "—"]]
	if leader_name != "":
		lines.append("top Hypobar here: %s" % leader_name)
	lines.append("SKY DECK · glass lift, free · base jump 1 Ⓐ to this QING")
	_lobby_sign.text = "\n".join(lines)


## The leader's LAU username: CHO.GetUserTokenAddress(wallet) → LAU.Username().
## Omitted (never guessed) if either read fails or the name is empty.
func _read_leader(wallet: String) -> void:
	var head: int = Chain.head_block
	var r1: Array = await Chain.multicall.run([Multicall.make_call(Contracts.CHO, "GetUserTokenAddress(address)", [wallet])], wallet, head)
	if wallet != _leader_wallet or r1.is_empty():
		return
	var a = Multicall.value(r1[0], ["address"])
	if a == null:
		return
	var lau := String(a[0]).to_lower()
	if lau == "" or lau.trim_prefix("0x").replace("0", "") == "":
		return
	var r2: Array = await Chain.multicall.run([Multicall.make_call(lau, "Username()")], wallet, head)
	if wallet != _leader_wallet or r2.is_empty():
		return
	var u = Multicall.value(r2[0], ["string"])
	if u == null:
		return
	var name := String(u[0]).strip_edges().left(12)
	if name == "":
		return
	leader_name = name
	_update_signs()


# --- The lift and the plank ----------------------------------------------------

func _car_global(y: float) -> Vector3:
	return _tower.to_global(Vector3(0, y, float(lift_info["z"])))


func plank_tip() -> Vector3:
	var b: float = plank_info["bearing"]
	var r: float = float(plank_info["to"]) - 1.6
	return _tower.to_global(Vector3(cos(b) * r, float(spec["deck"]) + 0.1, sin(b) * r))


func plank_dir() -> Vector3:
	var b: float = plank_info["bearing"]
	return (_tower.global_transform.basis * Vector3(cos(b), 0, sin(b))).normalized()


## Is the player standing on the sky deck or plank? (BaseJump labels free falls from here.)
func on_deck(p: Vector3) -> bool:
	if spec.is_empty() or _tower == null:
		return false
	var l := _tower.to_local(p)
	return absf(l.y - float(spec["deck"])) < 6.0 and Vector2(l.x, l.z).length() < float(plank_info.get("to", 0.0)) + 3.0


## Is the player in the tower (lobby, lift, deck)? A rebuild waits until they leave,
## so a floor added by a new Su never moves the deck under their feet.
func _player_on_site() -> bool:
	if _player == null or _tower == null or spec.is_empty():
		return false
	var l := _player.global_position - global_position
	return Vector2(l.x, l.z).length() < LandmarkPlan.PLAZA_R + 12.0 and l.y > 1.5


func _process(delta: float) -> void:
	_t += delta
	if not _blinkers.is_empty():
		_blink_mat.emission_energy_multiplier = 4.0 if fmod(_t, 1.5) < 0.25 else 0.4
	if _riding:
		_ride_tick(delta)
		return
	if not _pending.is_empty() and not _paying and not _player_on_site():
		var p: Dictionary = _pending
		_pending = {}
		_rebuild(p["spec"])
		return
	if spec.is_empty() or _player == null or _tower == null or not _player.is_physics_processing():
		_set_focus("")
		return
	var pp := _player.global_position
	var z := ""
	var deck: float = spec["deck"]
	var c0 := _car_global(0.0)
	var c1 := _car_global(deck)
	if Vector2(pp.x - c0.x, pp.z - c0.z).length() < 2.2 and absf(pp.y - c0.y) < 2.5:
		z = "lift_up"
	elif Vector2(pp.x - c1.x, pp.z - c1.z).length() < 2.2 and absf(pp.y - c1.y) < 2.5:
		z = "lift_down"
	elif exchange_y > 0.0 and Vector2(pp.x - c0.x, pp.z - c0.z).length() < 2.2 and absf(pp.y - _car_global(exchange_y).y) < 2.0:
		z = "lift_mid"
	else:
		var tip := plank_tip()
		if Vector2(pp.x - tip.x, pp.z - tip.z).length() < 2.6 and absf(pp.y - tip.y) < 2.5:
			z = "plank"
	_set_focus(z)


func _set_focus(z: String) -> void:
	if z == _focus:
		return
	_focus = z
	if _hud == null:
		return
	var k := ControlsHelp.key_of("interact")
	match z:
		"":
			_hud.hide_prompt()
		"lift_up":
			if exchange_y > 0.0:
				_hud.show_prompt("%s  Glass lift · free · first stop the YUE Exchange (%d m), then the sky deck (%d m)" % [k, int(exchange_y), int(spec["deck"])])
			else:
				_hud.show_prompt("%s  Glass lift to the sky deck · %d m · free" % [k, int(spec["deck"])])
		"lift_mid":
			_hud.show_prompt("%s  Glass lift up to the sky deck (%d m)  ·  %s  down to the lobby" % [k, int(spec["deck"]), ControlsHelp.key_of("crouch_descend")])
		"lift_down":
			_hud.show_prompt("%s  Glass lift down to the lobby" % k)
		"plank":
			var paid := Wallet.address != "" and not _practice_ok
			_hud.show_prompt("%s  BASE JUMP · %s" % [k, ("jump ticket %s to this QING (scored)" % ArcadePay.fee_text()) if paid else "practice jump (not recorded)"])


func _unhandled_input(event: InputEvent) -> void:
	if _focus == "lift_mid" and not _riding and event.is_action_pressed("crouch_descend"):
		get_viewport().set_input_as_handled()
		_start_ride(exchange_y, 0.0)
		return
	if _focus == "" or _riding or _paying or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	match _focus:
		"lift_up":
			_start_ride(0.0, exchange_y if exchange_y > 0.0 else float(spec["deck"]))
		"lift_mid":
			_start_ride(exchange_y, float(spec["deck"]))
		"lift_down":
			_start_ride(float(spec["deck"]), 0.0)
		"plank":
			_jump()


func _start_ride(from: float, to: float) -> void:
	_riding = true
	_ride_t = 0.0
	_ride_from = from
	_ride_to = to
	_set_focus("")
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	var arm := _player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	if arm:
		arm.spring_length = 8.0
	_hud.ticker("GLASS LIFT · %d m in %d s · free to ride" % [int(absf(to - from)), int(ceil(LandmarkPlan.lift_duration(to - from)))], DeepFieldTheme.ICE, 6.0)


func _ride_tick(delta: float) -> void:
	_ride_t += delta
	var h := absf(_ride_to - _ride_from)
	var d := LandmarkPlan.lift_travel(_ride_t, h)
	var y := _ride_from + d * signf(_ride_to - _ride_from)
	_car.position.y = y + 0.12
	if is_instance_valid(_player):
		_player.global_position = _car_global(y + 0.15)
	_hud.show_prompt("LIFT · %d m · %d m/s" % [int(y), int(round(absf(LandmarkPlan.lift_travel(_ride_t + 0.05, h) - LandmarkPlan.lift_travel(_ride_t - 0.05, h)) * 10.0))])
	if _ride_t >= LandmarkPlan.lift_duration(h):
		_riding = false
		_hud.hide_prompt()
		_player.velocity = Vector3.ZERO
		_player.set_physics_process(true)
		var arm := _player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
		var rig := _player.get_node_or_null("CameraRig")
		if arm and rig:
			arm.spring_length = float(rig.get("follow_distance"))
		_focus = "?"
		if exchange_y > 0.0 and is_equal_approx(_ride_to, exchange_y):
			_hud.ticker("YUE EXCHANGE · %d m · the desk is ahead of the lift; %s up to the sky deck, %s down" % [int(_ride_to),
				ControlsHelp.key_of("interact"), ControlsHelp.key_of("crouch_descend")], DeepFieldTheme.ICE, 12.0)
		elif _ride_to > 0.0:
			_hud.ticker("SKY DECK · %d m · the plank is %s; the landing ring %d m %s" % [int(_ride_to), _plank_compass(), int(_ring_dist()), _ring_dir()], DeepFieldTheme.ICE, 12.0)


func _jump() -> void:
	if Wallet.address == "" or _practice_ok:
		_practice_ok = false
		_launch("practice", {})
		return
	_paying = true
	_hud.hide_prompt()
	_hud.ticker("Jump ticket: approve %s to this QING in your wallet…" % ArcadePay.fee_text(), DeepFieldTheme.ICE, 20.0)
	var res: Dictionary = await ArcadePay.pay(_qing, "Sky deck · base jump")
	_paying = false
	if not res.get("ok", false):
		_practice_ok = true
		_focus = "?"
		_hud.ticker("Ticket not bought: %s · press %s again for a practice jump (not recorded)" % [res.get("message", "cancelled"), ControlsHelp.key_of("interact")], Color("#ff8fa0"), 12.0)
		return
	ArcadePay.use_credit(Wallet.address, _qing)  # this jump spends the credit it bought
	_launch("ticket", {"hash": res.get("hash", ""), "block": int(res.get("block", 0))})


func _launch(source: String, ticket: Dictionary) -> void:
	_set_focus("")
	var dir := plank_dir()
	jump_requested.emit(plank_tip() + dir * 2.6 + Vector3(0, 0.4, 0), dir, source, ticket)


func _ring_dist() -> float:
	return Vector2(ring_local().x - position.x, ring_local().z - position.z).length()


func _ring_dir() -> String:
	return FairSite._compass(Vector2(ring_local().x - position.x, ring_local().z - position.z))


func _plank_compass() -> String:
	var d := plank_dir()
	return "on the " + FairSite._compass(Vector2(d.x, d.z)) + " side"


# --- Preview cameras (territory_v2 --view=tower|deck|jump) --------------------

## Frames `camera` for a screenshot once the tower is built.
func frame(view: String, camera: Camera3D) -> void:
	if spec.is_empty() or _tower == null:
		return
	var base := global_position
	var deck: float = spec["deck"]
	var top: float = spec["top"]
	var fwd := (_tower.global_transform.basis * Vector3(0, 0, 1)).normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	match view:
		"tower":
			# From the plaza's edge toward the Core side, looking up the whole height
			# From open ground on the side toward the middle, the whole height in frame
			var inward := Vector3(-base.x, 0, -base.z).normalized().rotated(Vector3.UP, 0.6)
			var dist := clampf(top * 0.3, 60.0, 170.0)
			camera.position = base + inward * dist + Vector3(0, dist * 0.15, 0)
			var core := get_parent() as Node3D
			if core:
				var lp := camera.position - core.global_position
				camera.position.y = maxf(camera.position.y, float(_height_fn.call(lp.x, lp.z)) + core.global_position.y + 3.0)
			camera.look_at(base + Vector3(0, dist * 0.15 + dist * 0.64, 0))
			camera.fov = 85.0
		"deck":
			# On the sky deck by the plank's root, looking out along it over the territory
			var d := plank_dir()
			var sd := d.cross(Vector3.UP).normalized()
			var r0: float = plank_info["from"]
			var root := _tower.to_global(Vector3(0, deck, 0))
			camera.position = root + d * (r0 - 1.5) + sd * 0.6 + Vector3(0, 2.6, 0)
			camera.look_at(root + d * (r0 + 320.0) + Vector3(0, -deck * 0.38, 0))
			camera.fov = 78.0
		"jump":
			# Ahead of the jumper (BaseJump.preview puts them there), looking back at the tower
			var d := plank_dir()
			var p := jump_preview_at()
			var sd := d.cross(Vector3.UP).normalized()
			camera.position = p + d * 4.5 + sd * 1.4 + Vector3(0, -0.6, 0)
			camera.look_at(p - d * 24.0 + sd * 3.0 + Vector3(0, 3.0, 0))
			camera.fov = 70.0


## Where the --view=jump preview puts the jumper: 80 m out from the plank, a third of the way down.
func jump_preview_at() -> Vector3:
	return plank_tip() + plank_dir() * 80.0 + Vector3(0, -float(spec["deck"]) * 0.3, 0)
