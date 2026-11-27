extends SceneTree
## End-to-end check of the Telegram bridge (docs/SERVER.md §8d) against a mock Bot API
## (tools/tg_mock_api.gd on 127.0.0.1; TELEGRAM_API_BASE points the server at it).
## Game servers run in this process, with scripted clients (NetClient, throwaway test
## keys). Checks: the feature is off and silent with no token; a token without a chat id
## only logs the chat ids it sees; Telegram → game (text, edits replace, placeholders,
## cleaning, the wrong chat, muted users and bots ignored, history for late joiners);
## game → Telegram (guests refused, signed-in players posted as "<chain name> (in game)",
## plain text with links, mentions and markup neutralised, per-wallet and group limits,
## Telegram's 429 obeyed); the moments digest (batched, one post per gap, never guests,
## never a player who opted out, the future daily_record kind); and the token never in
## a log line, a client message or a Telegram text (a bad token's errors are masked too).
##   godot --headless --path . -s res://tools/tg_selftest.gd [-- --port=18797]
## Exit code 0 = every check passed. No network beyond 127.0.0.1 (chain names are put in by hand).

const KEY_A := "0x8b2a5c8f8e1f1c6f3d9a0b4e2c7d5f1a9e3b6c8d0f2a4c6e8b1d3f5a7c9e0b2d"
const KEY_B := "0x2f6c8e1a3b5d7f9e0c2a4b6d8f1e3c5a7b9d0e2f4a6c8b1d3e5f7a9c0b2d4e6f"
const ROOM := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const TOKEN := "7777777777:AAFmockTOKENmockTOKENmockTOKEN-xyz_9"
const OTHER_TOKEN := "8888888888:AAFotherTOKENotherTOKENotherTOKEN_q"
const CHAT := -1001234567890
const SECRET := "AAFmockTOKENmockTOKENmockTOKEN-xyz_9"

var failures := 0
var checks := 0
var mock: Node
var clients: Array = []
var got := {}       # client label → [S_TG lines]
var hist := {}      # client label → last S_TG_HISTORY
var status := {}    # client label → [S_TG_STATUS]
var feats := {}
var log_capture := LogCapture.new()


class LogCapture extends Logger:
	var _m := Mutex.new()
	var text := ""

	func _log_message(message: String, _error: bool) -> void:
		_m.lock()
		text += message + "\n"
		_m.unlock()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _n: bool, _t: int, _b: Array[ScriptBacktrace]) -> void:
		_m.lock()
		text += "%s %s %s:%d %s\n" % [code, rationale, file, line, function]
		_m.unlock()


func _initialize() -> void:
	OS.add_logger(log_capture)
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("PASS  ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func wait_until(cond: Callable, timeout_s: float = 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout_s * 1000.0:
			return false
		await process_frame
	return true


func wait_s(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame


func make_server(port: int, dir: String, env: Dictionary) -> Node:
	var s: Node = load("res://scripts/net/server/game_server.gd").new()
	s.port = port
	s.server_name = "tg-selftest"
	s.data_dir = dir
	s.quiet = true
	# Every key set: the process environment of whoever runs this is never used.
	var full := {"TELEGRAM_BOT_TOKEN": "", "TELEGRAM_CHAT_ID": "", "TELEGRAM_API_BASE": "", "TELEGRAM_MUTE_IDS": ""}
	full.merge(env, true)
	s.tg_env = full
	for f in ["server.log", "telegram_prefs.json", "telegram_history.json", "leaderboards.json", "tokens.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	root.add_child(s)
	return s


func make_client(label: String, key: String, url: String) -> Node:
	var c: Node = load("res://scripts/net/net_client.gd").new()
	c.name = label
	root.add_child(c)
	if key != "":
		c.signer_wallet = EthSign.address_of_private(key)
		c.signer = func(message: String) -> String: return EthSign.sign_personal(message, key)
	clients.append(c)
	got[label] = []
	status[label] = []
	c.tg_line.connect(func(l): got[label].append(l))
	c.tg_history.connect(func(ls): hist[label] = ls)
	c.tg_status.connect(func(d): status[label].append(d))
	c.connect_to(url)
	return c


func lines_of(label: String, pred: Callable) -> Array:
	return (got[label] as Array).filter(pred)


func server_log(s: Node) -> String:
	var p := String(s.data_dir).path_join("server.log")
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


func close_all(s: Node) -> void:
	for c in clients:
		c.close()
		c.queue_free()
	clients.clear()
	if s:
		s.stop()
		s.queue_free()
	await wait_s(0.2)


func _run() -> void:
	Engine.max_fps = 120
	var port := 18797
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = clampi(int(a.substr(7)), 1024, 65000)
	mock = load("res://tools/tg_mock_api.gd").new()
	mock.port = port + 1
	mock.token = TOKEN
	root.add_child(mock)
	ok(mock.start(), "mock Bot API listens on 127.0.0.1:%d" % mock.port)
	var api := "http://127.0.0.1:%d" % mock.port

	# ── 1. no token: off and silent ──
	var s0 := make_server(port, "user://tg_selftest0", {})
	ok(s0.start(), "a server with no TELEGRAM_BOT_TOKEN starts")
	ok(s0.telegram == null, "…with no bridge at all")
	var c0 := make_client("C0", KEY_A, "ws://127.0.0.1:%d" % port)
	ok(await wait_until(func(): return c0.is_online(), 6.0), "a client connects")
	ok(not c0.features.has("telegram") and not c0.has_telegram(), "the welcome does not offer telegram")
	c0.sign_in()
	await wait_until(func(): return c0.wallet != "", 8.0)
	c0._send(NetTg.send_msg("hello?"))
	ok(await wait_until(func(): return not status["C0"].is_empty(), 3.0) and not status["C0"][0]["ok"] and String(status["C0"][0]["error"]).contains("no Telegram"),
		"a C_TG to such a server is answered (no bridge), not a strike")
	ok(not hist.has("C0") and mock.requests.is_empty(), "no history sent and nothing asked of Telegram")
	ok(not server_log(s0).to_lower().contains("telegram"), "and nothing about Telegram in its log (silent)")
	await close_all(s0)

	# ── 2. a token without a chat id: discovery ──
	var s1 := make_server(port, "user://tg_selftest1", {"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_API_BASE": api})
	ok(s1.start(), "a server with a token but no chat id starts")
	mock.push_message(-100555, {"text": "hello bot"})
	ok(await wait_until(func(): return server_log(s1).contains("sees chat -100555"), 6.0), "it logs the chat ids it sees (to find yours)")
	var c1 := make_client("C1", "", "ws://127.0.0.1:%d" % port)
	await wait_until(func(): return c1.is_online(), 6.0)
	ok(not c1.has_telegram(), "…and does not offer telegram (nothing is relayed)")
	await close_all(s1)
	mock.updates.clear()

	# ── 3. the bridge ──
	var dir := "user://tg_selftest2"
	var s := make_server(port, dir, {"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_CHAT_ID": str(CHAT), "TELEGRAM_API_BASE": api, "TELEGRAM_MUTE_IDS": "666"})
	ok(s.start(), "a server with token + chat id + mock API starts")
	s.telegram.digest.min_gap_s = 1.0e9  # no digest until the moments part below (arrivals queue meanwhile)
	var url := "ws://127.0.0.1:%d" % port
	var wa := EthSign.address_of_private(KEY_A)
	var wb := EthSign.address_of_private(KEY_B)
	if s.names:
		s.names.put(wa, {"state": "ok", "username": "enteh", "lau_name": "", "lau_symbol": "", "lau": "0x" + "9".repeat(40), "block": 1})
		s.names.put(wb, {"state": "none", "block": 1})
	var a := make_client("A", KEY_A, url)
	var b := make_client("B", KEY_B, url)
	var g := make_client("G", "", url)
	ok(await wait_until(func(): return a.is_online() and b.is_online() and g.is_online(), 8.0), "three clients connected")
	ok(a.has_telegram() and g.has_telegram(), "the welcome offers telegram")
	ok(await wait_until(func(): return hist.has("G"), 3.0) and (hist["G"] as Array).is_empty(), "each gets the (empty) history after the welcome")
	a.sign_in()
	b.sign_in()
	ok(await wait_until(func(): return a.wallet != "" and b.wallet != "", 10.0), "A and B signed in")
	for c in [a, b, g]:
		c.join(ROOM, {"name": "claimed-" + String(c.name), "head": "bear", "acc": [], "body": "male"})

	# Telegram → game
	var m1: int = mock.push_message(CHAT, {"text": "gm frens"})
	ok(await wait_until(func(): return lines_of("G", func(l): return l["id"] == m1).size() == 1, 6.0), "a group message reaches every client (a guest too)")
	var l1: Dictionary = lines_of("A", func(l): return l["id"] == m1)[0] if not lines_of("A", func(l): return l["id"] == m1).is_empty() else {}
	ok(l1.get("src") == "tg" and l1.get("from") == "Ann Lee" and l1.get("text") == "gm frens" and int(l1.get("ts", 0)) > 0, "as {id, src tg, from (display name), text, ts}")
	ok(NetTg.speaker(l1) == "Ann Lee · Telegram", "drawn as \"Ann Lee · Telegram\"")
	var n_before := (got["A"] as Array).size()
	mock.push_message(-100999, {"text": "from another group"})
	mock.push_message(CHAT, {"text": "muted spam", "from": {"id": 666, "first_name": "Spam"}})
	mock.push_message(CHAT, {"text": "i am a bot", "from": {"id": 7, "is_bot": true, "first_name": "Rose"}})
	var m_photo: int = mock.push_message(CHAT, {"photo": [{"file_id": "x"}], "caption": "my bag"})
	ok(await wait_until(func(): return lines_of("A", func(l): return l["id"] == m_photo).size() == 1, 6.0), "a photo arrives…")
	ok(lines_of("A", func(l): return l["id"] == m_photo)[0]["text"] == "[photo] my bag", "…as \"[photo] my bag\"")
	ok((got["A"] as Array).size() == n_before + 1, "the other chat, the muted user and the bot were ignored")
	ok(int(s.telegram.stats["ignored_chat"]) == 1 and int(s.telegram.stats["muted"]) == 1, "counted: 1 other chat, 1 muted")
	var m_st: int = mock.push_message(CHAT, {"sticker": {"emoji": "🌻"}})
	var m_dirty: int = mock.push_message(CHAT, {"text": "two\nlines" + char(0x200b) + char(0x202e) + " " + "z".repeat(400), "from": {"id": 43, "first_name": "Sunny ✓"}})
	ok(await wait_until(func(): return lines_of("A", func(l): return l["id"] == m_dirty).size() == 1, 6.0), "a sticker and a long dirty line arrive")
	var ld: Dictionary = lines_of("A", func(l): return l["id"] == m_dirty)[0]
	ok(not String(ld["text"]).contains("\n") and not String(ld["text"]).contains(char(0x202e)) and String(ld["text"]).length() <= NetTg.TEXT_MAX,
		"cleaned: one line, no invisible characters, ≤ %d characters" % NetTg.TEXT_MAX)
	ok(ld["from"] == "Sunny", "a ✓ in a Telegram name is dropped (it is no badge)")
	ok(lines_of("A", func(l): return l["id"] == m_st)[0]["text"] == "[sticker 🌻]", "a sticker shows its emoji")
	mock.push_message(CHAT, {"message_id": m1, "text": "gm frens (edited)"}, true)
	ok(await wait_until(func(): return lines_of("A", func(l): return l["id"] == m1 and l["edited"]).size() == 1, 6.0), "an edit arrives with the same id…")
	var merged: Array = []
	for l in got["A"]:
		merged = NetTg.merge(merged, l)
	ok(merged.filter(func(l): return l["id"] == m1).size() == 1 and merged.filter(func(l): return l["id"] == m1)[0]["text"] == "gm frens (edited)", "…and replaces the line")

	# game → Telegram
	g._send(NetTg.send_msg("guest here"))
	ok(await wait_until(func(): return not status["G"].is_empty(), 3.0) and not status["G"][0]["ok"] and status["G"][0]["code"] == "guest", "a guest's line is refused (sign in first)")
	await wait_s(0.3)
	ok(mock.sent.is_empty(), "…and nothing went to Telegram")
	ok(a.send_tg("hello from the game, see https://evil.example.com/claim and ask @admin_bot <b>now</b> **please**"), "A (signed in) sends a line")
	ok(await wait_until(func(): return mock.sent.size() == 1, 8.0), "the bot posts it to Telegram")
	var p1: Dictionary = mock.sent[0] if not mock.sent.is_empty() else {"text": "", "body": {}, "chat_id": ""}
	ok(p1["chat_id"] == str(CHAT), "to the allowed chat only")
	ok(String(p1["text"]).begins_with("enteh (in game): "), "as \"<chain name> (in game): …\" (the chain's name for the verified wallet, not the claimed one): %s" % p1["text"])
	ok(not String(p1["text"]).contains("https://") and not String(p1["text"]).contains("evil.example") and String(p1["text"]).contains("evil[.]example[.]com"), "links are defanged")
	ok(not String(p1["text"]).contains("@admin") and String(p1["text"]).contains("@ admin_bot"), "@mentions are broken")
	ok(not String(p1["text"]).contains("<b>") and not String(p1["text"]).contains("**"), "markup is stripped")
	ok(not (p1["body"] as Dictionary).has("parse_mode") and bool((p1["body"] as Dictionary).get("disable_web_page_preview", false)), "plain text: no parse_mode, no link preview")
	ok(await wait_until(func(): return lines_of("G", func(l): return l["src"] == "game").size() == 1, 4.0), "every client sees it as a game line")
	var lg: Dictionary = lines_of("G", func(l): return l["src"] == "game")[0] if not lines_of("G", func(l): return l["src"] == "game").is_empty() else {}
	ok(lg.get("wallet") == wa and lg.get("id") == p1.get("message_id"), "with the verified wallet and Telegram's message id")
	ok(status["A"].any(func(d): return d["what"] == "send" and d["ok"]), "A is told it went")
	a.send_tg("again right away")
	ok(await wait_until(func(): return status["A"].any(func(d): return not d["ok"] and int(d["retry_s"]) > 0), 3.0), "a second line within 10 s is refused with a wait")
	await wait_s(1.1)
	b.send_tg("hi from b, link t.me/joinchat/abc")
	ok(await wait_until(func(): return mock.sent.size() == 2, 6.0), "B posts")
	ok(mock.sent.size() >= 2 and String(mock.sent[1]["text"]).begins_with(NetProto.short_wallet(wb) + " (in game): ") and String(mock.sent[1]["text"]).contains("t[.]me"),
		"a wallet with no LAU: the short wallet; t.me defanged")
	# the group's limit
	var keep_group = s.telegram.group
	s.telegram.group = TgRate.new([[2, 60.0]])
	s.telegram.group.note("group", s.telegram._now())
	s.telegram.group.note("group", s.telegram._now())
	s.telegram.per_wallet = TgRate.new([[1, 10.0], [30, 3600.0]])
	var nb: int = status["B"].size()
	b.send_tg("busy?")
	ok(await wait_until(func(): return status["B"].size() > nb, 3.0) and not status["B"][-1]["ok"] and String(status["B"][-1]["error"]).contains("busy"), "over the group's limit: \"Telegram is busy\"")
	s.telegram.group = keep_group
	# Telegram's own 429
	s.telegram.per_wallet = TgRate.new([[1, 10.0], [30, 3600.0]])
	mock.fail_sends = 1
	var t429 := Time.get_ticks_msec()
	b.send_tg("after a 429")
	ok(await wait_until(func(): return mock.sent.size() == 3, 8.0), "a 429 is waited out and the line still goes")
	ok(Time.get_ticks_msec() - t429 >= 900, "after retry_after (%d ms)" % (Time.get_ticks_msec() - t429))

	# opt-out and moments
	var np: int = status["B"].size()
	b.send_tg_prefs(false)
	ok(await wait_until(func(): return status["B"].size() > np and status["B"][-1]["what"] == "prefs", 3.0) and status["B"][-1]["moments"] == false, "B opts out of moments")
	ok(FileAccess.get_file_as_string(dir.path_join("telegram_prefs.json")).contains(wb), "kept in telegram_prefs.json")
	g._send(NetTg.prefs_msg(false))
	await wait_s(0.3)
	ok(status["G"].any(func(d): return d["what"] == "prefs" and not d["ok"]), "a guest has no choice to save")
	ok(s.telegram.digest.events.any(func(e): return e["ev"]["k"] == "arrive" and e["ev"]["w"] == wa), "joining the QING queued an arrival moment (a real server event)")
	s.telegram.digest = TgDigest.new()
	s.telegram.digest.min_gap_s = 3.0  # the real gap is 2 min, the real gather 15 s
	s.telegram.digest.gather_s = 0.6
	var sent_before: int = mock.sent.size()
	s._event({"k": "record", "w": wa, "n": "liar", "board": ROOM + "/arcade:void_lanes", "score": 4200, "verified": true}, "signed")
	s._event({"k": "result", "w": wa, "n": "x", "w2": wb, "n2": "y", "game": "pool", "stake": "2", "room": ROOM}, "signed")
	s._event({"k": "arrive", "w": wb, "n": "y", "room": ROOM}, "signed")
	s._event({"k": "guest", "room": ROOM}, "room", ROOM)
	s._event({"k": "daily_record", "w": wa, "n": "x", "game": "pool", "score": 9}, "signed")
	s._event({"k": "place", "w": wa, "n": "x", "room": ROOM, "place": "pub"}, "room", ROOM)
	ok(await wait_until(func(): return mock.sent.size() > sent_before, 8.0), "the moments go as one digest")
	await wait_s(0.5)
	ok(mock.sent.size() == sent_before + 1, "one post, not one per moment")
	var dg := String(mock.sent[sent_before]["text"]) if mock.sent.size() > sent_before else ""
	print("      digest: ", dg.replace("\n", " ⏎ "))
	ok(dg.begins_with("From the Dysnomia game:") and dg.contains("enteh set a new #1 on Void Lanes: 4,200 ✓"), "it carries the record, with the chain's name")
	ok(dg.contains("enteh set today's best at pool: 9"), "and the daily challenge's kind")
	ok(dg.contains("enteh walked into Sunny's Pub at"), "and where a player walked in")
	ok(not dg.contains("beat") and not dg.contains(NetProto.short_wallet(wb)), "nothing about B (opted out), so not the A-vs-B result")
	ok(not dg.to_lower().contains("guest"), "never a guest")
	ok(dg.ends_with("Open the game: " + NetTg.DOWNLOAD_URL), "and where to get the game")
	ok(await wait_until(func(): return lines_of("G", func(l): return l["src"] == "bot").size() == 1, 3.0), "clients see the digest as the game's line")
	var t_gap := Time.get_ticks_msec()
	s._event({"k": "arrive", "w": wa, "n": "x", "room": ROOM}, "signed")
	ok(await wait_until(func(): return mock.sent.size() > sent_before + 1, 8.0), "a later moment goes in the next digest…")
	ok(Time.get_ticks_msec() - t_gap >= 2000, "…only after the gap (%d ms)" % (Time.get_ticks_msec() - t_gap))
	var np2: int = status["B"].size()
	b.send_tg_prefs(true)
	await wait_until(func(): return status["B"].size() > np2 and status["B"][-1]["what"] == "prefs", 3.0)
	var pf := FileAccess.get_file_as_string(dir.path_join("telegram_prefs.json"))
	ok(status["B"][-1].get("moments", false) == true and not pf.contains(wb), "opting back in clears it (%s)" % pf)

	# a late joiner gets the history (edits applied)
	var late := make_client("L", "", url)
	ok(await wait_until(func(): return hist.has("L"), 6.0), "a late joiner gets the history")
	var hl: Array = hist.get("L", [])
	ok(hl.filter(func(l): return l["id"] == m1).size() == 1 and hl.filter(func(l): return l["id"] == m1)[0]["text"] == "gm frens (edited)", "with the edit applied")
	ok(hl.any(func(l): return l["src"] == "game") and hl.size() <= NetTg.HISTORY, "game lines too, at most %d" % NetTg.HISTORY)

	# malformed input with the bridge on: wrong JSON types are refused or struck, never a script error
	var fz := make_client("F", KEY_A, url)
	await wait_until(func(): return fz.is_online(), 6.0)
	fz.sign_in()
	await wait_until(func(): return fz.wallet != "", 8.0)
	var sent_fz: int = mock.sent.size()
	for w in [{}, [], [1, 2], -1, 1e300, true, null, {"a": {}}]:
		fz._send(NetProto.json_msg(NetTg.C_TG, {"text": w}))
		fz._send(NetProto.json_msg(NetTg.C_TG_PREFS, {"moments": w}))
	fz._send(PackedByteArray([NetTg.C_TG, 0xff, 0xfe, 0x7b]))
	fz._send(PackedByteArray([NetTg.C_TG_PREFS]))
	await wait_s(1.0)
	ok(not log_capture.text.contains("SCRIPT ERROR"), "malformed C_TG / C_TG_PREFS: no script error on the server")
	ok(mock.sent.size() == sent_fz, "…and nothing reached Telegram")

	# the token
	var paths_ok := true
	for r in mock.requests:
		if String(r["body"]).contains(SECRET):
			paths_ok = false
	ok(paths_ok, "the token is only in the request path, never a request body")
	var leak := false
	for label in got:
		for l in got[label]:
			if JSON.stringify(l).contains(SECRET):
				leak = true
	for label in status:
		for d in status[label]:
			if JSON.stringify(d).contains(SECRET):
				leak = true
	for p in mock.sent:
		if String(p["text"]).contains(SECRET):
			leak = true
	ok(not leak, "the token is in no client message and no Telegram text")
	s.telegram.save_now()
	ok(not FileAccess.get_file_as_string(dir.path_join("telegram_history.json")).contains(SECRET), "nor in the saved history")
	await close_all(s)

	# a bad token: Telegram answers 401; the errors are logged masked
	var s3 := make_server(port, "user://tg_selftest3", {"TELEGRAM_BOT_TOKEN": OTHER_TOKEN, "TELEGRAM_CHAT_ID": str(CHAT), "TELEGRAM_API_BASE": api})
	s3.start()
	ok(await wait_until(func(): return server_log(s3).contains("check TELEGRAM_BOT_TOKEN"), 6.0), "a wrong token: the log says to check it")
	# a dead API: network errors are logged masked too
	await close_all(s3)
	var s4 := make_server(port, "user://tg_selftest4", {"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_CHAT_ID": str(CHAT), "TELEGRAM_API_BASE": "http://127.0.0.1:%d" % (port + 2)})
	s4.start()
	ok(await wait_until(func(): return server_log(s4).contains("getUpdates failed"), 8.0), "an unreachable API: logged once, retried with back-off")
	var all_logs := ""
	for d2 in ["user://tg_selftest0", "user://tg_selftest1", "user://tg_selftest2", "user://tg_selftest3", "user://tg_selftest4"]:
		var lp: String = String(d2).path_join("server.log")
		all_logs += FileAccess.get_file_as_string(lp) if FileAccess.file_exists(lp) else ""
	ok(not all_logs.contains(SECRET) and not all_logs.contains(OTHER_TOKEN.get_slice(":", 1)), "no server log line holds a token (%d bytes of logs)" % all_logs.length())
	ok(not log_capture.text.contains(SECRET) and not log_capture.text.contains(OTHER_TOKEN.get_slice(":", 1)), "nor anything the engine printed (%d bytes)" % log_capture.text.length())
	await close_all(s4)
	mock.stop()
	print("\n%d checks, %d failed" % [checks, failures])
	OS.remove_logger(log_capture)
	quit(1 if failures > 0 else 0)
