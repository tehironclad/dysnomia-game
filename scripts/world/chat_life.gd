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
var _room_tag: Label3D


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
	_room_tag = core.get_node_or_null("Room/RoomTag") as Label3D
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
	if _room_tag:
		_room_tag.text = room_tag(_feed != null and _feed.is_loaded(), st, ls, maxi(_feed.head_seen if _feed else -1, Chain.head_block))
	_refresh_markers()
	Inspector.register(self, "Room glow, echoes and bubbles",
		"The Room's crown ring glows with this room's lines in the last %s blocks (≈ 24 h): %s line%s, glow %.2f (log scale, full at %d a day). Each new line sends a ripple up.\nEchoes: holograms of the latest %d speakers (LogEvent Username), each with their last line and its block.\nBubbles: a new line floats over its speaker when they stand here (your avatar; others' from the presence server), else their echo rises.\nTower markers: the day's top %d speakers by lines, on their skyline tower (speaker = the line's tx.from)." % [
			TokenFormat.group(str(ChatLines.DAY_BLOCKS)), ChatLines.count_text(st), "" if int(st["count"]) == 1 else "s", glow,
			ChatLines.FULL_GLOW_LINES, SpeakerEchoes.MAX, TOP])


## Pure: the words over the Room's door, from its own lines: "THE ROOM" while
## they are read, then how many lines today, or how long it has been quiet.
static func room_tag(loaded: bool, st: Dictionary, ls: Array, head: int) -> String:
	if not loaded:
		return "THE ROOM"
	var n := int(st.get("count", 0))
	if n > 0:
		return "THE ROOM · %s LINE%s TODAY" % [ChatLines.count_text(st), "" if n == 1 else "S"]
	var last := -1
	for l in ls:
		if ChatLines.is_chain_shaped(l):
			last = maxi(last, int(l["block"]))
	if last < 0:
		return "THE ROOM · SILENT"
	return "THE ROOM · QUIET %s" % ChatLines.age_text(last, head).to_upper()


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


## A speech bubble over `anchor`: a dark glass plate with the speaker's name in
## their colour (as in the chat dock) over the line, and the block (or "say").
## A line that names you has a gold edge. It pops in, holds, and fades.
func _bubble(anchor: Node3D, offset: Vector3, l: Dictionary, free_anchor: bool = false) -> void:
	var b := make_bubble(l, _names_me(l))
	b.position = offset
	anchor.add_child(b)
	b.scale = Vector3.ONE * 0.6
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(BUBBLE_S)
	tw.tween_method(func(a: float): _bubble_alpha(b, a), 1.0, 0.0, 1.2)
	tw.tween_callback(func():
		b.queue_free()
		if free_anchor and is_instance_valid(anchor):
			anchor.queue_free())


func _names_me(l: Dictionary) -> bool:
	var ps: PlayerState = Session.player
	if ps == null or ps.username == "" or String(l.get("wallet", "")) == Session.wallet:
		return false
	return ChatLines.mentions(String(l.get("text", "")), ps.username)


const BUBBLE_PX := 0.0052  # metres a label pixel
const BUBBLE_W := 520.0  # the line wraps at this many label pixels
const BUBBLE_PAD := 18.0


## The bubble (its bottom edge at the origin): plate, accent bar, name, line.
## Everything is billboarded on the vertical axis through the origin, so the
## parts stay stacked from any side.
static func make_bubble(l: Dictionary, names_me: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Bubble"
	var col := ChatLines.speaker_color(l)
	var tag := "say · not on chain" if String(l.get("source", "")) == "say" else "block %s" % TokenFormat.group(str(int(l.get("block", -1))))
	var name_text := "%s%s  ·  %s" % [ChatLines.speaker(l), ChatLines.badge_mark(l), tag]
	var body := ChatLines.clean_text(String(l.get("text", "")), 120)
	var body_font := DeepFieldTheme.body_font()
	var name_font := DeepFieldTheme.mono_font()
	var bs := body_font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_CENTER, BUBBLE_W, 32)
	var ns := name_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	var w_px := maxf(minf(maxf(bs.x, ns.x), BUBBLE_W + 40.0), 160.0) + BUBBLE_PAD * 2.0
	var h_px := bs.y + ns.y + 8.0 + BUBBLE_PAD * 2.0
	var w := w_px * BUBBLE_PX
	var h := h_px * BUBBLE_PX
	var plate := _quad(Vector2(w, h), Color(0.02, 0.03, 0.06, 0.82), 0)
	plate.name = "Plate"
	plate.position.y = h * 0.5
	root.add_child(plate)
	var edge := _quad(Vector2(w, 0.035), Color(Color("#ffd27a") if names_me else col, 0.95), 1)
	edge.name = "Edge"
	edge.position.y = h - 0.0175
	root.add_child(edge)
	var tail := _quad(Vector2(0.16, 0.16), Color(0.02, 0.03, 0.06, 0.82), 0, true)
	tail.name = "Tail"
	tail.position.y = 0.0
	root.add_child(tail)
	var nl := _label(name_font, 22, col.lerp(Color.WHITE, 0.15))
	nl.name = "Name"
	nl.text = name_text
	nl.position.y = h - (BUBBLE_PAD + ns.y * 0.5) * BUBBLE_PX
	root.add_child(nl)
	var tl := _label(body_font, 32, Color("#ffe6a8") if names_me else DeepFieldTheme.INK)
	tl.name = "Line"
	tl.text = body
	tl.width = BUBBLE_W
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.position.y = (BUBBLE_PAD + bs.y * 0.5) * BUBBLE_PX
	root.add_child(tl)
	return root


static func _label(font: Font, size: int, c: Color) -> Label3D:
	var lab := Label3D.new()
	lab.font = font
	lab.font_size = size
	lab.pixel_size = BUBBLE_PX
	lab.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lab.no_depth_test = true
	lab.modulate = c
	lab.outline_size = 6
	lab.outline_modulate = Color(0.02, 0.03, 0.06, 0.9)
	lab.render_priority = 3
	lab.outline_render_priority = 2
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lab


static func _quad(size: Vector2, c: Color, prio: int, diamond: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	if diamond:
		mi.rotation_degrees.z = 45.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.no_depth_test = true
	m.albedo_color = c
	m.render_priority = prio
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _bubble_alpha(b: Node3D, a: float) -> void:
	if not is_instance_valid(b):
		return
	for c in b.get_children():
		if c is Label3D:
			(c as Label3D).modulate.a = a
			(c as Label3D).outline_modulate.a = 0.9 * a
		elif c is MeshInstance3D:
			var m := (c as MeshInstance3D).material_override as StandardMaterial3D
			m.albedo_color.a = minf(m.albedo_color.a, 0.95 * a)


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
