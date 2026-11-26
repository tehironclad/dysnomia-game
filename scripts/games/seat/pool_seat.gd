class_name PoolSeat
extends Node
## Pool in first person. Seated at the table, the camera drops to cue height
## behind the cue ball; the mouse turns the aim around it, the ghost line is
## the real PoolSim run on a copy of the table (PoolAim.ghost), holding the
## shot charges the power and letting go strikes with a visible cue. The view
## can switch to overhead.
##
## Modes, from the room's lines (TableBook):
##   play     your live game and your shot: the shot is a room line
##            (TableBook.post: simulate, sign, receipt, read back); the balls
##            only roll once the chain has the line, replayed like anyone's;
##   wait     your live game, the other player's shot: theirs replays from the
##            chain in first person (from behind the cue ball they struck);
##   watch    someone else's live game: the same replays, no cue for you;
##   practice no live game: a local table on this computer, labelled so; nothing
##            is posted.
## A game over the game server (an invite: Invites, NetMatch) plays the same way,
## except that a shot goes to the server instead of the chain: no transaction,
## and both players' tables replay the server's ordered log of shots.

const AIM_SENS := 0.0028  # radians per mouse pixel
const FINE := 0.2  # with the fine-aim key held
const KEY_AIM := 0.6  # radians a second with the fine-aim keys
const STRIKE_T := 0.14
const EYE_BACK := 0.62
const EYE_UP := 0.2

var place: Node  # GamesPlace
var table: PoolTable3D
var seat: TableSeat
var book: TableBook
var mode := "practice"
var match_id := ""
var practice := PoolSim.new()
var angle := 0.0
var pitch := 0.0
var power := 550  # the last power used (the ghost's power while not charging)
var charge := -1.0  # -1 when not charging
var overhead := false
var state := "aim"  # aim | posting | strike | roll | idle
var preview_hold := -1.0  ## previews: hold the charge here

var _held := 0.0
var _cue: Node3D
var _ghost: MeshInstance3D
var _ghost_mesh: ImmediateMesh
var _ghost_ball: MeshInstance3D
var _ghost_key := ""
var _ghost_task := -1  # WorkerThreadPool task computing the next ghost (the sim takes 10–50 ms)
var _ghost_next := {}
var _ghost_next_key := ""
var _ghost_data := {}
var _strike_t := 0.0
var _strike_from := 0.0
var _pending := {}  # the shot to roll after the strike: {before, dx, dy, power, frames?}
var _shot_angle := 0.0
var _shot_cue := Vector3.ZERO
var _label := ""
var _practice_shots := 0
var _practice_potted: Array = []


func setup(p_place: Node, p_table: PoolTable3D, p_seat: TableSeat, p_book: TableBook) -> void:
	place = p_place
	table = p_table
	seat = p_seat
	book = p_book
	_build_cue()
	_build_ghost()
	table.roll_finished.connect(_on_roll_finished)
	Wallet.tx_stage.connect(_on_stage)


func is_active() -> bool:
	return seat.is_active() and seat.get_meta("owner", null) == self


# --- Sitting down and standing up ----------------------------------------------

func sit() -> void:
	seat.set_meta("owner", self)
	overhead = false
	charge = -1.0
	state = "aim"
	_pending = {}
	_pick_mode()
	if mode == "practice":
		table.show_sim(practice)
	else:
		var m := _match()
		table.show_sim(m["game"].sim)
	angle = PoolAim.default_angle(_snap(), angle)
	table.show_caption(false)
	book.changed.connect(_on_book)
	seat.title.text = "POOL · EIGHT-BALL · %s" % String(place.territory.get("name", "")).to_upper()
	_refresh_texts()
	seat.enter(_view_xf(), _view_fov(), place.player.get_node_or_null("PlayerModel"), [place.hud_layer])
	seat.howto.setup(howto_spec())
	seat.howto.open_card(GameHowto.Mode.KEY)
	await seat.entered
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## The how-to card: eight-ball's rules, what this seat is (practice / live / watching), the controls.
func howto_spec() -> Dictionary:
	var rules := PackedStringArray(["Eight-ball: the first ball you pot picks your group (solids or stripes). Clear it, then sink the 8 to win.",
		"Aim with the mouse: the ghost line is the real sim run ahead. Hold %s for power, let go to strike." % ControlsHelp.key_of("table_shoot")])
	match mode:
		"practice": rules.append("Practice: a table on this computer only; nothing is posted. A live game starts from the games list (%s)." % ControlsHelp.key_of("table_lobby"))
		"play": rules.append(("Game %s over the game server: your shot goes to the server (free, not a transaction) and both machines replay it." % match_id) if _match().get("net", false)
			else "Live game %s: your shot is a room line signed in your wallet; the balls roll once the chain has it." % match_id)
		_: rules.append(("Game %s over the game server: every shot replays here from the server's log." % match_id) if _match().get("net", false)
			else "Live game %s: every shot replays here from its room line." % match_id)
	return {"title": "Pool · Eight-ball", "tag": String(place.territory.get("name", "")), "rules": rules,
		"controls": controls(), "accent": TableSeat.ICE, "verb": "play", "esc": "stand up"}


## [[key, words]] for the card and the strip.
func controls() -> Array:
	var rows: Array = []
	if _can_aim_view():
		rows.append(["Mouse", "aim"])
		rows.append(["%s %s" % [ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right")], "fine aim (%s: slower)" % ControlsHelp.key_of("sprint")])
		rows.append(["hold %s" % ControlsHelp.key_of("table_shoot"), "power · release to strike"])
	rows.append([ControlsHelp.key_of("table_view"), "first person" if overhead else "overhead view"])
	rows.append([ControlsHelp.key_of("table_lobby"), "games & challenges"])
	rows.append([ControlsHelp.key_of("notifications"), "invite a player online"])
	rows.append(["Esc", "stand up"])
	return rows


func stand() -> void:
	if book.changed.is_connected(_on_book):
		book.changed.disconnect(_on_book)
	state = "aim"
	charge = -1.0
	preview_hold = -1.0
	_finish_ghost_task()
	_cue.visible = false
	_ghost.visible = false
	_ghost_ball.visible = false
	seat.set_meter(-1.0)
	table.hold_frame = -1
	table.show_caption(true)
	seat.leave()
	await seat.exited
	seat.remove_meta("owner")


# --- Which game -----------------------------------------------------------------

func _match() -> Dictionary:
	if match_id.begins_with("n"):
		return Invites.match_dict(match_id)  # a game over the game server
	return book.by_id.get(match_id, {}) if match_id != "" else {}


## Live: playing, or (a game over the game server) both players confirming its stake.
static func _live(m: Dictionary) -> bool:
	if m.is_empty() or m["game"] == null or m.get("abandoned", false):  # abandoned: idle 30 min, or the server restarted
		return false
	return m["status"] == "playing" or (m.get("net", false) and m["status"] == "confirm")


func _pick_mode() -> void:
	var m: Dictionary = place._latest("pool")
	var me := Invites.wallet_for(m)
	match_id = ""
	mode = "practice"
	if not _live(m):
		return
	match_id = String(m["id"])
	var mine := TableBook.player_index(m, me)
	if mine >= 0 and m.get("net", false):
		Invites.sat_down(match_id)
	if mine < 0:
		mode = "watch"
	elif TableBook.turn_index(m) == mine:
		mode = "play"
	else:
		mode = "wait"


## The table position the shooter sees now.
func _snap() -> PackedInt64Array:
	if table.is_rolling() or state == "strike":
		return table.current_snapshot()
	if mode == "practice":
		return practice.snapshot()
	var m := _match()
	return m["game"].sim.snapshot() if not m.is_empty() and m["game"] != null else practice.snapshot()


func _can_shoot() -> bool:
	return state == "aim" and (mode == "practice" or mode == "play")


# --- Input ----------------------------------------------------------------------

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var k := FINE if Input.is_action_pressed("sprint") else 1.0
		if _can_shoot() or charge >= 0.0:
			angle = wrapf(angle + event.relative.x * AIM_SENS * k, -PI, PI)
		pitch = clampf(pitch - event.relative.y * AIM_SENS * 0.6, -0.35, 0.5)
		return true
	if event.is_action_pressed("table_view"):
		overhead = not overhead
		seat.target = _view_xf()
		seat.target_fov = _view_fov()
		seat.snap()
		_refresh_texts()
		return true
	if event.is_action_pressed("table_shoot"):
		if _can_shoot():
			if mode == "play" and not _match().get("net", false):
				var b: String = place._table_blocker()
				if b != "":
					seat.status.text = b
					return true
			charge = 0.0
			_held = 0.0
		return true
	if event.is_action_released("table_shoot"):
		if charge >= 0.0 and state == "aim":
			_release()
		return true
	return false


func _process(delta: float) -> void:
	if not is_active():
		return
	if seat.is_inside():
		if _can_shoot():
			var k := FINE if Input.is_action_pressed("sprint") else 1.0
			angle = wrapf(angle + (Input.get_action_strength("move_right") - Input.get_action_strength("move_left")) * KEY_AIM * k * delta, -PI, PI)
		if charge >= 0.0:
			_held += delta
			charge = PoolAim.charge_at(_held) if preview_hold < 0.0 else preview_hold
		if state == "strike":
			_strike_t += delta
			if _strike_t >= STRIKE_T:
				_roll()
	seat.target = _view_xf()
	seat.target_fov = _view_fov()
	_update_cue()
	_update_ghost()
	_refresh_meter()


# --- Shooting ---------------------------------------------------------------------

func _release() -> void:
	var c := charge
	charge = -1.0
	var p := PoolAim.shot_params(angle, c)
	power = p["power"]
	if mode == "practice":
		var before := practice.snapshot()
		var r := practice.shoot(p["dx"], p["dy"], p["power"], PoolTable3D.FRAME_EVERY)
		_practice_shots += 1
		_practice_potted = r["pocketed"]
		_strike({"before": before, "frames": r.get("frames", []), "angle": angle, "power": p["power"], "charge": c})
		return
	var m := _match()
	if m.is_empty():
		return
	if m.get("net", false):
		state = "posting"
		_strike_from = c
		if Invites.send_move(m["id"], "shot", [p["dx"], p["dy"], p["power"]]):
			seat.status.text = "Shot sent to the game server (dx %d, dy %d, power %d). It rolls when the server's log has it, on both tables." % [p["dx"], p["dy"], p["power"]]
		else:
			state = "aim"
			seat.status.text = "Not sent: the game server isn't answering. Nothing was played."
		return
	state = "posting"
	_strike_from = c
	_label = "Pool #%s shot" % m["id"]
	seat.status.text = "Posting your shot as a room line: %s" % TableBook.shot_text(m["id"], p["dx"], p["dy"], p["power"])
	var r: Dictionary = await TableBook.post(place.qing, TableBook.shot_text(m["id"], p["dx"], p["dy"], p["power"]), _label)
	if not is_active():
		return
	if r["ok"]:
		seat.status.text = "On the chain: read back from block %d. Replaying it…" % r["block"]
		await book.feed([r["line"]])
	else:
		state = "aim"
		seat.status.text = "Not sent (%s): %s" % [String(r.get("stage", "?")), String(r.get("message", ""))]
	if state == "posting":
		state = "aim"


## Starts the strike animation; the balls roll when the cue reaches the ball.
func _strike(shot: Dictionary) -> void:
	_pending = shot
	_shot_angle = float(shot["angle"])
	var before: PackedInt64Array = shot["before"]
	_shot_cue = PoolAim.to_local(before[0], before[1])
	_strike_from = float(shot.get("charge", PoolAim.charge_of(int(shot["power"]))))
	_strike_t = 0.0
	state = "strike"
	table.show_snapshot(before)
	_ghost.visible = false
	_ghost_ball.visible = false


func _roll() -> void:
	state = "roll"
	var s := _pending
	if s.has("frames"):
		table.play_frames(s["before"], s["frames"])
	else:
		table.play_shot(s["before"], s["dx"], s["dy"], s["power"])


func _on_roll_finished() -> void:
	if not is_active() or state != "roll":
		return
	state = "aim"
	if mode == "practice":
		var pot: Array = _practice_potted.filter(func(b): return b != 0)
		if _practice_potted.has(0):
			practice.spot_cue()
			seat.call_out("SCRATCH", TableSeat.MAGENTA)
		elif not pot.is_empty():
			seat.call_out("POTTED " + ", ".join(pot.map(func(b): return str(b))), TableSeat.LIVE)
		var left := 0
		for b in range(1, 16):
			if practice.on_table(b):
				left += 1
		if left == 0:
			practice.rack()
			seat.call_out("RE-RACKED", TableSeat.ICE)
		table.show_sim(practice)
	else:
		var m := _match()
		if not m.is_empty() and m["game"] != null:
			table.show_sim(m["game"].sim)
			var ev: Array = m["events"]
			if not ev.is_empty():
				seat.call_out(String(ev[-1]).trim_prefix("shot: ").to_upper(), TableSeat.GOLD, 2.6)
		_pick_mode_keep()
	angle = PoolAim.default_angle(_snap(), angle) if mode != "practice" else angle
	_ghost_key = ""
	_refresh_texts()


## Re-reads whose turn it is in the same game (or drops to practice when it ended).
func _pick_mode_keep() -> void:
	var m := _match()
	if not _live(m):
		if not m.is_empty() and m["status"] == "over":
			seat.call_out("%s WON" % book.display(m["winner"]).to_upper() if not m["push"] else "PUSH", TableSeat.GOLD, 4.0)
		elif not m.is_empty() and m.get("abandoned", false):
			seat.call_out("GAME ABANDONED · NOBODY OWES", TableSeat.GOLD, 4.0)
		_pick_mode()
		if mode == "practice":
			table.show_sim(practice)
		return
	var mine := TableBook.player_index(m, Invites.wallet_for(m))
	mode = "watch" if mine < 0 else ("play" if TableBook.turn_index(m) == mine else "wait")


func _on_book() -> void:
	if not is_active():
		return
	if mode == "practice":
		# A game started while you practised: say so (stand up and sit again to join it).
		var m: Dictionary = place._latest("pool")
		if not m.is_empty() and m["status"] == "playing" and TableBook.player_index(m, Invites.wallet_for(m)) >= 0:
			seat.show_toast("Your game #%s is live: stand up (Esc) and sit again to play it." % m["id"])
		return
	var m := _match()
	if m.is_empty():
		return
	if m.has("last_shot") and String(m["last_shot"]["tx"]) != String(place._animated_tx) and state in ["aim", "posting", "idle"]:
		var s: Dictionary = m["last_shot"]
		place._animated_tx = String(s["tx"])
		var ang := PoolAim.angle_of(Vector2i(s["dx"], s["dy"]))
		angle = ang
		_strike({"before": s["before"], "dx": s["dx"], "dy": s["dy"], "power": s["power"], "angle": ang})
		if m.get("net", false):
			seat.status.text = "%s · shot %s of the game server's log (dx %d, dy %d, power %d)" % [book.display(m["players"][s["player"]]), String(s["tx"]).get_slice(":", 2), s["dx"], s["dy"], s["power"]]
		else:
			seat.status.text = "%s · shot from block %d · tx %s" % [book.display(m["players"][s["player"]]), s["block"], TableBook.short(String(s["tx"]))]
		return
	if state == "aim":
		_pick_mode_keep()
		_refresh_texts()


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	if not is_active() or label != _label:
		return
	match stage:
		"simulate": seat.status.text = "Simulating the line from your wallet…"
		"sign": seat.status.text = "Waiting for your signature in the browser wallet…"
		"pending": seat.status.text = "Sent %s · waiting for the receipt…" % String(info.get("hash", ""))
		"confirmed": seat.status.text = "Mined in block %d. Reading the line back from the chain…" % int(info.get("block", -1))


# --- Views ------------------------------------------------------------------------

func _view_xf() -> Transform3D:
	var g := table.global_transform
	if overhead:
		return g * Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0, PoolTable3D.BED + 2.3, 0))
	if state == "roll":
		var eye := PoolAim.eye_behind(_shot_cue, _shot_angle, 1.35, 0.85)
		var look := _shot_cue + PoolAim.dir3(_shot_angle) * 0.9
		return g * Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	if state == "aim" and (mode == "watch" or mode == "wait"):
		var eye := Vector3(0, PoolTable3D.BED + 1.05, 1.95)
		return g * Transform3D(Basis.looking_at(Vector3(0, PoolTable3D.BED, 0) - eye, Vector3.UP), eye)
	var s := _snap()
	var cue := PoolAim.to_local(s[0], s[1]) if s.size() >= 48 else Vector3.ZERO
	var a := _shot_angle if state == "strike" else angle
	if state == "strike":
		cue = _shot_cue
	var eye := PoolAim.eye_behind(cue, a, EYE_BACK, EYE_UP)
	var look := cue + PoolAim.dir3(a) * 0.75 + Vector3.UP * (pitch * 0.9 - 0.02)
	return g * Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


func _view_fov() -> float:
	return 50.0 if overhead else 62.0


# --- The cue and the ghost -----------------------------------------------------------

func _build_cue() -> void:
	_cue = Node3D.new()
	_cue.name = "Cue"
	table.add_child(_cue)
	var length := 1.45
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0062
	cm.bottom_radius = 0.0145
	cm.height = length
	cm.radial_segments = 12
	shaft.mesh = cm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.86, 0.68, 0.42)
	wood.roughness = 0.35
	shaft.material_override = wood
	shaft.rotation_degrees.x = -90.0
	shaft.position = Vector3(0, 0, length * 0.5)
	_cue.add_child(shaft)
	var butt := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.0125
	bm.bottom_radius = 0.0148
	bm.height = 0.5
	bm.radial_segments = 12
	butt.mesh = bm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.03, 0.02)
	dark.roughness = 0.3
	butt.material_override = dark
	butt.rotation_degrees.x = -90.0
	butt.position = Vector3(0, 0, length - 0.25)
	_cue.add_child(butt)
	var ferrule := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0063
	fm.bottom_radius = 0.0064
	fm.height = 0.022
	fm.radial_segments = 12
	ferrule.mesh = fm
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.96, 0.95, 0.9)
	ferrule.material_override = white
	ferrule.rotation_degrees.x = -90.0
	ferrule.position = Vector3(0, 0, 0.016)
	_cue.add_child(ferrule)
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.006
	tm.bottom_radius = 0.0062
	tm.height = 0.006
	tm.radial_segments = 12
	tip.mesh = tm
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.15, 0.35, 0.8)
	tip.material_override = blue
	tip.rotation_degrees.x = -90.0
	tip.position = Vector3(0, 0, 0.003)
	_cue.add_child(tip)
	_cue.visible = false


func _update_cue() -> void:
	var show := seat.is_inside() and (state == "strike" or (state in ["aim", "posting"] and _can_aim_view()))
	_cue.visible = show
	if not show:
		return
	var s := _snap()
	var cue := _shot_cue if state == "strike" else PoolAim.to_local(s[0], s[1])
	var a := _shot_angle if state == "strike" else angle
	var gap := 0.035
	if state == "strike":
		var u := clampf(_strike_t / STRIKE_T, 0.0, 1.0)
		gap = lerpf(0.035 + 0.26 * _strike_from, -0.012, u * u)
	elif charge >= 0.0:
		gap = 0.035 + 0.26 * charge
	elif state == "posting":
		gap = 0.035 + 0.26 * _strike_from
	var d := PoolAim.dir3(a)
	var fwd := (d + Vector3.DOWN * 0.09).normalized()  # the butt rides a little higher than the tip
	var tip := cue - d * (0.0286 + gap)
	_cue.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), tip)


func _can_aim_view() -> bool:
	return mode == "practice" or mode == "play"


func _build_ghost() -> void:
	_ghost_mesh = ImmediateMesh.new()
	_ghost = MeshInstance3D.new()
	_ghost.name = "AimGhost"
	_ghost.mesh = _ghost_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost.material_override = m
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	table.add_child(_ghost)
	_ghost_ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0286
	sm.height = 0.0572
	sm.radial_segments = 16
	sm.rings = 8
	_ghost_ball.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1, 1, 1, 0.28)
	_ghost_ball.material_override = gm
	_ghost_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	table.add_child(_ghost_ball)
	_ghost.visible = false
	_ghost_ball.visible = false


func _update_ghost() -> void:
	var on := seat.is_active() and state == "aim" and _can_aim_view()
	_ghost.visible = on
	_ghost_ball.visible = on and int(_ghost_data.get("target", -1)) >= 0
	if not on:
		return
	var p := PoolAim.shot_params(angle, charge if charge >= 0.0 else PoolAim.charge_of(power))
	var snap := _snap()
	var key := "%d,%d,%d,%s,%d" % [p["dx"], p["dy"], int(p["power"]) / 50, mode, hash(snap)]
	if _ghost_task >= 0:
		if not WorkerThreadPool.is_task_completed(_ghost_task):
			return
		WorkerThreadPool.wait_for_task_completion(_ghost_task)
		_ghost_task = -1
		_ghost_key = _ghost_next_key
		_ghost_data = _ghost_next
		_draw_ghost(_ghost_data)
	if key == _ghost_key:
		return
	# The ghost is the real PoolSim run ahead on a copy: off the main thread, so aiming stays smooth.
	_ghost_next_key = key
	if OS.has_feature("web") or Engine.is_editor_hint():
		_ghost_next = PoolAim.ghost(snap, p["dx"], p["dy"], p["power"])
		_ghost_key = key
		_ghost_data = _ghost_next
		_draw_ghost(_ghost_data)
		return
	_ghost_task = WorkerThreadPool.add_task(func(): _ghost_next = PoolAim.ghost(snap, p["dx"], p["dy"], p["power"]), false, "pool ghost")


func _finish_ghost_task() -> void:
	if _ghost_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_ghost_task)
		_ghost_task = -1
	_ghost_key = ""


func _draw_ghost(g: Dictionary) -> void:
	_ghost_mesh.clear_surfaces()
	var y := PoolTable3D.BED + 0.003
	var paths := [[g["cue_path"], Color(1, 1, 1, 0.75), 0.009], [g["target_path"], Color(1.0, 0.82, 0.3, 0.85), 0.009], [g["cue_after"], Color(0.5, 0.9, 1.0, 0.4), 0.006]]
	var any := false
	for path in paths:
		if (path[0] as Array).size() >= 2:
			any = true
	if not any:
		_ghost_ball.visible = false
		return
	_ghost_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for path in paths:
		var pts: Array = path[0]
		var col: Color = path[1]
		var w: float = path[2]
		var step := maxi(1, pts.size() / 60)
		var prev := Vector3.INF
		var k := 0
		while k < pts.size():
			var v: Vector2i = pts[k]
			var p3 := PoolAim.to_local(v.x, v.y)
			p3.y = y
			if prev != Vector3.INF and prev.distance_to(p3) > 0.0005:
				var fade := 1.0 - float(k) / float(maxi(1, pts.size())) * 0.6
				_ribbon(prev, p3, w, Color(col, col.a * fade))
			prev = p3
			k = k + step if k + step < pts.size() or k == pts.size() - 1 else pts.size() - 1
	_ghost_mesh.surface_end()
	var t := int(g["target"])
	if t >= 0:
		var c: Vector2i = g["contact_at"]
		_ghost_ball.position = PoolAim.to_local(c.x, c.y)
		_ghost_ball.visible = true
	else:
		_ghost_ball.visible = false


func _ribbon(a: Vector3, b: Vector3, w: float, c: Color) -> void:
	var d := (b - a).normalized()
	var side := Vector3(-d.z, 0, d.x) * w * 0.5
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_ghost_mesh.surface_set_color(c)
		_ghost_mesh.surface_add_vertex(v)


# --- The overlay ------------------------------------------------------------------

func _refresh_meter() -> void:
	if not seat.is_inside():
		return
	if state == "aim" and _can_aim_view():
		var c := charge if charge >= 0.0 else PoolAim.charge_of(power)
		var pw := PoolAim.power_from_charge(c)
		seat.set_meter(c, ("POWER %d · %.1f m/s" % [pw, PoolAim.speed_mps(pw)]) + ("" if charge >= 0.0 else "  (last shot · hold %s to charge)" % ControlsHelp.key_of("table_shoot")))
	else:
		seat.set_meter(-1.0)
	var t := int(_ghost_data.get("target", -1))
	var aim := ""
	if state == "aim":
		aim = ("aim → the %d ball" % t) if t > 0 else "aim → no ball (the cushion)"
	elif state == "roll":
		aim = "rolling…"
	seat.stats.text = _stats_text() + ("\n" + aim if aim != "" and _can_aim_view() else "")


func _stats_text() -> String:
	var s := _snap()
	var left := 0
	for b in range(1, 16):
		if s.size() >= 48 and s[b * 3 + 2] == 0:
			left += 1
	if mode == "practice":
		return "balls on the table: %d\nshots: %d" % [left, _practice_shots]
	var m := _match()
	if m.is_empty():
		return ""
	var g: EightBall = m["game"]
	var out := "#%s · shot %d\nballs on the table: %d" % [m["id"], g.shots + 1, left]
	if m.get("net", false) and Wager.code(m) != "none":
		out += "\n" + Wager.short(m, Invites.wallet_for(m))
	if g.groups[0] != "":
		out += "\n%s: %s · %s: %s" % [TableBook.short(m["players"][0]), g.groups[0], TableBook.short(m["players"][1]), g.groups[1]]
	else:
		out += "\nopen table (no groups yet)"
	return out


func _refresh_texts() -> void:
	var m := _match()
	match mode:
		"practice":
			seat.headline.text = "PRACTICE"
			seat.set_badge("PRACTICE · on this computer only: nothing is posted, nothing goes on chain. A live game starts from the table's list (%s)." % ControlsHelp.key_of("table_lobby"), false)
			seat.source.text = "PoolSim: integer physics (µm, 1/480 s ticks), the same code that replays every room line. The ghost is that sim run ahead on a copy of this table."
		"play":
			seat.headline.text = "YOUR SHOT"
			seat.set_badge("LIVE GAME #%s · your shot is a room line (CHOA.Chat) signed in your wallet; the balls roll when the chain has it" % m["id"], true)
		"wait":
			seat.headline.text = "%s TO SHOOT" % TableBook.short(m["players"][TableBook.turn_index(m)])
			seat.set_badge("LIVE GAME #%s · their shot replays here from its room line, from behind the cue ball" % m["id"], true)
		"watch":
			seat.headline.text = "WATCHING #%s" % m["id"]
			seat.set_badge("LIVE GAME #%s · %s vs %s · every shot replays from its room line" % [m["id"], book.display(m["players"][0]), book.display(m["players"][1])], true)
	if mode != "practice" and not m.is_empty():
		seat.source.text = "Table: replayed from this QING's room lines (%s), the game started at block %d, last move at block %d. Who shot = the line's tx.from." % [TableBook.short(place.qing), m["created_block"], m["last_block"]]
	if not m.is_empty() and m.get("net", false):
		_net_texts(m)
	seat.set_controls(controls())


## The overlay for a game over the game server (an invite): what it is, the stake.
func _net_texts(m: Dictionary) -> void:
	var vs := "%s vs %s" % [book.display(m["players"][0]), book.display(m["players"][1])]
	var keys := ControlsHelp.key_of("notifications")
	if m["status"] == "confirm":
		seat.headline.text = "CONFIRM THE STAKE"
		seat.set_badge("GAME #%s OVER THE GAME SERVER · %s · %s · %s: confirm it, or play without a stake" % [m["id"], vs, Wager.text(m, Invites.wallet_for(m), book.display), keys], true)
	else:
		match mode:
			"play":
				seat.set_badge("GAME #%s OVER THE GAME SERVER · %s · your shot goes to the server (no transaction) and both tables replay it" % [m["id"], vs], true)
			"wait":
				var t := TableBook.turn_index(m)
				if t >= 0 and String(m["names"][t]) != "":
					seat.headline.text = "%s TO SHOOT" % String(m["names"][t]).to_upper()
				seat.set_badge("GAME #%s OVER THE GAME SERVER · %s · their shot replays here from the server's log, from behind the cue ball" % [m["id"], vs], true)
			_:
				seat.set_badge("GAME #%s OVER THE GAME SERVER · %s" % [m["id"], vs], true)
	seat.source.text = "Table: replayed from the game server's move log (%d moves, ordered and stamped by the server; PoolSim's integers on both machines, which must agree on the result). Wager: %s." % [int(m.get("moves", 0)), Wager.text(m, Invites.wallet_for(m), book.display)]


## Previews (tools/screenshot.gd): "aim" holds a charge with the ghost; "roll" breaks and holds mid-roll.
func preview(phase: String) -> void:
	if phase != "howto":
		seat.howto.close_card(false)
	await get_tree().create_timer(0.3).timeout
	if phase == "overhead":
		overhead = true
		_refresh_texts()
	if phase == "aim" or phase == "overhead":
		angle += 0.035
		preview_hold = 0.72
		charge = 0.72
	elif phase == "roll":
		table.hold_frame = 34
		charge = 1.0
		_release()


func _exit_tree() -> void:
	_finish_ghost_task()
