extends Node3D
## Meta Resonance Array — the Beat Station south of player spawn.
## A working "chain reactor" club / power hub on a 30×30 m levelled site:
##   - octagonal steel stage deck with hazard trim, steps and safety railings
##   - 4 resonator pylons with coil rings that light up with territory CHARGE
##   - central reactor column whose plasma fill height is the CHARGE level
##   - glowing power conduits (flow speed / brightness = CHARGE) from pylons to the core
##     and from the deck down to the generators on the apron
##   - PA speaker stacks with VU meters driven by HYPOBAR / EPIBAR
##   - control desk + a video wall showing CHARGE / HYPO / EPI meters, scope and radar
##   - hovering scanning dish (spins up on META.Beat)
##   - CC0 props (generators, barrels, crates, tool cart, lamps, barriers) and locals.
## Triggers the META.Beat() visual: everything flashes, dish spins up, speakers thump.
## Deterministic from the territory seed.

signal player_entered_range
signal player_exited_range

const Kit = preload("res://scripts/world/structures/struct_kit.gd")
const MONUMENT_SHADER = preload("res://assets/shaders/monument.gdshader")
const CIRCLE_SHADER = preload("res://assets/shaders/monument_circle.gdshader")

const INTERACTION_RADIUS: float = 12.0
const DECK_H: float = 1.6           # Stage deck top above the levelled ground
const DECK_R: float = 9.6           # Octagon circumradius
const PYLON_HEIGHT: float = 12.0
const PYLON_BOTTOM_RADIUS: float = 0.8
const PYLON_TOP_RADIUS: float = 0.3
const PYLON_SPACING: float = 5.5    # Half-width of square formation
const COIL_COUNT: int = 6
const DISH_HEIGHT: float = 11.0
const DISH_RADIUS: float = 3.0
const DISH_TUBE: float = 0.25
const CORE_H: float = 4.5
const GROUND_RING_SIZE: float = 15.0
const VIOLET := Color(0.62, 0.3, 1.0)
const CYAN := Color(0.25, 0.85, 1.0)
const MAGENTA := Color(1.0, 0.25, 0.7)
const STEP_SIDES := [2, 4]
const GEN_SPOTS := [Vector3(-12.2, 0, -6.4), Vector3(-11.0, 0, -5.1)]      # Octagon sides (k: normal angle k*45 deg from +Z) with stairs

# ─── Materials ──────────────────────────────────────────────────────
var _pylon_material: ShaderMaterial
var _circle_material: ShaderMaterial
var _dish_material: StandardMaterial3D
var _conduit_mat: ShaderMaterial
var _coil_on: StandardMaterial3D
var _coil_off: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _cone_rim_mat: StandardMaterial3D
var _beam_cone: MeshInstance3D

# ─── Animated nodes ────────────────────────────────────────────────
var _dish_mesh: MeshInstance3D
var _runic_ring: MeshInstance3D
var _station_light: OmniLight3D
var _core_light: OmniLight3D
var _core_plasma: MeshInstance3D
var _core_spinner: Node3D
var _pylon_mats: Array[StandardMaterial3D] = []  # Per-pylon cap material for flash
var _coils: Array[MeshInstance3D] = []          # COIL_COUNT per pylon, bottom→top
var _cones: Array[MeshInstance3D] = []          # Speaker woofer cones (pulse)
var _screens: Array[ShaderMaterial] = []
var _vu_left: ShaderMaterial
var _vu_right: ShaderMaterial
var _desk_vu: ShaderMaterial
var _arcs: Array = []          # [MeshInstance3D, from, to] cyan chain-arcs between pylon tops
var _arc_mat: StandardMaterial3D
var _arc_timer: float = 0.0
var _arc_idx: int = 0
var _arc_rng := RandomNumberGenerator.new()
var _movers: Array[Node3D] = []   # Moving-head spot pivots

# ─── Animation / state ─────────────────────────────────────────────
var _dish_angle: float = 0.0
var _dish_speed: float = 0.5
var _beat_effect_timer: float = 0.0
const BEAT_EFFECT_DURATION: float = 3.0
const BEAT_DISH_SPEED: float = 4.0

var _power: float = 0.0
var _activity: float = 0.0
var _hypo: float = 0.0
var _epi: float = 0.0
var _bpm: float = 96.0
var _beat_phase: float = 0.0
var _accent: Color = Color.CYAN

var _player_in_range: bool = false
var _params: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func initialize(seed_value: int) -> void:
	## Build the entire beat station from the territory seed.
	_params = MonumentGenerator.get_monument_params(seed_value)
	_accent = _params.get("accent_color", Color.CYAN)
	_rng.seed = seed_value + 6060

	_create_materials()
	_build_site()
	_build_deck()
	_build_pylons()
	_build_core()
	_build_dish()
	_build_conduits()
	_build_header()
	_build_arcs()
	_build_ground_circle()
	_build_speakers()
	_build_control_desk()
	_build_video_wall()
	_build_props()
	_build_light()
	_build_locals(seed_value)
	_build_interaction_area()
	var keep: Array = [_dish_mesh, _runic_ring, _core_spinner, _core_plasma]
	keep.append_array(_cones)
	keep.append_array(_coils)
	for arc in _arcs:
		keep.append(arc[0])
	Kit.merge_static(self, keep)
	update_territory_state()


func update_territory_state() -> void:
	## Sync every gauge on the station with on-chain territory state.
	_power = clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
	_hypo = clampf(float(GameManager.territory_hypobar) / 1e12, 0.0, 1.0)
	_epi = clampf(float(GameManager.territory_epibar) / 1e12, 0.0, 1.0)
	_activity = clampf(_hypo + _epi, 0.0, 1.0)

	var scalars: Dictionary = GameManager.faung_scalars
	var tint := Vector3(
		clampf(float(scalars.get("phi", 0)) / 1e15, 0.0, 0.3),
		clampf(float(scalars.get("eta", 0)) / 1e15, 0.0, 0.3),
		clampf(float(scalars.get("mu", 0)) / 1e15, 0.0, 0.3))

	if _pylon_material:
		_pylon_material.set_shader_parameter("territory_power", _power)
		_pylon_material.set_shader_parameter("territory_activity", _activity)
		_pylon_material.set_shader_parameter("power_tint", tint)
	if _circle_material:
		_circle_material.set_shader_parameter("territory_power", _power)
	if _conduit_mat:
		_conduit_mat.set_shader_parameter("energy", 0.6 + _power * 3.4)
		_conduit_mat.set_shader_parameter("flow_speed", 0.3 + _power * 1.7)

	# Coil rings: one lit ring per sixth of CHARGE (always at least one, so it reads as alive)
	var lit := maxi(1, int(round(_power * COIL_COUNT)))
	for i in _coils.size():
		_coils[i].material_override = _coil_on if (i % COIL_COUNT) < lit else _coil_off

	# Reactor column fill = CHARGE
	if _core_plasma:
		var fill := 0.08 + _power * 0.92
		_core_plasma.scale = Vector3(1.0, fill, 1.0)
		_core_plasma.position.y = DECK_H + 0.55 + CORE_H * fill * 0.5
	if _core_mat:
		_core_mat.emission_energy_multiplier = 1.5 + _power * 4.0

	# Screens: bar meters = CHARGE / HYPO / EPI, scope + radar = activity
	for m in _screens:
		m.set_shader_parameter("value_a", _power)
		m.set_shader_parameter("value_b", _hypo if int(m.get_shader_parameter("mode")) == 0 else _activity)
		m.set_shader_parameter("value_c", _epi)
	if _vu_left:
		_vu_left.set_shader_parameter("value_a", 0.15 + _hypo * 0.85)
	if _vu_right:
		_vu_right.set_shader_parameter("value_a", 0.15 + _epi * 0.85)
	if _desk_vu:
		_desk_vu.set_shader_parameter("value_a", 0.2 + _activity * 0.8)

	# Busier territory → faster beat
	_bpm = 84.0 + _activity * 60.0

	if _station_light:
		_station_light.light_energy = 2.0 * (0.3 + _power * 0.7)
	if _beam_cone:
		_beam_cone.set_instance_shader_parameter("tint", Color(_accent.r, _accent.g, _accent.b, 0.5 + _power * 2.5))


func trigger_beat_effect() -> void:
	## Called when META.Beat() tx confirms — spin up dish, flash everything, boost light.
	_beat_effect_timer = BEAT_EFFECT_DURATION
	if _station_light:
		_station_light.light_energy = 12.0
	for mat in _pylon_mats:
		mat.emission_energy_multiplier = 8.0
	if _dish_material:
		_dish_material.emission_energy_multiplier = 6.0


func _process(delta: float) -> void:
	if _params.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
	Kit.update_night()

	# ── Dish rotation ──
	var current_speed := _dish_speed
	if _beat_effect_timer > 0.0:
		var effect_progress := _beat_effect_timer / BEAT_EFFECT_DURATION
		current_speed = lerpf(_dish_speed, BEAT_DISH_SPEED, effect_progress * effect_progress)
	_dish_angle += current_speed * delta
	if _dish_mesh:
		_dish_mesh.rotation.y = _dish_angle
		_dish_mesh.position.y = DISH_HEIGHT + sin(t * 0.6) * 0.3
	if _runic_ring:
		_runic_ring.rotation.y = -_dish_angle * 2.0
	if _core_spinner:
		_core_spinner.rotation.y += delta * (0.4 + _power * 1.6 + (3.0 if _beat_effect_timer > 0.0 else 0.0))

	# ── Club beat: speaker cones thump, core breathes ──
	_beat_phase = fmod(_beat_phase + delta * _bpm / 60.0, 1.0)
	var thump := pow(1.0 - _beat_phase, 4.0)
	var flash := 0.0
	if _beat_effect_timer > 0.0:
		flash = clampf(_beat_effect_timer / BEAT_EFFECT_DURATION, 0.0, 1.0)
		flash *= flash
	for c in _cones:
		var cr: float = c.get_meta("r", 0.3)
		c.scale = Vector3(cr, 1.0 + thump * (0.6 + _activity * 1.2 + flash * 3.0), cr)
	if _cone_rim_mat:
		_cone_rim_mat.emission_energy_multiplier = 0.6 + thump * (1.5 + _activity * 2.0) + flash * 6.0
	if _coil_on:
		_coil_on.emission_energy_multiplier = 2.0 + thump * 0.8 + flash * 10.0
	if _core_mat:
		_core_mat.emission_energy_multiplier = 1.5 + _power * 4.0 + thump * 0.6 + flash * 10.0
	if _conduit_mat:
		_conduit_mat.set_shader_parameter("flash", flash)
	for m in _screens:
		m.set_shader_parameter("flash", flash * 0.6)
	if _core_light:
		_core_light.light_energy = (1.2 + _power * 1.8) * (0.85 + thump * 0.3) + flash * 8.0

	# ── Chain-arcs: re-strike one arc every few frames; brighter with CHARGE and on Beat ──
	_arc_timer -= delta
	if _arc_timer <= 0.0 and _arcs.size() > 0:
		_arc_timer = 0.07
		var arc: Array = _arcs[_arc_idx % _arcs.size()]
		(arc[0] as MeshInstance3D).mesh = _arc_mesh(arc[1], arc[2])
		_arc_idx += 1
		for k in _arcs.size():
			(_arcs[k][0] as MeshInstance3D).visible = _arc_rng.randf() < 0.55 + _power * 0.4 or flash > 0.0
	if _arc_mat:
		_arc_mat.emission_energy_multiplier = 2.5 + _power * 3.0 + flash * 10.0

	# ── Moving heads sweep the pit and the deck floor ──
	for i in _movers.size():
		var ph := t * (0.45 + 0.13 * float(i)) + float(i) * 2.1
		var target := Vector3(sin(ph) * 6.5, 0.0, 6.5 + cos(ph * 1.3) * 5.0)
		if target.z < 9.0:
			target.y = DECK_H
		_movers[i].look_at(to_global(target), Vector3.UP)

	# ── Beat effect decay ──
	if _beat_effect_timer > 0.0:
		_beat_effect_timer -= delta
		var decay := clampf(_beat_effect_timer / BEAT_EFFECT_DURATION, 0.0, 1.0)
		for mat in _pylon_mats:
			mat.emission_energy_multiplier = lerpf(0.5, 8.0, decay * decay)
		if _dish_material:
			_dish_material.emission_energy_multiplier = lerpf(1.5, 6.0, decay * decay)
		if _station_light:
			_station_light.light_energy = lerpf(2.0, 12.0, decay * decay)
		if _beat_effect_timer <= 0.0:
			_beat_effect_timer = 0.0
	elif _station_light:
		_station_light.light_energy = 2.0 * (0.3 + _power * 0.7) * (sin(t * 1.2) * 0.2 + 0.8)


# ─── Materials ──────────────────────────────────────────────────────

func _create_materials() -> void:
	var accent := _accent
	_pylon_material = ShaderMaterial.new()
	_pylon_material.shader = MONUMENT_SHADER
	_pylon_material.set_shader_parameter("accent_color", Vector3(accent.r, accent.g, accent.b))
	_pylon_material.set_shader_parameter("glow_intensity", 1.2)
	_pylon_material.set_shader_parameter("wall_darken", 0.0)

	_circle_material = ShaderMaterial.new()
	_circle_material.shader = CIRCLE_SHADER
	_circle_material.set_shader_parameter("accent_color", Vector3(accent.r, accent.g, accent.b))
	_circle_material.set_shader_parameter("circle_radius", 7.0)

	_dish_material = StandardMaterial3D.new()
	_dish_material.albedo_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.75)
	_dish_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dish_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_dish_material.emission_enabled = true
	_dish_material.emission = accent
	_dish_material.emission_energy_multiplier = 1.5
	_dish_material.metallic = 0.6
	_dish_material.roughness = 0.15

	_conduit_mat = Kit.conduit(accent, 1.0, 2.0)
	_coil_on = Kit.glow(accent, 2.0, false)
	_coil_off = Kit.paint(Color(0.09, 0.09, 0.1), 0.35, 0.85)
	_core_mat = Kit.glow(accent.lightened(0.2), 3.0, false)
	_cone_rim_mat = Kit.glow(accent, 1.0, false)


# ─── Site & deck ────────────────────────────────────────────────────

func _build_site() -> void:
	## Painted concrete plaza over the whole levelled site (sunk so edges never float).
	var slab := Kit.box(self, Vector3(28.0, 0.6, 28.0), Vector3(0, -0.24, 0),
		Kit.ground_slab(2, Vector2(14.0, 14.0), _accent, _rng.randi()), Vector3.ZERO, false)
	slab.name = "Plaza"
	# Kerb around the plaza
	var kerb := Kit.pbr("brushed_concrete", 0.6, Color(0.8, 0.8, 0.78))
	for s: float in [-1.0, 1.0]:
		Kit.box(self, Vector3(28.4, 0.5, 0.25), Vector3(0, -0.1, 14.1 * s), kerb)
		Kit.box(self, Vector3(0.25, 0.5, 28.4), Vector3(14.1 * s, -0.1, 0), kerb)
	# Embankment from the kerb down to the real terrain so the plaza never floats
	Kit.skirt(self, Vector2(14.25, 14.25), 0.12, 4.5, Kit.pbr("brushed_concrete", 0.35, Color(0.58, 0.57, 0.55)))


func _build_deck() -> void:
	## Octagonal stage deck: concrete plinth, steel tread plate top, hazard trim, steps, rails.
	var plinth := Kit.cyl(self, DECK_R, DECK_R + 0.15, DECK_H + 0.4, Vector3(0, (DECK_H - 0.4) * 0.5, 0),
		Kit.pbr("brushed_concrete", 0.5, Color(0.62, 0.62, 0.62)), 8, Vector3(0, PI / 8.0, 0))
	plinth.name = "DeckPlinth"
	Kit.cyl(self, DECK_R - 0.12, DECK_R - 0.12, 0.04, Vector3(0, DECK_H + 0.02, 0),
		Kit.pbr("metal_plate", 0.45, Color(0.7, 0.7, 0.72)), 8, Vector3(0, PI / 8.0, 0), false)
	Kit.cyl(self, DECK_R + 0.04, DECK_R + 0.04, 0.16, Vector3(0, DECK_H - 0.06, 0),
		Kit.hazard(2.5), 8, Vector3(0, PI / 8.0, 0), false)
	# Violet rim LED strip under the deck lip + a skirt down to the plaza
	Kit.cyl(self, DECK_R + 0.06, DECK_R + 0.06, 0.05, Vector3(0, DECK_H - 0.2, 0),
		Kit.glow(VIOLET, 3.5), 8, Vector3(0, PI / 8.0, 0), false)
	Kit.cyl(self, DECK_R + 0.3, DECK_R + 0.55, 0.32, Vector3(0, 0.1, 0),
		Kit.pbr("brushed_concrete", 0.5, Color(0.5, 0.5, 0.5)), 8, Vector3(0, PI / 8.0, 0))

	var apothem := DECK_R * cos(PI / 8.0)
	for k in STEP_SIDES:
		_build_steps(apothem, float(k) * TAU / 8.0)
	_build_railings(apothem)
	# Open stage front: LED lip + a row of stage-edge uplights instead of a rail
	Kit.box(self, Vector3(2.0 * apothem * tan(PI / 8.0) - 0.2, 0.06, 0.06), Vector3(0, DECK_H + 0.04, apothem - 0.1), Kit.glow(CYAN, 3.0), Vector3.ZERO, false)


func _build_steps(apothem: float, ang: float) -> void:
	## Stair flight off octagon side at normal angle `ang` (stairs run outward along it).
	var root := Node3D.new()
	root.rotation.y = ang
	add_child(root)
	var tread := Kit.pbr("metal_plate", 0.5, Color(0.55, 0.55, 0.57))
	var n := int(ceil(DECK_H / 0.27))
	var rise := DECK_H / float(n)
	var run := 0.34
	for i in n:
		var depth := run * float(n - i)
		var h := rise * float(i + 1)
		Kit.box(root, Vector3(4.0, h, depth), Vector3(0, h * 0.5, apothem + depth * 0.5), tread)
		Kit.box(root, Vector3(4.02, 0.03, 0.08), Vector3(0, h + 0.005, apothem + depth - 0.04), Kit.hazard(4.0), Vector3.ZERO, false)
	var rail := Kit.paint(Color(0.85, 0.62, 0.1), 0.45, 0.6)
	var foot := apothem + run * float(n)
	for sx: float in [-2.05, 2.05]:
		var a := Vector3(sx, DECK_H + 1.0, apothem)
		var b := Vector3(sx, 1.0, foot)
		Kit.beam(root, a, b, 0.035, rail)
		Kit.beam(root, Vector3(sx, DECK_H, apothem), a, 0.04, rail)
		Kit.beam(root, Vector3(sx, 0.0, foot), b, 0.04, rail)


func _build_railings(apothem: float) -> void:
	## Safety rail on the 6 octagon sides that have no steps (posts + 2 rails, MultiMesh).
	var post_x: Array = []
	var rail_x: Array = []
	for k in 8:
		var ang := float(k) * TAU / 8.0  # side normal angle; k=0 → +Z, k=4 → -Z
		var nrm := Vector3(sin(ang), 0, cos(ang))
		var tan_ := Vector3(cos(ang), 0, -sin(ang))
		var half := apothem * tan(PI / 8.0) - 0.35
		var c := nrm * (apothem - 0.25)
		if k == 0:
			continue  # Open stage front
		if STEP_SIDES.has(k):
			# Step sides: short rail stubs either side of the 4 m stair opening
			for sd: float in [-1.0, 1.0]:
				var p0 := c + tan_ * sd * 2.05
				var p1 := c + tan_ * sd * half
				post_x.append(Kit.beam_xform(p1 + Vector3(0, DECK_H, 0), p1 + Vector3(0, DECK_H + 1.05, 0), 0.035))
				for h: float in [0.55, 1.05]:
					rail_x.append(Kit.beam_xform(p0 + Vector3(0, DECK_H + h, 0), p1 + Vector3(0, DECK_H + h, 0), 0.03))
			continue
		var posts := 4
		for i in posts:
			var p := c + tan_ * lerpf(-half, half, float(i) / float(posts - 1))
			post_x.append(Kit.beam_xform(p + Vector3(0, DECK_H, 0), p + Vector3(0, DECK_H + 1.05, 0), 0.035))
		for h: float in [0.55, 1.05]:
			rail_x.append(Kit.beam_xform(c - tan_ * half + Vector3(0, DECK_H + h, 0), c + tan_ * half + Vector3(0, DECK_H + h, 0), 0.03))
		# Kick plate
		var kp := Kit.box(self, Vector3(half * 2.0, 0.12, 0.02), c + Vector3(0, DECK_H + 0.1, 0), Kit.hazard(4.0), Vector3(0, ang, 0), false)
		kp.name = "KickPlate_%d" % k
	var rail := Kit.paint(Color(0.85, 0.62, 0.1), 0.45, 0.6)
	Kit.multi(self, Kit.unit_cylinder(8), post_x, rail)
	Kit.multi(self, Kit.unit_cylinder(8), rail_x, rail)


# ─── Pylons ─────────────────────────────────────────────────────────

func _pylon_positions() -> Array[Vector3]:
	return [
		Vector3(-PYLON_SPACING, DECK_H, -PYLON_SPACING),
		Vector3(PYLON_SPACING, DECK_H, -PYLON_SPACING),
		Vector3(-PYLON_SPACING, DECK_H, PYLON_SPACING),
		Vector3(PYLON_SPACING, DECK_H, PYLON_SPACING),
	]


func _build_pylons() -> void:
	## Resonator pylons: armoured base housing, monument-shader column, CHARGE coil rings, cap.
	var accent := _accent
	var housing := Kit.pbr("metal_plate", 0.6, Color(0.42, 0.43, 0.45), false)
	var dark := Kit.paint(Color(0.07, 0.07, 0.08), 0.5, 0.7)
	var positions := _pylon_positions()
	for i in positions.size():
		var pos: Vector3 = positions[i]
		var col_h := PYLON_HEIGHT - 1.4
		# Base housing with vents and a hazard band
		Kit.box(self, Vector3(2.0, 1.4, 2.0), pos + Vector3(0, 0.7, 0), housing)
		Kit.box(self, Vector3(2.04, 0.18, 2.04), pos + Vector3(0, 1.25, 0), Kit.hazard(3.0), Vector3.ZERO, false)
		for f in 4:
			var a := float(f) * PI * 0.5
			var o := Vector3(sin(a), 0, cos(a)) * 1.005
			Kit.box(self, Vector3(1.2, 0.5, 0.02), pos + o + Vector3(0, 0.55, 0), dark, Vector3(0, a, 0), false)
		# Status LED on the face toward the core
		var to_core := Vector3(-pos.x, 0, -pos.z).normalized()
		Kit.box(self, Vector3(0.12, 0.12, 0.03), pos + to_core * 1.01 + Vector3(0.6, 0.95, 0), Kit.glow(Color(0.2, 1.0, 0.4), 3.0), Vector3(0, atan2(to_core.x, to_core.z), 0), false)

		var cyl := CylinderMesh.new()
		cyl.top_radius = PYLON_TOP_RADIUS
		cyl.bottom_radius = PYLON_BOTTOM_RADIUS
		cyl.height = col_h
		var inst := MeshInstance3D.new()
		inst.name = "Pylon_%d" % i
		inst.mesh = cyl
		inst.material_override = _pylon_material
		inst.position = pos + Vector3(0.0, 1.4 + col_h * 0.5, 0.0)
		add_child(inst)

		# Coil rings (lit count = CHARGE)
		for c in COIL_COUNT:
			var y := 2.3 + float(c) * 1.45
			var frac := (y - 1.4) / col_h
			var r := lerpf(PYLON_BOTTOM_RADIUS, PYLON_TOP_RADIUS, frac) + 0.12
			var coil := Kit.ring(self, r, 0.07, pos + Vector3(0, y, 0), _coil_off)
			_coils.append(coil)

		var cap_mat := StandardMaterial3D.new()
		cap_mat.albedo_color = Color(accent.r * 0.2, accent.g * 0.2, accent.b * 0.2)
		cap_mat.emission_enabled = true
		cap_mat.emission = accent
		cap_mat.emission_energy_multiplier = 0.5
		cap_mat.roughness = 0.1
		cap_mat.metallic = 0.5
		var cap_inst := Kit.ball(self, PYLON_TOP_RADIUS * 1.5, pos + Vector3(0.0, PYLON_HEIGHT + PYLON_TOP_RADIUS * 0.5, 0.0), cap_mat)
		cap_inst.name = "PylonCap_%d" % i
		_pylon_mats.append(cap_mat)
		# Aviation light ring below the cap
		Kit.ring(self, PYLON_TOP_RADIUS + 0.1, 0.05, pos + Vector3(0, PYLON_HEIGHT - 0.2, 0), dark)


# ─── Reactor core ───────────────────────────────────────────────────

func _build_core() -> void:
	## Glass containment column; the plasma inside fills to the CHARGE level.
	var steel := Kit.pbr("metal_plate", 0.7, Color(0.35, 0.36, 0.38), false)
	var dark := Kit.paint(Color(0.06, 0.06, 0.07), 0.4, 0.8)
	Kit.cyl(self, 1.7, 1.9, 0.55, Vector3(0, DECK_H + 0.275, 0), steel, 16)
	Kit.cyl(self, 1.95, 1.95, 0.1, Vector3(0, DECK_H + 0.05, 0), Kit.hazard(3.0), 16, Vector3.ZERO, false)
	_core_plasma = Kit.cyl(self, 0.62, 0.62, CORE_H, Vector3(0, DECK_H + 0.55 + CORE_H * 0.5, 0), _core_mat, 16, Vector3.ZERO, false)
	_core_plasma.name = "CorePlasma"
	var glass_mi := Kit.cyl(self, 1.1, 1.1, CORE_H, Vector3(0, DECK_H + 0.55 + CORE_H * 0.5, 0), Kit.glass(Color(0.6, 0.75, 0.85, 0.18)), 24, Vector3.ZERO, false)
	glass_mi.name = "CoreGlass"
	# Clamp rings + vertical tie rods
	for k in 4:
		Kit.ring(self, 1.14, 0.08, Vector3(0, DECK_H + 0.7 + float(k) * (CORE_H - 0.3) / 3.0, 0), dark)
	for k in 6:
		var a := float(k) * TAU / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * 1.25
		Kit.beam(self, p + Vector3(0, DECK_H + 0.55, 0), p + Vector3(0, DECK_H + 0.55 + CORE_H, 0), 0.05, steel)
	# Top cap with a spinning field rotor
	var top_y := DECK_H + 0.55 + CORE_H
	Kit.cyl(self, 1.45, 1.3, 0.45, Vector3(0, top_y + 0.22, 0), steel, 16)
	_core_spinner = Node3D.new()
	_core_spinner.position = Vector3(0, top_y + 0.55, 0)
	add_child(_core_spinner)
	for k in 3:
		Kit.box(_core_spinner, Vector3(2.6, 0.06, 0.18), Vector3.ZERO, dark, Vector3(0, float(k) * PI / 3.0, 0), false)
	Kit.ring(_core_spinner, 1.3, 0.05, Vector3.ZERO, _cone_rim_mat)
	# Energy shaft from the core up to the dish
	_beam_cone = Kit.light_cone(self, Vector3(0, top_y + 0.6, 0), Vector3.UP, DISH_HEIGHT - top_y - 1.6, 0.25, 0.6, _accent, 1.5)


# ─── Dish ───────────────────────────────────────────────────────────

func _build_dish() -> void:
	_dish_mesh = MeshInstance3D.new()
	_dish_mesh.name = "ScanningDish"
	_dish_mesh.mesh = Kit.dish_mesh(DISH_RADIUS, 1.2, 32, 8)
	_dish_mesh.material_override = _dish_material
	_dish_mesh.position = Vector3(0.0, DISH_HEIGHT, 0.0)
	add_child(_dish_mesh)

	var accent := _accent
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5)
	inner_mat.emission_enabled = true
	inner_mat.emission = accent
	inner_mat.emission_energy_multiplier = 2.5
	inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var inner := Kit.ring(_dish_mesh, DISH_RADIUS * 0.6 + DISH_TUBE * 0.5, DISH_TUBE * 0.5, Vector3(0, -0.75, 0), inner_mat)
	inner.name = "InnerRing"
	# Rim ring + feed horn tripod
	Kit.ring(_dish_mesh, DISH_RADIUS, 0.06, Vector3.ZERO, Kit.paint(Color(0.2, 0.2, 0.22), 0.4, 0.8))
	for k in 3:
		var a := float(k) * TAU / 3.0
		Kit.beam(_dish_mesh, Vector3(cos(a), 0, sin(a)) * DISH_RADIUS * 0.95, Vector3(0, 1.3, 0), 0.03, Kit.paint(Color(0.2, 0.2, 0.22), 0.4, 0.8), 6, false)
	Kit.ball(_dish_mesh, 0.18, Vector3(0, 1.35, 0), inner_mat)

	var runic_mat := StandardMaterial3D.new()
	runic_mat.albedo_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.5)
	runic_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	runic_mat.emission_enabled = true
	runic_mat.emission = accent
	runic_mat.emission_energy_multiplier = 3.0
	runic_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_runic_ring = Kit.ring(self, DISH_RADIUS * 1.3, 0.04, Vector3(0, DISH_HEIGHT + 1.5, 0), runic_mat)
	_runic_ring.name = "RunicRing"
	# Rotate the runic ring with a subtle tilt so its counter-spin reads
	_runic_ring.rotation.x = 0.08


# ─── Conduits & cables ──────────────────────────────────────────────

func _build_conduits() -> void:
	## Energy conduits: pylon tops → dish, pylon bases → core (laid on the deck),
	## and cable bundles from the deck edge down to the generators on the plaza.
	var dish_center := Vector3(0.0, DISH_HEIGHT - 0.6, 0.0)
	for i in 4:
		var pos: Vector3 = _pylon_positions()[i]
		var top := Vector3(pos.x, DECK_H + PYLON_HEIGHT - 0.4, pos.z)
		var m := Kit.cable(self, top, dish_center, 0.4, 0.07, _conduit_mat, 12)
		m.name = "Conduit_%d" % i
		# Floor run: 2 cables per pylon, hugging the deck with a small hump at the core plinth
		var to_core := Vector3(-pos.x, 0, -pos.z).normalized()
		var side := Vector3(to_core.z, 0, -to_core.x)
		for s: float in [-0.22, 0.22]:
			var a := Vector3(pos.x, DECK_H + 0.1, pos.z) + to_core * 1.0 + side * s
			var end := Vector3(0, DECK_H + 0.12, 0) - to_core * 1.95 + side * s
			var pts: Array[Vector3] = []
			for k in 9:
				var t := float(k) / 8.0
				var p := a.lerp(end, t)
				p.y = DECK_H + 0.09 + (0.25 * smoothstep(0.75, 1.0, t))
				pts.append(p)
			Kit.tube(self, pts, 0.075, _conduit_mat)
	# Deck → generators: thick black cables draping over the deck edge
	var rubber := Kit.paint(Color(0.03, 0.03, 0.035), 0.7, 0.0)
	for g: Vector3 in GEN_SPOTS:
		var edge := Vector3(g.x, 0, g.z).normalized() * (DECK_R * cos(PI / 8.0) - 0.3)
		var pts: Array[Vector3] = [
			edge + Vector3(0, DECK_H + 0.08, 0) - edge.normalized() * 1.5,
			edge + Vector3(0, DECK_H + 0.1, 0),
			edge + edge.normalized() * 0.45 + Vector3(0, DECK_H - 0.15, 0),
			edge + edge.normalized() * 0.6 + Vector3(0, 0.4, 0),
			edge + edge.normalized() * 0.9 + Vector3(0, 0.08, 0),
			g.lerp(edge, 0.4) + Vector3(0, 0.07, 0),
			g + Vector3(0, 0.25, 0),
		]
		Kit.tube(self, pts, 0.06, rubber)


func _build_header() -> void:
	## Lit "META.BEAT" header box hung from a truss spanning the two front pylons.
	var y := DECK_H + 8.7
	var z := PYLON_SPACING
	var xs: Array = []
	Kit.truss_xforms(Vector3(-PYLON_SPACING + 0.45, y, z), Vector3(PYLON_SPACING - 0.45, y, z), 0.42, 0.5, xs, 0.03)
	Kit.multi(self, Kit.unit_cylinder(6), xs, Kit.paint(Color(0.6, 0.61, 0.63), 0.35, 0.9))
	var frame := Kit.paint(Color(0.03, 0.03, 0.035), 0.5, 0.4)
	Kit.box(self, Vector3(8.0, 1.5, 0.25), Vector3(0, y - 1.15, z), frame)
	for side: float in [1.0, -1.0]:
		var fz := z + side * 0.13
		Kit.label(self, "META.BEAT", Vector3(0, y - 1.12, fz), 300, Color(0.85, 0.97, 1.0), 0.0 if side > 0 else PI, 2.2, 0)
		Kit.box(self, Vector3(7.8, 0.06, 0.02), Vector3(0, y - 1.82, fz), Kit.glow(CYAN, 4.0), Vector3.ZERO, false)
		Kit.box(self, Vector3(7.8, 0.06, 0.02), Vector3(0, y - 0.48, fz), Kit.glow(VIOLET, 4.0), Vector3.ZERO, false)
	for sx: float in [-2.6, 2.6]:
		Kit.beam(self, Vector3(sx, y - 0.4, z), Vector3(sx, y - 0.2, z), 0.02, Kit.paint(Color(0.6, 0.6, 0.6), 0.3, 1.0))


func _build_arcs() -> void:
	## Crackling cyan chain-arcs between neighbouring pylon tops (meshes re-struck in _process).
	_arc_rng.seed = _rng.randi()
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_mat.albedo_color = Color(0.7, 0.95, 1.0)
	_arc_mat.emission_enabled = true
	_arc_mat.emission = CYAN
	_arc_mat.emission_energy_multiplier = 4.0
	var p := _pylon_positions()
	var pairs := [[0, 1], [1, 3], [3, 2], [2, 0]]
	for pr in pairs:
		var a: Vector3 = p[pr[0]] + Vector3(0, PYLON_HEIGHT - 0.7, 0)
		var b: Vector3 = p[pr[1]] + Vector3(0, PYLON_HEIGHT - 0.7, 0)
		var mi := MeshInstance3D.new()
		mi.material_override = _arc_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.mesh = _arc_mesh(a, b)
		add_child(mi)
		_arcs.append([mi, a, b])


func _arc_mesh(a: Vector3, b: Vector3) -> ArrayMesh:
	## Jagged lightning ribbon (two crossed strips) from a to b with a slight droop.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	var pts: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / float(n)
		var q := a.lerp(b, t)
		var amp := sin(t * PI) * 0.45
		q += Vector3(_arc_rng.randf_range(-amp, amp), _arc_rng.randf_range(-amp, amp) - sin(t * PI) * 0.5, _arc_rng.randf_range(-amp, amp))
		pts.append(q)
	var w := 0.05
	for axis: Vector3 in [Vector3.UP, (b - a).cross(Vector3.UP).normalized()]:
		for i in n:
			var o0 := axis * w
			for v: Vector3 in [pts[i] - o0, pts[i] + o0, pts[i + 1] + o0, pts[i] - o0, pts[i + 1] + o0, pts[i + 1] - o0]:
				st.add_vertex(v)
	return st.commit()


func _build_ground_circle() -> void:
	## The monument circle shader as a glowing inlay on the deck around the core.
	var quad := QuadMesh.new()
	quad.size = Vector2(GROUND_RING_SIZE, GROUND_RING_SIZE)
	var inst := MeshInstance3D.new()
	inst.name = "GroundCircle"
	inst.mesh = quad
	inst.material_override = _circle_material
	inst.position = Vector3(0.0, DECK_H + 0.05, 0.0)
	inst.rotation_degrees.x = -90.0
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


# ─── Club: speakers, desk, video wall ───────────────────────────────

func _build_speakers() -> void:
	## Two PA stacks flanking the crowd pit: textured cabinets, real-looking woofers (surround,
	## paper cone, dust cap) on the subs, perforated grilles + horns on the tops, flybar,
	## stencils, and a VU column = HYPO (left) / EPI (right).
	var cab := Kit.painted("metal_plate", Color(0.05, 0.05, 0.055), 1.6)
	var baffle := Kit.paint(Color(0.025, 0.025, 0.028), 0.85, 0.0)
	var surround := Kit.paint(Color(0.02, 0.02, 0.02), 0.6, 0.0)
	var paper := Kit.paint(Color(0.16, 0.16, 0.17), 0.9, 0.0)
	var cap := Kit.paint(Color(0.03, 0.03, 0.035), 0.25, 0.4)
	var steel := Kit.paint(Color(0.55, 0.56, 0.58), 0.35, 0.9)
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.2
	cone_mesh.bottom_radius = 0.92
	cone_mesh.height = 0.12
	cone_mesh.radial_segments = 24
	cone_mesh.cap_bottom = false
	for side: float in [-1.0, 1.0]:
		var root := Node3D.new()
		root.name = "SpeakerStack_%s" % ("L" if side < 0 else "R")
		root.position = Vector3(12.3 * side, 0, 6.3)
		root.rotation.y = -side * 0.55  # Toe in toward the crowd pit, clear of the stage sightline
		add_child(root)
		Kit.box(root, Vector3(1.5, 0.14, 1.0), Vector3(0, 0.07, 0), Kit.pbr("metal_plate", 0.8, Color(0.4, 0.4, 0.42), false))
		for cx: float in [-0.6, 0.6]:
			for cz: float in [-0.35, 0.35]:
				Kit.cyl(root, 0.06, 0.06, 0.05, Vector3(cx, 0.03, cz), surround, 10, Vector3(0, 0, PI * 0.5), false)
		var y := 0.14
		var specs := [[1.4, 1.0, 0.95, 2, 0.36, true], [1.4, 1.0, 0.95, 2, 0.36, true], [1.3, 0.62, 0.8, 2, 0.17, false], [1.3, 0.62, 0.8, 2, 0.17, false]]
		for s in specs:
			var w: float = s[0]
			var h: float = s[1]
			var d: float = s[2]
			var nc: int = s[3]
			var cr: float = s[4]
			var sub: bool = s[5]
			Kit.box(root, Vector3(w, h - 0.02, d), Vector3(0, y + h * 0.5, 0), cab)
			# Corner protectors + side handles
			for cx: float in [-1.0, 1.0]:
				for cy2: float in [-1.0, 1.0]:
					Kit.box(root, Vector3(0.07, 0.07, 0.07), Vector3(cx * (w * 0.5 - 0.02), y + h * 0.5 + cy2 * (h * 0.5 - 0.04), d * 0.5 - 0.02), steel, Vector3.ZERO, false)
				Kit.box(root, Vector3(0.02, 0.06, 0.22), Vector3(cx * (w * 0.5 + 0.01), y + h * 0.6, 0), steel, Vector3.ZERO, false)
			var fz := d * 0.5 + 0.004
			if sub:
				Kit.box(root, Vector3(w - 0.08, h - 0.1, 0.01), Vector3(0, y + h * 0.5, fz), baffle, Vector3.ZERO, false)
				for k in nc:
					var cxp := (float(k) - float(nc - 1) * 0.5) * (w / float(nc))
					var c := Vector3(cxp, y + h * 0.5, fz)
					Kit.ring(root, cr * 0.96, 0.03, c + Vector3(0, 0, 0.01), surround, Vector3(PI * 0.5, 0, 0), 28)
					var cone := MeshInstance3D.new()
					cone.mesh = cone_mesh
					cone.material_override = paper
					cone.position = c + Vector3(0, 0, -0.02)
					cone.rotation.x = -PI * 0.5   # Wide end out, apex back into the cabinet
					cone.scale = Vector3(cr, 1.0, cr)
					cone.set_meta("r", cr)
					root.add_child(cone)
					_cones.append(cone)
					Kit.ball(root, cr * 0.22, c + Vector3(0, 0, -0.06), cap, 12)
				Kit.box(root, Vector3(w - 0.2, 0.08, 0.02), Vector3(0, y + 0.08, fz + 0.005), Kit.paint(Color(0.0, 0.0, 0.0), 0.9, 0.0), Vector3.ZERO, false)
			else:
				# Perforated grille over a horn + two mids
				Kit.box(root, Vector3(w - 0.06, h - 0.08, 0.02), Vector3(0, y + h * 0.5, fz), Kit.grille(), Vector3.ZERO, false)
				Kit.box(root, Vector3(0.5, 0.2, 0.03), Vector3(0, y + h * 0.5, fz + 0.012), Kit.paint(Color(0.12, 0.12, 0.13), 0.35, 0.7), Vector3.ZERO, false)
			Kit.label(root, "DYS AUDIO", Vector3(side * -(w * 0.5 + 0.012), y + h * 0.5, 0), 48, Color(0.75, 0.75, 0.75), -side * PI * 0.5)
			y += h
		# Flybar on top with shackles + a cable loom out the back down to the deck feed
		Kit.box(root, Vector3(1.5, 0.08, 0.3), Vector3(0, y + 0.1, 0), steel)
		Kit.beam(root, Vector3(-0.55, y, 0), Vector3(-0.55, y + 0.1, 0), 0.02, steel)
		Kit.beam(root, Vector3(0.55, y, 0), Vector3(0.55, y + 0.1, 0), 0.02, steel)
		var loom: Array[Vector3] = [Vector3(0.3, y - 0.3, -0.5), Vector3(0.35, y - 0.6, -0.62), Vector3(0.4, 1.0, -0.66), Vector3(0.4, 0.06, -0.8), Vector3(0.6, 0.06, -1.4)]
		Kit.tube(root, loom, 0.05, Kit.paint(Color(0.03, 0.03, 0.035), 0.7, 0.0))
		# VU meter column on the stack's inner side
		var vu := Kit.screen(4, _accent, int(side * 7.0) + 11)
		Kit.box(root, Vector3(0.22, 2.6, 0.14), Vector3(-side * 0.82, 1.45, 0.25), cab)
		Kit.quad(root, Vector2(0.16, 2.45), Vector3(-side * 0.82, 1.45, 0.322), vu)
		if side < 0:
			_vu_left = vu
		else:
			_vu_right = vu
		Kit.label(root, "HYPO" if side < 0 else "EPI", Vector3(-side * 0.82, 2.86, 0.33), 40, Color(0.9, 0.9, 0.9), 0.0, 0.5)
		# Violet uplight on the floor in front of the stack (rim light for the stage)
		Kit.cyl(root, 0.16, 0.2, 0.25, Vector3(0.3 * side, 0.125, 0.95), Kit.paint(Color(0.05, 0.05, 0.05), 0.5, 0.6), 12)
		Kit.light_cone(root, Vector3(0.3 * side, 0.28, 0.95), Vector3(-side * 0.25, 1.0, -0.45), 7.0, 0.12, 0.9, VIOLET, 0.9)


func _build_control_desk() -> void:
	## DJ booth at the stage front: flight-case desk, two turntables, mixer, laptop, three
	## monitors (CHARGE/HYPO/EPI, radar, log) and an LED front panel facing the crowd.
	var root := Node3D.new()
	root.name = "DJBooth"
	root.position = Vector3(0, DECK_H, 4.3)
	add_child(root)
	var body := Kit.painted("metal_plate", Color(0.06, 0.06, 0.065), 1.4)
	var dark := Kit.paint(Color(0.03, 0.03, 0.035), 0.4, 0.4)
	var alu := Kit.paint(Color(0.6, 0.61, 0.63), 0.3, 0.95)
	Kit.box(root, Vector3(3.4, 1.0, 0.9), Vector3(0, 0.5, 0), body)
	for sx: float in [-1.7, 1.7]:
		Kit.box(root, Vector3(0.04, 1.0, 0.92), Vector3(sx, 0.5, 0), alu, Vector3.ZERO, false)
	Kit.box(root, Vector3(3.5, 0.05, 1.0), Vector3(0, 1.02, -0.05), dark)
	# Turntables: platter, label, tonearm
	for sx: float in [-1.05, 1.05]:
		Kit.box(root, Vector3(0.62, 0.08, 0.5), Vector3(sx, 1.08, -0.1), Kit.paint(Color(0.12, 0.12, 0.13), 0.35, 0.6))
		Kit.cyl(root, 0.2, 0.2, 0.02, Vector3(sx - 0.05, 1.13, -0.1), Kit.paint(Color(0.02, 0.02, 0.02), 0.2, 0.2), 24, Vector3.ZERO, false)
		Kit.cyl(root, 0.06, 0.06, 0.022, Vector3(sx - 0.05, 1.135, -0.1), Kit.glow(VIOLET if sx < 0 else CYAN, 2.0), 16, Vector3.ZERO, false)
		Kit.beam(root, Vector3(sx + 0.22, 1.15, -0.28), Vector3(sx + 0.05, 1.15, 0.02), 0.008, alu, 6, false)
	# Mixer with lit faders + laptop on a stand
	Kit.box(root, Vector3(0.6, 0.1, 0.5), Vector3(0, 1.09, -0.1), Kit.paint(Color(0.1, 0.1, 0.11), 0.4, 0.6))
	var leds: Array = []
	for r in 4:
		for c in 6:
			leds.append(Transform3D(Basis.from_scale(Vector3(0.03, 0.015, 0.03)), Vector3(-0.22 + float(c) * 0.088, 1.15, -0.28 + float(r) * 0.11)))
	Kit.multi(root, Kit.unit_box(), leds, Kit.glow(Color(1.0, 0.55, 0.15), 2.5), false)
	Kit.box(root, Vector3(0.4, 0.02, 0.28), Vector3(0.45, 1.25, -0.35), dark, Vector3(0.1, 0.2, 0))
	var lap := Kit.screen(3, CYAN, 9)
	Kit.quad(root, Vector2(0.38, 0.24), Vector3(0.45, 1.39, -0.46), lap, Vector3(-0.3, PI + 0.2, 0))
	# Front LED panel facing the audience (+Z) + logo
	_desk_vu = Kit.screen(5, _accent, 5)
	Kit.quad(root, Vector2(3.2, 0.62), Vector3(0, 0.52, 0.455), _desk_vu)
	Kit.label(root, "META.BEAT", Vector3(0, 0.9, 0.456), 44, Color(0.9, 0.95, 1.0), 0.0, 1.0)
	# Monitors on arms, facing the DJ (-Z side)
	var modes := [0, 2, 3]
	for i in 3:
		var x := (float(i) - 1.0) * 1.05
		var mon := Node3D.new()
		mon.position = Vector3(x, 1.62, 0.25)
		mon.rotation = Vector3(-0.15, PI + (float(i) - 1.0) * -0.25, 0)
		root.add_child(mon)
		Kit.box(mon, Vector3(0.8, 0.5, 0.05), Vector3.ZERO, dark)
		var scr := Kit.screen(modes[i], _accent, 30 + i)
		Kit.quad(mon, Vector2(0.74, 0.44), Vector3(0, 0, 0.027), scr)
		_screens.append(scr)
		Kit.beam(root, Vector3(x, 1.05, 0.25), Vector3(x, 1.38, 0.25), 0.025, dark)
	# Stage monitor wedges along the stage front edge, facing back at the performers
	var apo := DECK_R * cos(PI / 8.0)
	for x: float in [-3.0, -1.2, 1.2, 3.0]:
		var w := Kit.box(self, Vector3(0.75, 0.42, 0.55), Vector3(x, DECK_H + 0.21, apo - 0.5), Kit.painted("metal_plate", Color(0.05, 0.05, 0.055), 1.6), Vector3(0.5, PI, 0))
		w.name = "Wedge"
		Kit.box(self, Vector3(0.65, 0.3, 0.02), Vector3(x, DECK_H + 0.26, apo - 0.72), Kit.grille(), Vector3(0.5, PI, 0), false)


func _build_video_wall() -> void:
	## On-deck LED backdrop between the rear pylons (gauges left/right, visualiser centre),
	## a full square roof truss on the pylons with moving heads, a deck wash and a violet
	## back light.
	var truss := Kit.paint(Color(0.6, 0.61, 0.63), 0.35, 0.9)
	var frame := Kit.paint(Color(0.03, 0.03, 0.035), 0.6, 0.3)
	var z := -PYLON_SPACING + 0.9
	var y0 := DECK_H + 0.5
	var h := 4.6
	Kit.box(self, Vector3(9.0, h + 0.3, 0.3), Vector3(0, y0 + h * 0.5, z - 0.1), frame)
	var panels := [[-3.0, 2.8, 0], [0.0, 3.0, 5], [3.0, 2.8, 1]]
	for p in panels:
		var scr := Kit.screen(p[2], _accent, 40 + int(p[2]))
		scr.set_shader_parameter("brightness", 3.0)
		Kit.quad(self, Vector2(p[1], h), Vector3(p[0], y0 + h * 0.5, z + 0.06), scr)
		_screens.append(scr)
	Kit.label(self, "CHARGE  HYPO  EPI", Vector3(-3.0, y0 + 0.25, z + 0.08), 40, Color(0.9, 0.9, 0.95), 0.0, 0.6)
	Kit.label(self, "RESONANCE", Vector3(3.0, y0 + 0.25, z + 0.08), 40, Color(0.9, 0.9, 0.95), 0.0, 0.6)
	var xs: Array = []
	for sx: float in [-4.6, 4.6]:
		Kit.truss_xforms(Vector3(sx, DECK_H, z - 0.1), Vector3(sx, y0 + h + 0.3, z - 0.1), 0.3, 0.45, xs, 0.025)
	# Square roof truss tying the four pylons together (the front span carries the header)
	var ry := DECK_H + 8.7
	var c := PYLON_SPACING
	Kit.truss_xforms(Vector3(-c, ry, -c + 0.45), Vector3(-c, ry, c - 0.45), 0.42, 0.5, xs, 0.03)
	Kit.truss_xforms(Vector3(c, ry, -c + 0.45), Vector3(c, ry, c - 0.45), 0.42, 0.5, xs, 0.03)
	Kit.truss_xforms(Vector3(-c + 0.45, ry, -c), Vector3(c - 0.45, ry, -c), 0.42, 0.5, xs, 0.03)
	Kit.multi(self, Kit.unit_cylinder(6), xs, truss)
	# Moving-head fixtures hung under the truss (static ones are just glowing lenses)
	var heads: Array = []
	for k in 6:
		var t := float(k) / 5.0
		heads.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.38, 0.3)), Vector3(lerpf(-c + 0.8, c - 0.8, t), ry - 0.45, -c)))
		heads.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.38, 0.3)), Vector3(c, ry - 0.45, lerpf(-c + 0.8, c - 0.8, t))))
		heads.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.38, 0.3)), Vector3(-c, ry - 0.45, lerpf(-c + 0.8, c - 0.8, t))))
	Kit.multi(self, Kit.unit_box(), heads, Kit.paint(Color(0.06, 0.06, 0.07), 0.5, 0.6), false)
	# Two real moving spots on the front truss that sweep the crowd and deck floor
	for i in 2:
		var piv := Node3D.new()
		piv.position = Vector3(-c if i == 0 else c, ry - 0.6, 2.2)
		add_child(piv)
		Kit.box(piv, Vector3(0.34, 0.42, 0.34), Vector3(0, 0, 0), Kit.paint(Color(0.06, 0.06, 0.07), 0.5, 0.6), Vector3.ZERO, false)
		var col: Color = MAGENTA if i == 0 else CYAN
		var sp := SpotLight3D.new()
		sp.light_color = col
		sp.light_energy = 6.0
		sp.spot_range = 22.0
		sp.spot_angle = 14.0
		sp.spot_attenuation = 0.6
		sp.shadow_enabled = false
		piv.add_child(sp)
		Kit.light_cone(piv, Vector3(0, 0, -0.2), Vector3(0, 0, -1), 13.0, 0.12, 2.4, col, 1.1)
		_movers.append(piv)
	# Warm deck wash from the front truss + violet back light behind the LED wall
	var wash := Kit.spot(self, Vector3(0, ry - 0.6, c - 0.2), Vector3(0, DECK_H, 0.5), Color(1.0, 0.9, 0.78), 3.0, 16.0, 48.0)
	wash.name = "DeckWash"
	Kit.omni(self, Vector3(0, DECK_H + 4.5, -7.6), VIOLET, 2.6, 13.0)


# ─── Props, lamps, signage ──────────────────────────────────────────

func _build_props() -> void:
	# Generator yard (-X, -Z): generators, fuel drums, gas bottles, cable drum
	for g in GEN_SPOTS:
		Kit.prop(self, "portable_generator", g, -0.8 + _rng.randf_range(-0.1, 0.1))
	var drums: Array = []
	for i in 5:
		var p := Vector3(-12.6 + float(i % 2) * 0.68, 0, -8.6 + float(i / 2) * 0.68 + float(i % 2) * 0.3)
		drums.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	Kit.prop_multi(self, "barrel_03", drums)
	for i in 3:
		Kit.prop(self, "small_lpg_tank", Vector3(-8.4 + float(i) * 0.48, 0, -12.9), _rng.randf() * TAU)
	_cable_drum(Vector3(-8.6, 0, -7.4), 0.4)
	_build_backstage()
	# Kit stores (-X, -Z): crates, tool cart, ammo cases
	Kit.prop(self, "wooden_crate_02", Vector3(-11.6, 0, -10.8), 0.1)
	Kit.prop(self, "wooden_crate_02", Vector3(-11.0, 0, -10.6), -0.05)
	Kit.prop(self, "wooden_crate_02", Vector3(-11.3, 0.46, -10.7), 0.3)
	Kit.prop(self, "old_military_crate", Vector3(-9.6, 0, -12.4), 0.2)
	Kit.prop(self, "tool_cart", Vector3(-8.0, 0, -10.2), 2.6)
	# Crowd pit right up against the stage front: barrier line, FOH tent off to the side
	Kit.crowd_barrier(self, Vector3(-7.6, 0, 9.85), Vector3(7.6, 0, 9.85))
	_build_foh(Vector3(-10.2, 0, 12.4))
	# Light pools over the crowd (warm + cyan + magenta) so the plaza reads at night
	Kit.light_pool(self, Vector3(-4.0, 0.08, 11.8), 4.5, Color(1.0, 0.78, 0.5), 1.1)
	Kit.light_pool(self, Vector3(3.8, 0.08, 12.0), 4.5, CYAN, 1.1)
	Kit.light_pool(self, Vector3(0.0, 0.08, 10.8), 4.0, MAGENTA, 0.8)
	Kit.light_pool(self, Vector3(7.5, 0.08, 9.0), 4.0, Color(1.0, 0.78, 0.5), 0.8)
	Kit.light_pool(self, Vector3(0, DECK_H + 0.09, 1.5), 7.5, Color(1.0, 0.88, 0.7), 0.7)
	# Bollard lights along the plaza kerb with soft pools (front + sides)
	var bol: Array = []
	var lens: Array = []
	for i in 9:
		var t := -12.0 + float(i) * 3.0
		for p: Vector3 in [Vector3(t, 0, 13.6), Vector3(13.6, 0, t), Vector3(-13.6, 0, t)]:
			if absf(p.x) > 13.0 and absf(p.z) > 12.5:
				continue
			bol.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.9, 0.09)), p + Vector3(0, 0.45, 0)))
			lens.append(Transform3D(Basis.from_scale(Vector3(0.1, 0.12, 0.1)), p + Vector3(0, 0.8, 0)))
			Kit.light_pool(self, p + Vector3(0, 0.08, 0), 2.2, Color(1.0, 0.82, 0.55), 0.6)
	Kit.multi(self, Kit.unit_cylinder(8), bol, Kit.paint(Color(0.15, 0.15, 0.16), 0.5, 0.7), false)
	Kit.multi(self, Kit.unit_cylinder(8), lens, Kit.glow(Color(1.0, 0.82, 0.55), 4.0), false)
	# Concrete barriers guard the back-left corner (back-centre is kept for the billboard)
	for x: float in [-9.4, -11.0]:
		Kit.prop(self, "concrete_road_barrier", Vector3(x, 0, -13.3), _rng.randf_range(-0.06, 0.06))
	# Lighting masts on the wings and back corners, aimed at the stage (front pair carry spots)
	var masts := [Vector3(13.6, 0, 3.9), Vector3(-13.5, 0, 8.9), Vector3(13.0, 0, -12.9), Vector3(-13.0, 0, -12.9)]
	for i in masts.size():
		var p: Vector3 = masts[i]
		Kit.flood_mast(self, p, 7.5, Vector3(p.x * 0.25, DECK_H, p.z * 0.25), Color(1.0, 0.86, 0.68), 3, i < 2, 2.5)
		Kit.light_pool(self, Vector3(p.x * 0.55, 0.07, p.z * 0.55), 6.5, Color(1.0, 0.85, 0.65), 0.7)
	# Crew cabin (-X) and transformer (+X)
	Kit.cabin(self, Vector3(-12.2, 0, 2.0), PI * 0.5, Vector3(5.0, 2.5, 2.3), "CREW - BEAT OPS")
	_build_transformer(Vector3(12.2, 0, -4.4))
	# Cable protector ramp carrying the FOH snake along the side of the pit
	var ramp := Kit.box(self, Vector3(1.9, 0.08, 0.6), Vector3(-8.4, 0.08, 10.6), Kit.hazard(5.0), Vector3.ZERO, false)
	ramp.name = "CableRamp"
	# Speaker feeds: ground cables from each stack to the deck
	var rubber := Kit.paint(Color(0.03, 0.03, 0.035), 0.7, 0.0)
	for sx: float in [-1.0, 1.0]:
		var pts: Array[Vector3] = [Vector3(12.0 * sx, 0.3, 5.6), Vector3(11.3 * sx, 0.08, 5.4), Vector3(9.8 * sx, 0.08, 5.3),
			Vector3(9.1 * sx, 0.5, 4.9), Vector3(8.0 * sx, DECK_H + 0.08, 4.2)]
		Kit.tube(self, pts, 0.045, rubber)
	# Signage on proper stands
	var warn := "HIGH RESONANCE\nKEEP CLEAR DURING BEAT"
	var apo := DECK_R * cos(PI / 8.0)
	_sign_stand(warn, Vector3(apo + 3.3, 0, 2.7), PI * 0.5, Color(0.92, 0.7, 0.08), Color(0.05, 0.05, 0.05))
	_sign_stand(warn, Vector3(3.2, 0, -apo - 3.3), PI, Color(0.92, 0.7, 0.08), Color(0.05, 0.05, 0.05))
	_sign_stand("STAGE ACCESS\nAUTHORISED CREW", Vector3(apo + 3.3, 0, -2.5), PI * 0.5, Color(0.08, 0.2, 0.55), Color(0.92, 0.92, 0.92))
	_sign_stand("GEN YARD\n11 kV", Vector3(-9.6, 0, -5.6), PI * 0.5, Color(0.92, 0.7, 0.08), Color(0.05, 0.05, 0.05))


func _sign_stand(text: String, pos: Vector3, rot_y: float, bg: Color, fg: Color) -> void:
	## A-frame barrier sign standing on the plaza.
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var leg := Kit.paint(Color(0.85, 0.62, 0.1), 0.45, 0.6)
	for sx: float in [-0.75, 0.75]:
		Kit.beam(root, Vector3(sx, 0, 0.25), Vector3(sx, 1.25, 0), 0.03, leg)
		Kit.beam(root, Vector3(sx, 0, -0.25), Vector3(sx, 1.25, 0), 0.03, leg)
	Kit.sign_board(root, text, Vector3(0, 0.95, 0.06), 0.0, Vector2(1.6, 0.5), bg, fg, 32)


func _build_transformer(pos: Vector3) -> void:
	## Step-down transformer feeding the deck: finned tank, HV bushings, warning plates.
	var root := Node3D.new()
	root.name = "Transformer"
	root.position = pos
	root.rotation.y = PI * 0.5
	add_child(root)
	Kit.box(root, Vector3(3.0, 0.25, 2.2), Vector3(0, 0.0, 0), Kit.pbr("brushed_concrete", 0.7, Color(0.6, 0.6, 0.58)))
	var tank := Kit.paint(Color(0.32, 0.38, 0.34), 0.55, 0.5)
	Kit.box(root, Vector3(1.8, 1.8, 1.1), Vector3(0, 1.025, 0), tank)
	var fins: Array = []
	for i in 9:
		for sz: float in [-1.0, 1.0]:
			fins.append(Transform3D(Basis.from_scale(Vector3(0.04, 1.4, 0.32)), Vector3(-0.8 + float(i) * 0.2, 1.0, sz * 0.72)))
	Kit.multi(root, Kit.unit_box(), fins, tank)
	var porcelain := Kit.paint(Color(0.55, 0.3, 0.18), 0.25, 0.0)
	for k in 3:
		var bx := -0.55 + float(k) * 0.55
		for d in 5:
			Kit.cyl(root, 0.09, 0.09, 0.05, Vector3(bx, 2.0 + float(d) * 0.09, 0), porcelain, 10)
		Kit.cyl(root, 0.05, 0.05, 0.5, Vector3(bx, 2.15, 0), porcelain, 8)
		Kit.ball(root, 0.06, Vector3(bx, 2.45, 0), Kit.paint(Color(0.6, 0.6, 0.62), 0.3, 1.0))
	Kit.sign_board(root, "DANGER\nHIGH VOLTAGE", Vector3(0, 1.2, 0.57), 0.0, Vector2(0.9, 0.45), Color(0.92, 0.85, 0.75), Color(0.75, 0.05, 0.05), 30)
	Kit.box(root, Vector3(0.12, 0.12, 0.03), Vector3(0.7, 1.75, 0.565), Kit.glow(Color(0.2, 1.0, 0.4), 3.0), Vector3.ZERO, false)
	# HV feed to the deck: conduit from the bushings arcing to the deck side
	var deck_pt := Vector3(pos.x, 0, pos.z).normalized() * (DECK_R * cos(PI / 8.0) - 0.1) + Vector3(0, DECK_H - 0.3, 0)
	Kit.cable(self, pos + Vector3(-0.3, 2.45, 0), deck_pt, 0.3, 0.06, _conduit_mat, 10)
	Kit.cable(self, pos + Vector3(-0.3, 2.45, 0.55), deck_pt + Vector3(0, 0, 0.5), 0.3, 0.06, _conduit_mat, 10)
	Kit.cable(self, pos + Vector3(-0.3, 2.45, -0.55), deck_pt + Vector3(0, 0, -0.5), 0.3, 0.06, _conduit_mat, 10)


func _cable_drum(pos: Vector3, rot: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot
	add_child(root)
	var wood := Kit.paint(Color(0.36, 0.26, 0.16), 0.85, 0.0)
	for s: float in [-0.42, 0.42]:
		Kit.cyl(root, 0.62, 0.62, 0.06, Vector3(s, 0.62, 0), wood, 20, Vector3(0, 0, PI * 0.5))
	Kit.cyl(root, 0.42, 0.42, 0.8, Vector3(0, 0.62, 0), Kit.paint(Color(0.04, 0.04, 0.045), 0.6, 0.0), 20, Vector3(0, 0, PI * 0.5))


func _build_light() -> void:
	_station_light = Kit.omni(self, Vector3(0.0, DISH_HEIGHT, 0.0), _accent, 2.0, 25.0)
	_station_light.name = "StationLight"
	_station_light.omni_attenuation = 1.5
	_core_light = Kit.omni(self, Vector3(0, DECK_H + 3.0, 0), _accent.lightened(0.15), 2.0, 13.0)
	_core_light.name = "CoreLight"
	# Cyan crowd wash from the header truss
	var wash := Kit.spot(self, Vector3(0, DECK_H + 8.3, 5.9), Vector3(0, 0, 12.3), CYAN, 3.5, 16.0, 42.0)
	wash.name = "CrowdWash"


func _build_locals(seed_value: int) -> void:
	## DJ at the booth (arms up), crew on rounds, a visitor using the side stairs, security
	## at the barrier, the FOH engineer, and twelve in the pit in loose clumps.
	var dj := Kit.npc(self, seed_value + 101, [], Vector3(0, 0, 1), Callable(), Vector3(0, DECK_H, 3.45))
	if dj:
		Kit.arms_up(dj, false, _rng)
	Kit.npc(self, seed_value + 202, [
		Vector3(-9.5, 0, 3.7), Vector3(-9.0, 0, 9.0), Vector3(-9.5, 0, 3.7), Vector3(-9.4, 0, -4.0)])
	var sfoot := DECK_R * cos(PI / 8.0) + 0.34 * ceil(DECK_H / 0.27) + 0.4
	Kit.npc(self, seed_value + 303, [
		Vector3(sfoot + 0.4, 0, 1.6), Vector3(sfoot, 0, 0.0), Vector3(7.6, DECK_H, 0.0), Vector3(4.8, DECK_H, 2.6), Vector3(7.6, DECK_H, 0.0), Vector3(sfoot, 0, 0.0)])
	Kit.npc(self, seed_value + 404, [], Vector3(0, 0, 1), Callable(), Vector3(2.6, 0, 9.4))
	Kit.npc(self, seed_value + 505, [], Vector3(0.6, 0, -1), Callable(), Vector3(-10.2, 0, 13.05))
	Kit.crowd(self, seed_value + 606, Vector3(-7.4, 0, 10.4), Vector3(7.4, 0, 13.4), 12, Vector3(0, 0, -1))


func get_board_anchor() -> Transform3D:
	## Reserved spot for a 3.2 x 1.8 m media billboard (bottom 1.2 m up) at the back edge of
	## the plaza, facing the approach from player spawn (-Z). Board front = local -Z.
	return Transform3D(Basis.IDENTITY, Vector3(-4.6, 1.2 + 0.9, -13.5))


func _build_backstage() -> void:
	## Stacked-container backstage block (office below, artists' lounge above) with an
	## external stair, lit windows, signage and a roof light bar.
	var base := Vector3(9.5, 0, -11.1)
	var low := Kit.cabin(self, base, 0.0, Vector3(5.4, 2.6, 2.6), "BACKSTAGE", Color(1.0, 0.85, 0.62), true, Color(0.2, 0.28, 0.42))
	low.name = "Backstage"
	var up := Kit.cabin(self, base + Vector3(-0.5, 2.85, -0.1), 0.0, Vector3(4.6, 2.4, 2.4), "ARTISTS", Color(0.75, 0.6, 1.0), true, Color(0.55, 0.2, 0.3))
	up.name = "ArtistsLounge"
	# External stair + landing on the -X end
	var steel := Kit.paint(Color(0.85, 0.62, 0.1), 0.45, 0.6)
	var tread := Kit.pbr("metal_plate", 0.6, Color(0.5, 0.5, 0.52), false)
	for i in 10:
		var t := (float(i) + 0.5) / 10.0
		Kit.box(self, Vector3(0.9, 0.05, 0.3), base + Vector3(-3.3, 0.3 + t * 2.75, 1.55 - t * 2.8), tread)
	Kit.box(self, Vector3(1.0, 0.08, 1.2), base + Vector3(-3.3, 3.1, -1.75), tread)
	for sx: float in [-0.45, 0.45]:
		Kit.beam(self, base + Vector3(-3.3 + sx, 1.3, 1.6), base + Vector3(-3.3 + sx, 4.05, -1.2), 0.03, steel)
		Kit.beam(self, base + Vector3(-3.3 + sx, 0.0, -1.75), base + Vector3(-3.3 + sx, 3.1, -1.75), 0.05, steel)
	# Roof light bar + sign
	Kit.box(self, Vector3(4.2, 0.5, 0.1), base + Vector3(-0.5, 5.75, 1.0), Kit.paint(Color(0.03, 0.03, 0.035), 0.5, 0.3))
	Kit.label(self, "META CREW", Vector3(base.x - 0.5, 5.75, base.z + 1.06), 90, VIOLET.lightened(0.3), 0.0, 2.0)
	Kit.box(self, Vector3(4.2, 0.04, 0.04), base + Vector3(-0.5, 5.48, 1.06), Kit.glow(CYAN, 3.0), Vector3.ZERO, false)


func _build_foh(pos: Vector3) -> void:
	## Front-of-house mix position: pop-up canopy, desk with console, rack and a light bar.
	var root := Node3D.new()
	root.name = "FOH"
	root.position = pos
	add_child(root)
	var frame := Kit.paint(Color(0.6, 0.61, 0.63), 0.35, 0.9)
	var dark := Kit.paint(Color(0.05, 0.05, 0.06), 0.6, 0.3)
	Kit.box(root, Vector3(2.6, 0.12, 1.6), Vector3(0, 0.06, 0), Kit.pbr("metal_plate", 0.9, Color(0.4, 0.4, 0.42), false))
	for sx: float in [-1.2, 1.2]:
		for sz: float in [-0.75, 0.75]:
			Kit.beam(root, Vector3(sx, 0.1, sz), Vector3(sx, 2.35, sz), 0.03, frame, 6)
	Kit.box(root, Vector3(2.7, 0.06, 1.8), Vector3(0, 2.4, 0), Kit.paint(Color(0.08, 0.08, 0.1), 0.8, 0.0))
	Kit.box(root, Vector3(2.7, 0.25, 0.02), Vector3(0, 2.28, 0.9), Kit.paint(Color(0.08, 0.08, 0.1), 0.8, 0.0))
	Kit.label(root, "FOH", Vector3(0, 2.28, 0.92), 60, CYAN, 0.0, 1.2)
	Kit.label(root, "FOH", Vector3(0, 2.28, -0.92), 60, CYAN, PI, 1.2)
	# Desk + console facing the stage (-Z)
	Kit.box(root, Vector3(1.9, 0.8, 0.7), Vector3(0, 0.52, -0.25), dark)
	Kit.box(root, Vector3(1.7, 0.08, 0.6), Vector3(0, 0.96, -0.25), Kit.paint(Color(0.12, 0.12, 0.13), 0.4, 0.5), Vector3(0.2, 0, 0))
	var leds: Array = []
	for r in 4:
		for c in 18:
			leds.append(Transform3D(Basis.from_scale(Vector3(0.035, 0.02, 0.035)), Vector3(-0.75 + float(c) * 0.088, 1.0 + float(r) * 0.012, -0.45 + float(r) * 0.11)))
	Kit.multi(root, Kit.unit_box(), leds, Kit.glow(CYAN, 2.5), false)
	var scr := Kit.screen(1, CYAN, 55)
	Kit.box(root, Vector3(0.7, 0.45, 0.04), Vector3(0.5, 1.35, -0.52), dark, Vector3(-0.2, 0, 0))
	Kit.quad(root, Vector2(0.64, 0.4), Vector3(0.5, 1.35, -0.495), scr, Vector3(-0.2, 0, 0))
	_screens.append(scr)
	Kit.box(root, Vector3(0.6, 1.0, 0.6), Vector3(-1.0, 0.62, 0.3), dark)
	Kit.box(root, Vector3(0.5, 0.03, 0.02), Vector3(-1.0, 0.9, 0.61), Kit.glow(Color(0.3, 1.0, 0.45), 3.0), Vector3.ZERO, false)


func _build_interaction_area() -> void:
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
