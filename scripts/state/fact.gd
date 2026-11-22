class_name Fact
extends RefCounted
## A displayed chain value with its provenance (docs/LEARNINGS.md §10).
## Loading, empty, unavailable and zero are different things:
## - LOADING      read in flight           → "…"
## - OK           the chain answered       → the value
## - EMPTY        answered, nothing there  → "none"
## - UNAVAILABLE  the read failed          → "—" (never 0)
## - STALE        older than wanted        → value, marked stale
## - FLOOR        a capped/partial count   → "≥ value"

enum State { LOADING, OK, EMPTY, UNAVAILABLE, STALE, FLOOR }

var value = null
var state: State = State.LOADING
var source := ""  ## e.g. "QING.Entropy()"
var block := -1  ## block the value was read at (-1 unknown)
var note := ""  ## reason for UNAVAILABLE / explanation for FLOOR


static func loading(p_source: String) -> Fact:
	var f := Fact.new()
	f.source = p_source
	return f


static func ok(p_value, p_source: String, p_block: int = -1) -> Fact:
	var f := Fact.new()
	f.value = p_value
	f.state = State.OK
	f.source = p_source
	f.block = p_block
	return f


static func empty(p_source: String, p_block: int = -1) -> Fact:
	var f := ok(null, p_source, p_block)
	f.state = State.EMPTY
	return f


static func unavailable(p_source: String, reason: String = "") -> Fact:
	var f := Fact.new()
	f.state = State.UNAVAILABLE
	f.source = p_source
	f.note = reason
	return f


static func floor_of(p_value, p_source: String, why: String, p_block: int = -1) -> Fact:
	var f := ok(p_value, p_source, p_block)
	f.state = State.FLOOR
	f.note = why
	return f


func has_value() -> bool:
	return state in [State.OK, State.STALE, State.FLOOR]


## Text for display. `fmt` turns the raw value into a string (default str()).
func display(fmt: Callable = Callable()) -> String:
	match state:
		State.LOADING:
			return "…"
		State.UNAVAILABLE:
			return "—"
		State.EMPTY:
			return "none"
	var s: String = fmt.call(value) if fmt.is_valid() else str(value)
	if state == State.FLOOR:
		return "≥ " + s
	if state == State.STALE:
		return s + " (stale)"
	return s


## Tooltip line: where the number came from.
func provenance() -> String:
	var parts: PackedStringArray = [source]
	if block >= 0:
		parts.append("block %d" % block)
	match state:
		State.UNAVAILABLE:
			parts.append("unavailable" + (": " + note if note != "" else ""))
		State.FLOOR:
			parts.append("floor: " + note)
		State.STALE:
			parts.append("stale")
	return " · ".join(parts)
