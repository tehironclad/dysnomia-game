extends SceneTree
## Read-only: the diegetic loop's acts and goals for a wallet at a few
## territories, from the live chain (PlaySnapshot → PlayLoop). Nothing is signed.
##   godot --headless --path . -s res://tools/live_acts.gd [-- --wallet=0x… --qing=0x…,0x…]
const DEFAULT_QINGS := ["0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b", "0xd127839b83cbf537c29b7d268c135f745a0da2e8",
	"0x1299bbac80f7038c19c20843f80608bd80c14a74"]


func _initialize() -> void:
	_run.call_deferred()


func _wait(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while not cond.call() and t < max_s:
		await create_timer(0.25).timeout
		t += 0.25
	return cond.call()


func _run() -> void:
	var wallet := "0x18f621662d6a1f23700ea32d146b32195dc33111"
	var qings: Array = DEFAULT_QINGS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wallet="):
			wallet = a.substr(9).to_lower()
		elif a.begins_with("--qing="):
			qings = Array(a.substr(7).to_lower().split(","))
	var reg = root.get_node("Registry")
	var session = root.get_node("Session")
	var chat = root.get_node("ChatFeed")
	var PL = load("res://scripts/state/play_loop.gd")
	var PS = load("res://scripts/state/play_snapshot.gd")
	var NB = load("res://scripts/world/border/neighbours.gd")
	session.set_wallet(wallet)
	await _wait(func(): return session.player != null and not session.refreshing and session.record != null, 240.0)
	var ps = session.player
	print("wallet %s · LAU %s · YUE %s · readiness %s · bars at %d territories (block %d) · record %s" % [wallet,
		ps.lau if ps else "—", ps.yue if ps else "—", session.readiness.state if session.readiness else "—",
		session.bars.size(), session.bars_block, session.record.describe() if session.record and session.record.has_method("describe") else ("read" if session.record else "—")])
	for qing in qings:
		var q: Dictionary = reg.get_territory(qing)
		if q.is_empty():
			print("\n%s: not in the registry" % qing)
			continue
		var st = load("res://scripts/state/territory_state.gd").new()
		root.add_child(st)
		st.setup(q)
		await _wait(func(): return st.block > 0 and st.total_hypobar.state != 0, 90.0)
		var feed = chat.feed_for(qing, q)
		await feed.ensure_history(60)
		var sides := {}
		var found: Dictionary = NB.find(q, reg.all())
		for side in found:
			sides[side] = found[side]
			sides[side]["q"] = reg.get_territory(found[side]["address"])
		var extras: Dictionary = await PS.read_extras(qing, ps, sides)
		var snap: Dictionary = PS.build(st, wallet, ps, session.readiness, session.record, session.bars, session.bars_block, feed, sides, extras)
		print("\n== %s (%s) · TerritoryState block %d · Ω %s ==" % [q.get("name", "?"), qing, st.block, st.omega.display(func(v): return PL.dec(v))])
		for a in PL.acts(snap):
			print("  [%3d] %-6s @%-9s %s — %s   {%s%s}" % [a["priority"], a["kind"], a["anchor"], a["title"], a.get("detail", ""),
				a["call"], "" if a["doable"] else " · blocked: " + String(a["blocker"])])
		for g in PL.goals(snap):
			print("  goal: %s   (%s)" % [g["text"], g["source"]])
		st.queue_free()
	quit()
