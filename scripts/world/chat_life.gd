class_name ChatLife
extends Node3D
## The room's chat made visible in the territory (a child of the Core).
## Everything here is drawn from the room's own lines (territory state, the
## same for every viewer), except a bubble over a present player:
## - a new line floats as a speech bubble over its speaker when they are here
##   (ChatFeed.bubble_for: your own avatar, remote avatars from the presence
##   server); otherwise their echo (SpeakerEchoes, a hologram) rises from the
##   ground around the Room and speaks;
## - the Room's crown ring glows with the lines of the last day
##   (ChatLines.glow_for) and sends a ripple up on every new line;
## - the day's top three speakers carry a marker on their skyline tower
##   (BarColumns: towers exist for players with bars here).

const ECHO_R := 10.5
const ECHO_ANGLES := [38.0, 62.0, 118.0, 142.0, 220.0, 320.0]  # around the Room; +Z (90°) is the door
const BUBBLE_S := 9.0
const TOP := 3

var columns: BarColumns
var state: TerritoryState
var player: Node3D
var echoes: SpeakerEchoes
var tint := DeepFieldTheme.ICE
var glow := 0.0
var _pulse := 0.0
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _markers := {}  # wallet → Node3D
var _bubbles: Array = []  # [{node, t}]
var _refreshing := false
var _t := 0.0
var _feed: RoomFeed


func setup(core: TerritoryCore, p_columns: BarColumns, p_state: TerritoryState, p_player: Node3D, p_tint: Color) -> void:
	columns = p_columns
	state = p_state
	player = p_player
	tint = p_tint
	echoes = SpeakerEchoes.new()
	echoes.name = "ChatEchoes"
	add_child(echoes)
	var spots: Array = []
	for a_deg in ECHO_ANGLES:
		var a := deg_to_rad(a_deg)
		var at := Vector3(cos(a) * ECHO_R, 0.0, sin(a) * ECHO_R)
		var face := Vector3(at.x * 3.0, 0.0, at.z * 3.0 + 12.0)  # outward, toward arrival
		spots.append(Transform3D(Basis.looking_at(face - at, Vector3.UP, true), at))
	echoes.spots = spots
	# The Room's crown ring (TerritoryCore) carries the day's glow.
	var room := core.get_node_or_null("Room")
	if room:
		for c in room.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh:
				_ring_mat = (c as MeshInstance3D).material_override as StandardMaterial3D
	_light = OmniLight3D.new()
	_light.light_color = tint.lerp(DeepFieldTheme.ICE, 0.5)
	_light.omni_range = 16.0
	_light.light_energy = 0.0
	_light.position = Vector3(0.0, 5.5, 0.0)
	add_child(_light)
	ChatFeed.bubble.connect(_on_line)
	ChatFeed.current_changed.connect(_bind)
	ChatFeed.posted.connect(func(_ls, _res): state.refresh())  # re-read the bars a post moved
	state.changed.connect(_on_state)
	Session.changed.connect(_register_me)
	_register_me()
	_bind(ChatFeed.current)


func _bind(f: RoomFeed) -> void:
	if _feed and is_instance_valid(_feed) and _feed.lines_changed.is_connected(_on_lines):
		_feed.lines_changed.disconnect(_on_lines)
	_feed = f
	if f == null:
		return
	f.lines_changed.connect(_on_lines)
	if not f.lines.is_empty():
		_on_lines(f.lines)


func _register_me() -> void:
	if Session.wallet != "" and player:
		ChatFeed.register_speaker(Session.wallet, player)


## Ω for the chat bar's "what posting does here" note.
func _on_state() -> void:
	ChatFeed.omega = state.omega
	ChatFeed.note_changed.emit()
	_refresh_markers()


func _on_lines(ls: Array) -> void:
	echoes.update_from(ls.filter(func(l): return ChatLines.is_chain_shaped(l)))
	for lab in echoes.find_children("*", "Label3D", true, false):
		(lab as Label3D).pixel_size = 0.0075  # read from the plaza, not from inside a hall
	var st: Dictionary = ChatFeed.stats()
	glow = ChatLines.glow_for(int(st["count"]))
	_refresh_markers()
	Inspector.register(self, "Room glow, echoes and bubbles",
		"The Room's crown ring glows with this room's lines in the last %s blocks (≈ 24 h): %s line%s, glow %.2f (log scale, full at %d a day). Each new line sends a ripple up.\nEchoes: holograms of the latest %d speakers (LogEvent Username), each with their last line and its block.\nBubbles: a new line floats over its speaker when they stand here (your avatar; others' from the presence server), else their echo rises.\nTower markers: the day's top %d speakers by lines, on their skyline tower (speaker = the line's tx.from)." % [
			TokenFormat.group(str(ChatLines.DAY_BLOCKS)), ChatLines.count_text(st), "" if int(st["count"]) == 1 else "s", glow,
			ChatLines.FULL_GLOW_LINES, SpeakerEchoes.MAX, TOP])


## The day's top speakers → a marker on their tower (when they have one).
func _refresh_markers() -> void:
	if _refreshing or _feed == null or columns == null:
		return
	_refreshing = true
	var st: Dictionary = ChatFeed.stats()
	var day: Array = _feed.lines.filter(func(l): return ChatLines.is_chain_shaped(l) and int(l["block"]) > int(st["from_block"]))
	if day.any(func(l): return not l.has("wallet")):
		await _feed.resolve_wallets(day)
		st = ChatFeed.stats()
	var top: Array = st["speakers"].filter(func(s): return String(s["wallet"]) != "").slice(0, TOP)
	var keep := {}
	for i in top.size():
		var s: Dictionary = top[i]
		var w := String(s["wallet"])
		var tw: Dictionary = columns.tower_of(w)
		if tw.is_empty():
			continue
		keep[w] = true
		var m: Node3D = _markers.get(w)
		if m == null or not is_instance_valid(m):
			m = _make_marker()
			_markers[w] = m
		if m.get_parent() != tw["root"]:
			if m.get_parent():
				m.get_parent().remove_child(m)
			(tw["root"] as Node3D).add_child(m)
		m.position = Vector3(0.0, float(tw["height"]) + 6.2, 0.0)
		(m.get_node("Label") as Label3D).text = "TOP SPEAKER #%d · %s\n%d line%s today" % [i + 1, String(s["name"]), int(s["lines"]), "" if int(s["lines"]) == 1 else "s"]
	for w in _markers.keys():
		if not keep.has(w):
			if is_instance_valid(_markers[w]):
				(_markers[w] as Node).queue_free()
			_markers.erase(w)
	_refreshing = false


func _make_marker() -> Node3D:
	var root := Node3D.new()
	var gem := MeshInstance3D.new()
	gem.name = "Gem"
	var sm := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 1.8
	sm.radial_segments = 4
	sm.rings = 2
	gem.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = DeepFieldTheme.ICE
	mat.emission_enabled = true
	mat.emission = DeepFieldTheme.ICE
	mat.emission_energy_multiplier = 3.0
	gem.material_override = mat
	root.add_child(gem)
	var lab := Label3D.new()
	lab.name = "Label"
	lab.font = DeepFieldTheme.mono_font()
	lab.font_size = 40
	lab.pixel_size = 0.012
	lab.modulate = DeepFieldTheme.ICE
	lab.outline_size = 8
	lab.outline_modulate = Color(0, 0, 0, 0.85)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position.y = 1.9
	root.add_child(lab)
	return root


# --- New lines ------------------------------------------------------------------------

func _on_line(l: Dictionary) -> void:
	_pulse = 1.0
	_ripple()
	var anchor: Node3D = ChatFeed.bubble_for(String(l.get("wallet", "")))
	if anchor:
		_bubble(anchor, Vector3(0.0, 2.55, 0.0), l)
		return
	if l.get("world_pos") is Vector3:
		var spot := Node3D.new()
		get_tree().current_scene.add_child(spot)
		spot.global_position = l["world_pos"]
		_bubble(spot, Vector3(0.0, 2.55, 0.0), l, true)
		return
	if not ChatLines.is_chain_shaped(l):
		return
	# Not here in person: their echo rises from the ground around the Room.
	var fig := echoes.figure_for(l)
	if fig:
		var y := fig.position.y
		fig.position.y = y - 2.4
		var tw := fig.create_tween()
		tw.tween_property(fig, "position:y", y, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var lab := fig.find_child("*", false, false)
		for c in fig.get_children():
			if c is Label3D:
				lab = c
		if lab is Label3D:
			(lab as Label3D).modulate = Color(1.0, 1.0, 1.0)
			lab.create_tween().tween_property(lab, "modulate", Color(0.75, 0.92, 1.0), 4.0)


## A speech bubble over `anchor`: the line (and its block, or "say").
func _bubble(anchor: Node3D, offset: Vector3, l: Dictionary, free_anchor: bool = false) -> void:
	var lab := Label3D.new()
	lab.font = DeepFieldTheme.body_font()
	lab.font_size = 30
	lab.pixel_size = 0.0045
	lab.width = 520.0
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.modulate = DeepFieldTheme.INK
	lab.outline_size = 14
	lab.outline_modulate = Color(0.02, 0.03, 0.06, 0.92)
	var tag := "say · not on chain" if String(l.get("source", "")) == "say" else "block %d" % int(l.get("block", -1))
	lab.text = "%s%s · %s\n%s" % [ChatLines.speaker(l), ChatLines.badge_mark(l), tag, ChatLines.clean_text(String(l.get("text", "")), 120)]
	lab.position = offset
	anchor.add_child(lab)
	var tw := lab.create_tween()
	lab.scale = Vector3.ONE * 0.6
	tw.tween_property(lab, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(BUBBLE_S)
	tw.tween_property(lab, "modulate:a", 0.0, 1.2)
	tw.tween_callback(func():
		lab.queue_free()
		if free_anchor and is_instance_valid(anchor):
			anchor.queue_free())


## A ring of light leaves the Room's crown and rises.
func _ripple() -> void:
	var r := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = TerritoryCore.ROOM_RADIUS + 0.4
	tor.outer_radius = TerritoryCore.ROOM_RADIUS + 0.62
	tor.rings = 48
	r.mesh = tor
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(tint.lerp(DeepFieldTheme.ICE, 0.5), 0.9)
	r.material_override = m
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.position.y = 4.6
	add_child(r)
	var tw := r.create_tween().set_parallel(true)
	tw.tween_property(r, "position:y", 14.0, 2.6)
	tw.tween_property(r, "scale", Vector3(1.6, 1.0, 1.6), 2.6)
	tw.tween_property(m, "albedo_color:a", 0.0, 2.6)
	tw.chain().tween_callback(r.queue_free)


## --view=chat: the Room's front, its echoes and its glow.
func frame(cam: Camera3D) -> void:
	cam.global_position = global_position + Vector3(0.0, 3.4, 19.0)
	cam.look_at(global_position + Vector3(0.0, 2.6, 0.0))
	cam.fov = 62.0


func _process(delta: float) -> void:
	_t += delta
	_pulse = maxf(0.0, _pulse - delta * 0.5)
	var breath := 0.5 + 0.5 * sin(_t * (0.8 + 1.6 * glow))
	if _ring_mat:
		_ring_mat.emission_energy_multiplier = 1.5 + glow * (2.0 + 1.5 * breath) + _pulse * 4.0
	if _light:
		_light.light_energy = glow * (0.8 + 0.6 * breath) + _pulse * 3.0
	for m in _markers.values():
		if is_instance_valid(m):
			(m as Node3D).get_node("Gem").rotation.y += delta * 1.2
