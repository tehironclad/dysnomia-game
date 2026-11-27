extends TestCase
## The Telegram bridge's pure rules, with no network (NetTg, TgRate, TgDigest,
## TelegramBridge config): Telegram → game cleaning and placeholders, the labels that
## keep a Telegram name from passing for a chain identity, link and markup
## neutralising for game → Telegram, token masking, rate limits, the digest's batching,
## the access steps for a guest, the dock and TV rows.

const A := "0x1111111111111111111111111111111111111111"
const B := "0x2222222222222222222222222222222222222222"
const Q := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const TOKEN := "123456789:AAHfakeTOKENfakeTOKENfakeTOKEN_abc-12"


func _msg(extra: Dictionary) -> Dictionary:
	var m := {"message_id": 7, "date": 1764200000, "chat": {"id": -1001, "type": "supergroup"}, "from": {"id": 42, "first_name": "Ann", "last_name": "Lee"}}
	m.merge(extra, true)
	return m


func test_lines_from_telegram() -> void:
	var l := NetTg.line_from_message(_msg({"text": "gm frens"}))
	eq(l["id"], 7)
	eq(l["src"], "tg")
	eq(l["from"], "Ann Lee")
	eq(l["text"], "gm frens")
	eq(l["ts"], 1764200000)
	eq(l["edited"], false)
	var e := NetTg.line_from_message(_msg({"text": "gm fixed", "edit_date": 1764200100}), true)
	eq(e["ts"], 1764200100, "an edit carries its edit time")
	check(e["edited"], "an edit is marked")
	eq(NetTg.line_from_message(_msg({"new_chat_members": [{}]})), {}, "a service message shows nothing")
	eq(NetTg.line_from_message({"date": 1, "text": "x"}), {}, "no message id: nothing")


func test_placeholders() -> void:
	eq(NetTg.line_from_message(_msg({"photo": [{}]}))["text"], "[photo]")
	eq(NetTg.line_from_message(_msg({"photo": [{}], "caption": "my bag"}))["text"], "[photo] my bag", "a caption follows the placeholder")
	eq(NetTg.line_from_message(_msg({"sticker": {"emoji": "😀"}}))["text"], "[sticker 😀]")
	eq(NetTg.line_from_message(_msg({"sticker": {}}))["text"], "[sticker]")
	eq(NetTg.line_from_message(_msg({"animation": {}, "document": {}}))["text"], "[GIF]", "a GIF is also a document: GIF wins")
	eq(NetTg.line_from_message(_msg({"voice": {}}))["text"], "[voice message]")
	eq(NetTg.line_from_message(_msg({"poll": {}}))["text"], "[poll]")


func test_cleaning_and_caps() -> void:
	var l := NetTg.line_from_message(_msg({"text": "line one\nline two" + char(0x200b) + char(0x202e) + " reversed"}))
	eq(l["text"], "line one line two reversed", "one line, no invisible or reordering characters")
	var long := NetTg.line_from_message(_msg({"text": "x".repeat(5000)}))
	eq(long["text"].length(), NetTg.TEXT_MAX, "capped")
	check(long["text"].ends_with("…"), "a cut line says so")
	eq(NetTg.display_name({"from": {"first_name": "Sunny ✓", "last_name": "✅"}}), "Sunny", "no check marks: they would pass for the game's badge")
	eq(NetTg.display_name({"from": {"first_name": char(0x200b), "username": "annie"}}), "annie", "a blank name falls back to the username")
	eq(NetTg.display_name({"from": {}}), "someone")
	eq(NetTg.display_name({"sender_chat": {"title": "Atropa News"}, "from": {"first_name": "Group"}}), "Atropa News", "a channel or anonymous admin: the chat's title")
	eq(NetTg.display_name({"from": {"first_name": "y".repeat(80)}}).length(), NetTg.NAME_MAX)


func test_a_telegram_name_is_never_a_chain_identity() -> void:
	var tg := {"id": 1, "src": "tg", "from": "enteh", "text": "hi"}
	eq(NetTg.speaker(tg), "enteh · Telegram", "always labelled Telegram, even when it copies a LAU name")
	eq(NetTg.speaker(tg, func(_w): return "SHOULD NOT BE USED"), "enteh · Telegram", "never looked up as a wallet")
	var game := {"id": 2, "src": "game", "wallet": A, "from": "liar", "text": "hi"}
	eq(NetTg.speaker(game, func(w): return "realname" if w == A else "?"), "realname (in game)", "a game line: the chain's name for the verified wallet, not the server's claim")
	eq(NetTg.speaker(game), NetProto.short_wallet(A) + " (in game)")
	eq(NetTg.speaker({"id": 3, "src": "bot", "text": "x"}), "Dysnomia game · Telegram")
	var bb := ChatFeedPanel.tg_bbcode(tg, NetTg.speaker(tg))
	check(not bb.contains("✓") and bb.contains("· Telegram"), bb)
	check(ChatFeedPanel.tg_bbcode({"id": 1, "src": "tg", "text": "[b]x[/b]"}, "n · Telegram").contains("[lb]b]"), "BBCode in a line is escaped")


func test_client_cleans_a_servers_line() -> void:
	eq(NetTg.clean_line({"id": 5, "src": "tg", "from": "Ann ✓", "text": "hi\nthere", "ts": 9}), {"id": 5, "src": "tg", "from": "Ann", "text": "hi there", "ts": 9, "edited": false})
	eq(NetTg.clean_line({"id": 5, "src": "chain", "text": "x"}), {}, "an unknown source is no line")
	eq(NetTg.clean_line({"id": 0, "src": "tg", "text": "x"}), {}, "no id")
	eq(NetTg.clean_line({"id": 5, "src": "tg", "text": ""}), {}, "nothing to show")
	eq(NetTg.clean_line({"id": 5, "src": "game", "text": "x", "wallet": "0xnope"}), {}, "a game line needs a wallet")
	eq(NetTg.clean_line([1, 2]), {})
	eq(NetTg.clean_line({"id": {"x": 1}, "src": ["tg"], "text": 3}), {}, "wrong types: no script error, no line")


func test_edits_replace_and_history_caps() -> void:
	var ls: Array = []
	ls = NetTg.merge(ls, {"id": 1, "src": "tg", "text": "a"})
	ls = NetTg.merge(ls, {"id": 2, "src": "tg", "text": "b"})
	ls = NetTg.merge(ls, {"id": 1, "src": "tg", "text": "a2", "edited": true})
	eq(ls.size(), 2, "an edit replaces")
	eq(ls[0]["text"], "a2", "in place")
	ls = NetTg.merge(ls, {"id": 1, "src": "game", "text": "same id, other source"})
	eq(ls.size(), 3, "ids are per source")
	for i in 60:
		ls = NetTg.merge(ls, {"id": 100 + i, "src": "tg", "text": str(i)})
	eq(ls.size(), NetTg.HISTORY, "capped at HISTORY")
	eq(ls[-1]["text"], "59", "the newest kept")


func test_links_and_mentions_are_neutralised() -> void:
	var t := NetTg.outgoing_text("claim at https://scam.example.com/airdrop now, ask @admin_bot or t.me/x")
	check(not t.contains("https://"), t)
	check(not t.contains("scam.example"), t)
	check(not t.contains("@admin"), t)
	check(not t.contains("t.me"), t)
	check(t.contains("scam[.]example[.]com") and t.contains("@ admin_bot") and t.contains("[://]"), t)
	eq(NetTg.neutralise("visit пример.рф"), "visit пример[.]рф", "internationalised domains too")
	eq(NetTg.neutralise("1.5 Ⓐ, v2"), "1.5 Ⓐ, v2", "numbers stay")
	eq(NetTg.neutralise("/ban everyone"), "/ ban everyone", "no clickable bot command")
	eq(NetTg.neutralise(NetTg.neutralise("a.b @c https://x.io")), NetTg.neutralise("a.b @c https://x.io"), "idempotent")
	eq(NetTg.outgoing("a", "see https://x.io"), "a (in game): see https[://]x[.]io", "neutralised once, not twice")
	eq(NetTg.strip_markup("<b>bold</b> **x** [click](https://evil.io) `code`"), "bold x click (https://evil.io) code")
	var o := NetTg.outgoing("free-airdrop.com", "<a href='x'>hi</a> *there*")
	eq(o, "free-airdrop[.]com (in game): hi there", "the name is neutralised too, markup gone")
	eq(NetTg.outgoing_text("  \n "), "", "nothing to send")
	check(NetTg.outgoing_text("y".repeat(600)).length() <= NetTg.OUT_MAX + 40, "capped")


func test_token_is_masked() -> void:
	var s := NetTg.mask("GET https://api.telegram.org/bot%s/getUpdates failed" % TOKEN, TOKEN)
	check(not s.contains(TOKEN) and not s.contains("AAHfakeTOKEN"), s)
	check(s.contains("<bot token>"), s)
	eq(NetTg.mask("the secret half AAHfakeTOKENfakeTOKENfakeTOKEN_abc-12 alone", TOKEN), "the secret half <bot token> alone")
	eq(NetTg.mask("nothing", ""), "nothing")


func test_config_from_env() -> void:
	var env := func(d: Dictionary) -> Callable: return func(k): return String(d.get(k, ""))
	var off := TelegramBridge.config_from_env(env.call({}))
	eq(off["token"], "", "unset: off")
	eq(off["error"], "", "and silent")
	var on := TelegramBridge.config_from_env(env.call({"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_CHAT_ID": "-1001234567890", "TELEGRAM_MUTE_IDS": "5, 6\n7 x"}))
	eq(on["token"], TOKEN)
	eq(on["chat_id"], "-1001234567890")
	eq(on["api_base"], "https://api.telegram.org")
	eq(on["muted"], {"5": true, "6": true, "7": true})
	var bad := TelegramBridge.config_from_env(env.call({"TELEGRAM_BOT_TOKEN": "not a token"}))
	eq(bad["token"], "", "a malformed token: off")
	check(bad["error"] != "" and not bad["error"].contains("not a token"), "an error that never repeats the value")
	var bad_base := TelegramBridge.config_from_env(env.call({"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_API_BASE": "ftp://x"}))
	eq(bad_base["token"], "", "a strange base URL: off (it would carry the token)")
	eq(TelegramBridge.config_from_env(env.call({"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_API_BASE": "http://127.0.0.1:18790/"}))["api_base"], "http://127.0.0.1:18790")
	eq(TelegramBridge.config_from_env(env.call({"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_CHAT_ID": "my group"}))["token"], "", "a chat id must be a number")
	var disc := TelegramBridge.config_from_env(env.call({"TELEGRAM_BOT_TOKEN": TOKEN}))
	check(disc["token"] == TOKEN and disc["chat_id"] == "", "a token without a chat id: discovery (logs chat ids, relays nothing)")


func test_rate_limits() -> void:
	var r := TgRate.new([[1, 10.0], [30, 3600.0]])
	eq(r.take(A, 0.0), 0.0, "the first goes")
	near(r.take(A, 3.0), 7.0, 0.001, "then 10 s apart")
	eq(r.take(B, 3.0), 0.0, "per wallet")
	eq(r.take(A, 10.0), 0.0)
	var t := 10.0
	for i in 28:
		t += 10.0
		eq(r.take(A, t), 0.0, "line %d" % (i + 3))
	t += 10.0
	near(r.wait_s(A, t), 3600.0 - t, 0.001, "the 31st waits for the first to leave the hour")
	var g := TgRate.new([[18, 60.0], [1, 1.0]])
	var sent := 0
	for i in 120:
		if g.take("group", float(i) * 0.5) <= 0.0:
			sent += 1
	eq(sent, 18, "18 a minute for the group, at most one a second")
	g.prune(1000.0)
	eq(g.size(), 0, "housekeeping forgets idle keys")


func test_digest_batches() -> void:
	var d := TgDigest.new()
	check(d.add({"k": "result", "w": A, "w2": B, "game": "pool"}, 100.0))
	check(d.add({"k": "record", "w": A, "board": "x", "score": 5}, 101.0))
	check(not d.due(105.0), "the first moment waits for others to join it")
	check(d.due(116.0), "then it is due")
	var evs := d.take(116.0)
	eq(evs.size(), 2, "one post carries both")
	check(d.add({"k": "arrive", "w": B, "room": Q}, 120.0))
	check(not d.due(200.0), "at most one post every 2 min")
	check(d.due(236.1))
	check(not d.add({"k": "arrive", "w": B, "room": Q}, 300.0), "one arrival per player every 3 h")
	check(not d.add({"k": "result", "w": A, "w2": B, "game": "pool"}, 300.0), "the same line again within 10 min is dropped")
	for i in 10:
		d.add({"k": "place", "w": "0x%040d" % i, "place": "pub", "room": Q}, 400.0)
	d.add({"k": "result", "w": B, "w2": A, "game": "cards"}, 401.0)
	var batch := d.take(500.0)
	eq(batch.size(), TgDigest.MAX_LINES, "at most MAX_LINES a post")
	eq(String(batch[0]["k"]), "result", "results first: they are the news")
	check(d.events.size() > 0, "the rest wait for the next post")
	d.prune(5000.0)
	eq(d.events.size(), 0, "stale moments are dropped, not posted late")


func test_moment_lines() -> void:
	var c := {"name": func(w): return {A: "enteh", B: "bob.xyz"}.get(w, NetProto.short_wallet(w)), "place": func(r): return "Zürich QING" if r == Q else r,
		"game": func(g): return {"pool": "pool", "cards": "Twenty-One"}.get(g, g)}
	eq(NetTg.moment({"k": "result", "w": A, "w2": B, "game": "pool", "stake": "2"}, c), "enteh beat bob[.]xyz at pool (2 Ⓐ stake, honour-bound)", "honour-bound, and a name is neutralised")
	eq(NetTg.moment({"k": "result", "w": A, "w2": B, "game": "pool", "stake": "2", "paid": true}, c), "enteh beat bob[.]xyz at pool (2 Ⓐ stake, honour-bound)", "✓ paid needs a block")
	eq(NetTg.moment({"k": "result", "w": A, "w2": B, "game": "pool", "stake": "2", "paid": true, "paid_block": 28151102}, c), "enteh beat bob[.]xyz at pool (2 Ⓐ ✓ paid, block 28,151,102)")
	eq(NetTg.moment({"k": "result", "w": A, "w2": B, "game": "cards", "push": true}, c), "enteh and bob[.]xyz drew at Twenty-One")
	eq(NetTg.moment({"k": "record", "w": A, "board": Q + "/arcade:void_lanes", "score": 4200, "verified": true}, c), "enteh set a new #1 on Void Lanes: 4,200 ✓")
	eq(NetTg.moment({"k": "daily_record", "w": A, "game": "pool", "score": 9}, c), "enteh set today's best at pool: 9", "the daily challenge's kind, when it exists")
	eq(NetTg.moment({"k": "arrive", "w": A, "room": Q}, c), "enteh arrived in Zürich QING")
	eq(NetTg.moment({"k": "place", "w": A, "room": Q, "place": "pub"}, c), "enteh walked into Sunny's Pub at Zürich QING")
	eq(NetTg.moment({"k": "join", "w": A, "w2": B, "room": Q}, c), "enteh is on the way to join bob[.]xyz at Zürich QING")
	eq(NetTg.moment({"k": "guest", "room": Q}, c), "", "guests: never")
	eq(NetTg.moment({"k": "arrive", "w": "", "room": Q}, c), "", "no wallet: never")
	eq(NetTg.moment({"k": "online", "w": A}, c), "", "comings and goings online are not posted")
	eq(NetTg.moment({"k": "claim", "w": A, "claim": "rocket", "room": Q}, c), "", "an unchecked claim is not posted")
	var text := NetTg.digest_text(["a", "b"])
	check(text.begins_with("From the Dysnomia game:") and text.contains("• a\n• b") and text.ends_with("Open the game: " + NetTg.DOWNLOAD_URL), text)


func test_wire_sizes_and_codes() -> void:
	for c in [NetTg.C_TG, NetTg.C_TG_PREFS]:
		check(c >= 50 and c <= 54, "client codes in 50–54")
	for s in [NetTg.S_TG, NetTg.S_TG_HISTORY, NetTg.S_TG_STATUS]:
		check(s >= 110 and s <= 114, "server codes in 110–114")
	check(NetProto.size_ok(NetTg.send_msg("hi")), "a line fits")
	check(not NetProto.size_ok(NetTg.send_msg("x".repeat(2000))), "an oversized line is refused")
	check(NetProto.size_ok(NetTg.prefs_msg(false)))
	check(not NetProto.size_ok(PackedByteArray([NetTg.C_TG])), "an empty body is malformed")
	eq(NetProto.json_body(NetTg.send_msg("gm")), {"text": "gm"})


func test_guest_sees_the_sign_in_steps() -> void:
	var r := AccessGates.resolve("telegram", {"wallet": "", "net": {"online": true, "telegram": true, "signed": false, "state": ""}})
	eq(r["steps"].size(), 4)
	eq(r["steps"][0]["id"], "wallet")
	eq(r["current"], 0, "a guest with no wallet: connect one first")
	var ready := AccessGates.resolve("telegram", {"wallet": A, "signer": A, "relay": true, "linked": true,
		"net": {"online": true, "telegram": true, "signed": false, "state": ""}})
	eq(ready["steps"][ready["current"]]["id"], "server_sign_in", "then the free sign-in")
	eq(ready["steps"][ready["current"]]["action"], "net_sign_in")
	var done := AccessGates.resolve("telegram", {"wallet": A, "signer": A, "relay": true, "linked": true,
		"net": {"online": true, "telegram": true, "signed": true, "state": "signed"}})
	check(done["ready"], "signed in: ready")
	var off := AccessGates.resolve("telegram", {"wallet": A, "signer": A, "relay": true, "linked": true, "net": {"online": false}})
	eq(off["steps"][off["current"]]["id"], "server", "no server: says so")
	check("net_sign_in" in AccessSteps.BUILT_IN, "the Sign in button works everywhere")


func test_bar_modes_and_rows() -> void:
	eq(ChatBar.mode_label("telegram"), "TG")
	eq(ChatBar.mode_label("say"), "SAY")
	eq(ChatBar.mode_label("post"), "POST")
	check(ChatBar.hint_text().contains("Telegram"), ChatBar.hint_text())
	eq(ChatFeedPanel.tg_age({"ts": 0, "edited": true}), "edited")
	eq(ChatFeedPanel.tg_age({"ts": 1764200000}), NetTg.clock(1764200000))
	check(ChatFeedPanel.tg_state_line(false, 0).contains("—"), "unavailable is not empty")
	check(ChatFeedPanel.tg_state_line(true, 0).contains("nothing said"), "empty says so")
	check(ChatFeedPanel.tg_state_line(true, 3).contains("not on chain"), "every state says it is not on chain")
	var rows := PubTgScreen.screen_rows([{"id": 1, "src": "tg", "from": "Ann", "text": "gm", "ts": 1764200000},
		{"id": 2, "src": "game", "wallet": A, "text": "hi", "ts": 1764200060, "edited": true}], func(w): return "enteh" if w == A else "?")
	eq(rows.size(), 2)
	eq(rows[0]["who"], "Ann · Telegram")
	eq(rows[1]["who"], "enteh (in game)")
	check(String(rows[1]["age"]).ends_with("edited"))
	check(PubTgScreen.fs(DeepFieldTheme.FS_MIN) >= DeepFieldTheme.FS_MIN, "the TV's smallest type is at least FS_MIN")
	check(ControlsHelp.key_of("chat_source") != "", "the dock's switch has a key")
