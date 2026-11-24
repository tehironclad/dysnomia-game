class_name ActLoop
extends Node3D
## The diegetic gameplay loop at a territory (child of the Core; Core-local
## coordinates). Every few seconds it builds a PlaySnapshot from what the game
## already read, asks PlayLoop for the acts and goals, and shows them:
## - a beacon at the building where each act is done (ActBeacon);
## - the HUD tracker (ActTracker);
## - the Steward at the Core, who explains them in the land's words and opens
##   the real move (CoreActions: simulate → sign → receipt → re-read).
## When a move is confirmed it celebrates the *measured* change (CoreActions'
## su_measured / beat_confirmed, ChatFeed.posted re-read from YUE.Bar).
## The markers, tracker and steward's words are personal UI; nothing about the
## territory's own look depends on the viewer.

const REFRESH_S := 3.0
const EXTRAS_S := 90.0
const STEWARD_AT := Vector3(5.6, 0.0, 12.4)
const STEWARD_REACH := 2.8
const BORDER_INSET := 16.0

var territory: Dictionary = {}
var qing := ""
var state: TerritoryState
var core: TerritoryCore
var hud: HudV2
var actions: CoreActions
var border: BorderRing
var columns: BarColumns
var player: Node3D
var height_at: Callable   # (x, z) Core-local → ground y, Core-local
var acts: Array = []
var goals: Array = []
var _beacons := {}         # key → ActBeacon
var _extras := {}
var _extras_at := -1000000.0
var _reading_extras := false
var _t := 0.0
var _next := 0.0
var _sig := ""
var _steward: Node3D
var _near_steward := false
var _layer: CanvasLayer
var _panel: ActionPanel
var view_only := false


func setup(q: Dictionary, p_state: TerritoryState, p_core: TerritoryCore, p_hud: HudV2, p_actions: CoreActions,
		p_border: BorderRing, p_columns: BarColumns, p_player: Node3D, p_height: Callable, p_view_only: bool = false) -> void:
	territory = q
	qing = String(q["address"]).to_lower()
	state = p_state
	core = p_core
	hud = p_hud
	actions = p_actions
	border = p_border
	columns = p_columns
	player = p_player
	height_at = p_height
	view_only = p_view_only
	_build_steward()
	_layer = CanvasLayer.new()
	_layer.layer = 21
	add_child(_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.theme = DeepFieldTheme.get_theme()
	_layer.add_child(center)
	_panel = ActionPanel.new()
	center.add_child(_panel)
	_panel.closed.connect(_on_panel_closed)
	if actions:
		actions.su_measured.connect(_on_su_measured)
		actions.beat_confirmed.connect(_on_beat_confirmed)
	ChatFeed.posted.connect(_on_posted)
	Session.changed.connect(func(): _extras_at = -1000000.0)
	ChatFeed.feed_for(qing, territory)
	Inspector.register(self, "Acts here (personal)",
		"The markers and the tracker are this player's own to-do list, from chain reads (PlayLoop): Su at the pylons (Ω), Beat at the Heart (readiness probe), the room (last line's block, the door), crowns (the board), neighbours beyond the fields (your bars there, Ω there), dry wells (balanceOf(QING) = 0). Unread values show '—'.")


func _process(delta: float) -> void:
	_t += delta
	if _t >= _next:
		_next = _t + REFRESH_S
		_refresh()
	if view_only or player == null or _panel.is_open():
		return
	var lp := player.global_position - core.global_position
	var near := Vector2(lp.x, lp.z).distance_to(Vector2(STEWARD_AT.x, STEWARD_AT.z)) < STEWARD_REACH
	if near != _near_steward:
		_near_steward = near
		if near:
			hud.show_prompt("%s  Steward: what this land asks of you" % ControlsHelp.key_of("interact"))
		else:
			hud.hide_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if view_only or not _near_steward or _panel.is_open() or (actions and actions.is_open()):
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		hud.hide_prompt()
		open_steward()


# --- The loop -------------------------------------------------------------------

func snapshot() -> Dictionary:
	var feed: RoomFeed = ChatFeed.feeds.get(qing)
	return PlaySnapshot.build(state, Session.wallet, Session.player, Session.readiness, Session.record,
		Session.bars, Session.bars_block, feed, border.sides if border else {}, _extras)


func _refresh() -> void:
	if not _reading_extras and _t - _extras_at > EXTRAS_S and Session.wallet != "" and Session.player != null:
		_read_extras()
	var snap := snapshot()
	acts = PlayLoop.acts(snap)
	goals = PlayLoop.goals(snap)
	var sig := JSON.stringify([acts.map(func(a): return [a["key"], a["title"], a.get("detail", ""), a["doable"]]), goals.map(func(g): return g["text"])])
	if sig == _sig:
		return
	_sig = sig
	if hud.tracker:
		hud.tracker.show_loop(acts, goals, int(snap.get("block", -1)))
	_place_beacons()


func _read_extras() -> void:
	_reading_extras = true
	_extras_at = _t
	var ex: Dictionary = await PlaySnapshot.read_extras(qing, Session.player, border.sides if border else {})
	if not is_inside_tree():
		return
	_extras = ex
	_reading_extras = false
	_next = 0.0


## Core-local anchor of an act (null when it has no place here).
func anchor_of(a: Dictionary):
	var an := String(a["anchor"])
	match an:
		"pylon":
			return Vector3(-TerritoryCore.PYLON_GAP, 0.0, 3.0)
		"heart":
			return Vector3(0.0, 0.0, 0.0)
		"room":
			return Vector3(0.0, 0.0, TerritoryCore.ROOM_RADIUS + 1.9)
		"tower":
			var t := columns.tower_of(Session.wallet) if columns else {}
			if t.is_empty():
				return null
			var at: Vector3 = (t["root"] as Node3D).position
			var toward := -Vector3(at.x, 0.0, at.z).normalized()
			return Vector3(at.x, 0.0, at.z) + toward * 4.5
	if an.begins_with("border_"):
		var o := Neighbours.outward(an.substr(7)) * (JuliaHeightfield.SIZE_M * 0.5 - BORDER_INSET)
		return Vector3(o.x, 0.0, o.y)
	if an.begins_with("well_"):
		for w in TerritoryCore.WELLS:
			if "well_" + String(w["key"]) == an:
				var ang := deg_to_rad(float(w["angle"]))
				return Vector3(cos(ang), 0.0, sin(ang)) * TerritoryCore.WELL_RADIUS
	return null


func _place_beacons() -> void:
	var keep := {}
	for a in acts:
		var at = anchor_of(a)
		if at == null:
			continue
		var key := String(a["key"])
		keep[key] = true
		var b: ActBeacon = _beacons.get(key)
		if b == null or b.kind != String(a["kind"]):
			if b:
				b.queue_free()
			b = ActBeacon.new()
			b.name = "Act_" + key
			var lift := 6.8 if a["anchor"] == "heart" else (4.4 if String(a["anchor"]).begins_with("well_") else (9.0 if a["kind"] == "border" else 3.4))
			b.build(String(a["kind"]), lift)
			b.always_label = a["kind"] == "border"
			add_child(b)
			_beacons[key] = b
		var p: Vector3 = at
		if height_at.is_valid() and not String(a["anchor"]) in ["heart", "pylon", "room"]:
			p.y = float(height_at.call(p.x, p.z))
		b.position = p
		b.show_act(a)
	for k in _beacons.keys():
		if not keep.has(k):
			(_beacons[k] as Node).queue_free()
			_beacons.erase(k)


# --- The Steward ------------------------------------------------------------------

func _build_steward() -> void:
	_steward = Node3D.new()
	_steward.name = "Steward"
	var y := float(height_at.call(STEWARD_AT.x, STEWARD_AT.z)) if height_at.is_valid() else 0.0
	_steward.position = Vector3(STEWARD_AT.x, y, STEWARD_AT.z)
	add_child(_steward)
	var npc := AmbientNPC.new()
	npc.name = "Figure"
	_steward.add_child(npc)
	npc.setup(int(String(territory.get("entropy", "7")).right(6)), [], Vector3.BACK)
	var model := npc.get_node_or_null("Model")
	if model and model.has_method("set_outfit"):
		model.set_outfit("robe", 3)
	npc.rotation.y = PI * 0.82  # turned towards the arrival point
	var lectern := PlaceBase.load_piece("Prop_AccessPoint")
	lectern.position = Vector3(-0.9, 0.0, -0.4)
	lectern.rotation_degrees.y = 160.0
	lectern.scale = Vector3.ONE * 0.8
	_steward.add_child(lectern)
	Solid.wrap(lectern)
	var halo := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.2
	t.outer_radius = 0.235
	t.rings = 32
	t.ring_segments = 4
	halo.mesh = t
	halo.material_override = TerritoryCore._glow(DeepFieldTheme.ICE, 2.0)
	halo.position = Vector3(0.0, 2.15, 0.0)
	_steward.add_child(halo)
	var key := OmniLight3D.new()  # a warm key light so the figure reads against the plaza
	key.light_color = Color("#ffe2b8")
	key.light_energy = 1.6
	key.omni_range = 4.5
	key.position = Vector3(0.8, 2.4, 1.2)
	_steward.add_child(key)
	var sign := Label3D.new()
	sign.text = "STEWARD"
	sign.font = DeepFieldTheme.mono_font()
	sign.font_size = 40
	sign.pixel_size = 0.006
	sign.outline_size = 10
	sign.outline_modulate = Color(0.01, 0.015, 0.03, 0.9)
	sign.modulate = DeepFieldTheme.ICE
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0.0, 2.55, 0.0)
	_steward.add_child(sign)


## The Steward's words: the acts here, in the land's language, each with its call.
func steward_text() -> String:
	var lines: PackedStringArray = []
	var name := String(territory.get("name", qing))
	lines.append("\"%s computes itself from its numbers. This is what it asks of you%s.\"" % [name,
		(", read at block %d" % state.block) if state and state.block > 0 else ""])
	lines.append("")
	for a in acts:
		lines.append("◆ %s" % String(a["title"]).to_upper())
		lines.append("   %s" % a.get("lore", ""))
		var d := String(a.get("detail", ""))
		var why := "" if a["doable"] or String(a.get("blocker", "")) == "" else "  · not yet: " + String(a["blocker"])
		lines.append("   %s · %s%s" % [a["call"], d, why])
	lines.append("")
	lines.append("YOUR GOALS (from the chain)")
	for g in goals:
		lines.append("   %s   [%s]" % [g["text"], g["source"]])
	return "\n".join(lines)


func open_steward() -> void:
	_panel.show_panel("STEWARD · %s" % String(territory.get("name", "")).to_upper(), steward_text())
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var top := ""
	for a in acts:
		if a["doable"] and a["kind"] in ["su", "beat", "crown"]:
			top = "beat" if a["kind"] == "beat" else "su"
			break
	var ps: PlayerState = Session.player
	var identity_ready := Session.wallet != "" and ps != null and ps.ok and ps.has_lau() and ps.has_yue()
	if top == "su" and actions:
		_panel.set_primary("Su here now (simulate first)", true, func(): _panel.close(); actions.open_su())
	elif top == "beat" and actions:
		_panel.set_primary("Beat at the Heart (simulate first)", true, func(): _panel.close(); actions.open_beat())
	elif not identity_ready:
		# Not a refusal: the numbered steps in (connect, the window, the chain, LAU, YUE).
		_panel.set_primary("Connect wallet: the steps" if Session.wallet == "" else "What I still need", true, func():
			_panel.close()
			AccessSteps.popup(self, "identity", {"title": "Play as yourself at %s" % String(territory.get("name", ""))}))
	else:
		_panel.set_primary("Nothing to sign yet", false, Callable())
	_panel.set_secondary("Read the room (%s)" % ControlsHelp.key_of("chat_history"), ChatFeed.hud != null, func():
		_panel.close()
		ChatFeed.hud.feed.toggle_history())
	_panel.set_status("Each move is simulated from your wallet first; success is read back from the chain." if identity_ready
		else "Looking is free: walk anywhere, read the room, visit the fair and the arcade, M for the Field. Signing needs a wallet.")


func _on_panel_closed() -> void:
	if actions and actions.is_open():
		return
	if player:
		player.process_mode = Node.PROCESS_MODE_INHERIT
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_near_steward = false


# --- Celebrations (measured changes only) -----------------------------------------

func _on_su_measured(before: PackedInt64Array, after: PackedInt64Array, d_epi: PackedInt64Array, block: int) -> void:
	var o := PlayLoop.su_outcome(before, after, d_epi, block)
	var grew: bool = int(o["floors_after"]) > int(o["floors_before"])
	hud.celebrate("YOUR TOWER RISES" if grew else "SU · YOUR BARS GROW", String(o["text"]) + " · Ω here %s" % state.omega.display(func(v): return PlayLoop.dec(v)), ActBeacon.color_of("su"))
	burst(Vector3(-TerritoryCore.PYLON_GAP, 3.0, 3.0), ActBeacon.color_of("su"))
	var t := columns.tower_of(Session.wallet) if columns else {}
	var top := (t["root"] as Node3D).position + Vector3(0.0, BarColumns.height_for(after) + 2.0, 0.0) if not t.is_empty() else Vector3(-TerritoryCore.PYLON_GAP, 8.0, 3.0)
	burst(top, ActBeacon.color_of("crown"))
	rise_label(top, "+%s HYPOBAR%s" % [PlayLoop.dec(o["d_hypo"]), ("\n+%d FLOOR" % (int(o["floors_after"]) - int(o["floors_before"]))) if grew else ""], ActBeacon.color_of("crown"))
	_flare("su")
	_flare("crown")
	_next = _t + 4.0  # let the re-read land, then refresh the acts


func _on_beat_confirmed(block: int) -> void:
	hud.celebrate("THE HEART BEATS", "META.Beat · receipt status 1 · block %d" % block, ActBeacon.color_of("beat"))
	burst(Vector3(0.0, 11.0, 0.0), ActBeacon.color_of("beat"))
	_flare("beat")


func _on_posted(lines: Array, res: Dictionary) -> void:
	if lines.is_empty() or String(lines[0].get("qing", "")) != qing:
		return
	var block := int(res.get("block", -1))
	var delta := "—"
	var ps: PlayerState = Session.player
	if ps != null and ps.has_yue() and block > 0:
		var a := await Chain.rpc.call_decoded(ps.yue, "Bar(address)", [qing], ["uint256", "uint256"], "", block - 1)
		var b := await Chain.rpc.call_decoded(ps.yue, "Bar(address)", [qing], ["uint256", "uint256"], "", block)
		if a["ok"] and b["ok"]:
			delta = PlayLoop.dec(BigInt.sub(BigInt.from_hex(b["values"][0]), BigInt.from_hex(a["values"][0])))
	if not is_inside_tree():
		return
	hud.celebrate("YOUR LINE IS ON CHAIN", "+%s Hypobar here (YUE.Bar at %d → %d) · block %d" % [delta, block - 1, block, block], ActBeacon.color_of("room"))
	burst(Vector3(0.0, 3.0, TerritoryCore.ROOM_RADIUS + 1.9), ActBeacon.color_of("room"))
	_flare("room")


func _flare(key: String) -> void:
	var b: ActBeacon = _beacons.get(key)
	if b:
		b.flare()


## A one-shot burst of light (Core-local).
func burst(at: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 90
	p.lifetime = 1.8
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0.0, -5.0, 0.0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, col.lerp(Color.WHITE, 0.6))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.18
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.material = mat
	p.mesh = m
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


## A number rising from where it happened, then fading.
func rise_label(at: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = DeepFieldTheme.mono_font()
	l.font_size = 64
	l.pixel_size = 0.012
	l.outline_size = 14
	l.outline_modulate = Color(0.01, 0.015, 0.03, 0.85)
	l.modulate = col.lerp(Color.WHITE, 0.4)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = at
	add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", at.y + 7.0, 4.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(2.8)
	tw.chain().tween_callback(l.queue_free)
