extends SceneTree
## The mock Telegram Bot API (tools/tg_mock_api.gd) as its own process, for screenshots
## and trying the bridge by hand: a made-up group chat that says a few lines, edits one and
## posts a photo, then prints every message the game server's bot sends it. 127.0.0.1 only.
##   godot --headless --path . -s res://tools/tg_mock.gd -- [--port=18790] [--token=<test token>]
##       [--chat=-1001234567890] [--seconds=600] [--say="Name|text"]…
## Then start a game server pointed at it (the token is a throwaway, never a real one):
##   TELEGRAM_BOT_TOKEN=<same test token> TELEGRAM_CHAT_ID=<chat> TELEGRAM_API_BASE=http://127.0.0.1:18790 \
##     godot --headless --path . res://scenes/net/game_server.tscn -- --port=8787

const TEST_TOKEN := "1234567890:AAtestTOKENtestTOKENtestTOKENtest_00"
const SCRIPT := [["Ann Lee", "gm Sunny's Pub ☀️"], ["PulseRat", "anyone up for pool tonight?"],
	["Atropa Annie", "the arcade in Illinois Coin QING is packed lol"], ["Ann Lee", "[photo] my bag"],
	["Mo", "how do I get a LAU? asking for a friend"], ["PulseRat", "Void first, then the front door says the rest"]]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var port := 18790
	var token := TEST_TOKEN
	var chat := -1001234567890
	var secs := 600.0
	var extra: Array = []
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"port": port = int(v)
			"token": token = v
			"chat": chat = int(v)
			"seconds": secs = float(v)
			"say":
				var p := v.split("|", true, 1)
				if p.size() == 2:
					extra.append([p[0], p[1]])
	var mock: Node = load("res://tools/tg_mock_api.gd").new()
	mock.port = port
	mock.token = token
	mock.hold_cap_s = 25.0
	root.add_child(mock)
	if not mock.start():
		print("[tg-mock] port %d is taken" % port)
		quit(1)
		return
	print("[tg-mock] Bot API mock on http://127.0.0.1:%d, chat %d (a test token; never a real one)" % [port, chat])
	var ids := {}
	var uid := 100
	for line in SCRIPT + extra:
		uid += 1
		var who := String(line[0])
		var text := String(line[1])
		var fields := {"from": {"id": uid, "is_bot": false, "first_name": who}}
		if text.begins_with("[photo] "):
			fields["photo"] = [{"file_id": "x"}]
			fields["caption"] = text.substr(8)
		else:
			fields["text"] = text
		ids[who + text] = mock.push_message(chat, fields)
		await create_timer(0.4).timeout
	var first: int = ids.values()[1]
	mock.push_message(chat, {"message_id": first, "from": {"id": 102, "first_name": "PulseRat"}, "text": "anyone up for pool tonight? 2 Ⓐ stake"}, true)
	var seen := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		while seen < mock.sent.size():
			print("[tg-mock] the bot posted: %s" % String(mock.sent[seen]["text"]).replace("\n", " ⏎ "))
			seen += 1
		await process_frame
	mock.stop()
	quit()
