extends Node3D
## Territory shuttle port at (0, 100) on the 36×24 m levelled site. Fast travel is
## shuttle-only: main.gd opens the world map in shuttle mode within 12 m of this origin, so the
## pad reads as a passenger port with a clear walk-up to the boarding stairs.
##   - painted concrete apron (taxi line, hold-short bars, hazard border, joints, oil stains)
##   - octagonal pad with touchdown ring, target, pad number, blast scorch and skid marks
##   - perimeter chase lights (amber, sequential) + blue edge lights
##   - a parked VTOL passenger shuttle (lit cabin, door open) with a mobile airstair
##   - SHUTTLE TERMINAL kiosk + two-sided departure board ("BOARDING: PRESS E"), queue line
##   - fuel farm (two tanks with sight gauges = territory CHARGE), pump skid and hose
##   - control hut (converted container) with lit window, ops screens (HYPO / EPI), beacon
##   - perimeter dressing: container, crates on pallets, drums, gas bottles, tool cart; floodlight masts,
##     windsock, ground crew
## Deterministic from territory seed. Reads GameManager territory state for its gauges.

const Kit = preload("res://scripts/world/structures/struct_kit.gd")

const PAD_RADIUS: float = 8.0
const PAD_HEIGHT: float = 0.37      # Pad surface above the levelled ground
const PAD_SEGMENTS: int = 8         # Octagonal
const LIGHT_COUNT: int = 8
const LIGHT_CYCLE_SPEED: float = 0.3  # Seconds per light step
const APRON_HALF := Vector2(17.0, 11.0)

var _light_materials: Array[StandardMaterial3D] = []
var _light_positions: Array[Vector3] = []
var _chase_light: OmniLight3D
var _active_light_index: int = 0
var _light_timer: float = 0.0

var _accent: Color = Color(0.3, 0.8, 1.0)
var _pad_mat: ShaderMaterial
var _fuel_gauges: Array[ShaderMaterial] = []
var _ops_screens: Array[ShaderMaterial] = []
var _beacon_pivot: Node3D
var _beacon_light: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _lander_beacon: StandardMaterial3D
var _windsock: Node3D
var _terminal_seats: Array = []
var _queue_line: Array = []
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0


func initialize(seed_value: int) -> void:
	_rng.seed = seed_value + 8800
	_accent = Kit.CYAN  # The port wears Dysnomia relay cyan; the seed accent stays on the Beat Station

	_build_apron(seed_value)
	_build_pad_base(seed_value)
	_build_perimeter_lights()
	_build_shuttle()
	_build_terminal()
	_build_luggage_train()
	_build_edge_lights()
	_build_fuel_farm()
	_build_control_hut()
	_build_cargo()
	_build_masts_and_windsock()
	_build_crew(seed_value)
	Kit.merge_static(self, [_windsock, _beacon_pivot])

	if not GameManager.territory_state_changed.is_connected(_on_territory_state_changed):
		GameManager.territory_state_changed.connect(_on_territory_state_changed)
	_apply_territory_state()


func _on_territory_state_changed(_data: Dictionary) -> void:
	_apply_territory_state()


func _apply_territory_state() -> void:
	## Fuel = CHARGE, ops screens = HYPO / EPI, pad inlay brightness = CHARGE.
	var power := clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
	var hypo := clampf(float(GameManager.territory_hypobar) / 1e12, 0.0, 1.0)
	var epi := clampf(float(GameManager.territory_epibar) / 1e12, 0.0, 1.0)
	for i in _fuel_gauges.size():
		_fuel_gauges[i].set_shader_parameter("value_a", clampf(0.1 + power * (0.9 - float(i) * 0.12), 0.0, 1.0))
	for m in _ops_screens:
		m.set_shader_parameter("value_a", power)
		m.set_shader_parameter("value_b", hypo)
		m.set_shader_parameter("value_c", epi)
	if _pad_mat:
		_pad_mat.set_shader_parameter("accent_glow", 0.4 + power * 2.6)


func _process(delta: float) -> void:
	_time += delta
	Kit.update_night()
	# Sequential chase: one amber fixture bright at a time, one real light follows it
	_light_timer += delta
	if _light_timer >= LIGHT_CYCLE_SPEED and _light_materials.size() == LIGHT_COUNT:
		_light_timer -= LIGHT_CYCLE_SPEED
		_light_materials[_active_light_index].emission_energy_multiplier = 0.4
		_active_light_index = (_active_light_index + 1) % LIGHT_COUNT
		_light_materials[_active_light_index].emission_energy_multiplier = 6.0
		if _chase_light:
			_chase_light.position = _light_positions[_active_light_index] + Vector3(0, 0.5, 0)

	# Rotating hut beacon
	if _beacon_pivot:
		_beacon_pivot.rotation.y += delta * 3.2
	if _beacon_light:
		_beacon_light.light_energy = 0.6 + 0.6 * maxf(0.0, sin(_time * 3.2 * 2.0))
	# Lander anti-collision strobe
	if _lander_beacon:
		_lander_beacon.emission_energy_multiplier = 8.0 if fmod(_time, 1.6) < 0.12 else 0.3
	# Windsock sway in the thin breeze
	if _windsock:
		_windsock.rotation.y = 0.6 + sin(_time * 0.35) * 0.25 + sin(_time * 1.3) * 0.05
		_windsock.rotation.z = -0.25 + sin(_time * 2.1) * 0.04


# ─── Ground ─────────────────────────────────────────────────────────

func _build_apron(seed_value: int) -> void:
	var slab := Kit.box(self, Vector3(APRON_HALF.x * 2.0, 0.6, APRON_HALF.y * 2.0), Vector3(0, -0.24, 0),
		Kit.ground_slab(1, APRON_HALF, _accent, seed_value), Vector3.ZERO, false)
	slab.name = "Apron"
	var kerb := Kit.pbr("brushed_concrete", 0.6, Color(0.8, 0.8, 0.78))
	for s: float in [-1.0, 1.0]:
		Kit.box(self, Vector3(APRON_HALF.x * 2.0 + 0.4, 0.5, 0.25), Vector3(0, -0.1, (APRON_HALF.y + 0.1) * s), kerb)
		Kit.box(self, Vector3(0.25, 0.5, APRON_HALF.y * 2.0 + 0.4), Vector3((APRON_HALF.x + 0.1) * s, -0.1, 0), kerb)


func _build_pad_base(seed_value: int) -> void:
	## Raised octagonal pad: concrete plinth, painted marking surface, steel edge rim.
	var rot := Vector3(0, PI / 8.0, 0)
	var base := Kit.cyl(self, PAD_RADIUS, PAD_RADIUS + 0.25, PAD_HEIGHT + 0.25, Vector3(0, (PAD_HEIGHT - 0.25) * 0.5, 0),
		Kit.pbr("brushed_concrete", 0.5, Color(0.6, 0.6, 0.6)), PAD_SEGMENTS, rot)
	base.name = "PadBase"
	_pad_mat = Kit.ground_slab(0, APRON_HALF, _accent, seed_value)
	_pad_mat.set_shader_parameter("pad_radius", PAD_RADIUS - 0.1)
	_pad_mat.set_shader_parameter("pad_number", 1 + absi(seed_value) % 19)
	var top := Kit.cyl(self, PAD_RADIUS - 0.1, PAD_RADIUS - 0.1, 0.02, Vector3(0, PAD_HEIGHT + 0.01, 0), _pad_mat, 64, Vector3.ZERO, false)
	top.name = "PadSurface"
	var rim := Kit.cyl(self, PAD_RADIUS + 0.03, PAD_RADIUS + 0.03, 0.12, Vector3(0, PAD_HEIGHT - 0.09, 0),
		Kit.hazard(2.2), PAD_SEGMENTS, rot, false)
	rim.name = "EdgeTrim"


func _build_perimeter_lights() -> void:
	## 8 amber chase fixtures (sequenced) + 8 blue edge lights between them, on the pad rim.
	var housing := Kit.paint(Color(0.12, 0.12, 0.13), 0.4, 0.8)
	var blue := Kit.glow(_accent, 3.5)
	var r := PAD_RADIUS - 0.35
	for i in LIGHT_COUNT * 2:
		var angle: float = float(i) / float(LIGHT_COUNT * 2) * TAU
		var p := Vector3(cos(angle) * r, PAD_HEIGHT + 0.02, sin(angle) * r)
		Kit.cyl(self, 0.16, 0.19, 0.08, p + Vector3(0, 0.04, 0), housing, 12, Vector3.ZERO, false)
		if i % 2 == 0:
			var m := Kit.glow(Color(1.0, 0.68, 0.15), 0.4, false)
			var dome := Kit.cyl(self, 0.1, 0.13, 0.08, p + Vector3(0, 0.11, 0), m, 12, Vector3.ZERO, false)
			dome.name = "LightFixture_%d" % (i / 2)
			_light_materials.append(m)
			_light_positions.append(p)
		else:
			Kit.cyl(self, 0.09, 0.12, 0.06, p + Vector3(0, 0.1, 0), blue, 12, Vector3.ZERO, false)
	_chase_light = Kit.omni(self, _light_positions[0] + Vector3(0, 0.5, 0), Color(1.0, 0.7, 0.2), 1.6, 5.0)
	_chase_light.name = "ChaseLight"
	_light_materials[0].emission_energy_multiplier = 6.0


# ─── Passenger shuttle (the fast-travel craft) ──────────────────────

func _build_shuttle() -> void:
	## VTOL passenger shuttle parked on the pad: fuselage along X (nose -X), lit cabin
	## windows, wings with lift-fan nacelles, tail fin, gear legs, boarding door open on +Z.
	var root := Node3D.new()
	root.name = "PassengerShuttle"
	root.position = Vector3(-0.45, PAD_HEIGHT + 0.02, 0.0)  # Fuselage midpoint on the pad centre
	add_child(root)
	var hull := Kit.hull_material(Color(0.86, 0.86, 0.84))
	var belly := Kit.pbr("metal_plate", 0.8, Color(0.32, 0.33, 0.35), false)
	var dark := Kit.paint(Color(0.07, 0.07, 0.08), 0.45, 0.7)
	var seam := Kit.paint(Color(0.45, 0.45, 0.47), 0.5, 0.5)
	var cy := 2.75                     # Fuselage axis height above the pad
	var r := 1.45
	var axis := Vector3(0, 0, PI * 0.5)  # Cylinder Y -> X
	# Fuselage, belly fairing, nose, tail cone
	Kit.cyl(root, r, r, 10.0, Vector3(0, cy, 0), hull, 24, axis)
	Kit.box(root, Vector3(9.0, 0.5, 2.0), Vector3(0.3, cy - r + 0.12, 0), belly)
	Kit.ball(root, r, Vector3(-5.0, cy, 0), hull, 24).scale = Vector3(1.9, 1.0, 1.0)
	Kit.cyl(root, 0.55, r, 3.0, Vector3(6.5, cy + 0.15, 0), hull, 24, axis)
	# Cockpit glazing wrapping the nose
	var glass := Kit.glow(Color(0.25, 0.45, 0.6), 0.5)
	for s: float in [-1.0, 1.0]:
		Kit.box(root, Vector3(1.5, 0.45, 0.05), Vector3(-6.0, cy + 0.55, s * 0.98), glass, Vector3(0, s * 0.55, s * -0.25), false)
	Kit.box(root, Vector3(0.05, 0.42, 1.3), Vector3(-6.75, cy + 0.55, 0), glass, Vector3(0, 0, -0.5), false)
	# Panel seams + accent livery stripe
	for x: float in [-3.5, -0.5, 2.5, 4.9]:
		Kit.cyl(root, r + 0.008, r + 0.008, 0.03, Vector3(x, cy, 0), seam, 24, axis, false)
	for s: float in [-1.0, 1.0]:
		Kit.box(root, Vector3(10.6, 0.14, 0.04), Vector3(0.2, cy - 0.38, s * (r - 0.1)), Kit.glow(_accent, 1.4), Vector3.ZERO, false)
		# Cabin window strip: dark glazing band with warm lit windows
		Kit.box(root, Vector3(8.0, 0.56, 0.04), Vector3(0.0, cy + 0.42, s * (r - 0.14)), Kit.paint(Color(0.04, 0.05, 0.07), 0.15, 0.6), Vector3(s * 0.33, 0, 0), false)
		for k in 10:
			Kit.box(root, Vector3(0.42, 0.4, 0.04), Vector3(-3.6 + float(k) * 0.78, cy + 0.42, s * (r - 0.12)), Kit.glow(Color(1.0, 0.86, 0.62), 2.4), Vector3(s * 0.33, 0, 0), false)
		var rot := 0.0 if s > 0 else PI
		Kit.label(root, "DYSNOMIA SHUTTLE", Vector3(-1.2, cy - 0.05, s * (r + 0.01)), 130, Color(0.12, 0.13, 0.16), rot)
		Kit.label(root, "PASSENGER  DYS-369", Vector3(4.4, cy + 0.95, s * (r - 0.38)), 70, Color(0.2, 0.2, 0.22), rot)
		Kit.label(root, "NO STEP", Vector3(-0.6, cy - 0.45, s * 2.6), 50, Color(0.15, 0.15, 0.17), rot)
		# Cyan nose chevrons
		for k in 3:
			Kit.box(root, Vector3(0.12, 0.5, 0.03), Vector3(-4.6 + float(k) * 0.25, cy - 0.15, s * (r - 0.02)), Kit.glow(_accent, 1.6), Vector3(0, 0, 0.5), false)
	# Wings with lift-fan nacelles at the tips
	for s: float in [-1.0, 1.0]:
		Kit.box(root, Vector3(2.4, 0.16, 3.4), Vector3(-0.6, cy - 0.55, s * 2.9), hull, Vector3(0, 0, 0.04))
		var nac := Vector3(-0.6, cy - 0.45, s * 4.85)
		Kit.cyl(root, 1.0, 1.0, 0.7, nac, hull, 24)
		Kit.cyl(root, 0.85, 0.85, 0.72, nac, dark, 24, Vector3.ZERO, false)
		Kit.ring(root, 1.0, 0.05, nac + Vector3(0, 0.36, 0), Kit.glow(_accent, 1.2), Vector3.ZERO, 24)
		for b in 3:
			Kit.box(root, Vector3(1.6, 0.04, 0.16), nac + Vector3(0, 0.1, 0), seam, Vector3(0, float(b) * PI / 3.0, 0), false)
	# Tail fin + main engines
	Kit.box(root, Vector3(2.2, 2.3, 0.14), Vector3(6.4, cy + 1.9, 0), hull, Vector3(0, 0, -0.45))
	Kit.box(root, Vector3(1.2, 0.5, 0.15), Vector3(6.7, cy + 2.2, 0), Kit.glow(_accent, 1.0), Vector3(0, 0, -0.45), false)
	for s: float in [-0.5, 0.5]:
		Kit.cyl(root, 0.32, 0.42, 0.7, Vector3(8.2, cy + 0.15, s), dark, 16, axis)
		Kit.cyl(root, 0.28, 0.28, 0.02, Vector3(8.56, cy + 0.15, s), Kit.glow(Color(1.0, 0.45, 0.15), 0.8), 16, axis, false)
	_lander_beacon = Kit.glow(Color(1.0, 0.15, 0.1), 0.3, false)
	Kit.ball(root, 0.1, Vector3(7.3, cy + 3.05, 0), _lander_beacon)
	# Landing gear: 4 struts with oleo + pads + chocks
	for gx: float in [-3.6, 3.4]:
		for s: float in [-1.0, 1.0]:
			var foot := Vector3(gx, 0.1, s * 1.75)
			Kit.beam(root, Vector3(gx, cy - r + 0.25, s * 0.9), foot + Vector3(0, 0.4, 0), 0.12, belly)
			Kit.beam(root, foot + Vector3(0, 0.45, 0), foot + Vector3(0, 0.05, 0), 0.08, Kit.paint(Color(0.7, 0.7, 0.72), 0.2, 1.0))
			Kit.cyl(root, 0.42, 0.45, 0.12, foot, dark, 16)
			Kit.box(root, Vector3(0.32, 0.2, 0.45), foot + Vector3(-0.62, 0.0, 0), Kit.paint(Color(0.9, 0.55, 0.08), 0.6, 0.0), Vector3.ZERO, false)
	# Boarding door (+Z side, aft of the wing), open and lit from inside
	var door := Vector3(3.2, cy - 0.15, r - 0.05)
	Kit.box(root, Vector3(1.2, 2.1, 0.03), door + Vector3(0, 0, 0.06), Kit.hazard(4.0), Vector3.ZERO, false)
	Kit.box(root, Vector3(1.0, 1.9, 0.2), door, Kit.glow(Color(1.0, 0.9, 0.72), 1.5), Vector3.ZERO, false)
	Kit.box(root, Vector3(1.0, 1.9, 0.08), door + Vector3(-0.7, 0, 0.35), hull, Vector3(0, 0.9, 0))
	var door_light := Kit.omni(root, door + Vector3(0, 0.3, 1.3), Color(1.0, 0.88, 0.7), 1.3, 7.0)
	door_light.name = "DoorLight"
	_build_boarding_stairs(root, Vector3(3.2, 0.0, r + 0.25), cy - 1.1)


func _build_boarding_stairs(parent: Node3D, top_edge: Vector3, sill: float) -> void:
	## Mobile airstair: wheeled chassis, flight running out along +Z, top landing, canopy.
	var root := Node3D.new()
	root.name = "BoardingStairs"
	root.position = top_edge
	parent.add_child(root)
	var frame := Kit.paint(Color(0.9, 0.62, 0.08), 0.5, 0.5)
	var tread := Kit.pbr("metal_plate", 0.8, Color(0.55, 0.55, 0.57), false)
	var dark := Kit.paint(Color(0.06, 0.06, 0.07), 0.6, 0.3)
	var run := sill * 1.45
	var w := 1.2
	# Chassis + wheels
	Kit.box(root, Vector3(1.5, 0.35, run + 1.4), Vector3(0, 0.45, (run + 1.4) * 0.5), frame)
	for wz: float in [0.4, run + 0.9]:
		for s: float in [-0.8, 0.8]:
			Kit.cyl(root, 0.28, 0.28, 0.2, Vector3(s, 0.28, wz), dark, 14, Vector3(0, 0, PI * 0.5))
	# Top landing (meets the door sill)
	Kit.box(root, Vector3(w + 0.1, 0.1, 1.2), Vector3(0, sill, 0.6), tread)
	Kit.beam(root, Vector3(-0.6, 0.6, 1.1), Vector3(-0.6, sill, 1.1), 0.06, frame)
	Kit.beam(root, Vector3(0.6, 0.6, 1.1), Vector3(0.6, sill, 1.1), 0.06, frame)
	# Steps
	var n := 9
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var y := sill - t * (sill - 0.65)
		Kit.box(root, Vector3(w, 0.06, run / float(n) + 0.04), Vector3(0, y, 1.2 + t * run), tread)
	# Stringers + handrails
	for s: float in [-w * 0.5, w * 0.5]:
		Kit.beam(root, Vector3(s, sill, 1.2), Vector3(s, 0.6, 1.2 + run), 0.05, frame)
		Kit.beam(root, Vector3(s, sill + 1.0, 0.2), Vector3(s, sill + 1.0, 1.2), 0.03, frame)
		Kit.beam(root, Vector3(s, sill + 1.0, 1.2), Vector3(s, 1.6, 1.2 + run), 0.03, frame)
		for k in 4:
			var t := float(k) / 3.0
			var p := Vector3(s, sill - t * (sill - 0.6), 1.2 + t * run)
			Kit.beam(root, p, p + Vector3(0, 1.0, 0), 0.025, frame)
	# Canopy over the landing
	Kit.box(root, Vector3(w + 0.3, 0.06, 1.5), Vector3(0, sill + 2.15, 0.55), dark)
	for s: float in [-0.7, 0.7]:
		Kit.beam(root, Vector3(s, sill, 1.15), Vector3(s, sill + 2.12, 1.15), 0.03, frame)
	Kit.label(root, "BOARDING", Vector3(0, 0.45, run + 1.42), 70, Color(0.05, 0.05, 0.05), 0.0)


# ─── Shuttle terminal ───────────────────────────────────────────────

func _build_terminal() -> void:
	## A proper small passenger terminal on the +X side of the apron: steel frame, full-height
	## glazing to the pad and the +Z approach, deep canopy, seating, check-in, rooftop signs,
	## a departures board over the entrance, and a covered walkway to the airstair.
	var root := Node3D.new()
	root.name = "ShuttleTerminal"
	root.position = Vector3(14.3, 0, 0.9)   # Footprint x 12.0..16.6, z -3.2..5.0
	add_child(root)
	var W := 4.6    # along X
	var L := 8.2    # along Z
	var H := 3.4
	var steel := Kit.paint(Color(0.16, 0.17, 0.19), 0.4, 0.8)
	var panel := Kit.painted("container_side", Color(0.22, 0.24, 0.28), 0.5)
	var glass := Kit.glass(Color(0.55, 0.72, 0.85, 0.2))
	var warm := Kit.glow(Color(1.0, 0.86, 0.64), 1.5)
	# Plinth + floor
	Kit.box(root, Vector3(W + 1.6, 0.25, L + 1.4), Vector3(-0.4, 0.125, 0.4), Kit.pbr("brushed_concrete", 0.6, Color(0.62, 0.62, 0.6)))
	Kit.box(root, Vector3(W - 0.1, 0.04, L - 0.1), Vector3(0, 0.27, 0), Kit.pbr("metal_plate", 0.7, Color(0.45, 0.46, 0.48), false))
	# Solid back (+X) and -Z walls, lit interior back wall
	Kit.box(root, Vector3(0.15, H, L), Vector3(W * 0.5, 0.25 + H * 0.5, 0), panel)
	Kit.box(root, Vector3(W, H, 0.15), Vector3(0, 0.25 + H * 0.5, -L * 0.5), panel)
	Kit.box(root, Vector3(0.02, H - 0.6, L - 0.6), Vector3(W * 0.5 - 0.09, 0.25 + H * 0.5, 0), warm, Vector3.ZERO, false)
	# Glazing: full-height on the pad side (-X) and the approach end (+Z), with mullions
	Kit.box(root, Vector3(0.04, H - 0.1, L - 0.2), Vector3(-W * 0.5, 0.25 + H * 0.5, 0), glass, Vector3.ZERO, false)
	Kit.box(root, Vector3(W - 0.2, H - 1.6, 0.04), Vector3(0, 0.25 + (H - 1.6) * 0.5, L * 0.5), glass, Vector3.ZERO, false)
	var mull: Array = []
	for k in 6:
		var z := -L * 0.5 + float(k) * L / 5.0
		mull.append(Kit.beam_xform(Vector3(-W * 0.5, 0.25, z), Vector3(-W * 0.5, 0.25 + H, z), 0.05))
	for k in 4:
		var x := -W * 0.5 + float(k) * W / 3.0
		mull.append(Kit.beam_xform(Vector3(x, 0.25, L * 0.5), Vector3(x, 0.25 + H, L * 0.5), 0.05))
	mull.append(Kit.beam_xform(Vector3(-W * 0.5, 0.25 + 1.1, -L * 0.5), Vector3(-W * 0.5, 0.25 + 1.1, L * 0.5), 0.03))
	Kit.multi(root, Kit.unit_cylinder(6), mull, steel)
	# Upper +Z wall carries the departures board
	Kit.box(root, Vector3(W, 1.5, 0.15), Vector3(0, 0.25 + H - 0.75, L * 0.5), panel)
	var board := Kit.box(root, Vector3(3.6, 1.15, 0.08), Vector3(0, 0.25 + H - 0.72, L * 0.5 + 0.12), Kit.paint(Color(0.02, 0.02, 0.025), 0.4, 0.3))
	board.name = "DepartureBoard"
	var bz := L * 0.5 + 0.17
	Kit.label(root, "DEPARTURES", Vector3(0, 0.25 + H - 0.38, bz), 72, Color(0.55, 0.9, 1.0), 0.0, 1.8)
	Kit.label(root, "JOINED QINGS ONLY", Vector3(0, 0.25 + H - 0.72, bz), 64, Color(1.0, 0.75, 0.25), 0.0, 1.8)
	Kit.label(root, "BOARDING: PRESS E", Vector3(0, 0.25 + H - 1.06, bz), 64, Color(0.4, 1.0, 0.55), 0.0, 1.8)
	# Roof slab with a deep canopy over the pad-side glazing and the +Z entrance
	Kit.box(root, Vector3(W + 2.6, 0.22, L + 0.45), Vector3(-1.1, 0.25 + H + 0.11, 0.025), Kit.paint(Color(0.74, 0.75, 0.76), 0.45, 0.5))
	Kit.box(root, Vector3(W + 2.6, 0.05, 0.05), Vector3(-1.1, 0.25 + H - 0.02, L * 0.5 + 0.25), Kit.glow(_accent, 3.0), Vector3.ZERO, false)
	Kit.box(root, Vector3(0.05, 0.05, L + 0.45), Vector3(-W * 0.5 - 2.38, 0.25 + H - 0.02, 0.025), Kit.glow(_accent, 3.0), Vector3.ZERO, false)
	for z: float in [-L * 0.5 + 0.2, 0.0, L * 0.5 + 0.1]:
		Kit.beam(root, Vector3(-W * 0.5 - 2.2, 0.25, z), Vector3(-W * 0.5 - 2.2, 0.25 + H, z), 0.07, steel)
	# Rooftop signs: one to the pad (-X), one to the approach (+Z)
	Kit.box(root, Vector3(0.12, 0.9, 5.4), Vector3(-W * 0.5 + 0.3, 0.25 + H + 0.75, 0.2), steel)
	Kit.label(root, "SHUTTLE TERMINAL", Vector3(-W * 0.5 + 0.23, 0.25 + H + 0.75, 0.2), 120, Color(0.6, 0.93, 1.0), -PI * 0.5, 2.4)
	Kit.box(root, Vector3(4.3, 0.9, 0.12), Vector3(0.1, 0.25 + H + 0.75, L * 0.5 - 0.3), steel)
	Kit.label(root, "SHUTTLE TERMINAL", Vector3(0.1, 0.25 + H + 0.75, L * 0.5 - 0.23), 105, Color(0.6, 0.93, 1.0), 0.0, 2.4)
	# Interior: two benches with seated passengers, check-in counter with screen
	var seat := Kit.paint(Color(0.1, 0.35, 0.7), 0.5, 0.2)
	for bz2: float in [-2.2, 0.4]:
		Kit.box(root, Vector3(0.5, 0.06, 2.0), Vector3(-0.6, 0.72, bz2), seat)
		Kit.box(root, Vector3(0.08, 0.45, 2.0), Vector3(-0.38, 0.95, bz2), seat)
		Kit.beam(root, Vector3(-0.6, 0.27, bz2 - 0.8), Vector3(-0.6, 0.7, bz2 - 0.8), 0.03, steel)
		Kit.beam(root, Vector3(-0.6, 0.27, bz2 + 0.8), Vector3(-0.6, 0.7, bz2 + 0.8), 0.03, steel)
	Kit.box(root, Vector3(0.6, 1.05, 1.8), Vector3(1.4, 0.78, 2.4), steel)
	var scr := Kit.screen(3, Color(0.3, 0.85, 1.0), 77)
	Kit.box(root, Vector3(0.05, 0.42, 0.7), Vector3(1.2, 1.55, 2.4), steel)
	Kit.quad(root, Vector2(0.66, 0.38), Vector3(1.17, 1.55, 2.4), scr, Vector3(0, -PI * 0.5, 0))
	_ops_screens.append(scr)
	var inner := Kit.omni(root, Vector3(-1.6, 2.9, 1.0), Color(1.0, 0.86, 0.65), 1.6, 9.0)
	inner.name = "TerminalLight"
	Kit.light_pool(root, Vector3(-W * 0.5 - 1.2, 0.27, 0.6), 4.0, Color(1.0, 0.86, 0.65), 0.9)
	Kit.light_pool(root, Vector3(0, 0.27, L * 0.5 + 0.9), 3.0, Color(1.0, 0.86, 0.65), 0.8)
	# Downlights under the board so it reads from the approach
	Kit.box(root, Vector3(3.4, 0.06, 0.12), Vector3(0, 0.25 + H + 0.02, L * 0.5 + 0.32), Kit.glow(Color(1.0, 0.9, 0.75), 3.0), Vector3.ZERO, false)
	_terminal_seats = [root.position + Vector3(-0.75, 0.25, -2.6), root.position + Vector3(-0.75, 0.25, 0.9)]

	# Covered walkway from the terminal's pad-side door to the foot of the airstair
	var a := Vector3(11.6, 0, 3.4)
	var b := Vector3(4.2, 0, 5.7)
	var dir := (b - a).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var n := 4
	var posts: Array = []
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		for sd: float in [-1.15, 1.15]:
			var q := p + side * sd
			var gy := PAD_HEIGHT if Vector2(q.x, q.z).length() < PAD_RADIUS else 0.0
			posts.append(Kit.beam_xform(Vector3(q.x, gy, q.z), Vector3(q.x, 2.75, q.z), 0.045))
	Kit.multi(self, Kit.unit_cylinder(8), posts, steel)
	var len_ := a.distance_to(b)
	var roof := Kit.box(self, Vector3(2.7, 0.08, len_ + 0.4), (a + b) * 0.5 + Vector3(0, 2.8, 0), Kit.paint(Color(0.74, 0.75, 0.76), 0.45, 0.5))
	roof.basis = Basis.looking_at(dir, Vector3.UP)
	var strip := Kit.box(self, Vector3(0.06, 0.04, len_ + 0.4), (a + b) * 0.5 + Vector3(0, 2.74, 0), Kit.glow(_accent, 3.0), Vector3.ZERO, false)
	strip.basis = Basis.looking_at(dir, Vector3.UP)
	for i in n:
		var p := a.lerp(b, (float(i) + 0.5) / float(n))
		Kit.light_pool(self, Vector3(p.x, PAD_HEIGHT + 0.06 if Vector2(p.x, p.z).length() < PAD_RADIUS else 0.08, p.z), 1.8, Color(1.0, 0.9, 0.75), 0.7)
	# Queue posts and belts along the walkway
	var post := Kit.paint(Color(0.75, 0.76, 0.78), 0.25, 1.0)
	var belt := Kit.paint(Color(0.1, 0.25, 0.65), 0.6, 0.0)
	for sd: float in [-0.75, 0.75]:
		var prev := Vector3.INF
		for k in 4:
			var q := b - dir * (0.6 + float(k) * 1.4) + side * sd
			var gy := PAD_HEIGHT if Vector2(q.x, q.z).length() < PAD_RADIUS else 0.0
			q.y = gy
			Kit.cyl(self, 0.035, 0.035, 0.95, q + Vector3(0, 0.47, 0), post, 8)
			Kit.cyl(self, 0.15, 0.17, 0.04, q + Vector3(0, 0.02, 0), post, 12)
			if prev != Vector3.INF:
				Kit.beam(self, prev + Vector3(0, 0.88, 0), q + Vector3(0, 0.88, 0), 0.022, belt, 6, false)
			prev = q
	_queue_line = [b, dir]


func _build_edge_lights() -> void:
	## Amber edge lights along the apron's hazard border (every 2 m) and a cyan glow on the
	## pad ring: the front and left of the pad read at night.
	var xs: Array = []
	var hx := APRON_HALF.x - 0.45
	var hz := APRON_HALF.y - 0.45
	for i in int(hx * 2.0 / 2.0) + 1:
		var x := -hx + float(i) * 2.0
		for z: float in [-hz, hz]:
			xs.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.07, 0.09)), Vector3(x, 0.1, z)))
	for i in int(hz * 2.0 / 2.0) + 1:
		var z := -hz + float(i) * 2.0
		for x: float in [-hx, hx]:
			xs.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.07, 0.09)), Vector3(x, 0.1, z)))
	Kit.multi(self, Kit.unit_cylinder(8), xs, Kit.glow(Color(1.0, 0.66, 0.12), 3.0), false)
	for k in 8:
		var a := float(k) * TAU / 8.0
		Kit.light_pool(self, Vector3(cos(a), 0, sin(a)) * (PAD_RADIUS + 0.6) + Vector3(0, 0.08, 0), 2.4, _accent, 0.8)


func _build_luggage_train() -> void:
	## Baggage tug + two carts of suitcases parked on the pad beside the shuttle.
	var root := Node3D.new()
	root.name = "LuggageTrain"
	root.position = Vector3(-3.4, PAD_HEIGHT + 0.02, 5.5)
	root.rotation.y = 0.12
	add_child(root)
	var yellow := Kit.paint(Color(0.92, 0.62, 0.06), 0.55, 0.3)
	var dark := Kit.paint(Color(0.05, 0.05, 0.055), 0.6, 0.2)
	var steel := Kit.paint(Color(0.55, 0.56, 0.58), 0.35, 0.9)
	# Tug
	Kit.box(root, Vector3(1.3, 0.55, 0.95), Vector3(-2.1, 0.45, 0), yellow)
	Kit.box(root, Vector3(0.5, 0.5, 0.9), Vector3(-1.75, 0.95, 0), Kit.glass(Color(0.4, 0.55, 0.65, 0.35)))
	Kit.box(root, Vector3(0.55, 0.05, 0.95), Vector3(-1.75, 1.22, 0), yellow)
	for wx: float in [-2.55, -1.65]:
		for sz: float in [-0.48, 0.48]:
			Kit.cyl(root, 0.2, 0.2, 0.14, Vector3(wx, 0.2, sz), dark, 12, Vector3(PI * 0.5, 0, 0))
	Kit.box(root, Vector3(0.06, 0.08, 0.3), Vector3(-2.77, 0.55, 0.3), Kit.glow(Color(1.0, 0.9, 0.7), 4.0), Vector3.ZERO, false)
	Kit.box(root, Vector3(0.06, 0.08, 0.3), Vector3(-2.77, 0.55, -0.3), Kit.glow(Color(1.0, 0.9, 0.7), 4.0), Vector3.ZERO, false)
	# Carts with bags
	var bag_cols := [Color(0.55, 0.1, 0.1), Color(0.1, 0.25, 0.55), Color(0.15, 0.15, 0.16), Color(0.6, 0.45, 0.2), Color(0.2, 0.45, 0.3), Color(0.7, 0.7, 0.72)]
	for c in 2:
		var cx := -0.6 + float(c) * 1.55
		Kit.box(root, Vector3(1.35, 0.06, 0.9), Vector3(cx, 0.45, 0), steel)
		for sx: float in [-0.65, 0.65]:
			Kit.beam(root, Vector3(cx + sx, 0.45, -0.43), Vector3(cx + sx, 0.95, -0.43), 0.018, steel)
			Kit.beam(root, Vector3(cx + sx, 0.45, 0.43), Vector3(cx + sx, 0.95, 0.43), 0.018, steel)
			for sz: float in [-0.35, 0.35]:
				Kit.cyl(root, 0.11, 0.11, 0.08, Vector3(cx + sx * 0.8, 0.13, sz), dark, 10, Vector3(PI * 0.5, 0, 0))
		Kit.beam(root, Vector3(cx - 0.75, 0.35, 0), Vector3(cx - 0.95, 0.35, 0), 0.025, steel)
		for k in 5:
			var bsz := Vector3(_rng.randf_range(0.35, 0.55), _rng.randf_range(0.22, 0.35), _rng.randf_range(0.5, 0.7))
			var bp := Vector3(cx - 0.35 + float(k % 3) * 0.35, 0.48 + bsz.y * 0.5 + float(k / 3) * 0.3, _rng.randf_range(-0.12, 0.12))
			Kit.box(root, bsz, bp, Kit.paint(bag_cols[(k + c * 2) % bag_cols.size()], 0.6, 0.1), Vector3(0, _rng.randf_range(-0.3, 0.3), 0))


# ─── Fuel farm ──────────────────────────────────────────────────────

func _build_fuel_farm() -> void:
	## Two horizontal propellant tanks on saddles behind a low bund wall, pump skid, hose run.
	var root := Node3D.new()
	root.name = "FuelFarm"
	root.position = Vector3(-13.6, 0, -2.6)
	add_child(root)
	var tank := Kit.paint(Color(0.82, 0.82, 0.8), 0.4, 0.4)
	var steel := Kit.paint(Color(0.28, 0.29, 0.3), 0.45, 0.85)
	var concrete := Kit.pbr("brushed_concrete", 0.6, Color(0.6, 0.6, 0.58))
	# Bund wall
	Kit.box(root, Vector3(5.8, 0.15, 8.6), Vector3(0, 0.05, 0), concrete)
	for s: float in [-1.0, 1.0]:
		Kit.box(root, Vector3(5.8, 0.55, 0.2), Vector3(0, 0.27, 4.2 * s), concrete)
		Kit.box(root, Vector3(0.2, 0.55, 8.6), Vector3(2.8 * s, 0.27, 0), concrete)
	for t in 2:
		var x := -1.3 + float(t) * 2.6
		# Saddles
		for z: float in [-2.2, 2.2]:
			Kit.box(root, Vector3(1.8, 0.9, 0.35), Vector3(x, 0.55, z), concrete)
		Kit.cyl(root, 1.15, 1.15, 6.2, Vector3(x, 1.95, 0), tank, 24, Vector3(PI * 0.5, 0, 0))
		for z: float in [-3.1, 3.1]:
			Kit.ball(root, 1.15, Vector3(x, 1.95, z), tank, 20).scale = Vector3(1, 1, 0.35)
		# Bands
		for z: float in [-1.6, 0.0, 1.6]:
			Kit.cyl(root, 1.18, 1.18, 0.1, Vector3(x, 1.95, z), steel, 24, Vector3(PI * 0.5, 0, 0), false)
		Kit.cyl(root, 1.17, 1.17, 0.5, Vector3(x, 1.95, -2.7), Kit.hazard(3.0, Color(0.85, 0.12, 0.08), Color(0.9, 0.9, 0.88)), 24, Vector3(PI * 0.5, 0, 0), false)
		# Sight gauge (fuel level = CHARGE) on the tank end facing +Z
		var g := Kit.screen(4, Color(0.3, 1.0, 0.5), 60 + t)
		Kit.box(root, Vector3(0.22, 1.5, 0.08), Vector3(x + 0.55, 1.95, 3.45), steel)
		Kit.quad(root, Vector2(0.15, 1.38), Vector3(x + 0.55, 1.95, 3.5), g)
		_fuel_gauges.append(g)
		# Top manway, vent and walkway rail
		Kit.cyl(root, 0.3, 0.3, 0.2, Vector3(x, 3.15, 0.8), steel, 12)
		Kit.cyl(root, 0.05, 0.05, 0.8, Vector3(x, 3.4, -1.2), steel, 8)
		Kit.label(root, "LOX" if t == 0 else "CH4", Vector3(x, 1.95, 3.46), 140, Color(0.1, 0.1, 0.12), 0.0)
	Kit.label(root, "PROPELLANT - NO NAKED FLAME", Vector3(0, 0.38, 4.32), 60, Color(0.95, 0.85, 0.2), 0.0, 0.2)
	# Pump skid with piping
	var skid := Vector3(4.1, 0, 2.0)
	Kit.box(root, Vector3(1.6, 0.15, 1.2), skid + Vector3(0, 0.08, 0), steel)
	Kit.box(root, Vector3(0.9, 0.8, 0.7), skid + Vector3(-0.2, 0.55, 0), Kit.paint(Color(0.12, 0.3, 0.55), 0.5, 0.5))
	Kit.cyl(root, 0.18, 0.18, 0.7, skid + Vector3(0.5, 0.45, 0), steel, 12, Vector3(0, 0, PI * 0.5))
	Kit.box(root, Vector3(0.1, 0.1, 0.03), skid + Vector3(-0.2, 0.8, 0.36), Kit.glow(Color(0.2, 1.0, 0.4), 3.0), Vector3.ZERO, false)
	var pipe := Kit.paint(Color(0.85, 0.65, 0.1), 0.45, 0.6)
	for t in 2:
		var x := -1.3 + float(t) * 2.6
		var pts: Array[Vector3] = [Vector3(x, 1.0, 3.0), Vector3(x, 0.35, 3.0), Vector3(x, 0.35, 3.6), Vector3(3.3, 0.35, 3.6), Vector3(3.3, 0.35, 2.0), skid + Vector3(-0.65, 0.4, 0)]
		Kit.tube(root, pts, 0.07, pipe)
	# Fuel hose snaking across the apron toward the lander
	var hose := Kit.paint(Color(0.05, 0.05, 0.055), 0.6, 0.0)
	var hp: Array[Vector3] = [skid + Vector3(0.85, 0.45, 0), skid + Vector3(1.3, 0.08, 0.2), Vector3(6.4, 0.08, 2.9), Vector3(7.3, 0.08, 2.1),
		Vector3(8.2, PAD_HEIGHT + 0.06, 3.0), Vector3(9.4, PAD_HEIGHT + 0.06, 3.4), Vector3(10.4, PAD_HEIGHT + 0.25, 3.1)]
	Kit.tube(root, hp, 0.06, hose)
	Kit.light_pool(root, Vector3(0, 0.1, 4.8), 3.2, Color(1.0, 0.8, 0.5), 0.5)


# ─── Control hut ────────────────────────────────────────────────────

func _build_control_hut() -> void:
	var hut := Kit.cabin(self, Vector3(13.4, 0, -6.6), 0.0, Vector3(5.2, 2.6, 2.4), "PAD CONTROL")
	hut.name = "ControlHut"
	# Interior glow spills through the window
	var inner := Kit.omni(hut, Vector3(1.2, 1.6, 1.9), Color(1.0, 0.85, 0.62), 1.2, 6.0)
	inner.name = "HutLight"
	# Ops screens on a wall bracket beside the door (CHARGE / HYPO / EPI + radar)
	var bracket := Kit.paint(Color(0.08, 0.08, 0.09), 0.5, 0.6)
	for i in 2:
		var x := -0.3 + float(i) * 0.95
		Kit.box(hut, Vector3(0.85, 0.55, 0.06), Vector3(x, 1.6 + 0.2, 1.25), bracket)
		var scr := Kit.screen(0 if i == 0 else 2, Color(0.3, 0.85, 1.0), 70 + i)
		Kit.quad(hut, Vector2(0.78, 0.48), Vector3(x, 1.6 + 0.2, 1.285), scr)
		_ops_screens.append(scr)
	# Rotating amber beacon on a roof mast
	var mast_top := Vector3(-1.6, 0.2 + 2.6 + 1.4, -0.6)
	Kit.cyl(hut, 0.05, 0.06, 1.4, mast_top - Vector3(0, 0.7, 0), bracket, 8)
	Kit.cyl(hut, 0.16, 0.16, 0.1, mast_top + Vector3(0, 0.05, 0), bracket, 12)
	_beacon_mat = Kit.glow(Color(1.0, 0.6, 0.1), 5.0, false)
	Kit.cyl(hut, 0.12, 0.14, 0.22, mast_top + Vector3(0, 0.21, 0), _beacon_mat, 12, Vector3.ZERO, false)
	_beacon_pivot = Node3D.new()
	_beacon_pivot.position = mast_top + Vector3(0, 0.21, 0)
	hut.add_child(_beacon_pivot)
	Kit.light_cone(_beacon_pivot, Vector3.ZERO, Vector3(1, -0.05, 0), 5.0, 0.08, 0.55, Color(1.0, 0.6, 0.15), 0.8)
	_beacon_light = Kit.omni(hut, mast_top + Vector3(0, 0.4, 0), Color(1.0, 0.6, 0.15), 1.0, 9.0)
	# Antenna whip + small dish on the roof
	Kit.cyl(hut, 0.02, 0.03, 2.2, Vector3(2.1, 0.2 + 2.6 + 1.1, -0.8), bracket, 6)
	var dish := MeshInstance3D.new()
	dish.mesh = Kit.dish_mesh(0.5, 0.16, 16, 4)
	dish.material_override = Kit.paint(Color(0.85, 0.85, 0.83), 0.4, 0.3)
	dish.position = Vector3(0.3, 0.2 + 2.6 + 0.7, -0.7)
	dish.rotation = Vector3(-0.9, 0.4, 0)
	hut.add_child(dish)
	Kit.cyl(hut, 0.04, 0.04, 0.6, Vector3(0.3, 0.2 + 2.6 + 0.35, -0.7), bracket, 6)
	# Outside: tool cart, gas bottles, a bench of barrels
	Kit.prop(self, "tool_cart", Vector3(10.0, 0, -4.6), -0.9)
	Kit.prop(self, "small_lpg_tank", Vector3(16.2, 0, -4.9), 0.3)
	Kit.prop(self, "small_lpg_tank", Vector3(16.6, 0, -5.2), 1.3)


# ─── Cargo ──────────────────────────────────────────────────────────

func _build_cargo() -> void:
	# Shipping container (corrugated container texture) at the back-left
	var cont := Node3D.new()
	cont.name = "CargoContainer"
	cont.position = Vector3(-11.8, 0, 8.4)
	cont.rotation.y = 0.04
	add_child(cont)
	var ribbed := Kit.painted("container_side", Color(0.62, 0.24, 0.1), 0.4)
	Kit.box(cont, Vector3(6.06, 2.59, 2.44), Vector3(0, 1.295, 0), ribbed)
	var frame := Kit.paint(Color(0.35, 0.16, 0.08), 0.6, 0.6)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Kit.box(cont, Vector3(0.16, 2.6, 0.16), Vector3(sx * 2.96, 1.3, sz * 1.15), frame, Vector3.ZERO, false)
			Kit.box(cont, Vector3(0.18, 0.12, 0.18), Vector3(sx * 2.96, 0.06, sz * 1.15), Kit.paint(Color(0.2, 0.2, 0.2), 0.5, 0.8), Vector3.ZERO, false)
	# Doors at the +X end with locking bars
	for k in 4:
		Kit.beam(cont, Vector3(3.04, 0.15, -0.9 + float(k) * 0.6), Vector3(3.04, 2.45, -0.9 + float(k) * 0.6), 0.025, Kit.paint(Color(0.6, 0.6, 0.6), 0.4, 1.0), 6, false)
	Kit.label(cont, "DYSN 369024 7", Vector3(0, 2.1, 1.235), 90, Color(0.95, 0.95, 0.92), 0.0)
	Kit.label(cont, "AFFECTION LOGISTICS", Vector3(0, 1.5, 1.235), 70, Color(0.95, 0.95, 0.92), 0.0)
	# Pallets with crates in the front-right cargo bay
	var pallets := [Vector3(-7.4, 0, 9.5), Vector3(-5.8, 0, 9.7), Vector3(-4.2, 0, 9.5), Vector3(-15.6, 0, 4.2)]
	var wood := Kit.paint(Color(0.55, 0.42, 0.28), 0.85, 0.0)
	var slats: Array = []
	for i in pallets.size():
		var p: Vector3 = pallets[i]
		var yaw := _rng.randf_range(-0.12, 0.12)
		var b := Basis(Vector3.UP, yaw)
		for k in 3:
			slats.append(Transform3D(b * Basis.from_scale(Vector3(1.2, 0.1, 0.1)), p + b * Vector3(0, 0.05, -0.45 + float(k) * 0.45)))
		for k in 7:
			slats.append(Transform3D(b * Basis.from_scale(Vector3(0.1, 0.03, 1.0)), p + b * Vector3(-0.54 + float(k) * 0.18, 0.115, 0)))
		match i:
			0:
				Kit.prop(self, "wooden_crate_02", p + Vector3(-0.25, 0.13, 0), yaw)
				Kit.prop(self, "wooden_crate_02", p + Vector3(0.3, 0.13, 0), yaw)
				Kit.prop(self, "wooden_crate_02", p + Vector3(0.0, 0.6, 0), yaw + 0.1)
			1:
				Kit.prop(self, "old_military_crate", p + Vector3(0, 0.13, 0), yaw + PI * 0.5, 0.62)
				Kit.prop(self, "old_military_crate", p + Vector3(0, 0.32, 0), yaw + PI * 0.5 + 0.05, 0.62)
			2:
				var drums: Array = []
				for d in 4:
					drums.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p + Vector3(-0.3 + float(d % 2) * 0.62, 0.13, -0.3 + float(d / 2) * 0.62)))
				Kit.prop_multi(self, "barrel_03", drums)
			3:
				Kit.prop(self, "portable_generator", p + Vector3(0, 0.13, 0), yaw + 0.4)
	Kit.multi(self, Kit.unit_box(), slats, wood)
	# Loose gas bottles by the container
	for i in 3:
		Kit.prop(self, "small_lpg_tank", Vector3(-16.2 + float(i) * 0.45, 0, 10.3), _rng.randf() * TAU)
	# Concrete barriers marking the cargo bay edge
	Kit.prop(self, "concrete_road_barrier", Vector3(-2.6, 0, 9.9), PI * 0.5 + 0.05)
	Kit.sign_board(self, "CARGO HOLD AREA", Vector3(-5.8, 1.1, 10.75), 0.0, Vector2(1.6, 0.4), Color(0.92, 0.7, 0.08), Color(0.05, 0.05, 0.05), 40)
	Kit.beam(self, Vector3(-6.4, 0, 10.7), Vector3(-6.4, 1.3, 10.7), 0.03, Kit.paint(Color(0.5, 0.5, 0.5), 0.4, 0.9))
	Kit.beam(self, Vector3(-5.2, 0, 10.7), Vector3(-5.2, 1.3, 10.7), 0.03, Kit.paint(Color(0.5, 0.5, 0.5), 0.4, 0.9))


# ─── Masts & windsock ───────────────────────────────────────────────

func _build_masts_and_windsock() -> void:
	# Three masts: back-left, front-left (lights the cargo bay + front of the pad), back-right
	Kit.flood_mast(self, Vector3(-16.2, 0, -9.8), 8.0, Vector3(-1.0, 0, -0.5), Color(1.0, 0.92, 0.8), 3, true, 3.0)
	Kit.flood_mast(self, Vector3(-16.2, 0, 5.4), 8.0, Vector3(-3.0, 0, 5.0), Color(1.0, 0.92, 0.8), 3, true, 3.0)
	Kit.flood_mast(self, Vector3(16.4, 0, -9.4), 8.0, Vector3(4.0, 0, -2.0), Color(1.0, 0.92, 0.8), 3, true, 3.0)
	Kit.light_pool(self, Vector3(-6.0, 0.08, 6.0), 7.0, Color(1.0, 0.9, 0.75), 0.5)
	Kit.light_pool(self, Vector3(-6.0, 0.08, -3.6), 7.0, Color(1.0, 0.9, 0.75), 0.45)
	Kit.light_pool(self, Vector3(6.0, 0.08, -3.0), 7.0, Color(1.0, 0.9, 0.75), 0.45)
	# Windsock on a pole beside the control hut
	var pole := Vector3(9.9, 0, -9.9)
	var pole_mat := Kit.hazard(2.0, Color(0.9, 0.15, 0.08), Color(0.92, 0.92, 0.9))
	Kit.box(self, Vector3(0.6, 0.3, 0.6), pole + Vector3(0, 0.1, 0), Kit.pbr("brushed_concrete", 0.8, Color(0.6, 0.6, 0.6)))
	Kit.cyl(self, 0.05, 0.07, 5.0, pole + Vector3(0, 2.75, 0), pole_mat, 8)
	_windsock = Node3D.new()
	_windsock.position = pole + Vector3(0, 5.1, 0)
	add_child(_windsock)
	Kit.ring(_windsock, 0.3, 0.02, Vector3(0.05, 0, 0), Kit.paint(Color(0.3, 0.3, 0.3), 0.4, 0.9), Vector3(0, 0, PI * 0.5), 16)
	var orange := Kit.paint(Color(1.0, 0.38, 0.05), 0.8, 0.0)
	var white := Kit.paint(Color(0.92, 0.92, 0.9), 0.8, 0.0)
	for k in 5:
		var r0 := 0.3 - float(k) * 0.04
		var seg := Kit.cyl(_windsock, r0 - 0.04, r0, 0.42, Vector3(0.26 + float(k) * 0.42, -float(k) * 0.03, 0), orange if k % 2 == 0 else white, 12, Vector3(0, 0, PI * 0.5), false)
		seg.name = "Sock_%d" % k
	Kit.ball(self, 0.08, pole + Vector3(0, 5.3, 0), Kit.glow(Color(1.0, 0.1, 0.05), 4.0))


func _build_crew(seed_value: int) -> void:
	## Passengers queueing at the airstair, one boarding, two waiting inside the terminal,
	## a marshal, a fueller and a baggage handler.
	var foot: Vector3 = _queue_line[0] if _queue_line.size() == 2 else Vector3(4.2, 0, 5.7)
	var dir: Vector3 = _queue_line[1] if _queue_line.size() == 2 else Vector3(1, 0, 0)
	for k in 3:
		var q := foot - dir * (0.7 + float(k) * 0.95)
		q.y = PAD_HEIGHT if Vector2(q.x, q.z).length() < PAD_RADIUS else 0.0
		Kit.npc(self, seed_value + 840 + k, [], dir, Callable(), q)
	var stair_foot := Vector3(2.75, PAD_HEIGHT, 5.9)
	Kit.npc(self, seed_value + 811, [
		foot + Vector3(0, PAD_HEIGHT, 0), stair_foot, Vector3(2.75, PAD_HEIGHT + 1.65, 1.95), stair_foot])
	for k in _terminal_seats.size():
		Kit.npc(self, seed_value + 850 + k, [], Vector3(-1, 0, 0), Callable(), _terminal_seats[k], "sit")
	Kit.npc(self, seed_value + 833, [], Vector3(-1, 0, 0.3), Callable(), Vector3(4.6, PAD_HEIGHT, 7.0))
	Kit.npc(self, seed_value + 822, [], Vector3(-0.3, 0, -1), Callable(), Vector3(-9.3, 0, 0.6))
	Kit.npc(self, seed_value + 866, [], Vector3(1, 0, -0.2), Callable(), Vector3(-1.7, PAD_HEIGHT, 6.2))
