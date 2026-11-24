class_name FortuneStage
extends MidwayStage
## Saat Fortune Teller, v2: Higher or Lower with the teller's cards. Eight cards lie in a row on
## the counter (the deck is MidwaySim.cards, from the ticket); the first is face up. Aim left for
## LOWER, right for HIGHER (the plate lights), press: the next card turns over. The orb behind
## glows green for a right guess, red for a wrong one; after the last card she reads your fortune.

const CARD_Y := 1.084
const ROW_Z := 0.98
const STEP := 0.24
const RANKS := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const ORB := Vector3(0, 1.35, -0.3)

var _pivots: Array = []
var _faces: Array = []
var _under: MeshInstance3D
var _reading: Label3D
var _plates: Array = []      ## [lower, higher] MeshInstance3D
var _plate_off: Material
var _plate_on: Material
var _orb_light: OmniLight3D
var _orb_t := 0.0
var _orb_col := Color(0.7, 0.5, 1.0)
var _seen_round := -1


func build() -> void:
	var back := FairKit.glow(Color(0.42, 0.22, 0.75), 1.4, 0.8)
	var front := FairKit.paint(Color(0.97, 0.94, 0.86), 0.55, 0.0)
	var gold := FairKit.paint(Color(0.95, 0.74, 0.32), 0.25, 0.95)
	for k in MidwaySim.rounds("saat") + 1:
		var pivot := Node3D.new()
		pivot.position = Vector3(_x(k), CARD_Y, ROW_Z)
		add_child(pivot)
		FairKit.box(pivot, Vector3(0.19, 0.006, 0.28), Vector3(0, 0.003, 0), front)
		FairKit.box(pivot, Vector3(0.2, 0.004, 0.29), Vector3(0, -0.002, 0), back)
		FairKit.box(pivot, Vector3(0.12, 0.001, 0.2), Vector3(0, -0.0045, 0), gold)
		var f := FairKit.label(pivot, "", Vector3(0, 0.007, 0), 64, Color(0.3, 0.06, 0.4), 0.0, Color(1, 1, 1, 0), 0.0022)
		f.rotation.x = -PI * 0.5
		f.shaded = true
		_pivots.append(pivot)
		_faces.append(f)
	_under = FairKit.box(self, Vector3(0.24, 0.004, 0.33), Vector3(0, CARD_Y - 0.004, ROW_Z), FairKit.glow(Color(1.0, 0.82, 0.4), 4.0, 2.0))
	_plate_off = FairKit.paint(Color(0.12, 0.06, 0.18), 0.5, 0.3)
	_plate_on = FairKit.glow(Color(1.0, 0.82, 0.4), 4.0, 2.0)
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var pl := FairKit.box(self, Vector3(0.42, 0.012, 0.14), Vector3(sx * 0.3, CARD_Y + 0.004, 1.3), _plate_off)
		_plates.append(pl)
		var lb := FairKit.label(self, "LOWER" if i == 0 else "HIGHER", Vector3(sx * 0.3, CARD_Y + 0.012, 1.3), 40, Color(1.0, 0.95, 0.85), 0.0, Color(0.1, 0.02, 0.12), 0.0026)
		lb.rotation.x = -PI * 0.5
	_orb_light = FairKit.omni(self, ORB + Vector3(0, 0, 0.3), Color(0.7, 0.5, 1.0), 1.2, 3.0)
	_reading = FairKit.label(self, "", Vector3(0, 1.88, -0.3), 34, Color(1.0, 0.85, 0.5) * 1.5, 0.0, Color(0.05, 0.02, 0.08), 0.004)
	_reading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reading.width = 300.0
	_reading.visible = false
	_make_reticle(0.05, Color(1.0, 0.85, 0.3))
	_idle()


func _x(k: int) -> float:
	return -STEP * MidwaySim.rounds("saat") * 0.5 + k * STEP


func _begin() -> void:
	_seen_round = -1
	for k in _pivots.size():
		set_text(_faces[k], RANKS[int(sim.cards[k])])
	_reading.visible = false
	set_text(_reading, "“%s”" % MidwayGame.fortune(sim.seed_v))
	_orb_col = Color(0.7, 0.5, 1.0)


func _idle() -> void:
	for k in _pivots.size():
		_pivots[k].rotation.z = PI if k > 0 else 0.0
		set_text(_faces[k], "A" if k == 0 else "")
	_under.position.x = _x(0)
	_reading.visible = false
	for p in _plates:
		p.material_override = _plate_off


func eye() -> Transform3D:
	return look(Vector3(0, 1.85, 2.15), Vector3(0, 1.1, 0.4))


func fov() -> float:
	return 58.0


func impact_pos() -> Vector3:
	return Vector3(_x(mini(sim.round_i, _pivots.size() - 1)), CARD_Y + 0.15, ROW_Z) if sim else Vector3(0, 1.3, 1.0)


func press_sound() -> String:
	return "flip"


func result_sound() -> String:
	return ""


func aim_hot() -> bool:
	return sim != null and sim.phase == "ready"


func on_result() -> void:
	_orb_col = Color(0.3, 1.0, 0.5) if sim.last_good else Color(1.0, 0.3, 0.35)
	_orb_t = 1.0
	var k := mini(sim.round_i, _pivots.size() - 1)
	FairFx.squash(_pivots[k], 0.4 if sim.last_good else 0.15, Vector3.UP)
	if sim.last_good:
		kick(0.03 + 0.01 * sim.streak, 0.06 if sim.last_bonus else 0.0)


func render() -> void:
	if sim == null:
		return
	var turning := sim.round_i + 1 if sim.phase == "fly" else -1
	for k in _pivots.size():
		var up := k <= sim.round_i
		var a := 0.0 if up else PI
		if k == turning:
			var u := smooth(float(sim.phase_t) / MidwaySim.FLIP_T)
			a = PI * (1.0 - u)
			_pivots[k].position.y = CARD_Y + 0.12 * sin(u * PI)
		else:
			_pivots[k].position.y = CARD_Y
		_pivots[k].rotation.z = a
	_under.position.x = lerpf(_under.position.x, _x(mini(sim.round_i, _pivots.size() - 1)), 0.25)
	var pick := 0 if aim.x < 0.0 else 1
	var live := sim.phase == "ready"
	for i in 2:
		var on := (live and i == pick) or (sim.phase == "fly" and i == (0 if sim.guess < 0 else 1))
		_plates[i].material_override = _plate_on if on else _plate_off
	_reticle.visible = live
	if live:
		_reticle.position = Vector3(0.3 if pick == 1 else -0.3, CARD_Y + 0.12, 1.3)
		_reticle.rotation = Vector3.ZERO
		_reticle_feedback()
	if _orb_t > 0.0:
		_orb_t = maxf(0.0, _orb_t - 0.02)
	_orb_light.light_color = Color(0.7, 0.5, 1.0).lerp(_orb_col, _orb_t)
	_orb_light.light_energy = 1.2 + 4.0 * _orb_t
	_reading.visible = sim.done or (sim.round_i >= MidwaySim.rounds("saat") and sim.phase_t > 10)
