class_name FairSite
extends Node3D
## The Affection Fair in a v2 territory. Sits on its own deck (the Julia terrain is
## never flattened), sized by the territory's Development tier, and sells ride tickets
## through ArcadePay: 1 Ⓐ AFFECTION.transfer to this territory's QING, simulated,
## signed, receipt-verified, then the ride starts. No wallet → a free preview ride
## that is labelled as such and records nothing.
##
## Development tier (0..5) → fair tier: Wild/Outpost = surveyed lot, Settlement =
## night market + carousel, Town = + wheel and drop tower, City/Capital = grand fair.

const AT := Vector2(0.0, 112.0)   ## preferred spot (relative to the Core); the search starts here
const HALF := 40.0                ## the fair builds within ±38 m
const RADIUS := 42.0              ## round terrace that carries it
const KEEP_CLEAR := [Vector2(0, 0), Vector2(26, 18), Vector2(-26, 18), Vector2(0, -11.5), Vector2(0, 16)]  ## Core, arcade, monolith, plinth, arrival
const CLEAR_M := 62.0             ## how far the fair's centre stays from those

var _qing := ""
var _hud: Node
var _player: CharacterBody3D
var _fair: Node3D
var _tier := -1
var _focus: RideBase = null
var _riding: RideBase = null
var _paying := false
var _ground_mat: Material = null  ## the terrain's own material (colours by world XZ) so the terrace continues the land


static func fair_tier(dev_tier: int) -> int:
	return [0, 0, 1, 2, 3, 3][clampi(dev_tier, 0, 5)]


## Finds where the fair belongs on this territory's land: every sample of the round
## footprint on the plateau (height ≥ land_floor, relative to the Core), the flattest
## such spot, clear of the Core's landmarks, preferring the south side near arrival.
## Pure and deterministic (same terrain → same spot). Returns {ok, at, top, low, land}.
static func find_site(height_fn: Callable, land_floor: float = -2.5) -> Dictionary:
	var best := {"ok": false, "score": INF}
	var fallback := {"ok": false, "land": -1.0}
	for gx in range(-12, 13):
		for gz in range(-12, 13):
			var c := Vector2(gx * 16.0, gz * 16.0)
			if c.length() > 205.0:
				continue
			var clear := true
			for k in KEEP_CLEAR:
				if c.distance_to(k) < CLEAR_M:
					clear = false
					break
			if not clear:
				continue
			var top := -INF
			var low := INF
			var on_land := 0
			var n := 0
			for ring in [0.0, 0.5, 1.0]:
				var steps := 1 if ring == 0.0 else 12
				for i in steps:
					var a := TAU * i / steps
					var p: Vector2 = c + Vector2(cos(a), sin(a)) * RADIUS * ring
					var h: float = height_fn.call(p.x, p.y)
					top = maxf(top, h)
					low = minf(low, h)
					n += 1
					if h >= land_floor:
						on_land += 1
			var land := float(on_land) / n
			if land > fallback["land"]:
				fallback = {"ok": false, "at": c, "top": top, "low": low, "land": land}
			if on_land < n:
				continue
			# Flat, close to arrival, south side preferred
			var score := (top - low) * 4.0 + c.distance_to(AT) * 0.05
			if score < best["score"]:
				best = {"ok": true, "at": c, "top": top, "low": low, "land": 1.0, "score": score}
	return best if best["ok"] else fallback


func setup(qing: String, hud: Node, player: CharacterBody3D, height_fn: Callable, tint: Color = Color(0.6, 0.8, 1.0), ground_mat: Material = null) -> void:
	_ground_mat = ground_mat
	_qing = qing.to_lower()
	_hud = hud
	_player = player
	var site := find_site(height_fn)
	var at: Vector2 = site.get("at", AT)
	position = Vector3(at.x, 0.0, at.y)
	# Terrace top just above the highest ground in the footprint; on the plateau the
	# relief is ~3 m, so the sloped rim stays low and reads as built ground.
	position.y = float(site.get("top", 0.0)) + 0.12
	_build_terrace(position.y - float(site.get("low", position.y)) + 1.5, tint)


func set_dev_tier(dev_tier: int) -> void:
	var t := fair_tier(dev_tier)
	if t == _tier or _riding != null:
		return
	_tier = t
	if _fair:
		_fair.queue_free()
	_focus = null
	_fair = Funfair.new()
	_fair.name = "Funfair"
	add_child(_fair)
	_fair.initialize(_qing.hex_to_int() if _qing.length() < 16 else _qing.right(12).hex_to_int(), t)
	if t == 0 and _fair.has_method("set_unlock_hint"):
		_fair.set_unlock_hint("Opens at Settlement development · grow this QING's Hypobar")
	if t > 0 and _hud:
		var names := ["", "Night Market", "Fairground", "Grand Fair"]
		var dir := _compass(Vector2(position.x, position.z))
		_hud.ticker("AFFECTION FAIR · %s open · %d m %s of the Core · rides %s each" % [
			names[t], int(Vector2(position.x, position.z).length()), dir, ArcadePay.fee_text()], DeepFieldTheme.ICE, 30.0)
	print("[Fair] development %d → fair tier %d · %d rides · at %s" % [dev_tier, t, _fair.get_rides().size(), str(Vector2(position.x, position.z))])
	for r in _fair.get_rides():
		r.booth_focus.connect(_on_focus)
		r.ride_caption.connect(func(text: String) -> void:
			if text != "":
				_hud.ticker(text, DeepFieldTheme.ICE, 3.0))
		r.ride_finished.connect(_on_finished)


static func _compass(v: Vector2) -> String:
	## Map directions with -Z as north (the way you face on arrival).
	var a := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(a / 45.0)) % 8]


func _on_focus(ride: RideBase, inside: bool) -> void:
	if inside and _riding == null:
		_focus = ride
		var paid := Wallet.address != ""
		_hud.show_prompt("%s  %s · %s" % [ControlsHelp.key_of("interact"), ride.item.get("name", "Ride"),
			("%s to this QING" % ArcadePay.fee_text()) if paid else "free preview (no wallet)"])
	elif _focus == ride:
		_focus = null
		_hud.hide_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _focus == null or _riding != null or _paying or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	_hud.hide_prompt()
	var ride := _focus
	if Wallet.address == "":
		_start(ride, "PREVIEW RIDE · nothing paid")
		return
	_paying = true
	_hud.ticker("Ticket: approve %s to this QING in your wallet…" % ArcadePay.fee_text(), DeepFieldTheme.ICE, 20.0)
	var res: Dictionary = await ArcadePay.pay(_qing, "Affection Fair · %s" % ride.item.get("name", "ride"))
	_paying = false
	if not res.get("ok", false):
		_hud.ticker("Ticket not bought: %s" % res.get("message", "cancelled"), Color("#ff8fa0"), 10.0)
		return
	_start(ride, "TICKET VERIFIED · block %d" % int(res.get("block", 0)))


func _start(ride: RideBase, note: String) -> void:
	_riding = ride
	_focus = null
	_hud.ticker(note, DeepFieldTheme.ICE, 6.0)
	ride.start_ride(_player)


func _on_finished(ride: RideBase) -> void:
	if ride == _riding:
		_riding = null


func _build_terrace(depth: float, tint: Color) -> void:
	## A round regolith terrace (same Poly Haven moon_dusted_02 as the terrain shader,
	## tinted with the territory colour) whose sides slope out into the ground like an
	## embankment, plus a faint ring of light at the rim. No square slab.
	var rd := "res://assets/textures/polyhaven/moon_dusted_02/moon_dusted_02_"
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(rd + "diff_1k.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load(rd + "nor_gl_1k.jpg")
	mat.roughness_texture = load(rd + "rough_1k.jpg")
	mat.albedo_color = Color(0.55, 0.55, 0.58).lerp(tint, 0.18)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	var slope := clampf(depth * 2.2, 3.0, 14.0)
	var m := CylinderMesh.new()
	m.top_radius = RADIUS
	m.bottom_radius = RADIUS + slope
	m.height = depth
	m.radial_segments = 64
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	# Prefer the terrain's own shader: it colours by world position, so the terrace
	# carries the territory's contours and glow straight across instead of a flat disc.
	mi.material_override = _ground_mat if _ground_mat else mat
	mi.position = Vector3(0, -depth * 0.5 - 0.02, 0)
	add_child(mi)
	# Walkable: flat top + the sloped sides (players can walk straight up the rim)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = RADIUS
	sh.height = depth
	cs.shape = sh
	cs.position = mi.position
	body.add_child(cs)
	var rim := CollisionShape3D.new()
	rim.shape = m.create_convex_shape()
	rim.position = mi.position
	body.add_child(rim)
	add_child(body)
	# Rim light: a thin emissive ring in the territory colour
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = tint
	glow.emission_enabled = true
	glow.emission = tint
	glow.emission_energy_multiplier = 1.4
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS - 0.12
	ring.outer_radius = RADIUS + 0.12
	ring.rings = 96
	var ri := MeshInstance3D.new()
	ri.mesh = ring
	ri.material_override = glow
	ri.scale = Vector3(1.0, 0.25, 1.0)
	ri.position.y = 0.03
	add_child(ri)
