class_name ChatLines
extends RefCounted
## Pure helpers for chat lines (no network): keys and merging, site-API
## messages → lines, compact formatting for the HUD feed, and the day's
## activity (lines and top speakers) that the world draws.
##
## A line is a Dictionary (ChatLog's shape plus a source):
##   {block, log_index, tx, soul, aura, name, text, qing, badge,
##    source: "chain" | "site" | "say", wallet?}
## "chain" lines were read from LogEvent logs here; "site" lines came from the
## site accelerator (GET /api/qing-chat, chain-backed) and are replaced by the
## chain's copy when it lands; "say" lines are free presence chat (Net), never
## on chain, with no block.

const DAY_BLOCKS := 8400  # ≈ 24 h at ≈ 10.3 s a block (LEARNINGS §0)
const FEED_CHARS := 140
const FULL_GLOW_LINES := 24  # lines a day for the brightest room glow


static func key(l: Dictionary) -> String:
	if String(l.get("source", "chain")) == "say":
		return "say:%s:%d" % [String(l.get("wallet", "")), int(l.get("ms", 0))]
	return "%s:%d" % [String(l.get("tx", "")).to_lower(), int(l.get("log_index", 0))]


static func is_chain_shaped(l: Dictionary) -> bool:
	return String(l.get("source", "chain")) != "say" and int(l.get("block", -1)) > 0


## Merges `more` into `into` (chain order kept), de-duplicated by (tx, log
## index). A chain copy replaces a site copy of the same line (it carries the
## Aura, so the ✓/⚠ badge), keeping a resolved wallet. Returns the lines that
## were new.
static func merge(into: Array, more: Array) -> Array:
	var at := {}
	for i in into.size():
		at[key(into[i])] = i
	var fresh: Array = []
	var appended := false
	for l in more:
		var k := key(l)
		if at.has(k):
			var i: int = at[k]
			var old: Dictionary = into[i]
			if String(old.get("source", "chain")) == "site" and String(l.get("source", "chain")) == "chain":
				var nl: Dictionary = l.duplicate()
				if old.has("wallet") and not nl.has("wallet"):
					nl["wallet"] = old["wallet"]
				into[i] = nl
			continue
		at[k] = into.size()
		into.append(l)
		fresh.append(l)
		appended = true
	if appended:
		into.sort_custom(_before)
	return fresh


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ab := int(a.get("block", -1))
	var bb := int(b.get("block", -1))
	if ab < 0 or bb < 0:  # say lines (no block) keep arrival order at the end
		if ab < 0 and bb < 0:
			return int(a.get("ms", 0)) < int(b.get("ms", 0))
		return bb < 0
	return ab < bb or (ab == bb and int(a.get("log_index", 0)) < int(b.get("log_index", 0)))


## A site-API message ({from, fromName, soul, text, txHash, block, logIndex,
## qingAddr}) → a line. It has no Aura, so no badge until the chain's copy
## replaces it. The API's "from" is not used as the speaker's wallet: that is
## resolved from the chain (tx.from) when needed.
static func from_site(m: Dictionary, qing: String) -> Dictionary:
	if not (m.get("txHash") is String) or not m.has("block"):
		return {}
	return {
		"block": int(m.get("block", -1)),
		"log_index": int(m.get("logIndex", 0)),
		"tx": String(m["txHash"]).to_lower(),
		"soul": String(m.get("soul", "")),
		"aura": "",
		"name": String(m.get("fromName", "")),
		"text": String(m.get("text", "")),
		"qing": String(m.get("qingAddr", qing)).to_lower(),
		"badge": "",
		"source": "site",
	}


## A free line from the presence server (Net.chat_received), not on chain.
static func say_line(wallet: String, name: String, text: String, ms: int) -> Dictionary:
	return {"block": -1, "log_index": 0, "tx": "", "soul": "", "aura": "", "name": name, "text": text,
		"badge": "", "source": "say", "wallet": wallet.to_lower(), "ms": ms}


## Text fit for one HUD line: data URIs named by kind and size, control
## characters and newlines flattened, invisible and direction-override characters
## dropped (a name or line can't hide or reverse text: U+200B–200F, U+202A–202E,
## U+2066–2069, U+FEFF, C1 controls), long lines cut with an ellipsis.
static func clean_text(text: String, max_chars: int = FEED_CHARS) -> String:
	var t := text.strip_edges()
	if t.begins_with("data:"):
		var end := t.find(",")
		var head := t.substr(5, end - 5) if end > 5 else t.substr(5, 24)
		var mime := head.split(";")[0]
		var kind := mime.split("/")[0] if mime != "" else "data"
		var payload := t.length() - (end + 1) if end > 0 else t.length()
		var bytes := payload * 3 / 4 if head.contains("base64") else payload
		return "[%s · %s]" % [kind if kind != "" else "data", _size(bytes)]
	# Encrypted direct messages posted through the room (the site's DM feature): the payload
	# is ciphertext for someone else, so name it instead of printing the code.
	if t.begins_with("[DM:"):
		return "(private message)"
	if t.begins_with("[ENABLE_DM:"):
		return "(turned on private messages)"
	var out := ""
	for ch in t:
		var c := ch.unicode_at(0)
		if c == 10 or c == 13 or c == 9 or c == 0x2028 or c == 0x2029:
			out += " "  # one line: a line/paragraph separator would fake a second speaker's line
		elif NetProto.hidden_char(c):
			continue
		else:
			out += ch
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.length() > max_chars:
		out = out.left(max_chars - 1).strip_edges() + "…"
	return out


static func _size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	return "%.1f kB" % (bytes / 1024.0)


## A speaker's name as shown: the chain's Username is anyone's text, so it is one
## clean line of at most NAME_CHARS characters.
const NAME_CHARS := 32


static func speaker(l: Dictionary) -> String:
	var nm := clean_text(String(l.get("name", "")), NAME_CHARS)
	return nm if nm != "" else "?"


static func badge_mark(l: Dictionary) -> String:
	match String(l.get("badge", "")):
		"og": return " ✓"
		"imposter": return " ⚠"
	return ""


## "name ✓: text" (plain).
static func compact(l: Dictionary, max_chars: int = FEED_CHARS) -> String:
	return "%s%s: %s" % [speaker(l), badge_mark(l), clean_text(String(l.get("text", "")), max_chars)]


## Where a line came from, for its hover/inspector note.
static func provenance(l: Dictionary) -> String:
	match String(l.get("source", "chain")):
		"say":
			return "said through the presence server: free, not on chain, no block"
		"site":
			return "block %d · tx %s · via the site accelerator (/api/qing-chat), chain copy pending" % [int(l["block"]), String(l.get("tx", ""))]
	return "block %d · tx %s · log %d · LogEvent from %s" % [int(l["block"]), String(l.get("tx", "")), int(l.get("log_index", 0)), String(l.get("qing", "the board"))]


static func esc(s: String) -> String:
	return s.replace("[", "[lb]")


## One feed line in BBCode. Chain lines carry their block (dim) when `blocks`;
## say lines are tagged "say". `meta` wraps it in a [url] whose meta is the key.
static func bbcode(l: Dictionary, blocks: bool = false, meta: bool = false, max_chars: int = FEED_CHARS) -> String:
	var badge := ""
	match String(l.get("badge", "")):
		"og": badge = " [color=#64e3a8]✓[/color]"
		"imposter": badge = " [color=#ff8fa0]⚠[/color]"
	var pre := ""
	if String(l.get("source", "chain")) == "say":
		pre = "[color=#8e97a9]say[/color] "
	elif blocks:
		pre = "[color=#5d6578]%d[/color] " % int(l.get("block", -1))
	var body := "%s[color=#a8e6ff]%s[/color]%s  %s" % [pre, esc(speaker(l)), badge, esc(clean_text(String(l.get("text", "")), max_chars))]
	return "[url=%s]%s[/url]" % [key(l), body] if meta else body


# --- The day's activity (territory state: chain lines only) ---------------------------

## Lines in the last DAY_BLOCKS blocks up to `head`, and the speakers ranked by
## lines (then by latest). `capped` = the history read stopped at its line
## limit, so when every loaded line is inside the day the count is a floor.
## {count, floor, from_block, speakers: [{key, name, lines, last_block, wallet}]}
static func day_stats(lines: Array, head: int, capped: bool = false) -> Dictionary:
	var from := head - DAY_BLOCKS
	var count := 0
	var by := {}
	var earliest_in := true
	var chain_n := 0
	for l in lines:
		if not is_chain_shaped(l):
			continue
		chain_n += 1
		var b := int(l["block"])
		if b <= from:
			earliest_in = false
			continue
		count += 1
		var k := "%s|%s" % [String(l.get("name", "")), String(l.get("soul", ""))]
		var s: Dictionary = by.get(k, {"key": k, "name": speaker(l), "lines": 0, "last_block": 0, "wallet": ""})
		s["lines"] += 1
		s["last_block"] = maxi(int(s["last_block"]), b)
		if String(l.get("wallet", "")) != "":
			s["wallet"] = String(l["wallet"])
		by[k] = s
	var speakers: Array = by.values()
	speakers.sort_custom(func(a, b): return a["lines"] > b["lines"] or (a["lines"] == b["lines"] and a["last_block"] > b["last_block"]))
	return {"count": count, "floor": capped and earliest_in and chain_n > 0, "from_block": from, "speakers": speakers}


## 0 (silent) … 1 (FULL_GLOW_LINES or more a day), log-scaled.
static func glow_for(count: int) -> float:
	if count <= 0:
		return 0.0
	return clampf(log(1.0 + count) / log(1.0 + FULL_GLOW_LINES), 0.0, 1.0)


static func count_text(stats: Dictionary) -> String:
	return "%d%s" % [int(stats["count"]), "+" if stats.get("floor", false) else ""]


# --- The dock: faces, mentions, ages (personal UI) -------------------------------------

## A speaker's colour in the UI: the same name (and Soul) always gets the same
## hue, light enough to read on black glass.
static func speaker_color(l: Dictionary) -> Color:
	var k := "%s|%s" % [String(l.get("name", "")).to_lower(), String(l.get("soul", ""))]
	if String(l.get("source", "chain")) == "say" and String(l.get("wallet", "")) != "":
		k = String(l["wallet"]).to_lower()
	var h := float(hash(k) & 0xffff) / 65536.0
	return Color.from_hsv(h, 0.42, 1.0)


## Whether `text` names `who` (your Username): case-insensitive, as a whole
## word or after an @. Names shorter than 2 letters never match.
static func mentions(text: String, who: String) -> bool:
	var n := who.strip_edges().to_lower()
	if n.length() < 2:
		return false
	var t := text.to_lower()
	var from := 0
	while true:
		var i := t.find(n, from)
		if i < 0:
			return false
		var before := t.substr(i - 1, 1) if i > 0 else ""
		var after := t.substr(i + n.length(), 1) if i + n.length() < t.length() else ""
		if not _wordy(before) and not _wordy(after):
			return true
		from = i + 1
	return false


static func _wordy(ch: String) -> bool:
	if ch == "":
		return false
	var c := ch.unicode_at(0)
	return (c >= 48 and c <= 57) or (c >= 97 and c <= 122) or c == 95


## Roughly how long ago a block was, from the block count (DAY_BLOCKS ≈ 24 h):
## "now", "12 min", "5 h", "40 d". "—" when either block is unknown.
static func age_text(block: int, head: int) -> String:
	if block <= 0 or head <= 0:
		return "—"
	var s := float(maxi(0, head - block)) * 86400.0 / float(DAY_BLOCKS)
	if s < 90.0:
		return "now"
	if s < 3600.0:
		return "%d min" % int(round(s / 60.0))
	if s < 86400.0 * 1.5:
		return "%d h" % int(round(s / 3600.0))
	return "%d d" % int(round(s / 86400.0))
