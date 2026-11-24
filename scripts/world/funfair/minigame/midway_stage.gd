class_name MidwayStage
extends Node3D
## A midway game's props in its stall, and the 3D that plays it. Built once with the fair (idle:
## the stall's own wheel, rails, pegs or targets, no processing), then while a round runs
## MidwayPlay calls render() every frame: the stage only READS its MidwaySim (positions, phase,
## score) and moves a handful of nodes. No allocations per frame; labels change only when their
## text does. Coordinates are the stall's own (+Z toward the player at the counter).
##
## Subclasses: StrikerStage, TossStage, RingStage, ShyStage, PrimeStage, WheelStage, FortuneStage.
##
## Game feel (dress(), once after build()): every stage gets a FairFx (bursts, sparks, confetti,
## pop-ups, a frame of chase bulbs round the back wall), a FairCrowd (onlookers who gather and
## cheer), a prize shelf (FairPrizes: what's left today, and yours), hanging lamps and a stage
## spot that lights while a round runs. MidwayPlay calls impact_pos() / on_press() / on_result()
## when the sim says something happened; a stage can also kick() the camera itself (a hard hit).

var game := ""
var sim: MidwaySim = null
var aim := Vector2.ZERO       ## the live aim (AIM units), for the sight before a press
var ticket := ""              ## the ticket's tx hash ("" in practice)
var _reticle: MeshInstance3D
var host: Node = null          ## the MidwayPlay running a round here (kick, sounds)
var fx: FairFx
var crowd: FairCrowd
var shelf: Node3D
var _spot: SpotLight3D
var _ret_cold: Material
var _ret_hot: Material


static func create(id: String) -> MidwayStage:
	var s: MidwayStage
	match id:
		"striker": s = StrikerStage.new()
		"entropy": s = TossStage.new()
		"regolith": s = RingStage.new()
		"crystal": s = ShyStage.new()
		"motzkin": s = PrimeStage.new()
		"waat": s = WheelStage.new()
		"saat": s = FortuneStage.new()
		_: return null
	s.game = id
	s.name = "Stage_" + id
	return s


## Builds the idle props (call once, after adding under the stall's root).
func build() -> void:
	pass


## The shared dressing (call once, after build()).
func dress() -> void:
	fx = FairFx.new()
	fx.name = "Fx"
	add_child(fx)
	var fr := frame_rect()
	if fr.size.x > 0.0:
		fx.bulb_frame(Vector3(fr.position.x, fr.position.y, frame_z()), fr.size.x, fr.size.y)
	crowd = FairCrowd.new()
	crowd.name = "Crowd"
	add_child(crowd)
	var sx := shelf_xform()
	if sx != Transform3D():
		shelf = FairPrizes.shelf(self, sx)
	for lx in lamp_xs():
		FairKit.model(self, "hanging_industrial_lamp", Vector3(lx, 2.84, 0.35), 0.0, 0.5)
		FairKit.mesh(self, FairKit.sphere_mesh(0.04, 8), Vector3(lx, 2.21, 0.35), FairKit.glow(Color(1.0, 0.8, 0.5), 6.0, 2.0), Vector3.ZERO, false)
	_spot = SpotLight3D.new()
	_spot.position = Vector3(0, 2.6, 1.6)
	_spot.light_color = Color(1.0, 0.9, 0.75)
	_spot.light_energy = 2.2
	_spot.spot_range = 7.0
	_spot.spot_angle = 42.0
	_spot.shadow_enabled = false
	_spot.visible = false
	add_child(_spot)
	_spot.look_at_from_position(_spot.position, spot_at(), Vector3.UP)
	_ret_hot = FairKit.glow(Color(0.35, 1.0, 0.5), 6.0, 3.0)


## The back wall's bulb frame: centre (x, y) and size (w, h); zero size for none.
func frame_rect() -> Rect2:
	return Rect2(Vector2(0, 1.6), Vector2(3.6, 2.2))


func frame_z() -> float:
	return -1.2


## The prize shelf (front facing local +Z), or Transform3D() for none.
func shelf_xform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(1.66, 0.12, 0.25))


func lamp_xs() -> Array:
	return [-1.0, 1.0]


func spot_at() -> Vector3:
	return Vector3(0, 1.4, -0.9)


## Re-stocks the shelf (the fair's QING; after a prize is won).
func refresh_shelf(qing: String) -> void:
	if shelf:
		FairPrizes.fill(shelf, qing, game)


## Where the last result happened (stage space): pop-ups and bursts start there.
func impact_pos() -> Vector3:
	return Vector3(0, 1.6, -0.8)


## A press was taken (a throw left the hand, a shot fired…).
func on_press() -> void:
	pass


## A result came in (sim.last_*): the stage's own reaction (squash, sparks…).
func on_result() -> void:
	pass


## The sound a press makes.
func press_sound() -> String:
	return "whoosh"


## The sound a result makes (before the shared pop / coin / buzz).
func result_sound() -> String:
	return "clack"


## Is the live aim on something worth hitting? (the sight turns green)
func aim_hot() -> bool:
	return false


## The celebration's wide shot (stage space): the stall, the crowd, the confetti.
func cheer_eye() -> Transform3D:
	return look(Vector3(2.6, 2.1, 6.6), Vector3(0.0, 1.35, 0.6))


## Asks the round for camera shake (m) and a hit-stop (s).
func kick(shake: float, stop: float = 0.0) -> void:
	if host and host.has_method("kick"):
		host.kick(shake, stop)


func sound(id: String, pitch: float = 1.0, db: float = 0.0) -> void:
	FairSfx.play(self, id, pitch, db)


## The reticle's colour follows aim_hot() (call from render()).
func _reticle_feedback() -> void:
	if _reticle == null:
		return
	var hot := aim_hot()
	if _ret_cold == null:
		_ret_cold = _reticle.material_override
	var want: Material = _ret_hot if hot else _ret_cold
	if _reticle.material_override != want:
		_reticle.material_override = want
	var s := 1.0 + (0.12 * sin(Time.get_ticks_msec() * 0.02) if hot else 0.0)
	_reticle.scale = Vector3.ONE * s


func begin(p_sim: MidwaySim, p_ticket: String) -> void:
	sim = p_sim
	ticket = p_ticket
	aim = Vector2.ZERO
	if _spot:
		_spot.visible = true
	if fx:
		fx.set_mode("idle")
	_begin()
	render()


func end() -> void:
	sim = null
	if _reticle:
		_reticle.visible = false
	if _spot:
		_spot.visible = false
	if fx:
		fx.set_mode("still")
	if crowd:
		crowd.disperse()
	host = null
	_idle()


## Called every frame while the round runs: stage the sim's state.
func render() -> void:
	pass


func _begin() -> void:
	pass


func _idle() -> void:
	pass


## The first-person eye (stall space) while playing.
func eye() -> Transform3D:
	return look(Vector3(0, 1.66, 2.0), Vector3(0, 1.3, -0.8))


func fov() -> float:
	return 60.0


## The power meter shown in the overlay (0..1), or -1 for none.
func meter() -> float:
	return -1.0


## Live aim from the mouse/keys is used by this game (0, 1 or 2 axes).
func aim_axes() -> int:
	return MidwaySim.axes(game)


static func look(from: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


## Smooth 0..1.
static func smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## A point on a throw's arc from a to b at u (0..1), `h` m above the straight line at the top.
static func arc(a: Vector3, b: Vector3, u: float, h: float) -> Vector3:
	return a.lerp(b, u) + Vector3.UP * (4.0 * h * u * (1.0 - u))


func _make_reticle(r: float, c: Color) -> MeshInstance3D:
	_reticle = FairKit.mesh(self, FairKit.torus_mesh(r * 0.8, r, 24, 4), Vector3.ZERO, FairKit.glow(c, 4.0, 2.0), Vector3.ZERO, false)
	_reticle.visible = false
	return _reticle


## A label that only touches its text when it changes.
static func set_text(l: Label3D, t: String) -> void:
	if l.text != t:
		l.text = t
