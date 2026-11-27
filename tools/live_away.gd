extends SceneTree
## Read-only: the real "while you were away" card for a wallet, from the live chain.
## Nothing is signed and nothing is stored.
##   godot --headless --path . -s res://tools/live_away.gd [-- --wallet=0x… --since=<block> | --stored]
## --since=<block>: the baseline is read from the chain AT that block (archive state: your
##   bars, your QINGs' boards, the registry then), as if you had visited then. Default: ≈ 3 days ago.
## --stored: compare with the baseline this computer stored at the wallet's last visit (user://away.cfg).
## --names: also print each room's newest lines (to see what a mention would match).

const DEFAULT_WALLET := "0x18f621662d6a1f23700ea32d146b32195dc33111"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var wallet := DEFAULT_WALLET
	var since := -1
	var stored := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wallet="):
			wallet = a.substr(9).to_lower()
		elif a.begins_with("--since="):
			since = int(a.substr(8))
		elif a == "--stored":
			stored = true
	var AR = load("res://scripts/state/away_read.gd")
	var AD = load("res://scripts/state/away_diff.gd")
	var AS = load("res://scripts/state/away_store.gd")
	var AL = load("res://scripts/autoload/alerts.gd")
	var chain = root.get_node("Chain")
	var t0 := Time.get_ticks_msec()
	var head: int = await chain.refresh_head()
	if head < 0:
		print("chain head: — (the node did not answer)")
		quit(1)
		return
	var ps = await load("res://scripts/state/player_state.gd").read(wallet)
	print("wallet %s · LAU %s · Username %s · YUE %s · Aura %s · head %d" % [wallet, ps.lau if ps.has_lau() else "—",
		ps.username if ps.username != "" else "—", ps.yue if ps.has_yue() else "—", ps.aura if ps.aura != "" else "—", head])
	var prev: Dictionary = {}
	if stored:
		prev = AS.load_for(wallet)
		print("baseline: stored on this computer%s" % ((" at block %d" % int(prev["block"])) if not prev.is_empty() else ": none (a first visit: no card)"))
	else:
		if since <= 0:
			since = head - 8400 * 3
		prev = await AR.at_block(wallet, since, {"player": ps})
		print("baseline: read from the chain at block %d (%s)" % [since, "ok" if not prev.is_empty() else "— (could not be read)"])
		if prev.is_empty():
			quit(1)
			return
		print("  then: bars at %d QINGs · boards of %d · %d QINGs registered" % [prev["bars"].size(), prev["qings"].size(), int(prev["registry"]["count"])])
	var now: Dictionary = await AR.read(wallet, prev, {"player": ps})
	print("now:  block %d · bars %s at %d QINGs · rooms %d (%s) · lines read to %s · boards %d%s · registry %s (%d, logs to %d)" % [
		int(now["block"]), "ok" if now["bars_ok"] else "—", now["bars"].size(), now["rooms_list"].size(),
		", ".join(now["rooms_list"].slice(0, 6).map(func(q): return String(root.get_node("Registry").get_territory(q).get("name", q)))) + ("…" if now["rooms_list"].size() > 6 else ""),
		str(now["rooms_to"]) if now["rooms_ok"] else "—", now["qings"].size(), (" (%d failed)" % now["qings_failed"].size()) if not now["qings_failed"].is_empty() else "",
		"ok" if now["registry_ok"] else "—", int(now["registry"].get("count", -1)), int(now["registry"].get("cursor", -1))])
	var n := 0
	for q in now["room_lines"]:
		n += now["room_lines"][q].size()
	print("      %d new room line%s since then (own lines included in this count)" % [n, "" if n == 1 else "s"])
	var card: Dictionary = AD.compute(prev, now, AD.me_of(ps, wallet), AL.names_for(now))
	print("")
	for line in AD.lines(card):
		print(line)
	print("\n(%.1f s, read-only)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()
