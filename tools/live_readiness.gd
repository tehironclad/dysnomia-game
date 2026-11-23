extends SceneTree
## Read-only: identity + WORLD readiness for real players (players.json).
##   godot --headless --path . -s res://tools/live_readiness.gd [-- --n=12] [--wallet=0x…]
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var n := 12
	var wallets: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--wallet="):
			wallets.append(a.substr(9))
	if wallets.is_empty():
		for p in root.get_node("Players").all().slice(0, n):
			wallets.append(p["wallet"])
	var PS = load("res://scripts/state/player_state.gd")
	var RD = load("res://scripts/state/readiness.gd")
	var counts := {}
	for w in wallets:
		var ps = await PS.read(w)
		var r = await RD.evaluate(ps)
		counts[r.state] = counts.get(r.state, 0) + 1
		var hv := []
		for k in ["fomalhaute", "fornax", "tethys", "qzu"]:
			hv.append("%s:%s" % [k.left(4), r.holdings.get(k, {}).get("verdict", "?")])
		print("%s… %-12s %-11s %s | %s%s" % [w.left(10), ps.username.left(12), r.state, " ".join(hv), r.reason.left(70),
			" | crows-bouncer" if ps.is_bouncer() else ""])
	print("states: ", counts)
	quit()
