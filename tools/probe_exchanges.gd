extends SceneTree
## Headless, read-only: builds a territory, opens the Swap Hall's swap panel and the
## YUE Exchange panel as --session's wallet would see them (nothing is signed), types
## an amount, and prints what each panel shows: the quote, the approval it needs, the
## simulation from that wallet. Catches runtime errors in the exchange UI without a GPU.
##   godot --headless --path . -s res://tools/probe_exchanges.gd -- [--qing=0x…] [--session=0x…]
##       [--token=<index in the swap list>] [--mode=0|1|2] [--amount=1000] [--yue-amount=0.0001] [--kind=0|1]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var qing := "0xb0ba7d36b7f0505879179ece7401f24eb653c6e1"
	var session := "0x18f621662d6a1f23700ea32d146b32195dc33111"
	var token := 0
	var mode := 0
	var amount := "1000"
	var yamount := "0.0001"
	var kind := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="): qing = a.substr(7).to_lower()
		elif a.begins_with("--session="): session = a.substr(10).to_lower()
		elif a.begins_with("--token="): token = int(a.substr(8))
		elif a.begins_with("--mode="): mode = int(a.substr(7))
		elif a.begins_with("--amount="): amount = a.substr(9)
		elif a.begins_with("--yue-amount="): yamount = a.substr(13)
		elif a.begins_with("--kind="): kind = int(a.substr(7))
	var gm = root.get_node("GameManager")
	gm.territory_address = qing
	gm.is_chain_sourced = true
	root.get_node("Session").set_wallet(session)
	var t0 := Time.get_ticks_msec()
	while root.get_node("Session").player == null and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	change_scene_to_file("res://scenes/territory/territory_v2.tscn")
	for i in 10:
		await process_frame
	var ex = current_scene.get("exchanges")
	if ex == null:
		print("no exchanges node")
		quit(1)
		return
	var sp = ex.swap_panel
	await sp.open()
	sp._select(token)
	sp._mode.select(mode)
	sp._on_change()
	sp._amount.text = amount
	await sp.quote()
	print("== SWAP PANEL ==\n", sp.status.text, "\n-- list --")
	for b in sp._rows:
		print(b.text.replace("\n", " |"))
	print("-- token --\n", sp.info.text, "\n-- quote --\n", sp.result.text)
	sp.close()
	var yp = ex.yue_panel
	await yp.open()
	yp._kind.select(kind)
	yp._amount.text = yamount
	yp._plan_trade()
	t0 = Time.get_ticks_msec()
	while not (yp.result.text.contains("Simulated") or yp.result.text.contains("approve first") or yp.result.text.contains("No ")) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	print("\n== YUE PANEL ==\n", yp.status.text, "\n-- list --")
	for b in yp._rows.slice(0, 6):
		print(b.text.replace("\n", " |"))
	print("-- desk --\n", yp.info.text, "\n-- trade --\n", yp.result.text)
	quit(0)
