extends SceneTree
## Read-only live check of the chat bar and the HUD feed (nothing is signed):
##   godot --headless --path . -s res://tools/live_chat.gd [-- --qing=0x… --player=0x…]
## 1. enters the territory (default Zürich QING) in play mode and prints the
##    HUD feed's lines (site accelerator first, then the chain's copy);
## 2. opens the chat bar, checks gameplay keys are lifted, sends with no wallet,
##    with a fake wallet (no LAU) and with a real player viewed read-only:
##    each must stop at its precondition, never at a signature;
## 3. for the real player: the door, eth_call simulations of one line and of a
##    3-line Multicall3 batch from that wallet, and eth_estimateGas.

const ZURICH := "0xb0ba7d36b7f0505879179ece7401f24eb653c6e1"
const FAKE := "0x000000000000000000000000000000000000dead"
const PLAYER := "0xb644ba4797c8eab1c5a33c41e00096eb4e06d465"  # PulsePunk: spoke in Zürich

var _qing := ZURICH
var _player := PLAYER


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			_qing = a.substr(7).to_lower()
		elif a.begins_with("--player="):
			_player = a.substr(9).to_lower()
	_run.call_deferred()


func _wait(cond: Callable, s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame
	return cond.call()


func _run() -> void:
	var gm = root.get_node("GameManager")
	gm.territory_address = _qing
	gm.territory_name = String(root.get_node("Registry").get_territory(_qing).get("name", ""))
	gm.is_chain_sourced = true
	change_scene_to_file("res://scenes/territory/territory_v2.tscn")
	var cf = root.get_node("ChatFeed")
	var ok := await _wait(func(): return cf.current != null and cf.current.is_loaded(), 120.0)
	var lines_mod = load("res://scripts/state/chat_lines.gd")
	print("\n== HUD feed: %s ==" % gm.territory_name)
	if not ok:
		print("FAIL feed did not load within 120 s")
	var f = cf.current
	print(f.describe())
	var st: Dictionary = cf.stats()
	print("lines loaded: %d · today: %s · history ok: %s" % [f.lines.size(), lines_mod.count_text(st), str(f.history_ok)])
	var by_src := {}
	for l in f.lines:
		by_src[l.get("source", "?")] = int(by_src.get(l.get("source", "?"), 0)) + 1
	print("by source: %s" % str(by_src))
	for l in f.lines.slice(maxi(0, f.lines.size() - 6)):
		print("  [%d] %s   (%s)" % [l["block"], lines_mod.compact(l, 90), l.get("source", "")])
	await _wait(func(): return cf.hud != null and cf.hud.feed != null, 5.0)
	print("HUD feed visible: %s · header: %s" % [str(cf.feed_visible()), cf.hud.feed.header.text])

	print("\n== Chat bar ==")
	var bar = cf.hud.bar
	bar.open("gm from the chat bar check")
	print("bar open: %s · gameplay keys lifted: %s (move_forward events: %d)" % [str(bar.is_open()),
		str(load("res://scripts/ui/chat_input_guard.gd").is_suspended()), InputMap.action_get_events("move_forward").size()])
	print("note: %s" % bar.note.text)
	await _send(cf, bar, "no wallet")

	var sess = root.get_node("Session")
	sess.set_wallet(FAKE)
	await _wait(func(): return sess.player != null, 60.0)
	bar.open("gm from a fake wallet")
	await _send(cf, bar, "fake wallet %s (no LAU)" % FAKE)
	var data: String = load("res://scripts/chain/abi.gd").encode_call("Chat(address,string)", [_qing, "gm"])
	var sim: Dictionary = await root.get_node("Chain").get("rpc").eth_call(load("res://scripts/chain/contracts.gd").CHOA, data, FAKE)
	print("  eth_call CHOA.Chat from the fake wallet: %s" % (("reverts: " + String(sim["revert"]["message"])) if sim.get("kind") == "revert" else str(sim.get("ok"))))

	sess.set_wallet(_player)
	await _wait(func(): return sess.player != null and not sess.refreshing, 90.0)
	print("\n== Real player, read-only: %s (LAU %s, Username %s) ==" % [_player, sess.player.lau, sess.player.username])
	var room = await load("res://scripts/state/room_state.gd").read(_qing, sess.player)
	print("door: %s" % room.describe().replace("\n", " · "))
	print("chat blocker: %s" % (room.chat_blocker() if room.chat_blocker() != "" else "none: this wallet may post here"))
	var rpcn = root.get_node("Chain").get("rpc")
	var C = load("res://scripts/chain/contracts.gd")
	var r1: Dictionary = await rpcn.eth_call(C.CHOA, data, _player)
	print("simulate 1 line (eth_call from the wallet): %s" % (("ok " + String(r1["result"]).right(1)) if r1["ok"] else String(r1.get("revert", {}).get("message", r1.get("error", "")))))
	var g1: Dictionary = await rpcn.estimate_gas(_player, C.CHOA, data)
	var outbox = load("res://scripts/state/chat_outbox.gd")
	var b3: Dictionary = outbox.encode_batch(_qing, ["one", "two", "three"])
	var r3: Dictionary = await rpcn.eth_call(b3["to"], b3["data"], _player)
	var g3: Dictionary = await rpcn.estimate_gas(_player, b3["to"], b3["data"])
	var gp: Dictionary = await rpcn.gas_price()
	print("simulate 3-line Multicall3 batch: %s" % ("ok" if r3["ok"] else String(r3.get("revert", {}).get("message", "failed"))))
	print("gas: 1 line %s · 3-line batch %s · gas price %s wei" % [str(g1.get("gas", "—")), str(g3.get("gas", "—")),
		load("res://scripts/chain/bigint.gd").to_decimal(gp["wei"]) if gp["ok"] else "—"])
	cf.measure_gas()
	await _wait(func(): return cf.gas_note != "", 30.0)
	bar.open("gm from %s (view only)" % sess.player.username)
	print("note: %s" % bar.note.text)
	await _send(cf, bar, "real player viewed read-only")
	print("\n== Into the arcade: the feed keeps running ==")
	var before = cf.current
	change_scene_to_file("res://scenes/places/arcade_place.tscn")
	await _wait(func(): return current_scene != null and current_scene.get("chat_ctl") != null, 30.0)
	for i in 30:
		await process_frame
	var ctl = current_scene.get("chat_ctl")
	print("same feed object: %s · HUD feed visible: %s · bar allowed (T is the place's): %s" % [str(cf.current == before), str(cf.feed_visible()), str(cf.bar_allowed())])
	print("arcade's chat panel reads the shared feed: %s · its history asks for 400 lines" % str(ctl != null and ctl.feed == cf.current))
	await _wait(func(): return cf.current.loaded_limit >= 400, 120.0)
	print("lines now: %d (history limit %d)" % [cf.current.lines.size(), cf.current.loaded_limit])
	print("\nlive_chat done")
	quit()


func _send(cf, bar, what: String) -> void:
	bar.send()
	var e: Dictionary = cf.outbox.entries[-1] if not cf.outbox.entries.is_empty() else {}
	await _wait(func(): return not e.is_empty() and (e["state"] == "failed" or e["state"] == "posted"), 60.0)
	print("send (%s): state %s · kind %s · %s" % [what, e.get("state", "—"), e.get("kind", ""), e.get("message", "")])
	print("  bar after: open %s (reason shown: %s) · text still in the bar: '%s'" % [str(bar.is_open()), bar.status.text, bar.edit.text])
	bar.close()
	bar._kept = ""
