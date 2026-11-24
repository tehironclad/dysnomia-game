class_name ChatDraft
extends RefCounted
## The chat bar's typing state, with no UI: lines you sent (Up/Down recall
## them, the line being typed is kept while you browse), quick lines for the
## number keys, and the length rule. Text is never lost: a line that failed
## comes back through `restore`.

const MAX_LEN := ChatPanel.MAX_LEN
const HISTORY := 50
## Quick lines (actions chat_quick_1 … chat_quick_4). They only fill the bar:
## Enter still sends, so a key press never signs anything by itself.
const QUICK := ["gm ☀️", "anyone here?", "gg", "🌻 for the room"]

var history: Array = []  # oldest first
var _cursor := -1  # -1 = not browsing; else an index into history
var _stash := ""  # what was typed before browsing


## Why `text` cannot be sent ("" = it can).
static func reject_reason(text: String) -> String:
	var t := text.strip_edges()
	if t == "":
		return "empty"
	if t.length() > MAX_LEN:
		return "too long: %d of %d characters" % [t.length(), MAX_LEN]
	return ""


static func quick(i: int) -> String:
	return QUICK[i] if i >= 0 and i < QUICK.size() else ""


## Remembers a sent line (consecutive repeats once) and stops browsing.
func remember(text: String) -> void:
	var t := text.strip_edges()
	_cursor = -1
	_stash = ""
	if t == "":
		return
	if history.is_empty() or history[-1] != t:
		history.append(t)
	while history.size() > HISTORY:
		history.pop_front()


## Up: the previous line (keeps `current` to come back to). Returns the text
## to show.
func older(current: String) -> String:
	if history.is_empty():
		return current
	if _cursor == -1:
		_stash = current
		_cursor = history.size() - 1
	elif _cursor > 0:
		_cursor -= 1
	return history[_cursor]


## Down: the next line, or back to what was being typed.
func newer(current: String) -> String:
	if _cursor == -1:
		return current
	if _cursor < history.size() - 1:
		_cursor += 1
		return history[_cursor]
	_cursor = -1
	return _stash


func browsing() -> bool:
	return _cursor != -1


## A failed line back into the bar: into an empty bar as is; otherwise the
## typed text stays and the failed line waits in history (Up).
static func restore(current: String, failed: String) -> String:
	return failed if current.strip_edges() == "" else current
