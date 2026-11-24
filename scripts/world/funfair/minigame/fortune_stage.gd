class_name FortuneStage
extends MidwayStage
## Saat Fortune Teller: three cards face down on the counter. Each press turns one: PAST, PRESENT
## and FUTURE, each a slice of the ticket's transaction hash (in practice: the local seed, and the
## card says so). The third card raises the reading over the orb.

const CARD_Y := 1.082
const NAMES := ["PAST", "PRESENT", "FUTURE"]

var _cards: Array = []
var _faces: Array = []       ## Label3D on each turned card
var _reading: Label3D
var _back: Material
var _front: Material


func build() -> void:
	_back = FairKit.glow(Color(0.42, 0.22, 0.75), 1.4, 0.8)
	_front = FairKit.paint(Color(0.95, 0.92, 0.84), 0.6, 0.0)
	for i in 3:
		var pivot := Node3D.new()
		pivot.position = Vector3(-0.46 + i * 0.46, CARD_Y, 1.02)
		add_child(pivot)
		var c := FairKit.box(pivot, Vector3(0.32, 0.008, 0.46), Vector3.ZERO, _back)
		_cards.append(c)
		var f := FairKit.label(self, "", pivot.position + Vector3(0, 0.012, 0), 24, Color(0.18, 0.08, 0.3), 0.0, Color(1, 1, 1, 0), 0.002)
		f.rotation.x = -PI * 0.5
		f.shaded = true
		f.visible = false
		_faces.append(f)
	_reading = FairKit.label(self, "", Vector3(0, 1.86, -0.3), 34, Color(1.0, 0.85, 0.5) * 1.5, 0.0, Color(0.05, 0.02, 0.08), 0.004)
	_reading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reading.width = 300.0
	_reading.visible = false


func _hex() -> String:
	if ticket != "":
		return Abi.strip0x(ticket).to_lower()
	return ("%08x" % sim.seed_v).repeat(8)


func _begin() -> void:
	var h := _hex()
	for i in 3:
		_cards[i].get_parent().rotation.z = 0.0
		_cards[i].material_override = _back
		_faces[i].visible = false
		var chunk := h.substr(i * 21, 21)
		if ticket == "":
			set_text(_faces[i], "%s\npractice\nno ticket" % NAMES[i])
		else:
			set_text(_faces[i], "%s\n%s\n%s\n%s" % [NAMES[i], chunk.substr(0, 7), chunk.substr(7, 7), chunk.substr(14, 7)])
	_reading.visible = false
	set_text(_reading, "“%s”" % MidwayGame.fortune(sim.seed_v))


func _idle() -> void:
	for i in 3:
		_cards[i].get_parent().rotation.z = 0.0
		_cards[i].material_override = _back
		_faces[i].visible = false
	_reading.visible = false


func eye() -> Transform3D:
	return look(Vector3(0, 1.74, 1.98), Vector3(0, 1.25, -0.1))


func fov() -> float:
	return 58.0


func render() -> void:
	if sim == null:
		return
	for i in 3:
		var turned := sim.round_i > i
		var since := (sim.tick - sim.last_tick) if turned and sim.round_i == i + 1 else 999
		var u := clampf(since / 18.0, 0.0, 1.0) if turned else 0.0
		_cards[i].get_parent().rotation.z = PI * u if u < 1.0 else 0.0
		_cards[i].material_override = _front if u >= 0.5 else _back
		_faces[i].visible = u >= 1.0
	_reading.visible = sim.round_i >= 3 and sim.tick - sim.last_tick > 20
