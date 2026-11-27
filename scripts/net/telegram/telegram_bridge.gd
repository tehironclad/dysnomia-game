class_name TelegramBridge
extends Node
## The game server's side of the Telegram bridge (docs/SERVER.md §8d). Only the
## server talks to Telegram: it long-polls the Bot API (getUpdates, ~25 s, an
## HTTPRequest that never blocks the server's frame) and posts with sendMessage
## (plain text: no parse_mode, link previews off). Clients never see the token.
##
## Config, from the environment only (config_from_env):
##   TELEGRAM_BOT_TOKEN   the bot's token (from @BotFather). Never printed, logged or sent:
##                        every log line goes through NetTg.mask.
##   TELEGRAM_CHAT_ID     the one group it bridges; every other chat is ignored. Unset: the
##                        bridge only LOGS the chat ids it sees (to find yours), relays nothing,
##                        and the server does not offer "telegram".
##   TELEGRAM_API_BASE    https://api.telegram.org (tests point it at a mock).
##   TELEGRAM_MUTE_IDS    Telegram user ids whose lines never reach the game (comma-separated);
##                        also <data>/telegram_mute.txt, one id a line, re-read every minute.
## No token: the bridge is not created at all (silent).
##
## Telegram → game: text (and edits, which replace) from the allowed chat become lines
## (NetTg.line_from_message) for every client; non-text is a placeholder; the last
## NetTg.HISTORY are kept (and saved) for players who join later. Bots, muted users and
## service messages are dropped.
## Game → Telegram: signed-in players only (the server's verified wallet), limited per
## wallet (1 per 10 s, 30 an hour) and for the group (18 a minute, 1 a second); the post is
## "<chain name> (in game): text" with links, mentions and markup neutralised.
## Moments: real server events (NetTg.MOMENT_KINDS) batched by TgDigest, one bot post at
## most every 2 min; never for guests, never for a wallet that opted out (C_TG_PREFS, kept
## in <data>/telegram_prefs.json).

signal line(l: Dictionary)                       ## a line for every client (S_TG)
signal answer(peer_id: int, d: Dictionary)       ## an S_TG_STATUS for one connection

const POLL_TIMEOUT_S := 25
const HTTP_TIMEOUT_S := 45.0
const NAME_WAIT_S := 4.0          ## a post waits this long for the chain's name, then uses the short wallet
const RETRY_MIN_S := 5.0
const RETRY_MAX_S := 300.0
const QUEUE_MAX := 8              ## posts waiting (lines + digests); more is "busy"
const BUSY_WAIT_S := 8.0          ## refuse a line that would wait longer than this for the group's limit
const MUTE_FILE := "telegram_mute.txt"
const PREFS_FILE := "telegram_prefs.json"
const HISTORY_FILE := "telegram_history.json"
const DEFAULT_API := "https://api.telegram.org"

var token := ""
var chat_id := ""
var api_base := DEFAULT_API
var data_dir := "user://server"
var env_muted := {}               ## telegram user id → true (TELEGRAM_MUTE_IDS)
var file_muted := {}              ## … (telegram_mute.txt)
var opted_out := {}               ## wallet → true: no moments about them
var history: Array = []
## Callables the server gives: log_fn(text); name_fn(wallet) -> {name, final};
## place_fn(room) -> String; game_fn(game id) -> String.
var log_fn: Callable
var name_fn: Callable
var place_fn: Callable
var game_fn: Callable

var per_wallet := TgRate.new([[1, 10.0], [30, 3600.0]])
var group := TgRate.new([[18, 60.0], [1, 1.0]])
var digest := TgDigest.new()
var stats := {"from_tg": 0, "edits": 0, "ignored_chat": 0, "muted": 0, "to_tg": 0, "digests": 0, "refused": 0, "errors": 0}

var _poll: HTTPRequest
var _send: HTTPRequest
var _poll_busy := false
var _send_busy := false
var _next_poll := 0.0
var _poll_backoff := RETRY_MIN_S
var _send_pause_until := 0.0
var _offset := 0
var _pending: Array = []          ## lines waiting for their speaker's chain name: {wallet, text, peer, at}
var _queue: Array = []            ## ready posts: {kind: chat|digest, text, shown, wallet, peer, name}
var _inflight := {}
var _seen_chats := {}             ## chat id → true (logged once)
var _mute_at := -1000.0
var _save_due := false
var _save_at := 0.0
var _warned := {}


## Pure: the bridge's config from an environment getter (Callable(name) -> String).
## {token, chat_id, api_base, muted: {id: true}, error}; token "" = off. A malformed
## token or base URL turns it off with an error that never repeats the token.
static func config_from_env(env: Callable) -> Dictionary:
	var tok := String(env.call("TELEGRAM_BOT_TOKEN")).strip_edges()
	var cid := String(env.call("TELEGRAM_CHAT_ID")).strip_edges()
	var base := String(env.call("TELEGRAM_API_BASE")).strip_edges().trim_suffix("/")
	var out := {"token": "", "chat_id": "", "api_base": DEFAULT_API, "muted": parse_ids(String(env.call("TELEGRAM_MUTE_IDS"))), "error": ""}
	if tok == "":
		return out
	if not token_ok(tok):
		out["error"] = "TELEGRAM_BOT_TOKEN does not look like a bot token (<digits>:<35 letters> from @BotFather); the Telegram bridge is off"
		return out
	if base != "" and not base_ok(base):
		out["error"] = "TELEGRAM_API_BASE must be an http(s):// address with no spaces; the Telegram bridge is off"
		return out
	if cid != "" and not chat_id_ok(cid):
		out["error"] = "TELEGRAM_CHAT_ID must be a number like -1001234567890; the Telegram bridge is off"
		return out
	out["token"] = tok
	out["chat_id"] = cid
	if base != "":
		out["api_base"] = base
	return out


static func token_ok(t: String) -> bool:
	var c := t.find(":")
	if c < 3 or c > 14 or not t.left(c).is_valid_int() or t.length() - c - 1 < 20 or t.length() - c - 1 > 80:
		return false
	for ch in t.substr(c + 1):
		if not (ch.is_valid_identifier() or ch == "-" or (ch >= "0" and ch <= "9")):
			return false
	return true


static func base_ok(b: String) -> bool:
	if not (b.begins_with("https://") or b.begins_with("http://")) or b.length() > 200:
		return false
	for ch in b:
		if ch.unicode_at(0) <= 32 or ch in ["?", "#", "@", "\\", "\"", "'", "<", ">"]:
			return false
	return NetProto.login_host(b) != ""


static func chat_id_ok(c: String) -> bool:
	return c.is_valid_int() and c.length() <= 20


## Pure: "123, 456\n789" → {"123": true, …} (whole numbers only).
static func parse_ids(s: String) -> Dictionary:
	var out := {}
	for part in s.replace("\n", ",").replace(" ", ",").split(",", false):
		var p := part.strip_edges()
		if p.is_valid_int():
			out[str(int(p))] = true
	return out


func configure(cfg: Dictionary) -> void:
	token = String(cfg.get("token", ""))
	chat_id = String(cfg.get("chat_id", ""))
	api_base = String(cfg.get("api_base", DEFAULT_API))
	env_muted = cfg.get("muted", {})


## Relaying (the server offers "telegram"): a token and the chat.
func enabled() -> bool:
	return token != "" and chat_id != ""


func _ready() -> void:
	_poll = HTTPRequest.new()
	_poll.name = "Poll"
	_poll.timeout = HTTP_TIMEOUT_S
	_poll.max_redirects = 0  # a redirect would carry the token's URL elsewhere
	_poll.request_completed.connect(_on_poll)
	add_child(_poll)
	_send = HTTPRequest.new()
	_send.name = "Send"
	_send.timeout = 20.0
	_send.max_redirects = 0
	_send.request_completed.connect(_on_send)
	add_child(_send)
	_load_prefs()
	_load_history()
	_reload_mutes(true)
	if enabled():
		_log("Telegram bridge on: chat %s via %s (%d muted ids)" % [chat_id, NetProto.login_host(api_base), env_muted.size() + file_muted.size()])
	else:
		_log("Telegram: TELEGRAM_CHAT_ID is not set, so nothing is relayed. The chat ids this bot sees are logged here: " +
			"put yours in TELEGRAM_CHAT_ID (docs/SERVER.md §5c).")


func _log(text: String) -> void:
	var t := NetTg.mask(text, token)
	if log_fn.is_valid():
		log_fn.call(t)
	else:
		print(t)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _url(method: String) -> String:
	return "%s/bot%s/%s" % [api_base, token, method]


# ── the loop ────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if token == "":
		return
	var now := _now()
	if not _poll_busy and now >= _next_poll:
		_start_poll()
	_ripen(now)
	if enabled() and digest.due(now) and _queue.size() < QUEUE_MAX and group.wait_s("group", now) <= 0.0:
		_post_digest(now)
	if not _send_busy and not _queue.is_empty() and now >= _send_pause_until and group.wait_s("group", now) <= 0.0:
		_send_next(now)
	if now - _mute_at > 60.0:
		_reload_mutes(false)
		per_wallet.prune(now)
	if _save_due and now - _save_at > 5.0:
		_save_history()


func _start_poll() -> void:
	var body := JSON.stringify({"offset": _offset, "timeout": POLL_TIMEOUT_S, "allowed_updates": ["message", "edited_message"]})
	var err := _poll.request(_url("getUpdates"), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_poll_failed("could not start a getUpdates request (error %d)" % err)
		return
	_poll_busy = true


func _poll_failed(why: String) -> void:
	_poll_busy = false
	stats["errors"] += 1
	_warn("poll", "Telegram getUpdates failed: %s; retrying in %d s" % [why, int(_poll_backoff)])
	_next_poll = _now() + _poll_backoff
	_poll_backoff = minf(_poll_backoff * 2.0, RETRY_MAX_S)


## Logs a warning once per kind until it clears (a dead network would fill the log).
func _warn(kind: String, text: String) -> void:
	if _warned.has(kind):
		return
	_warned[kind] = true
	_log(text)


func _on_poll(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_poll_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_poll_failed("network (HTTPRequest result %d)" % result)
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if code != 200 or not (j is Dictionary) or not NetProto.flag_of(j.get("ok", false)):
		var desc := NetProto.clean_text(NetProto.str_of(j.get("description", "")) if j is Dictionary else "", 160)
		if code == 401 or code == 404:
			desc += " (check TELEGRAM_BOT_TOKEN)"
		elif code == 409:
			desc += " (another program polls this bot, or a webhook is set: deleteWebhook)"
		elif code == 429 and j is Dictionary and j.get("parameters") is Dictionary:
			_poll_backoff = maxf(_poll_backoff, float(NetProto.int_of(j["parameters"].get("retry_after", 5), 5)))
		_poll_failed("HTTP %d %s" % [code, desc])
		return
	_warned.erase("poll")
	_poll_backoff = RETRY_MIN_S
	_next_poll = _now()
	var res = j.get("result", [])
	if not (res is Array):
		return
	for u in res:
		if not (u is Dictionary):
			continue
		var uid := NetProto.int_of(u.get("update_id", -1), -1)
		if uid >= 0:
			_offset = maxi(_offset, uid + 1)
		if u.get("message") is Dictionary:
			_on_message(u["message"], false)
		elif u.get("edited_message") is Dictionary:
			_on_message(u["edited_message"], true)


## One message from Telegram: only the allowed chat, never bots or muted users.
func _on_message(msg: Dictionary, edited: bool) -> void:
	var chat = msg.get("chat")
	if not (chat is Dictionary):
		return
	var cid := str(NetProto.int_of(chat.get("id", 0)))
	if chat_id == "":
		if not _seen_chats.has(cid):
			_seen_chats[cid] = true
			_log("Telegram: this bot sees chat %s (%s \"%s\"). To bridge it: TELEGRAM_CHAT_ID=%s in the server's environment file, then restart." % [
				cid, NetProto.clean_text(NetProto.str_of(chat.get("type", "")), 20), NetProto.clean_text(NetProto.str_of(chat.get("title", "")), 60), cid])
		return
	if cid != chat_id:
		stats["ignored_chat"] += 1
		if not _seen_chats.has(cid):
			_seen_chats[cid] = true
			_log("Telegram: ignored a message from another chat (%s); only %s is bridged" % [cid, chat_id])
		return
	var fr = msg.get("from")
	if fr is Dictionary and NetProto.flag_of(fr.get("is_bot", false)):
		return
	var uid := str(NetProto.int_of(fr.get("id", 0))) if fr is Dictionary else ""
	if uid != "" and (env_muted.has(uid) or file_muted.has(uid)):
		stats["muted"] += 1
		return
	var l := NetTg.line_from_message(msg, edited)
	if l.is_empty():
		return
	stats["edits" if edited else "from_tg"] += 1
	_publish(l)


func _publish(l: Dictionary) -> void:
	history = NetTg.merge(history, l, NetTg.HISTORY)
	_save_due = true
	line.emit(l)


# ── game → Telegram ────────────────────────────────────────────────────────

## A signed-in player's line (C_TG). {ok: true} when it was taken (the post follows;
## S_TG brings it back once Telegram took it), else {ok: false, error, retry_s}.
func submit(peer_id: int, wallet: String, text: String, now: float) -> Dictionary:
	if not enabled():
		return {"ok": false, "error": "This server has no Telegram bridge."}
	if wallet == "":
		return {"ok": false, "error": "Sign in to the game server first (a free signature): guests can read Telegram, not write to it.", "code": "guest"}
	var t := NetTg.outgoing_text(NetTg.mask(text, token))
	if t == "":
		return {"ok": false, "error": "Nothing to send."}
	var w := per_wallet.wait_s(wallet, now)
	if w > 0.0:
		stats["refused"] += 1
		return {"ok": false, "error": "Slow down: one Telegram line every 10 s, 30 an hour (next in %d s)." % ceili(w), "retry_s": ceili(w)}
	var gw := group.wait_s("group", now)
	if _pending.size() + _queue.size() >= QUEUE_MAX or gw > BUSY_WAIT_S:
		stats["refused"] += 1
		var r := maxi(ceili(gw), 5)
		return {"ok": false, "error": "Telegram is busy right now (the group's limit): try again in %d s." % r, "retry_s": r}
	per_wallet.note(wallet, now)
	_pending.append({"wallet": wallet, "text": t, "peer": peer_id, "at": now})
	if name_fn.is_valid():
		name_fn.call(wallet)  # starts the chain read now
	return {"ok": true}


## Lines whose speaker's chain name has been read (or waited NAME_WAIT_S for) → the queue.
func _ripen(now: float) -> void:
	var keep: Array = []
	for j in _pending:
		var r: Dictionary = name_fn.call(j["wallet"]) if name_fn.is_valid() else {"name": NetProto.short_wallet(j["wallet"]), "final": true}
		if not bool(r.get("final", false)) and now - float(j["at"]) < NAME_WAIT_S:
			keep.append(j)
			continue
		var nm := String(r.get("name", ""))
		if nm == "":
			nm = NetProto.short_wallet(j["wallet"])
		_queue.append({"kind": "chat", "text": NetTg.mask(NetTg.outgoing(nm, j["text"]), token), "shown": j["text"], "wallet": j["wallet"],
			"peer": j["peer"], "name": nm})
	_pending = keep


func _send_next(now: float) -> void:
	var job: Dictionary = _queue.pop_front()
	var body := JSON.stringify({"chat_id": chat_id, "text": job["text"], "disable_web_page_preview": true,
		"link_preview_options": {"is_disabled": true}})
	var err := _send.request(_url("sendMessage"), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_send_done(job, false, "could not start the request (error %d)" % err)
		return
	group.note("group", now)
	_send_busy = true
	_inflight = job


func _on_send(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_send_busy = false
	var job := _inflight
	_inflight = {}
	if job.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_send_done(job, false, "network (HTTPRequest result %d)" % result)
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if code == 429 and j is Dictionary and j.get("parameters") is Dictionary:
		var ra := clampi(NetProto.int_of(j["parameters"].get("retry_after", 5), 5), 1, 600)
		_send_pause_until = _now() + ra
		_log("Telegram asked to slow down (retry after %d s)" % ra)
		_queue.push_front(job)
		return
	if code != 200 or not (j is Dictionary) or not NetProto.flag_of(j.get("ok", false)):
		var desc := NetProto.clean_text(NetProto.str_of(j.get("description", "")) if j is Dictionary else "", 160)
		_send_done(job, false, "HTTP %d %s" % [code, desc])
		return
	var res = j.get("result")
	_send_done(job, true, "", NetProto.int_of(res.get("message_id", 0)) if res is Dictionary else 0,
		NetProto.int_of(res.get("date", 0)) if res is Dictionary else 0)


func _send_done(job: Dictionary, ok: bool, why: String, msg_id: int = 0, date: int = 0) -> void:
	if not ok:
		stats["errors"] += 1
		_log("Telegram sendMessage failed: %s" % why)
		if job["kind"] == "chat":
			answer.emit(int(job["peer"]), {"what": "send", "ok": false, "error": "Telegram did not take it: %s" % NetProto.clean_text(why, 120)})
		return
	var ts := date if date > 0 else int(Time.get_unix_time_from_system())
	if job["kind"] == "chat":
		stats["to_tg"] += 1
		_log("telegram ← %s (%s): %s" % [job["wallet"], job["name"], job["shown"]])
		answer.emit(int(job["peer"]), {"what": "send", "ok": true})
		if msg_id > 0:
			_publish({"id": msg_id, "src": "game", "from": String(job["name"]), "wallet": job["wallet"], "text": NetTg.clip(String(job["shown"]), NetTg.TEXT_MAX),
				"ts": ts, "edited": false})
	else:
		stats["digests"] += 1
		_log("telegram ← digest: %s" % String(job["shown"]))
		if msg_id > 0:
			_publish({"id": msg_id, "src": "bot", "from": NetTg.BOT_NAME, "text": NetTg.clip(String(job["shown"]), NetTg.TEXT_MAX), "ts": ts, "edited": false})


# ── game moments ───────────────────────────────────────────────────────────

## A server event (GameServer._event). Queued when it is a moment, about signed-in
## players who have not opted out.
func moment(ev: Dictionary) -> bool:
	if not enabled() or not NetTg.MOMENT_KINDS.has(String(ev.get("k", ""))):
		return false
	var ws := _wallets_of(ev)
	if ws.is_empty():
		return false
	for w in ws:
		if w == "" or opted_out.has(w):
			return false
	if not digest.add(ev.duplicate(), _now()):
		return false
	if name_fn.is_valid():
		for w in ws:
			name_fn.call(w)  # read the names now; the digest formats them when it posts
	return true


static func _wallets_of(ev: Dictionary) -> Array:
	var w := String(ev.get("w", ""))
	if w == "":
		return []
	var out := [w]
	if String(ev.get("k", "")) in ["result", "join"]:
		out.append(String(ev.get("w2", "")))
	return out


func _post_digest(now: float) -> void:
	var evs := digest.take(now)
	var lines: Array = []
	var ctx := {"name": func(w: String) -> String:
			if not name_fn.is_valid():
				return NetProto.short_wallet(w)
			var r: Dictionary = name_fn.call(w)
			return String(r.get("name", NetProto.short_wallet(w))),
		"place": place_fn, "game": game_fn}
	for ev in evs:
		var skip := false
		for w in _wallets_of(ev):
			if w == "" or opted_out.has(w):
				skip = true  # opted out after the moment was queued
		if skip:
			continue
		var s := NetTg.moment(ev, ctx)
		if s != "":
			lines.append(s)
	if lines.is_empty():
		return
	_queue.append({"kind": "digest", "text": NetTg.mask(NetTg.digest_text(lines), token), "shown": " · ".join(PackedStringArray(lines)), "peer": -1})


# ── players' choices ───────────────────────────────────────────────────────

## C_TG_PREFS: post this wallet's moments (default) or not. Saved.
func set_moments(wallet: String, on: bool) -> void:
	if wallet == "":
		return
	var was := not opted_out.has(wallet)
	if on:
		opted_out.erase(wallet)
	else:
		opted_out[wallet] = true
	if was != on:
		_save_prefs()


func moments_on(wallet: String) -> bool:
	return not opted_out.has(wallet)


func _load_prefs() -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join(PREFS_FILE))) if FileAccess.file_exists(data_dir.path_join(PREFS_FILE)) else null
	if j is Dictionary and j.get("opted_out") is Array:
		for w in j["opted_out"]:
			var cw := NetProto.clean_wallet(NetProto.str_of(w))
			if cw != "":
				opted_out[cw] = true


func _save_prefs() -> void:
	var f := FileAccess.open(data_dir.path_join(PREFS_FILE), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"opted_out": opted_out.keys()}))


func _load_history() -> void:
	var path := data_dir.path_join(HISTORY_FILE)
	if not enabled() or not FileAccess.file_exists(path):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if j is Dictionary and String(j.get("chat", "")) == chat_id and j.get("lines") is Array:
		for d in j["lines"]:
			var l := NetTg.clean_line(d)
			if not l.is_empty():
				history = NetTg.merge(history, l, NetTg.HISTORY)


func _save_history() -> void:
	_save_due = false
	_save_at = _now()
	var f := FileAccess.open(data_dir.path_join(HISTORY_FILE), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"chat": chat_id, "lines": history}))


func _reload_mutes(first: bool) -> void:
	_mute_at = _now()
	var path := data_dir.path_join(MUTE_FILE)
	var ids := parse_ids(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not first and ids.size() != file_muted.size():
		_log("Telegram: %d muted ids in %s" % [ids.size(), MUTE_FILE])
	file_muted = ids


func save_now() -> void:
	if _save_due:
		_save_history()
