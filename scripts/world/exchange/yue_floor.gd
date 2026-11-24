class_name YueFloor
extends Node3D
## The YUE Exchange in a tower's sky lobby: a glass pod hung off the front of the
## glass lift shaft, a stop of the existing lift (Landmark.exchange_y). Every
## landmark class carries one (Sky Inn, Grand Hotel, Supertall, Burj); below
## Settlement there is no tower and the Swap Hall's counter is the desk instead.
## Its boards show this territory's pair (QING.Asset(), the rate with its block,
## how many known YUEs hold stock) and the territories that have a rate: the
## same for every viewer. The desk opens the Hong/Hung panel (YuePanel).
## Local frame: the tower's (+Z = the front, the lift shaft at z = lift_z).

signal use_desk

const POD_W := 18.0
const POD_D := 12.0
const POD_H := 4.6
const REACH := 2.4
const BOARD_L := 10.0  ## the side boards: length along the wall, height, centre height
const BOARD_H := 3.6
const BOARD_Y := 2.35
const LIST_ROWS := 7    ## rated territories on the right-hand board (it must fit BOARD_H)

var floor_y := 0.0
var desk_at := Vector3.ZERO
var _lift_front := 0.0
var _player: CharacterBody3D
var _hud: Node
var _tint := Color("#7fd3ff")
var _board: Label3D
var _list: Label3D
var _focus := ""


## Pure: the exchange floor's height for a landmark spec: about a fifth of the roof,
## in whole 4 m floors, above the lobby (≥ 16 m) and a short ride (≤ 96 m).
static func floor_height(spec: Dictionary) -> float:
	if spec.is_empty():
		return -1.0
	var roof: float = spec["roof"]
	var f := clampf(snappedf(roof * 0.2, LandmarkPlan.FLOOR_M), 16.0, 96.0)
	return minf(f, roof - 12.0)


func build(spec: Dictionary, lift_info: Dictionary, player: CharacterBody3D, hud: Node, tint: Color, tower_title: String) -> void:
	_player = player
	_hud = hud
	_tint = tint
	floor_y = floor_height(spec)
	var lz: float = lift_info["z"]
	var half: float = lift_info["half"]
	_lift_front = lz + half
	position = Vector3(0, floor_y, 0)
	var z0 := _lift_front
	var z1 := z0 + POD_D
	var zc := (z0 + z1) * 0.5
	var metal := Landmark._metal(Color(0.14, 0.15, 0.17))
	var dark := Landmark._metal(Color(0.2, 0.19, 0.24))
	dark.metallic = 0.35
	dark.roughness = 0.12
	var glass := Landmark._glass(0.16)
	var glow := Landmark._glow(_tint, 2.0)
	var pink := Landmark._glow(Color("#ff8fd0"), 2.2)
	# The slab (and an invisible sill inside the shaft, so the car's stop has a floor)
	_box(Vector3(POD_W, 0.5, POD_D), Vector3(0, -0.25, zc), metal, true)
	_box(Vector3(POD_W - 0.4, 0.06, POD_D - 0.4), Vector3(0, 0.03, zc), dark)
	Solid.box(self, Vector3(half * 2.0, 0.5, half * 2.0), Vector3(0, -0.25, lz))
	_box(Vector3(POD_W + 0.2, 0.12, 0.2), Vector3(0, -0.5, z1), glow)
	# Struts back to the tower under the slab
	for s in [-1.0, 1.0]:
		var a := Vector3(s * (POD_W * 0.5 - 1.0), -0.5, z1 - 1.0)
		var b := Vector3(s * 3.0, -7.0, z0 - 3.0)
		var mid := (a + b) * 0.5
		var strut := _box(Vector3(0.35, 0.35, a.distance_to(b)), mid, metal)
		strut.look_at_from_position(mid, b, Vector3.UP)
	# Glass walls on three sides (solid), the back open to the shaft beside it
	for s in [-1.0, 1.0]:
		_box(Vector3(0.12, POD_H, POD_D), Vector3(s * POD_W * 0.5, POD_H * 0.5, zc), glass, true)
		_box(Vector3(0.16, POD_H, 0.16), Vector3(s * POD_W * 0.5, POD_H * 0.5, z1), glow)
		# The back either side of the lift door
		var bw := POD_W * 0.5 - half - 0.3
		_box(Vector3(bw, POD_H, 0.12), Vector3(s * (half + 0.3 + bw * 0.5), POD_H * 0.5, z0), glass, true)
	_box(Vector3(POD_W, POD_H, 0.12), Vector3(0, POD_H * 0.5, z1), glass, true)
	_box(Vector3(POD_W + 0.4, 0.35, POD_D + 0.4), Vector3(0, POD_H + 0.17, zc), metal, true)
	_box(Vector3(POD_W + 0.5, 0.1, 0.1), Vector3(0, POD_H, z1 + 0.2), glow)
	# The desk: a curved bar of three segments facing the lift, the view behind it
	var dz := z1 - 3.2
	for k in [-1, 0, 1]:
		var yaw: float = -0.35 * k
		_box(Vector3(3.2, 1.1, 0.9), Vector3(k * 3.0, 0.55, dz + absf(k) * 0.55), metal, true, yaw)
		_box(Vector3(3.25, 0.05, 0.95), Vector3(k * 3.0, 1.12, dz + absf(k) * 0.55), pink, false, yaw)
	var term := PlaceBase.load_piece("Prop_Computer")
	term.position = Vector3(0, 0.0, dz + 0.9)
	term.rotation.y = PI
	add_child(term)
	desk_at = Vector3(0, 0, dz - 1.3)
	var title := _label("YUE EXCHANGE", Vector3(0, POD_H - 0.9, z1 - 0.3), 0.012, 96, Color("#ffb8e6"), false, PI)
	title.outline_size = 10
	_label("%s · %d m · Hong / Hung at the territory's fixed rate" % [tower_title, int(floor_y)], Vector3(0, POD_H - 1.75, z1 - 0.3), 0.0075, 48, DeepFieldTheme.INK, true, PI)
	# Side boards: this territory's pair, and the territories that trade. Lit screens (a
	# self-lit navy face in a glowing frame) with the text centred on them, big enough to
	# read from the desk (2026-11-24: they were small, off-centre and on bare black metal).
	var face := Landmark._glow(Color(0.035, 0.05, 0.09), 1.0)
	var frame := Landmark._glow(_tint, 1.6)
	for s in [-1.0, 1.0]:
		var x: float = s * (POD_W * 0.5 - 0.15)
		_box(Vector3(0.06, BOARD_H, BOARD_L), Vector3(x, BOARD_Y, zc), face)
		for e in [-1.0, 1.0]:
			_box(Vector3(0.08, 0.06, BOARD_L + 0.12), Vector3(x, BOARD_Y + e * (BOARD_H * 0.5 + 0.03), zc), frame)
			_box(Vector3(0.08, BOARD_H, 0.06), Vector3(x, BOARD_Y, zc + e * (BOARD_L * 0.5 + 0.03)), frame)
	# A left-aligned Label3D starts at its position: each text starts a margin in from the
	# board's near end (the left board's text runs toward -z, the right board's toward +z).
	_board = _label("reading the desk…", Vector3(-POD_W * 0.5 + 0.2, BOARD_Y, zc + BOARD_L * 0.5 - 0.45), 0.0050, 64, DeepFieldTheme.INK, true, PI * 0.5)
	_list = _label("", Vector3(POD_W * 0.5 - 0.2, BOARD_Y, zc - BOARD_L * 0.5 + 0.45), 0.0038, 64, Color("#ffd27a"), true, -PI * 0.5)
	for l in [_board, _list]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.outline_size = 10
		l.outline_modulate = Color(0.0, 0.0, 0.02, 0.95)
		l.double_sided = false
	for p in [Vector3(-4, POD_H - 0.6, zc), Vector3(4, POD_H - 0.6, zc)]:
		var o := OmniLight3D.new()
		o.position = p
		o.light_color = Color(1.0, 0.9, 0.96)
		o.light_energy = 3.0
		o.omni_range = 11.0
		add_child(o)


func _box(size: Vector3, at: Vector3, mat: Material, solid: bool = false, yaw: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.rotation.y = yaw
	mi.material_override = mat
	add_child(mi)
	if solid:
		Solid.box(self, size, at, yaw)
	return mi


func _label(text: String, at: Vector3, px: float, size: int, color: Color, mono: bool, yaw: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = DeepFieldTheme.mono_font() if mono else DeepFieldTheme.display_font()
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 4
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.position = at
	l.rotation.y = yaw
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


## Boards from the reads (YueExchange.read_desk without a wallet, rated_scan).
func show_desk(d: Dictionary, name: String, rated: Variant) -> void:
	if _board:
		_board.text = board_text(d, name)
	if _list:
		var lines: Array = ["WHERE THE DESKS TRADE"]
		if rated == null:
			lines.append("— (the rate scan did not answer)")
		else:
			lines.append("QING.GetMarketRate(Asset) · block %s" % TokenFormat.group(str(YueExchange.rated_block())))
			lines.append("%d of %d territories have a rate" % [rated.size(), Registry.count()])
			for r in rated.slice(0, LIST_ROWS):
				lines.append("%-22s %s" % [String(r["name"]).left(22), PulseX.fmt(r["rate"], 18, 6)])
		_list.text = "\n".join(lines)


static func board_text(d: Dictionary, name: String) -> String:
	if not d.get("ok", false):
		return "THIS TERRITORY\n%s\n— %s" % [name, d.get("error", "the chain did not answer")]
	var p: Dictionary = d["pairs"][0]
	var lines: Array = ["THIS TERRITORY · block %s" % TokenFormat.group(str(d["block"])), name.left(30),
		"%s for %s (QING.Asset())" % [d["qing_symbol"], p["symbol"]]]
	if p["rate"] == null:
		lines.append("rate —")
	elif BigInt.is_zero(p["rate"]):
		lines.append("no market rate set:")
		lines.append("every YUE refuses this pair")
		lines.append("(ExchangeRateNotFound)")
	else:
		lines.append("1 %s = %s %s" % [d["qing_symbol"], PulseX.fmt(p["rate"], 18, 8), p["symbol"]])
	var n := 0
	for k in d["desks"]:
		if (k["stock_qing"] != null and not BigInt.is_zero(k["stock_qing"])) or (k["stock_asset"] != null and not BigInt.is_zero(k["stock_asset"])):
			n += 1
	lines.append("%d of %d known YUEs hold stock" % [n, d["desks"].size()])
	return "\n".join(lines)


func _process(_delta: float) -> void:
	if _player == null or not _player.is_physics_processing() or not is_inside_tree():
		_set_focus("")
		return
	var lp := to_local(_player.global_position)
	var near := Vector2(lp.x - desk_at.x, lp.z - desk_at.z).length() < REACH and absf(lp.y) < 2.5
	_set_focus("desk" if near else "")


func _set_focus(z: String) -> void:
	if z == _focus:
		return
	_focus = z
	if _hud == null:
		return
	if z == "":
		_hud.hide_prompt()
	else:
		_hud.show_prompt("%s  YUE Exchange desk: Hong / Hung at fixed rates (you sign)" % ControlsHelp.key_of("interact"))


func _unhandled_input(event: InputEvent) -> void:
	if _focus != "desk" or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	_set_focus("")
	_focus = "?"
	use_desk.emit()


## Screenshot camera: from beside the lift door, looking over the desk and out;
## "board" / "list": from mid-floor, square on to the left / right side board.
func preview_transform(which: String = "") -> Transform3D:
	var t := Transform3D()
	var zc := _lift_front + POD_D * 0.5
	if which == "board" or which == "list":
		var s := -1.0 if which == "board" else 1.0
		t.origin = to_global(Vector3(-s * 1.5, 1.7, zc))
		return t.looking_at(to_global(Vector3(s * POD_W * 0.5, BOARD_Y, zc)), Vector3.UP)
	t.origin = to_global(Vector3(5.5, 2.1, _lift_front + 1.0))
	return t.looking_at(to_global(Vector3(-4.0, 1.9, _lift_front + POD_D * 0.62)), Vector3.UP)
