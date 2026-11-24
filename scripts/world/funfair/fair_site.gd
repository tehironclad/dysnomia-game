class_name FairSite
extends Node3D
## The Affection Fair in a v2 territory. Sits on its own deck (the Julia terrain is
## never flattened), sized by the territory's Development tier, and sells ride tickets
## through ArcadePay: 1 Ⓐ AFFECTION.transfer to this territory's QING, simulated,
## signed, receipt-verified, then the ride starts. No wallet → a free preview ride
## that is labelled as such and records nothing. Use works at a ride's booth or
## anywhere near the ride; the midway stalls and the high striker are games
## (MidwayGame / MidwayOverlay) sold the same way, seeded by the ticket's tx hash.
##
## Development tier (0..5) → fair tier: Wild/Outpost = surveyed lot, Settlement =
## night market + carousel, Town = + wheel and drop tower, City/Capital = grand fair.

const AT := Vector2(0.0, 112.0 * TerritoryLayout.SCALE)   ## preferred spot (relative to the Core), ≈158 m south
const REACH := 205.0 * TerritoryLayout.SCALE  ## the search covers centres this far from the Core (≈290 m)
const HALF := 40.0                ## the fair builds within ±38 m
const RADIUS := 42.0              ## round terrace that carries it
const KEEP_CLEAR := [Vector2(0, 0), Vector2(26, 18), Vector2(-26, 18), Vector2(0, -11.5), Vector2(0, 16)]  ## Core, arcade, monolith, plinth, arrival
const CLEAR_M := 62.0             ## how far the fair's centre stays from those
const MIN_CORE := 78.0 * TerritoryLayout.SCALE  ## and from the Core itself (≈110 m): out beyond the Core's ring road

var _qing := ""
var _hud: Node
var _player: CharacterBody3D
var _fair: Node3D
var _tier := -1
var _focus: RideBase = null
var _riding: RideBase = null
var _paying := false
var _focus_key := ""   ## "ride:<id>" / "game:<id>" / "" (the prompt shown)
var _focus_game := ""
var _game: MidwayOverlay = null
var _height_fn: Callable   ## ground height at (x, z) relative to the Core (parent), minus the Core's y
var _voyage: Node = null
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
	var g := TerritoryLayout.grid_steps(16.0, REACH)
	for gx in range(-g, g + 1):
		for gz in range(-g, g + 1):
			var c := Vector2(gx * 16.0, gz * 16.0)
			if c.length() > REACH or c.length() < MIN_CORE or not TerritoryLayout.inside(c, RADIUS):
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
	_height_fn = height_fn
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
	_focus_game = ""
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
	_focus_key = ""
	for r in _fair.get_rides():
		r.ride_caption.connect(func(text: String) -> void:
			if text != "":
				_hud.ticker(text, DeepFieldTheme.ICE, 3.0))
		r.ride_finished.connect(_on_finished)


static func _compass(v: Vector2) -> String:
	## Map directions with -Z as north (the way you face on arrival).
	var a := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(a / 45.0)) % 8]


## What Use would do here: the nearest ride (its booth, or anywhere near the ride
## itself) or midway game in reach. Checked by distance every frame, so it works
## however the player arrived (walking, landing, set down by a ride).
func _process(_delta: float) -> void:
	if _fair == null or _player == null or _riding != null or _paying or _game != null:
		return
	var p := _player.global_position
	var best := INF
	var f := {}
	for r in _fair.get_rides():
		var b: Vector3 = r.to_global(r.booth_local_position)
		var db := Vector2(p.x - b.x, p.z - b.z).length()
		var c: Vector3 = r.global_position
		var dc := Vector2(p.x - c.x, p.z - c.z).length()
		if absf(p.y - b.y) > 6.0:
			continue
		if db < r.booth_radius + 1.2 and db < best:
			best = db
			f = {"ride": r}
		elif dc < r.reach_radius and dc + 2.0 < best:
			best = dc + 2.0
			f = {"ride": r}
	for g in _fair.game_spots:
		var gp: Vector3 = _fair.to_global(g["pos"])
		var dg := Vector2(p.x - gp.x, p.z - gp.z).length()
		if dg < 2.4 and absf(p.y - gp.y) < 3.0 and dg < best:
			best = dg
			f = {"game": g["id"]}
	var key := ""
	if f.has("ride"):
		key = "ride:" + String(f["ride"].ride_id)
	elif f.has("game"):
		key = "game:" + String(f["game"])
	if key == _focus_key:
		return
	_focus_key = key
	_focus = f.get("ride", null)
	_focus_game = String(f.get("game", ""))
	var paid := Wallet.address != ""
	var price := ("%s to this QING" % ArcadePay.fee_text()) if paid else "free practice (no wallet)"
	if _focus != null:
		_hud.show_prompt("%s  RIDE %s · %s" % [ControlsHelp.key_of("interact"), String(_focus.item.get("name", "Ride")).to_upper(), price])
	elif _focus_game != "":
		_hud.show_prompt("%s  PLAY %s · %s" % [ControlsHelp.key_of("interact"), MidwayGame.title(_focus_game), price])
	else:
		_hud.hide_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if (_focus == null and _focus_game == "") or _riding != null or _paying or _game != null or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	_hud.hide_prompt()
	var ride := _focus
	var game := _focus_game
	var what := String(ride.item.get("name", "ride")) if ride else MidwayGame.title(game)
	_focus_key = ""
	if Wallet.address == "":
		if ride:
			_start(ride, "PREVIEW RIDE · nothing paid")
		else:
			_play(game, randi() & 0x7fffffff, false, "practice · nothing paid · not on the board", {})
		return
	_paying = true
	_hud.show_prompt("TICKET · approve %s to this QING in your wallet window…" % ArcadePay.fee_text())
	_hud.ticker("Ticket for %s: approve %s to this QING in your wallet…" % [what, ArcadePay.fee_text()], DeepFieldTheme.ICE, 20.0)
	# A ticket is a plain transfer to the QING (no arcade credit is left behind)
	var res: Dictionary = await ArcadePay.transfer_to_qing(_qing, "Affection Fair · %s (%s)" % [what, ArcadePay.fee_text()])
	_paying = false
	_hud.hide_prompt()
	if not res.get("ok", false):
		var msg := "Ticket not bought (%s): %s" % [res.get("stage", "?"), res.get("message", "cancelled")]
		print("[Fair] ", msg)
		_hud.ticker(msg, Color("#ff8fa0"), 14.0)
		_hud.show_prompt(msg)
		get_tree().create_timer(6.0).timeout.connect(func(): if _focus_key == "": _hud.hide_prompt())
		return
	print("[Fair] ticket %s verified · block %d" % [res["hash"], int(res["block"])])
	if ride:
		_start(ride, "TICKET VERIFIED · block %d" % int(res.get("block", 0)))
	else:
		_play(game, MidwayGame.seed_from_tx(String(res["hash"])), true,
			"ticket %s · block %d · this round is seeded by its hash" % [ArcadeScores.short(String(res["hash"])), int(res["block"])], res)


## A midway game in the overlay; the player stands still while it runs.
func _play(id: String, seed_v: int, paid: bool, note: String, ticket: Dictionary) -> void:
	_hud.hide_prompt()
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_game = MidwayOverlay.new()
	layer.add_child(_game)
	_game.start(id, seed_v, paid, note, ArcadeScores.board(_qing, "fair:" + id))
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_game.finished.connect(func(sc: int) -> void:
		if paid and sc >= 0 and MidwayGame.max_score(id) > 0:
			var rank := ArcadeScores.record(_qing, "fair:" + id, {"score": sc, "wallet": Wallet.address, "tx": ticket.get("hash", ""),
				"block": int(ticket.get("block", 0)), "at": int(Time.get_unix_time_from_system())})
			if rank > 0:
				_hud.ticker("%s · %d · #%d on this stall's board (this computer)" % [MidwayGame.title(id), sc, rank], Color("#ffd27a"), 10.0)
		layer.queue_free()
		_game = null
		_focus_key = ""
		_player.set_physics_process(true))


func _start(ride: RideBase, note: String) -> void:
	_riding = ride
	_focus = null
	_focus_key = ""
	_hud.ticker(note, DeepFieldTheme.ICE, 6.0)
	ride.start_ride(_player)
	if ride is RocketRide:
		# After liftoff the player flies it (RocketVoyage)
		ride.voyage = true
		if not ride.voyage_handoff.is_connected(_start_voyage):
			ride.voyage_handoff.connect(_start_voyage)


func _start_voyage(ride: RocketRide) -> void:
	_voyage = RocketVoyage.new()
	_voyage.name = "RocketVoyage"
	get_tree().current_scene.add_child(_voyage)
	_voyage.ended.connect(func(_to_field: bool) -> void:
		_voyage = null)
	_voyage.begin(ride, _player, _hud, ground_y)


## World ground height at global (x, z), from the territory's own heightfield.
func ground_y(x: float, z: float) -> float:
	var core := get_parent() as Node3D
	if core == null or not _height_fn.is_valid():
		return 0.0
	var c := core.global_position
	return c.y + float(_height_fn.call(x - c.x, z - c.z))


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
