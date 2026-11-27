class_name NetTg
extends RefCounted
## The Telegram bridge's wire messages and every pure rule it follows (docs/SERVER.md
## §8d, LEARNINGS §18). Only the game SERVER talks to Telegram (TelegramBridge); the
## game gets Telegram's lines from the server and sends its own through it. Clients
## never see the bot token and never call Telegram. Pure: the server, the client and
## the tests share it. Its own message numbers, like NetBump and NetEvents:
##
##   C_TG        (client → server) [50]  json {text}       a signed-in player's line to the Telegram group
##   C_TG_PREFS  (client → server) [51]  json {moments}    post my game moments to Telegram (default true)
##   S_TG        (server → clients) [110] json {line}      one line (new, or an edit: the same id replaces it)
##   S_TG_HISTORY (server → client) [111] json {lines}     the last HISTORY lines, right after the welcome
##   S_TG_STATUS (server → client) [112] json {what: send|prefs, ok, error, retry_s, moments}
##
## A line: {id (Telegram's message_id), src, from, text, ts (unix), edited, wallet}
##   src "tg"   a member of the group wrote it: `from` is their Telegram display name, a
##              free text anyone can set. It is NEVER a chain identity: always shown as
##              "<name> · Telegram", no ✓ badge, never matched against LAU names.
##   src "game" a signed-in player wrote it in the game: `wallet` is the wallet the server's
##              sign-in proved; each client shows the chain's name for it (LauNames).
##   src "bot"  the server's digest of game moments.
## Nothing here is on chain: every surface says "Telegram · free · not on chain".

const C_TG := 50
const C_TG_PREFS := 51
const S_TG := 110
const S_TG_HISTORY := 111
const S_TG_STATUS := 112

## Listed in S_WELCOME "features" only by a server whose bridge is configured.
const FEATURE := "telegram"
const SIZES := {C_TG: 1024, C_TG_PREFS: 64}

const HISTORY := 50          ## lines a server keeps for players who join later
const TEXT_MAX := 280        ## a Telegram line as the game shows it
const NAME_MAX := 32         ## a Telegram display name as the game shows it
const OUT_MAX := 200         ## a game line to Telegram (NetProto.CHAT_MAX_CHARS)
const SOURCES := ["tg", "game", "bot"]
const DOWNLOAD_URL := "https://enterdysnomia.com/download"
const BOT_NAME := "Dysnomia game"
## Where the group is, for every label ("Sunny's Pub on Telegram").
const GROUP := "Sunny's Pub"

## What a non-text message shows as (the first field a message has wins).
const PLACEHOLDERS := [["photo", "[photo]"], ["sticker", "[sticker]"], ["animation", "[GIF]"], ["video_note", "[video message]"],
	["video", "[video]"], ["voice", "[voice message]"], ["audio", "[audio]"], ["document", "[file]"], ["poll", "[poll]"],
	["venue", "[place]"], ["location", "[location]"], ["contact", "[contact]"], ["dice", "[dice]"], ["game", "[game]"], ["story", "[story]"]]

## Server events that become Telegram moments (the digest). "daily_record" comes from the
## daily challenge (another feature): accepted when it exists, never needed.
const MOMENT_KINDS := ["result", "record", "daily_record", "join", "arrive", "place"]


static func size_ok(msg: PackedByteArray) -> bool:
	return not msg.is_empty() and SIZES.has(int(msg[0])) and msg.size() >= 2 and msg.size() <= int(SIZES[int(msg[0])])


static func send_msg(text: String) -> PackedByteArray:
	return NetProto.json_msg(C_TG, {"text": text})


static func prefs_msg(moments: bool) -> PackedByteArray:
	return NetProto.json_msg(C_TG_PREFS, {"moments": moments})


static func line_msg(line: Dictionary) -> PackedByteArray:
	return NetProto.json_msg(S_TG, {"line": line})


static func history_msg(lines: Array) -> PackedByteArray:
	return NetProto.json_msg(S_TG_HISTORY, {"lines": lines})


static func status_msg(d: Dictionary) -> PackedByteArray:
	return NetProto.json_msg(S_TG_STATUS, d)


# ── Telegram → game ─────────────────────────────────────────────────────────

## The marks a Telegram name must not carry: they would look like the game's ✓ badge.
const BADGE_MARKS := ["✓", "✔", "☑", "✅", "🗸"]


## Pure: a Telegram sender as the game names them: first + last name, else the
## username, else "someone" (a channel or an anonymous admin: the chat's title).
## Cleaned (invisible characters, one line), check marks dropped, ≤ NAME_MAX.
static func display_name(msg: Dictionary) -> String:
	var n := ""
	var sc = msg.get("sender_chat")
	var fr = msg.get("from")
	if sc is Dictionary:
		n = NetProto.str_of(sc.get("title", ""))
	elif fr is Dictionary:
		n = (NetProto.str_of(fr.get("first_name", "")) + " " + NetProto.str_of(fr.get("last_name", ""))).strip_edges()
		if NetProto.clean_text(n, NAME_MAX) == "":
			n = NetProto.str_of(fr.get("username", ""))
	for m in BADGE_MARKS:
		n = n.replace(m, "")
	n = NetProto.clean_text(n, NAME_MAX)
	return n if n != "" else "someone"


## Pure: "[photo]" etc. for a message without text, "" for a text message.
static func placeholder(msg: Dictionary) -> String:
	for p in PLACEHOLDERS:
		if msg.has(p[0]):
			if p[0] == "sticker" and msg["sticker"] is Dictionary:
				var e := NetProto.clean_text(NetProto.str_of(msg["sticker"].get("emoji", "")), 4)
				return "[sticker %s]" % e if e != "" else "[sticker]"
			return String(p[1])
	return ""


## Pure: a Telegram message (from the allowed chat) → a line, or {} for a service
## message (someone joined, a pin…) or one with nothing to show.
static func line_from_message(msg: Dictionary, edited: bool = false) -> Dictionary:
	var id := NetProto.int_of(msg.get("message_id", 0))
	if id <= 0:
		return {}
	var text := NetProto.str_of(msg.get("text", ""))
	var ph := ""
	if text == "":
		ph = placeholder(msg)
		if ph == "":
			return {}
		var cap := NetProto.str_of(msg.get("caption", ""))
		text = ph + ((" " + cap) if cap != "" else "")
	text = clip(NetProto.clean_text(text, TEXT_MAX * 4), TEXT_MAX)
	if text == "":
		return {}
	var ts := NetProto.int_of(msg.get("edit_date", 0)) if edited else 0
	if ts <= 0:
		ts = NetProto.int_of(msg.get("date", 0))
	return {"id": id, "src": "tg", "from": display_name(msg), "text": text, "ts": maxi(0, ts), "edited": edited}


## Pure: at most `n` characters, "…" when cut.
static func clip(s: String, n: int) -> String:
	return s if s.length() <= n else s.left(n - 1).strip_edges() + "…"


## Client side: a server's line, cleaned (the server is somebody's laptop): {} when it
## is not a line this game shows.
static func clean_line(d) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var src := NetProto.str_of(d.get("src", ""))
	var id := NetProto.int_of(d.get("id", 0))
	if not SOURCES.has(src) or id <= 0:
		return {}
	var text := clip(NetProto.clean_text(NetProto.str_of(d.get("text", "")), TEXT_MAX * 4), TEXT_MAX)
	if text == "":
		return {}
	var from := NetProto.str_of(d.get("from", ""))
	for m in BADGE_MARKS:
		from = from.replace(m, "")
	var l := {"id": id, "src": src, "from": NetProto.clean_text(from, NAME_MAX), "text": text,
		"ts": maxi(0, NetProto.int_of(d.get("ts", 0))), "edited": NetProto.flag_of(d.get("edited", false))}
	if src == "game":
		l["wallet"] = NetProto.clean_wallet(NetProto.str_of(d.get("wallet", "")))
		if l["wallet"] == "":
			return {}
	return l


## Pure: who a line is from, as every surface draws it. `chain_name`: Callable(wallet)
## -> String (the chain's name for a game line's verified wallet; the short wallet if
## none). A Telegram name always carries " · Telegram": it is nobody's chain identity.
static func speaker(l: Dictionary, chain_name: Callable = Callable()) -> String:
	match String(l.get("src", "")):
		"tg":
			var n := String(l.get("from", ""))
			return "%s · Telegram" % (n if n != "" else "someone")
		"game":
			var w := String(l.get("wallet", ""))
			var nm := String(chain_name.call(w)) if chain_name.is_valid() else NetProto.short_wallet(w)
			return "%s (in game)" % nm
	return "%s · Telegram" % BOT_NAME


## Pure: merges a line into a list kept in order (an edit replaces the line with its id).
## Returns the list, at most `cap` lines (oldest dropped).
static func merge(lines: Array, l: Dictionary, cap: int = HISTORY) -> Array:
	for i in lines.size():
		if int(lines[i].get("id", 0)) == int(l["id"]) and String(lines[i].get("src", "")) == String(l["src"]):
			lines[i] = l
			return lines
	lines.append(l)
	while lines.size() > cap:
		lines.pop_front()
	return lines


## Pure: "12:04" (UTC) for a line's time, "" when unknown.
static func clock(ts: int) -> String:
	if ts <= 0:
		return ""
	var t := Time.get_datetime_dict_from_unix_time(ts)
	return "%02d:%02d" % [int(t["hour"]), int(t["minute"])]


# ── game → Telegram ─────────────────────────────────────────────────────────
# A bot's message looks authoritative, so nothing a player types (or a LAU name,
# or a QING's name) may become a link or a mention there: dots between letters are
# defanged ("scam[.]com"), "://" becomes "[://]", "@name" becomes "@ name" and a
# bot command "/x" becomes "/ x". Markup goes: the bot sends plain text (no
# parse_mode), and HTML tags, markdown links and emphasis marks are stripped first.

static var _rx := {}


static func _re(key: String, pat: String) -> RegEx:
	if not _rx.has(key):
		_rx[key] = RegEx.create_from_string(pat)
	return _rx[key]


## Pure: HTML tags, markdown links ([text](url) → "text (url)") and emphasis marks gone.
static func strip_markup(s: String) -> String:
	s = _re("tag", "</?[A-Za-z][^<>]{0,80}>").sub(s, "", true)
	s = _re("mdlink", "\\[([^\\]]{0,200})\\]\\(([^)]{0,300})\\)").sub(s, "$1 ($2)", true)
	for m in ["**", "__", "||", "```", "`", "~", "*"]:
		s = s.replace(m, "")
	return s


## Pure: no link, mention or bot command survives (see above). Idempotent.
static func neutralise(s: String) -> String:
	s = _re("scheme", "(?<!\\[)://").sub(s, "[://]", true)
	s = _re("dot", "(?<=[\\p{L}\\p{N}])\\.(?=\\p{L})").sub(s, "[.]", true)
	s = _re("at", "@(?=[\\p{L}\\p{N}_])").sub(s, "@ ", true)
	s = _re("cmd", "(^|\\s)/(?=\\p{L})").sub(s, "$1/ ", true)
	return s


## Pure: a player's text as it may go to Telegram: one line, printable, markup and
## links gone, ≤ OUT_MAX. "" = nothing to send.
static func outgoing_text(text: String) -> String:
	var t := NetProto.clean_text(strip_markup(NetProto.clean_text(text, OUT_MAX * 2)), OUT_MAX * 2)
	return clip(neutralise(t), OUT_MAX + 40).strip_edges()


## Pure: the bot's message for a player's line: "<name> (in game): text".
static func outgoing(name: String, text: String) -> String:
	var n := neutralise(NetProto.clean_text(strip_markup(name), NetProto.NAME_MAX_CHARS + 8))
	return "%s (in game): %s" % [n if n != "" else "someone", outgoing_text(text)]


## Pure: `token` (and the token's secret half) replaced, for anything logged or sent.
static func mask(s: String, token: String) -> String:
	if token == "":
		return s
	s = s.replace(token, "<bot token>")
	var colon := token.find(":")
	if colon > 0 and token.length() - colon > 8:
		s = s.replace(token.substr(colon + 1), "<bot token>")
	return s


# ── game moments (the digest) ──────────────────────────────────────────────

## Pure: one Telegram line for a server event, "" when it is not a moment we post.
## ctx: name: Callable(wallet) -> String (the chain's name or the short wallet);
## place: Callable(room) -> String (a QING's name); game: Callable(game id) -> String.
## A wager is honour-bound: "✓ paid" only when the event carries a verified payment
## (paid true + paid_block; the server itself never says so). Every name and place
## is neutralised (a LAU named "free-airdrop.com" must not become a link).
static func moment(ev: Dictionary, ctx: Dictionary = {}) -> String:
	var k := String(ev.get("k", ""))
	if not MOMENT_KINDS.has(k):
		return ""
	var nf = ctx.get("name")
	var pf = ctx.get("place")
	var gf = ctx.get("game")
	var who := func(w: String) -> String:
		return neutralise(NetProto.clean_text(String(nf.call(w)) if nf is Callable else NetProto.short_wallet(w), NetProto.NAME_MAX_CHARS + 8))
	var where := func(room: String) -> String:
		var r := room.get_slice("/", 0)
		if r == "":
			return "a QING"
		return neutralise(NetProto.clean_text(String(pf.call(r)) if pf is Callable else NetProto.short_wallet(r), 40))
	var game := func(g: String) -> String:
		return neutralise(NetProto.clean_text(String(gf.call(g)) if gf is Callable else g, 40))
	var w := String(ev.get("w", ""))
	var w2 := String(ev.get("w2", ""))
	if w == "" or (k in ["result", "join"] and w2 == ""):
		return ""  # guests: never
	var a: String = who.call(w)
	var room := String(ev.get("room", ""))
	var stake := String(ev.get("stake", ""))
	match k:
		"result":
			var b: String = who.call(w2)
			if NetProto.flag_of(ev.get("push", false)):
				return "%s and %s drew at %s" % [a, b, game.call(String(ev.get("game", "")))]
			var st := ""
			if stake != "" and stake.is_valid_float():
				var paid := NetProto.flag_of(ev.get("paid", false)) and NetProto.int_of(ev.get("paid_block", 0)) > 0
				st = (" (%s Ⓐ ✓ paid, block %s)" % [stake, NetEvents.grouped(NetProto.int_of(ev["paid_block"]))]) if paid else (" (%s Ⓐ stake, honour-bound)" % stake)
			return "%s beat %s at %s%s" % [a, b, game.call(String(ev.get("game", ""))), st]
		"record":
			return "%s set a new #1 on %s: %s%s" % [a, neutralise(NetEvents.board_title(String(ev.get("board", "")))),
				NetEvents.grouped(maxi(0, NetProto.int_of(ev.get("score", 0)))), " ✓" if NetProto.flag_of(ev.get("verified", false)) else ""]
		"daily_record":
			var what := String(ev.get("game", ""))
			var title: String = game.call(what) if what != "" else neutralise(NetEvents.board_title(String(ev.get("board", ""))))
			return "%s set today's best at %s: %s%s" % [a, title, NetEvents.grouped(maxi(0, NetProto.int_of(ev.get("score", 0)))),
				" ✓" if NetProto.flag_of(ev.get("verified", false)) else ""]
		"join":
			return "%s is on the way to join %s at %s" % [a, who.call(w2), where.call(room)]
		"arrive":
			return "%s arrived in %s" % [a, where.call(room)]
		"place":
			var pl := String(NetEvents.PLACES.get(String(ev.get("place", "")), ""))
			if pl == "":
				return ""
			return "%s walked into %s at %s" % [a, pl, where.call(room)]
	return ""


## Pure: the digest message: the moments, one a line, then where to get the game.
static func digest_text(lines: Array) -> String:
	var out := PackedStringArray(["From the Dysnomia game:"])
	for l in lines:
		out.append("• " + String(l))
	out.append("Open the game: " + DOWNLOAD_URL)
	return "\n".join(out)
