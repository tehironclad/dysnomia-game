extends SceneTree
## Read-only: how developed is every territory? Σ YUE.Bar(QING) over the known
## players (a floor), per territory, in Multicall batches pinned to one block.
## Prints the distribution and the leaders; --json=<abs path> writes it all.
##   godot --headless --path . -s res://tools/live_development.gd [-- --json=/abs/out.json]
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			out = a.substr(7)
	var chain = root.get_node("Chain")
	var terr: Array = root.get_node("Registry").all()
	var players: Array = root.get_node("Players").all()
	var head: int = await chain.refresh_head()
	var MC = load("res://scripts/chain/multicall.gd")
	var BI = load("res://scripts/chain/bigint.gd")
	var calls: Array = []
	for q in terr:
		for p in players:
			calls.append(MC.make_call(p["yue"], "Bar(address)", [q["address"]]))
	var t0 := Time.get_ticks_msec()
	var res: Array = await chain.multicall.run(calls, "", head)
	print("read %d bars in %d ms at block %d (%d players known)" % [calls.size(), Time.get_ticks_msec() - t0, head, players.size()])
	var rows: Array = []
	var failed := 0
	for i in terr.size():
		var th := PackedInt64Array()
		var te := PackedInt64Array()
		var n := 0
		for j in players.size():
			var v = MC.value(res[i * players.size() + j], ["uint256", "uint256"])
			if v == null:
				failed += 1
				continue
			var hb = BI.from_hex(v[0])
			var eb = BI.from_hex(v[1])
			if not BI.is_zero(hb) or not BI.is_zero(eb):
				n += 1
			th = BI.add(th, hb)
			te = BI.add(te, eb)
		rows.append({"address": terr[i]["address"], "name": terr[i].get("name", ""), "hypo": BI.to_decimal(th),
			"epi": BI.to_decimal(te), "lh": BI.log10(th), "le": BI.log10(te), "reactors": n})
	print("failed reads: %d" % failed)
	var buckets := {}
	for r in rows:
		var k := "none" if is_inf(r["lh"]) else str(int(floor(r["lh"])))
		buckets[k] = buckets.get(k, 0) + 1
	print("Hypobar total, by order of magnitude (log10): ", buckets)
	var eb := {}
	for r in rows:
		var k := "none" if is_inf(r["le"]) else str(int(floor(r["le"])))
		eb[k] = eb.get(k, 0) + 1
	print("Epibar total, by order of magnitude: ", eb)
	var rb := {}
	for r in rows:
		rb[r["reactors"]] = rb.get(r["reactors"], 0) + 1
	print("reactors (players with bars): ", rb)
	rows.sort_custom(func(x, y): return (x["lh"] if not is_inf(x["lh"]) else -1.0) > (y["lh"] if not is_inf(y["lh"]) else -1.0))
	print("\ntop 20 by Hypobar:")
	for r in rows.slice(0, 20):
		print("  %-32s hypo 1e%.1f  epi 1e%.1f  reactors %d" % [String(r["name"]).left(32), r["lh"], r["le"] if not is_inf(r["le"]) else -1.0, r["reactors"]])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify({"block": head, "players": players.size(), "rows": rows}))
	quit()
