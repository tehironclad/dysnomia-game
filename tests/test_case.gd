class_name TestCase
extends RefCounted
## Minimal assertion base for tests/run.gd. Subclasses define test_* methods.

var failures: PackedStringArray = []
var current := ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current, msg])


func check(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)


func eq(actual, expected, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%s expected <%s> got <%s>" % [msg, str(expected), str(actual)])


func near(actual: float, expected: float, tol: float, msg: String = "") -> void:
	if absf(actual - expected) > tol:
		fail("%s expected %s ± %s got %s" % [msg, expected, tol, actual])


func load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		fail("cannot open %s" % path)
		return null
	return JSON.parse_string(f.get_as_text())
