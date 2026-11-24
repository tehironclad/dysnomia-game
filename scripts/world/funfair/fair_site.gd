class_name FairSite
extends Node3D
## The Affection Fair in a v2 territory. Sits on its own deck (the Julia terrain is
## never flattened), sized by the territory's Development tier, and sells ride tickets
## through ArcadePay: 1 Ⓐ AFFECTION.transfer to this territory's QING, simulated,
## signed, receipt-verified, then the ride starts. No wallet → a free preview ride
## that is labelled as such and records nothing.
##
## Development tier (0..5) → fair tier: Wild/Outpost = surveyed lot, Settlement =
## night market + carousel, Town = + wheel and drop tower, City/Capital = grand fair.

const AT := Vector2(0.0, 112.0)   ## relative to the Core, south of the arrival point
const HALF := 40.0                ## the fair builds within ±38 m

var _qing := ""
var _hud: Node
var _player: CharacterBody3D
var _fair: Node3D
var _tier := -1
var _focus: RideBase = null
var _riding: RideBase = null
var _paying := false


static func fair_tier(dev_tier: int) -> int:
	return [0, 0, 1, 2, 3, 3][clampi(dev_tier, 0, 5)]


func setup(qing: String, hud: Node, player: CharacterBody3D, height_fn: Callable) -> void:
	_qing = qing.to_lower()
	_hud = hud
	_player = player
	# Deck height: the highest ground under the footprint, so nothing is buried
	var top := -INF
	var low := INF
	for ix in range(-4, 5):
		for iz in range(-4, 5):
			var h: float = height_fn.call(position.x + ix * HALF / 4.0, position.z + iz * HALF / 4.0)
			top = maxf(top, h)
			low = minf(low, h)
	position.y = top + 0.15
	_build_deck(position.y - low + 2.0)


func set_dev_tier(dev_tier: int) -> void:
	var t := fair_tier(dev_tier)
	if t == _tier or _riding != null:
		return
	_tier = t
	if _fair:
		_fair.queue_free()
	_focus = null
	_fair = Funfair.new()
	_fair.name = "Funfair"
	add_child(_fair)
	_fair.initialize(_qing.hex_to_int() if _qing.length() < 16 else _qing.right(12).hex_to_int(), t)
	if t == 0 and _fair.has_method("set_unlock_hint"):
		_fair.set_unlock_hint("Opens at Settlement development · grow this QING's Hypobar")
	for r in _fair.get_rides():
		r.booth_focus.connect(_on_focus)
		r.ride_caption.connect(func(text: String) -> void:
			if text != "":
				_hud.ticker(text, DeepFieldTheme.ICE, 3.0))
		r.ride_finished.connect(_on_finished)


func _on_focus(ride: RideBase, inside: bool) -> void:
	if inside and _riding == null:
		_focus = ride
		var paid := Wallet.address != ""
		_hud.show_prompt("%s  %s · %s" % [ControlsHelp.key_of("interact"), ride.item.get("name", "Ride"),
			("%s to this QING" % ArcadePay.fee_text()) if paid else "free preview (no wallet)"])
	elif _focus == ride:
		_focus = null
		_hud.hide_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _focus == null or _riding != null or _paying or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	_hud.hide_prompt()
	var ride := _focus
	if Wallet.address == "":
		_start(ride, "PREVIEW RIDE · nothing paid")
		return
	_paying = true
	_hud.ticker("Ticket: approve %s to this QING in your wallet…" % ArcadePay.fee_text(), DeepFieldTheme.ICE, 20.0)
	var res: Dictionary = await ArcadePay.pay(_qing, "Affection Fair · %s" % ride.item.get("name", "ride"))
	_paying = false
	if not res.get("ok", false):
		_hud.ticker("Ticket not bought: %s" % res.get("message", "cancelled"), Color("#ff8fa0"), 10.0)
		return
	_start(ride, "TICKET VERIFIED · block %d" % int(res.get("block", 0)))


func _start(ride: RideBase, note: String) -> void:
	_riding = ride
	_focus = null
	_hud.ticker(note, DeepFieldTheme.ICE, 6.0)
	ride.start_ride(_player)


func _on_finished(ride: RideBase) -> void:
	if ride == _riding:
		_riding = null


func _build_deck(depth: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.33, 0.36)
	mat.roughness = 0.85
	mat.metallic = 0.25
	var m := BoxMesh.new()
	m.size = Vector3(HALF * 2.0, depth, HALF * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = Vector3(0, -depth * 0.5 - 0.02, 0)
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = m.size
	cs.shape = sh
	cs.position = mi.position
	body.add_child(cs)
	add_child(body)
	# Ramp down to the arrival side so the deck can be walked onto
	var ramp_len := clampf(depth * 3.0, 6.0, 40.0)
	var rm := BoxMesh.new()
	rm.size = Vector3(10.0, 0.4, ramp_len)
	var ramp := MeshInstance3D.new()
	ramp.mesh = rm
	ramp.material_override = mat
	var ang := atan2(depth - 2.0, ramp_len)
	ramp.rotation.x = -ang
	ramp.position = Vector3(0, -(depth - 2.0) * 0.5, -HALF - cos(ang) * ramp_len * 0.5 + 0.5)
	add_child(ramp)
	var rb := StaticBody3D.new()
	var rc := CollisionShape3D.new()
	var rs := BoxShape3D.new()
	rs.size = rm.size
	rc.shape = rs
	rb.add_child(rc)
	rb.transform = ramp.transform
	add_child(rb)
