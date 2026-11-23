class_name Phenomena
extends Node3D
## On-chain events made visible (WP 5.6, plan §3.6). Every phenomenon carries
## its block number. Watches, from the moment the territory opens (history is
## not replayed as events):
## - bars moved here (TerritoryState.bars_moved) → a cascade up the pylons;
## - a room line here (LogEvent 0xb916… from this QING) → etched on the wall;
## - a Void line (LogEvent 0x6b81… from Fomalhaute) → the monolith and ticker;
## - a new territory anywhere (NewQing via Registry.catch_up) → a named
##   shooting star crossing the sky.

signal room_lines(lines: Array)
signal void_lines(lines: Array)

const LOG_POLL_S := 12.0
const FOUNDING_POLL_S := 90.0

var qing := ""
var core: TerritoryCore
var hud: HudV2
var monolith: VoidMonolith
var sky_y := 160.0
var _room_after := -1
var _void_after := -1
var _polling := false
var _stars: Array = []


func setup(p_qing: String, p_core: TerritoryCore, p_hud: HudV2, p_monolith: VoidMonolith, state: TerritoryState, ground_y: float) -> void:
	qing = p_qing.to_lower()
	core = p_core
	hud = p_hud
	monolith = p_monolith
	sky_y = ground_y + 170.0
	state.bars_moved.connect(_on_bars_moved)
	Registry.founded.connect(_on_founded)
	var t1 := Timer.new()
	t1.wait_time = LOG_POLL_S
	t1.timeout.connect(_poll_logs)
	add_child(t1)
	t1.start()
	var t2 := Timer.new()
	t2.wait_time = FOUNDING_POLL_S
	t2.timeout.connect(func(): if not Registry.catching_up: Registry.catch_up())
	add_child(t2)
	t2.start()
	_prime()


## The latest few lines, so the wall and the monolith are not blank on arrival
## (shown as history, not as events).
func _prime() -> void:
	var head := await Chain.refresh_head()
	if head < 0:
		return
	_room_after = head
	_void_after = head
	var q := Registry.get_territory(qing)
	var rh: Dictionary = await ChatLog.room_history(qing, int(q.get("block", Contracts.MAP_FIRST_BLOCK)), head, 6)
	for l in rh["lines"]:
		core.etch_line("%s: %s" % [l["name"], l["text"]], l["block"])
	var vh: Dictionary = await ChatLog.void_history(head, 1)
	if not vh["lines"].is_empty():
		monolith.show_line(vh["lines"][-1])


func _poll_logs() -> void:
	if _polling or _room_after < 0:
		return
	_polling = true
	var head := await Chain.refresh_head()
	if head > _room_after:
		var r: Dictionary = await ChatLog.tail(qing, true, _room_after, head)
		if r["ok"]:
			_room_after = head
			for l in r["lines"]:
				core.etch_line("%s: %s" % [l["name"], l["text"]], l["block"])
				hud.ticker("ROOM · %s · block %d" % [ChatLog.format_line(l).split("] ", true, 1)[1], l["block"]])
			if not r["lines"].is_empty():
				room_lines.emit(r["lines"])
				Cues.play(self, "line")
	if head > _void_after:
		var v: Dictionary = await ChatLog.tail(Contracts.FOMALHAUTE, false, _void_after, head)
		if v["ok"]:
			_void_after = head
			for l in v["lines"]:
				monolith.show_line(l)
				hud.ticker("VOID · %s · block %d" % [ChatLog.format_line(l).split("] ", true, 1)[1], l["block"]], DeepFieldTheme.MUTED)
			if not v["lines"].is_empty():
				void_lines.emit(v["lines"])
	_polling = false


func _on_bars_moved(delta: PackedInt64Array, block: int) -> void:
	var lg := BigInt.log10(delta)
	core.cascade(0.0 if is_inf(lg) else clampf(lg / 9.0, 0.0, 1.0))
	Cues.play(self, "cascade")
	hud.ticker("BARS · +%s Hypobar here (known players) · block %d" % [TokenFormat.group(BigInt.to_decimal(delta)), block], Color("#ffb070"))


func _on_founded(records: Array) -> void:
	for i in records.size():
		var r: Dictionary = records[i]
		var nm := String(r.get("name", ""))
		if nm == "":
			nm = String(r["address"]).left(10)
		hud.ticker("NEW TERRITORY · %s · block %d" % [nm, int(r.get("block", -1))], Color("#ffd27a"), 40.0)
		shooting_star("%s · block %d" % [nm, int(r.get("block", -1))], i * 2.5)
	if not records.is_empty():
		Cues.play(self, "founded")


## A streak across the sky carrying a name.
func shooting_star(text: String, delay: float = 0.0) -> void:
	var root := Node3D.new()
	add_child(root)
	var streak := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(14.0, 0.25, 0.25)
	streak.mesh = bx
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("#fff3c4")
	m.emission_enabled = true
	m.emission = Color("#ffd27a")
	m.emission_energy_multiplier = 6.0
	streak.mesh = bx
	streak.material_override = m
	root.add_child(streak)
	var lab := Label3D.new()
	lab.font = DeepFieldTheme.mono_font()
	lab.font_size = 96
	lab.pixel_size = 0.06
	lab.text = text
	lab.modulate = Color("#ffd27a")
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = Vector3(0.0, -6.0, 0.0)
	root.add_child(lab)
	var z := -220.0 + randf() * 80.0
	root.position = Vector3(-320.0, sky_y, z)
	root.rotation.z = deg_to_rad(-8.0)
	root.visible = false
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): root.visible = true)
	tw.tween_property(root, "position", Vector3(320.0, sky_y - 60.0, z + 40.0), 9.0)
	tw.tween_callback(root.queue_free)
