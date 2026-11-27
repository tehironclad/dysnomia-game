class_name AlertPrefs
extends RefCounted
## Which alerts a player wants (F2 · Online & voice → Notifications), on this
## computer (user://alerts.cfg): each kind on/off, the sound, the taskbar flash
## when the game window is not focused. All on by default.

const PATH := "user://alerts.cfg"
const LABELS := {
	"mention": "A room line names you (your LAU's Username)",
	"invite": "Someone invites you or asks you to join them",
	"arrive": "Someone arrives in one of your QINGs (game server)",
	"crown": "Someone passes you on a crown (lost lead)",
}

var kinds := {"mention": true, "invite": true, "arrive": true, "crown": true}
var sound := true
var flash := true
var path := PATH


func _init(p_path: String = PATH) -> void:
	path = p_path


func on(kind: String) -> bool:
	return bool(kinds.get(kind, true))


func set_kind(kind: String, value: bool) -> void:
	if kinds.has(kind):
		kinds[kind] = value


func load_prefs() -> void:
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return
	for k in kinds:
		kinds[k] = bool(c.get_value("kinds", k, kinds[k]))
	sound = bool(c.get_value("alerts", "sound", sound))
	flash = bool(c.get_value("alerts", "flash", flash))


func save_prefs() -> void:
	var c := ConfigFile.new()
	for k in kinds:
		c.set_value("kinds", k, kinds[k])
	c.set_value("alerts", "sound", sound)
	c.set_value("alerts", "flash", flash)
	c.save(path)
