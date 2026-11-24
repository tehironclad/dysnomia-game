class_name DoorWalk
extends RefCounted
## The timeline of walking through a door (pure: no nodes, testable).
##   ENTER: the player turns and walks to the door, the door opens, the screen
##          fades to black; done = change scene.
##   ARRIVE: the screen fades in while the player walks in through the
##          entrance, the door closing behind; done = hand control back.
## About 1.5–2.4 s either way, and skip() ends it at once (ENTER still
## finishes its fade, quickly). DoorSequence drives the nodes from this.

enum Kind { ENTER, ARRIVE }

const FADE_S := 0.45        ## ENTER: fade to black
const FADE_IN_S := 0.55     ## ARRIVE: fade in from black
const DOOR_S := 0.5         ## a door opens or closes in this long
const MIN_SPEED := 1.8      ## m/s: the Walk clip (1.7 m/s at 1×) never looks slowed down
const MAX_SPEED := 4.0      ## m/s: still a walk (HumanAvatar jogs from 4.5; the Walk clip tops out at 2.4×)
const MIN_TOTAL := 1.4
const MAX_TOTAL := 2.4
const SKIP_FADE_S := 0.12   ## ENTER, skipped: what is left of the fade

var kind: int
var t := 0.0
var distance := 0.0
var speed := 0.0
var walk_s := 0.0
var total := 0.0
var skipped := false
var _skip_at := -1.0


func _init(p_kind: int, p_distance: float) -> void:
	kind = p_kind
	distance = maxf(0.0, p_distance)
	speed = walk_speed(distance)
	walk_s = distance / speed + 0.25  # + turning and getting going
	if kind == Kind.ENTER:
		total = clampf(walk_s + 0.1, MIN_TOTAL, MAX_TOTAL)
	else:
		total = clampf(walk_s, MIN_TOTAL, MAX_TOTAL)


## A walking pace that covers `distance` in about 1.3 s, inside the walk band.
static func walk_speed(dist: float) -> float:
	return clampf(dist / 1.3, MIN_SPEED, MAX_SPEED)


func step(dt: float) -> void:
	t = minf(t + maxf(dt, 0.0), total)


## When the fade starts (ENTER): in time to be black as the walk ends.
func fade_at() -> float:
	return maxf(0.5, total - FADE_S)


## 0 = clear … 1 = black.
func fade() -> float:
	if kind == Kind.ENTER:
		if _skip_at >= 0.0:
			return maxf(_fade_enter(_skip_at), clampf((t - _skip_at) / SKIP_FADE_S, 0.0, 1.0))
		return _fade_enter(t)
	return 1.0 - _smooth(clampf(t / FADE_IN_S, 0.0, 1.0))


func _fade_enter(at: float) -> float:
	return _smooth(clampf((at - fade_at()) / FADE_S, 0.0, 1.0))


## 0 = shut … 1 = open. ENTER opens it as you near it; ARRIVE closes it
## behind you once you are through.
func door_open() -> float:
	if kind == Kind.ENTER:
		return _smooth(clampf((t - 0.15) / DOOR_S, 0.0, 1.0))
	var close_at := maxf(0.4, total - DOOR_S - 0.1)
	return 1.0 - _smooth(clampf((t - close_at) / DOOR_S, 0.0, 1.0))


## Whether the player is still being walked.
func walking() -> bool:
	return not done() and (kind == Kind.ENTER or t < walk_s)


func done() -> bool:
	if kind == Kind.ENTER and _skip_at >= 0.0:
		return t >= _skip_at + SKIP_FADE_S - 1e-6 or t >= total
	return t >= total - 1e-6


## A key press: ARRIVE ends now; ENTER rushes the fade.
func skip() -> void:
	if skipped:
		return
	skipped = true
	if kind == Kind.ARRIVE:
		t = total
	else:
		_skip_at = t
		total = minf(total, t + SKIP_FADE_S)


static func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
