class_name MidwayStage
extends Node3D
## A midway game's props in its stall, and the 3D that plays it. Built once with the fair (idle:
## the stall's own wheel, rails, pegs or targets, no processing), then while a round runs
## MidwayPlay calls render() every frame: the stage only READS its MidwaySim (positions, phase,
## score) and moves a handful of nodes. No allocations per frame; labels change only when their
## text does. Coordinates are the stall's own (+Z toward the player at the counter).
##
## Subclasses: StrikerStage, TossStage, RingStage, ShyStage, PrimeStage, WheelStage, FortuneStage.

var game := ""
var sim: MidwaySim = null
var aim := Vector2.ZERO       ## the live aim (AIM units), for the sight before a press
var ticket := ""              ## the ticket's tx hash ("" in practice)
var _reticle: MeshInstance3D


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


func begin(p_sim: MidwaySim, p_ticket: String) -> void:
	sim = p_sim
	ticket = p_ticket
	aim = Vector2.ZERO
	_begin()
	render()


func end() -> void:
	sim = null
	if _reticle:
		_reticle.visible = false
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
