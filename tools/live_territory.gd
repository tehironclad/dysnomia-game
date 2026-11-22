extends SceneTree
## Read-only: prints a territory's shared state from the chain.
##   godot --headless --path . -s res://tools/live_territory.gd -- --qing=0x… | --name=Shell
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var addr := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			addr = a.substr(7)
		elif a.begins_with("--name="):
			var hits: Array = root.get_node("Registry").search(a.substr(7), 1)
			if not hits.is_empty():
				addr = hits[0]["address"]
	var q: Dictionary = root.get_node("Registry").get_territory(addr)
	if q.is_empty():
		print("unknown territory")
		quit(1)
		return
	# Load lazily: classes that use autoloads cannot be referenced at a -s script's parse time.
	var st = load("res://scripts/state/territory_state.gd").new()
	root.add_child(st)
	st.setup(q)
	await st.changed
	var tok := func(v): return TokenFormat.wei_to_tokens(BigInt.coerce(v))
	var dec := func(v): return TokenFormat.group(BigInt.to_decimal(BigInt.coerce(v)))
	print("%s (%s) @ block %d" % [q["name"], q["address"], st.block])
	print("  Fornax %s · Eris %s · Tethys %s" % [st.fornax.display(tok), st.eris.display(tok), st.tethys.display(tok)])
	print("  Ω (Hypobar per Su) %s" % st.omega.display(dec))
	print("  cover %s · asset %s" % [st.cover_charge.display(tok), st.asset.display()])
	print("  Hypobar total %s · Epibar total %s · reactors %s · lit bands %d" % [st.total_hypobar.display(dec), st.total_epibar.display(dec), st.reactors.display(), st.lit_bands()])
	for i in mini(5, st.board.size()):
		var r: Dictionary = st.board[i]
		print("   #%d %s… Hypobar %s Epibar %s" % [i + 1, String(r["wallet"]).left(10), dec.call(r["hypobar"]), dec.call(r["epibar"])])
	quit()
