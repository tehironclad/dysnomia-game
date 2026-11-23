extends SceneTree
## Read-only: the Phase 5 live moves against the real chain. Nothing is signed.
##   godot --headless --path . -s res://tools/live_moves.gd [-- --wallet=0x… --qing=0x…]
## Prints the Su and Beat previews (simulated from the wallet), the room's door
## for that wallet, the newest room lines and Void lines with their badges,
## and the World watch (deployer nonce, CREATE addresses, bytecode).
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var wallet := "0x18f621662d6a1f23700ea32d146b32195dc33111"
	var qing := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wallet="):
			wallet = a.substr(9).to_lower()
		elif a.begins_with("--qing="):
			qing = a.substr(7).to_lower()
	var reg = root.get_node("Registry")
	var q: Dictionary = reg.get_territory(qing)
	print("territory: %s (%s), founded block %d" % [q.get("name", "?"), qing, int(q.get("block", -1))])
	var ps = await load("res://scripts/state/player_state.gd").read(wallet)
	print("wallet %s  LAU %s  YUE %s  name %s  block %d" % [wallet, ps.lau, ps.yue, ps.username, ps.block])
	var MV = load("res://scripts/state/moves.gd")
	if ps.has_yue():
		var su: Dictionary = await MV.su_preview(wallet, ps.yue, qing)
		print("\n-- Su preview --")
		print(su.get("message", "") if not su["ok"] else "\n".join(su["lines"]) + "\n(block %d)" % su["block"])
	var bt: Dictionary = await MV.beat_preview(wallet, String(q.get("waat", "0")))
	print("\n-- Beat preview --")
	print(bt.get("message", "") if not bt["ok"] else "\n".join(bt["lines"]) + "\n(block %d)" % bt["block"])
	var room = await load("res://scripts/state/room_state.gd").read(qing, ps)
	print("\n-- Door --\n", room.describe(), "\nchat blocker: '", room.chat_blocker(), "'  join steps: ", room.join_steps().size())
	var CL = load("res://scripts/state/chat_log.gd")
	var head: int = await root.get_node("Chain").refresh_head()
	var t0 := Time.get_ticks_msec()
	var rh: Dictionary = await CL.room_history(qing, int(q.get("block", 0)), head, 8)
	print("\n-- Room lines (ok=%s, scanned from %d, %d ms) --" % [rh["ok"], rh["scanned_from"], Time.get_ticks_msec() - t0])
	for l in rh["lines"]:
		print(CL.format_line(l))
	t0 = Time.get_ticks_msec()
	var vh: Dictionary = await CL.void_history(head, 12)
	print("\n-- Void lines (ok=%s, scanned from %d, %d ms) --" % [vh["ok"], vh["scanned_from"], Time.get_ticks_msec() - t0])
	var badges := {}
	for l in vh["lines"]:
		badges[l["badge"]] = badges.get(l["badge"], 0) + 1
		print(CL.format_line(l))
	print("badges: ", badges)
	var world = root.get_node("World")
	await world.check()
	print("\n-- World watch --\n", world.status, " · ", world.headline())
	for e in world.evidence:
		print("  ", e)
	print("  site: ", world.site.display())
	quit()
