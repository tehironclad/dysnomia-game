class_name ArcadeGame
extends Node2D
## Base class for the arcade cabinet games (see ArcadeCatalog for the list).
##
## The cabinet makes a 320×240 SubViewport, adds `load(script).new()` to it, then calls `start(seed)`
## when a paid credit is spent, or `attract()` for the idle demo. Everything is drawn inside SIZE with
## `_draw()`; no external art.
##
## Simulation: a fixed 60 Hz step. `_process` feeds `step(DT)` only while `playing` or in attract
## mode; tests call `step(dt)` directly. Input is read from the `Input` singleton (a SubViewport gets
## no input events) through the actions move_left / move_right / move_forward (up) / move_back
## (down) / jump (fire), and the arrow keys (look_*) too. `scripted_input` (a bitmask of IN_*)
## replaces the keyboard for tests. A dive-in 3D world may set `input_remap` so the keys match its
## camera (e.g. Entropy Drift's chase view steers the 2D field's vertical axis with left/right).
## `game_over(score)` is emitted once per credit, never in attract mode (the demo just restarts).

signal game_over(score: int)

const SIZE := Vector2i(320, 240)
const DT := 1.0 / 60.0
const MAX_SUBSTEPS := 4
const ATTRACT_SEED := 0x5EED

# Palette: Deep Field black, the cabinet's neon accents.
const BLACK := Color("#030407")
const ICE := Color("#7fe9ff")
const GOLD := Color("#ffd36b")
const MAGENTA := Color("#ff4fd8")
const INK := Color("#e9edf4")
const MUTED := Color("#8e97a9")
const DIM := Color("#5d6578")

# Input bits.
const IN_LEFT := 1
const IN_RIGHT := 2
const IN_UP := 4
const IN_DOWN := 8
const IN_FIRE := 16
const ACTIONS := {
	IN_LEFT: "move_left", IN_RIGHT: "move_right", IN_UP: "move_forward", IN_DOWN: "move_back",
	IN_FIRE: "jump",
}
const ALT_ACTIONS := {IN_LEFT: "look_left", IN_RIGHT: "look_right", IN_UP: "look_up", IN_DOWN: "look_down"}

var playing := false  ## a paid run is live
var score := 0
var lives := 3
var attract_mode := false  ## the self-playing demo is running
var over := false  ## the game-over screen is up (after game_over was emitted)
var scripted_input := -1  ## >= 0: use these IN_* bits instead of the Input singleton (tests)
var input_remap := {}  ## keyboard IN_* bit → game IN_* bit (a 3D world's controls); empty = as is
var held := 0  ## IN_* bits held this step
var pressed := 0  ## IN_* bits that went down this step
var t := 0.0  ## simulated seconds since start / attract
var rng := RandomNumberGenerator.new()
var ai_rng := RandomNumberGenerator.new()  ## the demo player's own dice (attract only)

var _emitted := false
var _acc := 0.0
var _over_t := 0.0
var _attract_runs := 0


func title() -> String:
	return "Arcade"


## One line: how to play.
func blurb() -> String:
	return ""


## A fresh run, deterministic from the seed.
func start(seed: int) -> void:
	attract_mode = false
	_begin(seed)
	playing = true


## The self-playing demo loop. Never emits game_over.
func attract() -> void:
	playing = false
	attract_mode = true
	_attract_runs = 0
	_begin(ATTRACT_SEED)


## Freezes the simulation where it is (the cabinet calls this when it powers down a screen).
func stop() -> void:
	playing = false
	attract_mode = false


## One fixed simulation step. Reads input, advances the game, asks for a redraw.
func step(dt: float) -> void:
	if not (playing or attract_mode):
		return
	var now := _read_input()
	pressed = now & ~held
	held = now
	t += dt
	_tick(dt)
	queue_redraw()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _process(delta: float) -> void:
	if playing or attract_mode:
		_acc = minf(_acc + delta, DT * MAX_SUBSTEPS)
		while _acc >= DT and (playing or attract_mode):
			_acc -= DT
			step(DT)
	elif over:
		var before := int(_over_t * 2.0)
		_over_t += delta
		if int(_over_t * 2.0) != before:
			queue_redraw()  # the blinking prompt, twice a second


# ── for subclasses ───────────────────────────────────────────────────────────


## Reset the game's own state for a new run (rng is already seeded; score/lives/t are reset).
func _reset() -> void:
	pass


## Advance the game by dt. `held` / `pressed` hold this step's input.
func _tick(_dt: float) -> void:
	pass


## The demo player's input (IN_* bits) for this step.
func _demo_input() -> int:
	return 0


## Draw the playfield (the base draws the background, HUD and overlays around it).
func _draw_game() -> void:
	pass


## The run is lost. Emits game_over once; in attract mode restarts the demo instead.
func end_game() -> void:
	if attract_mode:
		_attract_runs += 1
		_begin(ATTRACT_SEED + _attract_runs)
		return
	if _emitted or not playing:
		return
	_emitted = true
	playing = false
	over = true
	_over_t = 0.0
	queue_redraw()
	game_over.emit(score)


## Takes a life; ends the game at zero. Returns true when that was the last one.
func lose_life() -> bool:
	lives -= 1
	if lives <= 0:
		lives = 0
		end_game()
		return true
	return false


func _begin(seed: int) -> void:
	rng.seed = seed
	ai_rng.seed = seed ^ 0xA1
	score = 0
	lives = 3
	t = 0.0
	over = false
	_emitted = false
	held = 0
	pressed = 0
	_acc = 0.0
	_reset()
	# A button still held from spending the credit is not a press.
	held = 0 if attract_mode else _read_input()
	queue_redraw()


func _read_input() -> int:
	if attract_mode:
		return _demo_input()
	if scripted_input >= 0:
		return scripted_input
	var bits := 0
	for table in [ACTIONS, ALT_ACTIONS]:
		for bit in table:
			if InputMap.has_action(table[bit]) and Input.is_action_pressed(table[bit]):
				bits |= bit
	return remap_bits(bits, input_remap)


## Applies a keyboard → game bit map (bits not in the map pass through). Pure.
static func remap_bits(bits: int, remap: Dictionary) -> int:
	if remap.is_empty():
		return bits
	var out := 0
	for bit in [IN_LEFT, IN_RIGHT, IN_UP, IN_DOWN, IN_FIRE]:
		if bits & bit:
			out |= int(remap.get(bit, bit))
	return out


# ── drawing ──────────────────────────────────────────────────────────────────


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), BLACK)
	_draw_game()
	if playing or over:
		_draw_hud()
	if attract_mode:
		_draw_attract()
	elif over:
		_draw_game_over()
	elif not playing:
		_draw_title_card()


func _draw_hud() -> void:
	text(Vector2(6, 12), "%07d" % score, 11, INK)
	for i in lives:
		var c := Vector2(SIZE.x - 10 - i * 12, 8)
		_diamond(c, 4.0, ICE)


func _draw_attract() -> void:
	draw_rect(Rect2(0, 84, SIZE.x, 66), Color(BLACK, 0.72))
	text_centered(108, title().to_upper(), 20, ICE)
	text_centered(126, blurb(), 9, MUTED)
	if int(t * 1.6) % 2 == 0:
		text_centered(144, "INSERT CREDIT", 10, GOLD)


func _draw_game_over() -> void:
	draw_rect(Rect2(0, 78, SIZE.x, 80), Color(BLACK, 0.8))
	draw_line(Vector2(40, 78), Vector2(SIZE.x - 40, 78), Color(MAGENTA, 0.6), 1.0)
	draw_line(Vector2(40, 158), Vector2(SIZE.x - 40, 158), Color(MAGENTA, 0.6), 1.0)
	text_centered(104, "GAME OVER", 22, MAGENTA)
	text_centered(126, "SCORE %d" % score, 13, INK)
	if int(_over_t * 2.0) % 2 == 0:
		text_centered(146, title().to_upper(), 9, DIM)


func _draw_title_card() -> void:
	text_centered(112, title().to_upper(), 20, ICE)
	text_centered(132, blurb(), 9, MUTED)


## Left-aligned text with its baseline at pos.
func text(pos: Vector2, s: String, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Text centred on the screen width, baseline at y.
func text_centered(y: float, s: String, size: int, color: Color, x0: float = 0.0, width: float = -1.0) -> void:
	var w := float(SIZE.x) if width < 0.0 else width
	draw_string(ThemeDB.fallback_font, Vector2(x0, y), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, color)


## A line with a soft neon halo.
func glow_line(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	draw_line(a, b, Color(color, 0.22), width + 2.5, true)
	draw_line(a, b, color, width, true)


## A closed polyline with a halo.
func glow_poly(points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, Color(color, 0.22), width + 2.5, true)
	draw_polyline(closed, color, width, true)


func _diamond(c: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
