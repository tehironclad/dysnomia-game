extends GamesPlace
## Sunny's Pub, in TehSunFlowrScioety QING (q☀️🌻). You arrive on the street
## facing its front: the neon SUNNY'S PUB sign over the door, suns either
## side, sunflowers in the planters, string lights. Inside (PubRoom): brick and
## planks, the long bar under the AFFECTION ON TAP board, a backlit wall of
## bottles, booths, sofas on rugs, darts, neon and a crystal chandelier; Sunny
## (the sun-headed goat) behind the bar and the regulars (PubLife). The games
## stay: a corner of arcade cabinets (1 Ⓐ a play, paid to this QING), the pool
## table and the card table, played in this QING's room lines.
##
## The bar menu (BarMenu, at the counter): every drink is the visitor's own real
## call through the write rule, then measured on chain; a round for the house
## is 1 Ⓐ to this QING, and the room cheers only once the receipt shows it.
##
## Ordering (2026-11-25): Pour hides the menu at once; while the wallet works a small line says
## where it is (the menu's own status words). Once the receipt is read, PourScene shows Sunny
## pouring and sliding the glass down, then you drinking it (any key skips); then the menu comes
## back with what the chain measured. A failed order brings the menu straight back with why.
## Sunny's words are VoiceLines (real recordings when they exist; subtitles always).

const HX := PubRoom.W
const BACK := PubRoom.BACK
const FRONT := PubRoom.FRONT
const STREET := 17.0
const BAR_ZONE := Rect2(PubRoom.COUNTER_X0 - 0.6, PubRoom.COUNTER_Z + 0.4, PubRoom.COUNTER_X1 - PubRoom.COUNTER_X0 + 1.2, 2.6)

var room: PubRoom
var life: PubLife
var bar_menu: BarMenu
var sunny: Node3D
var _bubble: Label3D
var _bubble_t := 0.0
var _talk_i := 0
var _till: Label3D
var _deco := PubKit.Batch.new()  # sunflowers, suns and stems: a few draw calls
var bar_state := "idle"  ## the bar: idle | menu | waiting (the wallet has the order) | pour (PourScene)
var pour_scene: PourScene
var subtitles: SubtitleBar
var _wait_chip: PanelContainer
var _wait_label: Label
var _wait_said := false
var _greeted := false
var _idle_t := 40.0
var _idle_i := 0


func _ready() -> void:
	load_territory()
	floor_y = 0.0
	_environment()
	_street()
	room = PubRoom.new()
	room.build(self, BarMenu.board_lines())
	life = PubLife.new()
	add_child(life)
	life.setup(room)
	sunny = life.sunny
	_signs()
	_deco.commit(self, "Deco")
	var entries: Array = load("res://scripts/places/arcade_place.gd")._catalog().filter(func(e): return e.get("playable", true) and e.get("kind", "game") != "cartridge")
	for i in mini(3, entries.size()):
		add_cabinet(entries[i], Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-HX + 0.7, 0, -2.6 + i * 1.3)))
	add_pool_table(Transform3D(Basis(), Vector3(4.0, 0, 1.8)))
	add_card_table(Transform3D(Basis(), Vector3(-3.6, 0, 3.2)))
	exit_at = Vector3(0, 0, STREET - 0.8)
	exit_radius = 2.2
	setup_player(Vector3(0, 0.1, STREET - 3.0), 0.0)
	add_door("curtain", 3.0, 2.8, Vector3(0, 0, STREET - 0.1), Color(1.0, 0.8, 0.45))
	setup_hud("SUNNY'S PUB · %s" % String(territory.get("name", "")).to_upper())
	info_label.text = "The bar (%s at the counter: drinks are your own AFFECTION calls, 1–2 Ⓐ each to this QING; a round is %s), the arcade (%s), pool and Twenty-One in this room's lines (%s: the chat)." % [
		ControlsHelp.key_of("bar_menu"), Prices.text(Prices.ROUND), Prices.menu_line(), ControlsHelp.key_of("chat")]
	var spots: Array = []
	for x in [-5.6, -4.3, -3.0, 0.9, 2.2, 3.5]:
		var at := Vector3(x, 0.0, -2.9)
		spots.append(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP, true), at))
	setup_games(spots)
	_build_menu()
	add_spot(PubRoom.order_spot(), 1.4, func(): return "order at the bar: Sunny's menu (AFFECTION on tap)", _open_menu)
	_read_till()
	_apply_view()


func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.55, 0.45)
	e.ambient_light_energy = 0.28
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 1.0
	we.environment = e
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -30, 0)
	moon.light_energy = 0.22
	moon.light_color = Color(0.7, 0.75, 1.0)
	add_child(moon)
	Config.register_scene(e, moon)


func _street() -> void:
	box(self, Vector3(30, 0.2, STREET - FRONT + 2), Vector3(0, -0.1, (STREET + FRONT) * 0.5), mat(Color(0.16, 0.16, 0.18), 0.9), true)
	box(self, Vector3(30, 0.02, 3.0), Vector3(0, 0.01, FRONT + 1.6), mat(Color(0.3, 0.28, 0.26), 0.85))  # pavement
	var brick := PubKit.pbr("brick_wall_02", 2.4, Color(0.95, 0.72, 0.6))
	var wood := PubKit.pbr("dark_planks", 1.2, Color(0.75, 0.6, 0.5))
	# The facade with its door, two bay windows lit warm from inside.
	box(self, Vector3(HX - 1.1, 5.0, 0.4), Vector3(-(HX + 1.1) * 0.5, 2.5, FRONT), brick, true)
	box(self, Vector3(HX - 1.1, 5.0, 0.4), Vector3((HX + 1.1) * 0.5, 2.5, FRONT), brick, true)
	box(self, Vector3(2.2, 1.8, 0.4), Vector3(0, 4.1, FRONT), brick)
	box(self, Vector3(2.4, 0.15, 0.5), Vector3(0, 3.2, FRONT), wood)
	# Bay windows: dark glass glowing warm from inside, so the OPEN neon reads against it.
	var warm := ShaderMaterial.new()
	warm.shader = load("res://assets/shaders/pub_window.gdshader")
	warm.set_shader_parameter("glass_tint", Color(0.05, 0.03, 0.02))
	warm.set_shader_parameter("glow_tint", Color(1.0, 0.62, 0.28))
	warm.set_shader_parameter("glow", 0.3)
	warm.set_shader_parameter("size_m", Vector2(3.0, 1.8))
	for sx in [-1.0, 1.0]:
		box(self, Vector3(3.0, 1.8, 0.06), Vector3(sx * 4.2, 1.9, FRONT + 0.21), warm)
		box(self, Vector3(3.3, 0.14, 0.3), Vector3(sx * 4.2, 2.85, FRONT + 0.25), wood)
		box(self, Vector3(3.3, 0.14, 0.3), Vector3(sx * 4.2, 0.95, FRONT + 0.25), wood)
		box(self, Vector3(0.06, 1.8, 0.08), Vector3(sx * 4.2, 1.9, FRONT + 0.25), wood)  # mullion
		_planter(Vector3(sx * 4.2, 0, FRONT + 0.75))
	var sign := Label3D.new()
	sign.text = "SUNNY'S PUB"
	sign.font = DeepFieldTheme.display_font()
	sign.font_size = 150
	sign.pixel_size = 0.011
	sign.outline_size = 20
	sign.outline_modulate = Color(0.2, 0.05, 0.0, 0.9)
	sign.modulate = Color(1.0, 0.8, 0.25)
	sign.position = Vector3(0, 4.35, FRONT + 0.25)
	add_child(sign)
	var tag := Label3D.new()
	tag.text = "est. on PulseChain · affection on tap · arcade · pool · cards"
	tag.font = DeepFieldTheme.mono_font()
	tag.font_size = 40
	tag.pixel_size = 0.008
	tag.modulate = Color(1.0, 0.9, 0.7)
	tag.position = Vector3(0, 3.55, FRONT + 0.25)
	add_child(tag)
	for sx in [-1.0, 1.0]:
		_sun(Vector3(sx * 7.6, 4.2, FRONT + 0.25), 0.55)
	# OPEN in red neon in the right window; string lights along the facade.
	var open := MeshInstance3D.new()
	open.mesh = PubKit.text_mesh("OPEN", 0.008, 0.02, DeepFieldTheme.display_font())
	open.material_override = PubKit.neon(Color(1.0, 0.18, 0.12), 9.0)
	open.position = Vector3(4.2, 2.25, FRONT + 0.3)
	add_child(open)
	var bulbs: Array[Vector3] = []
	for seg in [[-7.4, -1.3], [1.3, 7.4]]:
		var n := 14
		for k in n + 1:
			var t := float(k) / float(n)
			bulbs.append(Vector3(lerpf(seg[0], seg[1], t), 3.05 - sin(t * PI) * 0.28, FRONT + 0.45))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PubKit.sphere(0.05, 8)
	mm.instance_count = bulbs.size()
	for i in bulbs.size():
		mm.set_instance_transform(i, Transform3D(Basis(), bulbs[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = PubKit.neon(Color(1.0, 0.72, 0.4), 6.0)
	add_child(mmi)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.78, 0.35)
	lamp.light_energy = 2.5
	lamp.omni_range = 10.0
	lamp.position = Vector3(0, 4.0, FRONT + 2.0)
	add_child(lamp)
	var back := Label3D.new()
	back.text = "BACK TO %s" % String(territory.get("name", "")).to_upper()
	back.font = DeepFieldTheme.mono_font()
	back.font_size = 36
	back.pixel_size = 0.01
	back.modulate = DeepFieldTheme.ICE
	back.position = Vector3(0, 2.6, STREET)
	back.rotation_degrees.y = 180.0
	add_child(back)
	box(self, Vector3(3.0, 0.06, 0.06), Vector3(0, 0.03, STREET - 0.2), glow(DeepFieldTheme.ICE, 2.0))
	# Keep people on the street.
	for sx in [-1.0, 1.0]:
		box(self, Vector3(0.2, 2.0, STREET - FRONT + 1), Vector3(sx * 7.5, 1.0, (STREET + FRONT) * 0.5 + 0.5), mat(Color(0.1, 0.1, 0.12)), true)
	box(self, Vector3(16, 2.0, 0.2), Vector3(0, 1.0, STREET + 0.6), mat(Color(0.1, 0.1, 0.12)), true)


func _planter(at: Vector3) -> void:
	box(self, Vector3(2.6, 0.5, 0.5), at + Vector3(0, 0.25, 0), mat(Color(0.28, 0.15, 0.08), 0.8), true)
	var green := PubKit.flat(Color(0.2, 0.45, 0.12))
	for i in 4:
		var x := -0.9 + i * 0.6
		var h := 1.1 + 0.15 * (i % 2)
		_deco.add_mesh(PubKit.cyl(0.02, 0.025, h, 6), Transform3D(Basis(), at + Vector3(x, 0.5 + h * 0.5, 0)), green)
		_sunflower(at + Vector3(x, 0.5 + h, 0.05))


## Petals and seed disc, batched with the rest of Sunny's decorations (_deco).
func _sunflower(at: Vector3, yaw: float = 0.0) -> void:
	var petal := PubKit.flat(Color(1.0, 0.78, 0.1), 0.7)
	var face := Transform3D(Basis(Vector3.UP, yaw), at)
	var pm := PubKit.sphere(0.06, 8)
	for k in 12:
		var a := TAU * k / 12.0
		var xf := Transform3D(Basis(Vector3.BACK, a - PI * 0.5) * Basis.from_scale(Vector3(0.45, 1.0, 0.2)), Vector3(cos(a) * 0.1, sin(a) * 0.1, 0))
		_deco.add_mesh(pm, face * xf, petal)
	_deco.add_mesh(PubKit.cyl(0.06, 0.06, 0.03, 12), face * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.01)), PubKit.flat(Color(0.25, 0.14, 0.05)))


func _sun(at: Vector3, r: float) -> void:
	var gold := glow(Color(1.0, 0.8, 0.2), 2.6)
	_deco.add_mesh(PubKit.cyl(r, r, 0.05, 24), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at), gold)
	for i in 12:
		var a := TAU * i / 12.0
		_deco.box_at(Vector3(0.08, r * 0.6, 0.04), at + Vector3(cos(a) * r * 1.55, sin(a) * r * 1.55, 0), gold, Vector3(0, 0, a - PI * 0.5))


## Sunny's own marks inside: the sun on the back wall, sunflowers painted by the
## booths, the till chalkboard (the QING's real balance, with its block), the bubble.
func _signs() -> void:
	_sun(Vector3(7.7, 3.7, BACK + 0.2), 0.45)
	for i in 3:
		_sunflower(Vector3(-HX + 0.2, 2.3 + 0.25 * (i % 2), 2.0 + i * 0.5), PI * 0.5)
	var board := Node3D.new()
	board.position = Vector3(4.85, 3.4, BACK + 0.17)
	add_child(board)
	box(board, Vector3(1.5, 0.95, 0.04), Vector3.ZERO, PubKit.pbr("wood_table_001", 1.0, Color(0.6, 0.45, 0.35)))
	box(board, Vector3(1.38, 0.83, 0.02), Vector3(0, 0, 0.025), mat(Color(0.06, 0.08, 0.07), 0.95))
	_till = Label3D.new()
	_till.font = DeepFieldTheme.mono_font()
	_till.font_size = 26
	_till.pixel_size = 0.0042
	_till.modulate = Color(0.92, 0.92, 0.86)
	_till.position = Vector3(0, 0, 0.04)
	_till.text = "THE TILL\nreading…"
	board.add_child(_till)
	_bubble = Label3D.new()
	_bubble.font = DeepFieldTheme.body_font()
	_bubble.font_size = 30
	_bubble.pixel_size = 0.005
	_bubble.width = 900.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.outline_size = 10
	_bubble.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	_bubble.modulate = Color(1.0, 0.93, 0.7)
	_bubble.position = Vector3(0, 2.3, 0)  # over Sunny's head, wherever Sunny is working
	_bubble.text = "Welcome to Sunny's! %s at the bar for the menu." % ControlsHelp.key_of("interact")
	sunny.add_child(_bubble)


## The QING's AFFECTION balance, read at a known block. "—" if it won't read.
func _read_till(block: int = -1) -> void:
	if block < 0:
		block = await Chain.refresh_head()
	if block < 0:
		_till.text = "THE TILL\nthis QING holds —\n(chain unavailable)"
		return
	var r := await ArcadePay.read_balance(qing, block)
	_till.text = ("THE TILL\nthis QING holds\n%s\nAFFECTION.balanceOf\nblock %s" % [ArcadePay.fmt(r["balance"]), TokenFormat.group(str(block))]) if r["ok"] else "THE TILL\nthis QING holds —\n(the read failed)"


func _build_menu() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(center)
	bar_menu = BarMenu.new()
	center.add_child(bar_menu)
	bar_menu.setup(qing, String(territory.get("name", "")))
	bar_menu.closed.connect(func():
		if bar_state != "menu":
			return
		bar_state = "idle"
		life.attend(Vector3.INF)
		say_line("goodbye")
		_resume())
	bar_menu.order_started.connect(_on_order_started)
	bar_menu.order_failed.connect(_on_order_failed)
	bar_menu.status_changed.connect(_on_order_status)
	bar_menu.poured.connect(func(d, r):
		_on_served(d["look"], 1, "· %s · block %s" % [d["name"], TokenFormat.group(str(r["block"]))]))
	bar_menu.round_bought.connect(func(r):
		life.cheer()
		_read_till(r["block"])
		_on_served(BarTab.ROUND["look"], 3, "· %s to this QING · block %s" % [ArcadePay.fmt(r["value"]), TokenFormat.group(str(r["block"]))]))
	pour_scene = PourScene.new()
	pour_scene.name = "PourScene"
	add_child(pour_scene)
	subtitles = SubtitleBar.new()
	_ui_layer.add_child(subtitles)
	_build_wait_chip()
	var ask := Button.new()
	ask.text = "Ask Sunny about the house"
	ask.pressed.connect(_talk)
	bar_menu.actions.add_child(ask)


func _open_menu(preselect: String = "") -> void:
	if bar_state != "idle":
		return
	bar_state = "menu"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	life.attend(player.global_position)
	life.talk(3.0)
	say_line("menu_open")
	bar_menu.open(preselect)


## Sunny says one of his lines (VoiceLines: his recording if it exists; the subtitle always),
## with a measured `detail` after the words in the subtitle only.
func say_line(id: String, detail: String = "") -> void:
	var r := VoiceLines.say(sunny, "sunny", id, detail)
	_say("Sunny: " + String(r["text"]), float(r["seconds"]) + 2.0)


## Sunny says `text` (the bubble over his head and the subtitle at the bottom).
func _say(text: String, seconds: float = 10.0) -> void:
	_bubble.text = text
	_bubble_t = seconds
	life.talk(minf(seconds, 5.0))
	if subtitles:
		var words := text.trim_prefix("Sunny: ")
		subtitles.show_line("Sunny", words.left(1).to_upper() + words.substr(1), seconds)
	_idle_t = maxf(_idle_t, seconds + 20.0)


# --- An order, from Pour to the drink -----------------------------------------------

## Pour / Buy pressed: the menu goes; a small line follows the wallet (simulate, sign, receipt).
func _on_order_started(d: Dictionary) -> void:
	if bar_state != "menu":
		return
	bar_state = "waiting"
	bar_menu.visible = false
	_wait_said = false
	_show_wait("%s · simulating from your wallet…" % String(d.get("name", "Your order")))
	say_line("order_taken")


func _on_order_status(text: String, _c: Color) -> void:
	if _wait_chip == null or not _wait_chip.visible:
		return
	_wait_label.text = text
	if not _wait_said and text.begins_with("Waiting for your signature"):
		_wait_said = true
		say_line("payment_waiting")


func _on_order_failed(_d: Dictionary, _r: Dictionary) -> void:
	_wait_chip.visible = false
	say_line("payment_failed")
	if bar_state == "waiting":
		bar_state = "menu"
		bar_menu.reveal()  # with why it wasn't poured
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## The receipt was read: the pour. Still at the bar: the scene; walked off: Sunny pours anyway.
func _on_served(look: Array, rounds: int, detail: String) -> void:
	_wait_chip.visible = false
	if bar_state != "waiting":
		life.play_pour(look, rounds)
		say_line("here_you_go", detail)
		return
	_play_pour(look, rounds, detail)


func _play_pour(look: Array, rounds: int, detail: String, preview_t: float = -1.0) -> void:
	bar_state = "pour"
	bar_menu.visible = false
	hud_layer.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	pour_scene.play(self, life, player, look, rounds, detail, say_line)
	if preview_t >= 0.0:
		pour_scene.preview_at(preview_t)
		return
	await pour_scene.finished
	hud_layer.visible = true
	bar_state = "menu"
	bar_menu.reveal()  # what the chain measured
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	life.attend(player.global_position)
	say_line("order_another")


func _build_wait_chip() -> void:
	_wait_chip = PanelContainer.new()
	_wait_chip.theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style(Color(1.0, 0.78, 0.4, 0.5))
	sb.bg_color = Color(DeepFieldTheme.BLACK, 0.86)
	_wait_chip.add_theme_stylebox_override("panel", sb)
	_wait_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait_chip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wait_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wait_chip.offset_top = 64
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait_chip.add_child(col)
	var t := Label.new()
	t.theme_type_variation = "DisplayLabel"
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	t.text = "YOUR ORDER · IN YOUR WALLET WINDOW"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	_wait_label = Label.new()
	_wait_label.theme_type_variation = "MonoLabel"
	_wait_label.add_theme_font_size_override("font_size", 15)
	_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_wait_label)
	var esc := Label.new()
	esc.theme_type_variation = "MutedLabel"
	esc.add_theme_font_size_override("font_size", 13)
	esc.text = "Esc: walk around meanwhile (Sunny pours when the chain has it)"
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(esc)
	_wait_chip.visible = false
	_ui_layer.add_child(_wait_chip)


func _show_wait(text: String) -> void:
	_wait_label.text = text
	_wait_chip.visible = true
	_wait_chip.reset_size()


## Sunny says what the chain says: the house's Ⓐ, the room's games, who owes.
func _talk() -> void:
	_talk_i += 1
	match _talk_i % 4:
		1:
			_say("Sunny: reading the till…")
			var head := await Chain.refresh_head()
			var r := {"ok": false}
			if head >= 0:
				r = await ArcadePay.read_balance(qing, head)
			_say(("Sunny: this QING holds %s (AFFECTION.balanceOf at block %d). Every play on those cabinets adds %s." % [ArcadePay.fmt(r["balance"]), head, ArcadePay.fee_text()]) if r["ok"] else "Sunny: the till won't read just now: —")
		2:
			var live := book.matches.filter(func(m): return m["status"] == "playing").size()
			var open := book.matches.filter(func(m): return m["status"] == "open").size()
			_say("Sunny: %d game%s on, %d challenge%s waiting, all in this room's lines. Grab a cue or a seat." % [live, "" if live == 1 else "s", open, "" if open == 1 else "s"])
		3:
			var owed: Array = book.debts().filter(func(d): return d["match"]["paid"] == false)
			if owed.is_empty():
				_say("Sunny: nobody owes anybody here, as far as the chain shows. Keep it that way.")
			else:
				var d: Dictionary = owed[0]
				_say("Sunny: %s still owes %s %s from game #%s. The chain remembers, friend." % [book.display(d["loser"]), book.display(d["winner"]), ArcadePay.fmt(d["stake"]), d["match"]["id"]])
		0:
			_say("Sunny: the AFFECTION pours mint into AFFECTION's own reserve, not your bars. Want your bars to grow? The House Su.")


func _any_open() -> bool:
	return super._any_open() or bar_state != "idle"


func _at_bar() -> bool:
	return player != null and BAR_ZONE.has_point(Vector2(player.global_position.x, player.global_position.z))


func _unhandled_input(event: InputEvent) -> void:
	match bar_state:
		"pour":  # any key skips to the end
			if GameHowto.is_press(event):
				get_viewport().set_input_as_handled()
				pour_scene.skip()
			return
		"waiting":  # Esc: walk around while the wallet works; the pour still comes
			if event.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				bar_state = "idle"
				_wait_label.text += "  ·  you stepped away"
				life.attend(Vector3.INF)
				_resume()
			return
	if bar_menu and bar_menu.is_open():
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			bar_menu.close()
		return
	if event.is_action_pressed("bar_menu") and not _any_open() and not is_walking_up() and not panel_open():
		get_viewport().set_input_as_handled()
		if _at_bar():
			_open_menu()
		elif player.global_position.z < FRONT:  # inside: the key works from anywhere, you walk up
			say_line("come_closer")
			walk_up_to(PubRoom.order_spot(), func(): _open_menu())
		return
	super._unhandled_input(event)


func _process(delta: float) -> void:
	super._process(delta)
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.text = "%s at the bar: the menu" % ControlsHelp.key_of("bar_menu")
	if life and player and bar_state == "idle":
		life.attend(player.global_position if _at_bar() else Vector3.INF)
		_idle_barks(delta)


## Sunny greets you once you're inside, and now and then says something to the room.
func _idle_barks(delta: float) -> void:
	if player.global_position.z > FRONT:
		return
	if not _greeted:
		_greeted = true
		say_line("greeting")
		return
	_idle_t -= delta
	if _idle_t <= 0.0:
		say_line(String(VoiceLines.IDLE_SUNNY[_idle_i % VoiceLines.IDLE_SUNNY.size()]))
		_idle_i += 1
		_idle_t = 45.0 + 20.0 * float(_idle_i % 3)


# --- Fixed views for tools/screenshot.gd (--view=street|bar|lounge|room|games|menu) ---

const VIEWS := {
	"street": [Vector3(3.4, 1.9, 15.6), Vector3(-0.6, 2.7, 8.0)],
	"bar": [Vector3(1.6, 1.75, 0.4), Vector3(-1.2, 2.0, -7.5)],
	"lounge": [Vector3(-0.8, 1.9, 4.2), Vector3(-7.6, 0.8, 5.8)],
	"room": [Vector3(8.6, 3.8, 7.2), Vector3(-3.0, 0.9, -4.5)],
	"games": [Vector3(-2.0, 2.4, -3.0), Vector3(-8.0, 1.0, 3.0)],
	"stools": [Vector3(-2.2, 1.55, -2.6), Vector3(-3.6, 1.1, -6.0)],
	"cabinets": [Vector3(4.5, 1.7, 0.5), Vector3(-9.3, 1.8, -1.3)],
}


## Previews of an order (tools/screenshot.gd --view=waiting|pour|slide|handover|drink|cheers):
## nothing is ordered, signed or sent; the subtitle says PREVIEW instead of a block.
const PREVIEW_POUR := {"pour": 0.9, "slide": 2.1, "handover": 3.3, "drink": 5.6, "cheers": 8.0}


func _preview_order(view: String) -> void:
	subtitles.hold = true
	_open_menu("alpha_sour")
	await get_tree().process_frame
	var d := BarTab.drink("alpha_sour")
	_on_order_started(d)
	if view == "waiting":
		_on_order_status("Waiting for your signature in the browser wallet…", DeepFieldTheme.ICE)
		return
	_wait_chip.visible = false
	_play_pour(d["look"], 1, "· PREVIEW: nothing was ordered", float(PREVIEW_POUR[view]))


func _apply_view() -> void:
	var view := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			view = a.substr(7)
	if view == "":
		return
	if view == "menu" or view == "order":
		player.position = PubRoom.order_spot() + Vector3(0.3, 0.1, 2.2)
		player.rotation.y = 0.0
		if view == "menu":
			_open_menu.call_deferred("alpha_sour")
		return
	if view == "waiting" or PREVIEW_POUR.has(view):
		_greeted = true
		player.position = PubRoom.order_spot() + Vector3(0.3, 0.1, 0.4)
		player.rotation.y = 0.0
		_preview_order.call_deferred(view)
		return
	if not VIEWS.has(view):
		return
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.look_at_from_position(VIEWS[view][0], VIEWS[view][1])
	cam.current = true
