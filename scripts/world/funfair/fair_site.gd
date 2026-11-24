class_name FairSite
extends Node3D
## The Affection Fair in a v2 territory. Sits on its own deck (the Julia terrain is
## never flattened), sized by the territory's Development tier, and sells ride tickets
## through ArcadePay: 1 Ⓐ AFFECTION.transfer to this territory's QING, simulated,
## signed, receipt-verified, then the ride starts. No wallet → a free preview ride
## that is labelled as such and records nothing. Use works at a ride's booth or
## anywhere near the ride; the midway stalls and the high striker are first-person 3D
## mini games (MidwayPlay: MidwaySim rules, the stall's MidwayStage), sold the same way:
## 1 Ⓐ + the game's code in wei (FairProgress), seeded by the ticket's tx hash. Each stall
## shows the room's verified board (FairBoard); the Upsilon Rocket unlocks for a wallet once
## the chain shows a ticket for every game here (FairProgress; RocketLights by its booth).
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
var _game: MidwayPlay = null
var _lights: RocketLights = null
var _progress := {"codes": [], "state": "nowallet", "block": -1, "wallet": ""}
var _boards_busy := false
var _progress_busy := false
var _preview := false
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
	_lights = null
	for r in _fair.get_rides():
		if r.ride_id == "rocket":
			_lights = RocketLights.new()
			_lights.name = "RocketLights"
			_lights.position = Vector3(9.6, 0.0, 10.2)
			r.add_child(_lights)
			_lights.build()
		r.ride_caption.connect(func(text: String) -> void:
			if text != "":
				_hud.ticker(text, DeepFieldTheme.ICE, 3.0))
		r.ride_finished.connect(_on_finished)
	if t > 0 and not _fair.game_spots.is_empty():
		refresh_boards()
		refresh_progress()
		for g in _fair.game_spots:
			g["stage"].refresh_shelf(_qing)  # the prize shelves: what's left today, and yours


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
	# Another wallet connected (or none now): its own progress, read from the chain
	if not _preview and not _progress_busy and Wallet.address.to_lower() != String(_progress.get("wallet", "")):
		refresh_progress()
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
	if _focus != null and _rocket_locked(_focus):
		_hud.show_prompt("%s  UPSILON ROCKET · %s" % [ControlsHelp.key_of("interact"), _progress_line()])
	elif _focus != null:
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
	if ride and _rocket_locked(ride):
		# The rocket opens once the chain shows a ticket for every game here (checked again now)
		_hud.ticker("%s · each game's 1 Ⓐ ticket at this QING lights a lamp by the rocket" % _progress_line(), Color("#ffd27a"), 8.0)
		_hud.show_prompt("UPSILON ROCKET · " + _progress_line())
		refresh_progress()
		return
	if Wallet.address == "":
		if ride:
			_start(ride, "PREVIEW RIDE · nothing paid")
		else:
			_play(game, randi() & 0x7fffffff, false, "PRACTICE · nothing paid · on no board (connect a wallet to play for the boards)", {})
		return
	_paying = true
	_hud.show_prompt("TICKET · approve %s to this QING in your wallet window…" % ArcadePay.fee_text())
	_hud.ticker("Ticket for %s: approve %s to this QING in your wallet…" % [what, ArcadePay.fee_text()], DeepFieldTheme.ICE, 20.0)
	# A ticket is a plain transfer to the QING (no arcade credit is left behind). A game's ticket carries its code in the last wei (1 Ⓐ + k wei): the chain then knows
	# which stall it paid for (the rocket's progress); the screen still says 1 Ⓐ.
	var fee := FairProgress.fee_wei(game) if ride == null else ArcadePay.FEE_WEI
	var res: Dictionary = await ArcadePay.transfer_to_qing(_qing, "Affection Fair · %s (%s)" % [what, ArcadePay.fee_text()], fee)
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
		var code := FairProgress.code_of(res.get("value", BigInt.zero()))
		FairProgress.add_verified(String(res["from"]), _qing, code, int(res["block"]))
		if String(_progress.get("wallet", "")) == String(res["from"]).to_lower():
			_progress["codes"] = FairProgress.merge(_progress["codes"], [code] if code > 0 else [])
			_show_progress()
		refresh_progress()
		_play(game, MidwayGame.seed_from_tx(String(res["hash"])), true,
			"TICKET %s · block %s · this round is seeded by its hash" % [ArcadeScores.short(String(res["hash"])), ArcadeScores.grouped(int(res["block"]))], res)


## A midway game in first person at its stall (MidwayPlay); the player stands still while it runs.
func _play(id: String, seed_v: int, paid: bool, note: String, ticket: Dictionary) -> void:
	_hud.hide_prompt()
	var spot := {}
	for g in _fair.game_spots:
		if g["id"] == id:
			spot = g
	if spot.is_empty() or spot.get("stage") == null:
		return
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	refresh_boards()  # others may have posted since: the result screen shows the latest
	_game = MidwayPlay.new()
	_game.name = "MidwayPlay"
	add_child(_game)
	_game.closed.connect(func(sc: int) -> void:
		if paid and sc >= 0:
			_hud.ticker("%s · %d · on this computer's board; post it to the room from the result screen" % [MidwayGame.title(id), sc], Color("#ffd27a"), 8.0)
		_game.queue_free()
		_game = null
		_focus_key = ""
		_player.set_physics_process(true)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED))
	_game.start(self, spot["stage"], id, seed_v, paid, note, ticket, [_hud] if _hud is CanvasLayer else [])


## Reads the room's score lines and writes every stall's board (and an open result screen).
func refresh_boards() -> void:
	if _boards_busy or _qing == "":
		return
	_boards_busy = true
	_write_boards()
	await FairBoard.read(_qing)
	_boards_busy = false
	_write_boards()


func _write_boards() -> void:
	if _fair == null:
		return
	var st := FairBoard.state_of(_qing)
	for g in _fair.game_spots:
		var l = g.get("board")
		if l is Label3D and is_instance_valid(l):
			var t := FairBoard.sign_text(String(g["id"]), st)
			if l.text != t:
				l.text = t
	if _game != null:
		_game.refresh_boards()


## The connected wallet's games played here, from the chain (FairProgress), onto the rocket's board.
func refresh_progress() -> void:
	var w := Wallet.address.to_lower()
	if w == "":
		_progress = {"codes": [], "state": "nowallet", "block": -1, "wallet": ""}
		_show_progress()
		return
	if _progress_busy:
		return
	_progress_busy = true
	var c := FairProgress.cached(w, _qing)
	if _progress.get("wallet", "") != w:
		_progress = {"codes": c["codes"], "state": "reading", "block": c["block"], "wallet": w}
		_show_progress()
	var r: Dictionary = await FairProgress.refresh(w, _qing)
	_progress_busy = false
	if Wallet.address.to_lower() != w:
		return
	_progress = {"codes": r["codes"], "state": "ok" if r["ok"] else "failed", "block": int(r["block"]), "wallet": w}
	print("[Fair] rocket progress %s@%s: %s (%s, block %d)" % [w, _qing, str(r["codes"]), _progress["state"], int(r["block"])])
	_show_progress()


func _show_progress() -> void:
	if _lights:
		_lights.show_progress(_progress["codes"], _progress["state"], int(_progress["block"]))
	_focus_key = ""  # the prompt re-reads it


## Locked: the rocket, a wallet connected, and not every game played here (or not read yet).
func _rocket_locked(ride: RideBase) -> bool:
	if ride == null or ride.ride_id != "rocket" or Wallet.address == "":
		return false
	return not (_progress.get("state", "") == "ok" or _progress.get("state", "") == "failed") or not FairProgress.unlocked(_progress["codes"])


func _progress_line() -> String:
	match String(_progress.get("state", "")):
		"reading": return "Rocket: reading your tickets from the chain… —"
		"failed":
			return FairProgress.text(_progress["codes"]) + " (read failed: —)"
	return FairProgress.text(_progress["codes"])


## Previews (screenshot.gd --fair=<game>|rocket): first person at a stall, a scripted round of
## practice (nothing is paid or posted), held at `phase`: aim | play | result; `board`: the stall's
## room board close up.
func preview_game(id: String, phase: String, codes: Array = []) -> void:
	_preview = true
	if id == "rocket":
		_progress = {"codes": codes, "state": "ok", "block": FairProgress.FROM_BLOCK + 4200, "wallet": "preview"}
		_show_progress()
		if _lights:
			var cam := Camera3D.new()
			add_child(cam)
			cam.global_position = _lights.to_global(Vector3(0.0, 1.9, 4.4))
			cam.look_at(_lights.to_global(Vector3(0.0, 1.65, 0.0)))
			cam.fov = 60.0
			cam.current = true
		return
	if phase == "board":  # the stall's room board, close up
		for g in _fair.game_spots:
			var l = g.get("board")
			if g["id"] == id and l is Label3D:
				var cam := Camera3D.new()
				add_child(cam)
				var c: Vector3 = l.to_global(Vector3(0.6, -0.62, 0.0))
				cam.global_position = c + l.global_transform.basis.z.normalized() * 1.9 + Vector3.UP * 0.1
				cam.look_at(c)
				cam.fov = 50.0
				cam.current = true
		return
	_play(id, 0x2b1c0de5, false, "PREVIEW · practice round · nothing paid or posted", {})
	if _game == null:
		return
	var g := _game
	await get_tree().create_timer(1.3).timeout
	g.begin_play()
	g.hold = true
	var plan: Dictionary = {"striker": [[96 + 46, 0, 0]], "entropy": [[30, -120, 0]], "regolith": [[20, 0, 0], [130, -300, 200]],
		"crystal": [[10, 200, 0], [90, -200, 400]], "motzkin": [[260, 0, 0], [420, 300, 200]], "waat": [[20, 0, 0]], "saat": [[0, 0, 0], [40, 0, 0]]}
	var stop := {"striker": 96 + 46 + 16 + 30, "entropy": 30 + 30, "regolith": 130 + 20, "crystal": 90 + 14, "motzkin": 424, "waat": 60, "saat": 70}
	var presses: Array = plan.get(id, [])
	var i := 0
	var until: int = stop.get(id, 60)
	if phase == "result":
		until = MidwaySim.MAX_TICKS
	elif phase == "aim":  # still aiming: the sight (and the meter) before the first press
		var aims := {"striker": [40, 0, 0], "entropy": [40, 250, 0], "regolith": [40, -330, 190], "crystal": [40, 120, 300],
			"motzkin": [300, -200, 150], "waat": [40, 0, 0], "saat": [10, 0, 0]}
		var a: Array = aims.get(id, [40, 0, 0])
		presses = [[MidwaySim.MAX_TICKS, a[1], a[2]]]
		until = int(a[0])
		g.set_aim(Vector2(a[1], a[2]))
	while not g.sim.done and g.sim.tick < until:
		if i < presses.size() and g.sim.tick >= int(presses[i][0]) and g.sim.accepts():
			g.set_aim(Vector2(presses[i][1], presses[i][2]))
			g.press()
			i += 1
		elif phase == "result" and id == "motzkin" and g.sim.accepts():
			for k in g.sim.schedule.size():  # the preview shoots the primes it sees
				var e: Array = g.sim.schedule[k]
				if g.sim.target_up(k, g.sim.tick) and g.sim.tick - int(e[1]) > 12 and MidwaySim.is_prime(int(e[3])):
					g.set_aim(Vector2(int(MidwaySim.SLOTS_X[int(e[0]) % 4]) * MidwaySim.AIM / 1800, (int(MidwaySim.SLOTS_Y[int(e[0]) / 4]) - 1825) * MidwaySim.AIM / 700))
					g.press()
					break
		elif phase == "result" and id != "motzkin" and g.sim.accepts() and g.sim.phase_t > 20:
			g.press()
		g.sim.step()
	if presses.size() > 0:
		g.set_aim(Vector2(presses[-1][1], presses[-1][2]))
	g.hold = phase != "result"


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
