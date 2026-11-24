extends SceneTree
## Read-only: every LAU a wallet owns (LauFinder), the current one marked.
##   godot --headless --path . -s res://tools/live_laus.gd [-- --wallet=0x…]
var _w := "0x18f621662d6a1f23700ea32d146b32195dc33111"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wallet="):
			_w = a.substr(9)
	_run.call_deferred()


func _run() -> void:
	var finder = load("res://scripts/state/lau_finder.gd")
	var r: Dictionary = await finder.find(_w)
	if not r.get("ok", false):
		print("FAIL ", r.get("error", ""))
		quit(1)
		return
	print("%d LAUs at block %d" % [r["laus"].size(), r["block"]])
	for l in r["laus"]:
		print("  %s %s  %s" % ["●" if l["current"] else " ", l["address"], finder.label(l)])
	quit(0)
