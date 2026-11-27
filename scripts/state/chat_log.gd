class_name ChatLog
extends RefCounted
## Room and Void lines, read from the chain (WP 5.3/5.4). The chain is the
## archive; the site's /api/qing-chat is only an optional accelerator.
##
## - Room: LogEvent(string Username, uint64 Soul, uint64 Aura, string LogLine),
##   topic 0xb916…, emitted by each QING. Nothing is indexed. Anyone can emit a
##   copy of this event, so only logs whose emitter is a known territory count.
## - Void: LogEvent(uint64 Soul, uint64 Aura, string), topic 0x6b81…, emitted by
##   Fomalhaute from block 21,000,000; the text is "<Username> line".
##
## Names are not unique. A line's Aura comes from the speaking LAU (its
## Saat(2) = uint160(creator) % MotzkinPrime), so it authenticates the speaker:
## OG when it matches the Aura of the name's owner (name_claims.json, built by
## the site from the chain), imposter when it doesn't, no badge for unknown or
## generic names.
##
## Line: {block, log_index, tx, soul, aura, name, text, qing?, badge}

const CLAIMS_PATH := "res://assets/data/name_claims.json"
const VOID_PATTERN := "^<([^>]+)>\\s*([\\s\\S]*)$"
const WINDOW := 500000

static var _claims := {}
static var _generic := {}
static var _claims_loaded := false
static var _re: RegEx


# --- Parsing ------------------------------------------------------------------

static func parse_room(log: Dictionary) -> Dictionary:
	var data := String(log.get("data", ""))
	if Abi.strip0x(data).length() < 256:
		return {}
	var v := Abi.decode(["string", "uint64", "uint64", "string"], data)
	var out := _base(log)
	out["qing"] = String(log.get("address", "")).to_lower()
	out["name"] = v[0]
	out["soul"] = BigInt.to_decimal(BigInt.from_hex(v[1]))
	out["aura"] = BigInt.to_decimal(BigInt.from_hex(v[2]))
	out["text"] = v[3]
	out["badge"] = verdict(out["name"], out["aura"])
	return out


static func parse_void(log: Dictionary) -> Dictionary:
	var data := String(log.get("data", ""))
	if Abi.strip0x(data).length() < 192:
		return {}
	var v := Abi.decode(["uint64", "uint64", "string"], data)
	var out := _base(log)
	out["soul"] = BigInt.to_decimal(BigInt.from_hex(v[0]))
	out["aura"] = BigInt.to_decimal(BigInt.from_hex(v[1]))
	var raw: String = v[2]
	if _re == null:
		_re = RegEx.create_from_string(VOID_PATTERN)
	var m := _re.search(raw)
	out["name"] = m.get_string(1) if m else ""
	out["text"] = m.get_string(2) if m else raw
	out["badge"] = verdict(out["name"], out["aura"])
	return out


static func _base(log: Dictionary) -> Dictionary:
	return {
		"block": String(log.get("blockNumber", "0x0")).hex_to_int(),
		"log_index": String(log.get("logIndex", "0x0")).hex_to_int(),
		"tx": String(log.get("transactionHash", "")),
	}


# --- Names ----------------------------------------------------------------------

const _LOOK := {"а": "a", "в": "b", "е": "e", "ё": "e", "к": "k", "м": "m", "н": "h", "о": "o", "р": "p",
	"с": "c", "т": "t", "у": "y", "х": "x", "ѕ": "s", "і": "i", "ї": "i", "ј": "j", "ԁ": "d", "ӏ": "l", "ɡ": "g",
	"α": "a", "β": "b", "ε": "e", "η": "n", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p", "τ": "t",
	"υ": "u", "χ": "x", "ω": "w"}


## The site's name normalisation (lib/name-registry.js), minus NFKC (Godot has
## none): lower case, invisible characters dropped, Cyrillic/Greek lookalikes
## mapped to Latin, and I/l/1, 0/o, rn/m, vv/w folded in names of 3+ letters.
static func normalize(name: String) -> String:
	var t := fold_case(name)
	if t.length() >= 3:
		for ch in ["i", "1", "|", "!", "¡", "ı"]:
			t = t.replace(ch, "l")
		t = t.replace("0", "o").replace("rn", "m").replace("vv", "w")
	return t


## The first half of normalize: lower case, invisible characters dropped,
## Cyrillic/Greek lookalikes mapped to Latin, whitespace collapsed (no I/l/1
## folding, which only applies to whole names of 3+ letters).
static func fold_case(name: String) -> String:
	var s := ""
	for ch in name.to_lower():
		var c := ch.unicode_at(0)
		if (c >= 0x200b and c <= 0x200f) or (c >= 0x2028 and c <= 0x202f) or (c >= 0x2060 and c <= 0x206f) \
				or c == 0xfeff or c == 0x00ad or c == 0x034f or c == 0x180e:
			continue
		s += _LOOK.get(ch, ch)
	# collapse whitespace
	var parts := s.split(" ", false)
	var t := " ".join(parts).strip_edges()
	t = t.replace("\t", " ").replace("\n", " ")
	return t


static func _load_claims() -> void:
	_claims_loaded = true
	var f := FileAccess.open(CLAIMS_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	_claims = d.get("names", {})
	for g in d.get("generic", []):
		_generic[String(g)] = true


## "og" | "imposter" | "" (no badge: unknown or generic name).
static func verdict(name: String, aura_decimal: String) -> String:
	if not _claims_loaded:
		_load_claims()
	var n := normalize(name)
	if n == "" or _generic.has(n) or not _claims.has(n):
		return ""
	return "og" if String(_claims[n]) == aura_decimal else "imposter"


# --- History and tail ----------------------------------------------------------------

## Newest `limit` room lines of `qing`, scanning back from `to_block` to
## `from_block` (its founding). {ok, lines (chain order), scanned_from}.
static func room_history(qing: String, from_block: int, to_block: int, limit: int = 60) -> Dictionary:
	return await _history(qing, Contracts.TOPIC_ROOM_CHAT, from_block, to_block, limit, true)


static func void_history(to_block: int, limit: int = 80) -> Dictionary:
	return await _history(Contracts.FOMALHAUTE, Contracts.TOPIC_VOID_CHAT, Contracts.VOID_CHAT_FROM_BLOCK, to_block, limit, false)


static func _history(emitter: String, topic: String, from_block: int, to_block: int, limit: int, room: bool) -> Dictionary:
	var lines: Array = []
	var end := to_block
	var ok := true
	while end >= from_block and lines.size() < limit:
		var start := maxi(from_block, end - WINDOW + 1)
		var r: Dictionary = await Chain.logs.scan(emitter, [topic], start, end)
		var chunk := parse_logs(r["logs"], emitter, room)
		lines = chunk + lines
		if not r["ok"]:
			ok = false
			break
		end = start - 1
	if lines.size() > limit:
		lines = lines.slice(lines.size() - limit)
	return {"ok": ok, "lines": lines, "scanned_from": end + 1}


## New lines in (after_block, to_block].
static func tail(emitter: String, room: bool, after_block: int, to_block: int) -> Dictionary:
	if to_block <= after_block:
		return {"ok": true, "lines": []}
	var r: Dictionary = await Chain.logs.scan(emitter, [Contracts.TOPIC_ROOM_CHAT if room else Contracts.TOPIC_VOID_CHAT], after_block + 1, to_block)
	return {"ok": r["ok"], "lines": parse_logs(r["logs"], emitter, room)}


## Parses and filters: the emitter must be the expected contract (a known QING
## for rooms, Fomalhaute for the Void); de-duplicated, chain order.
static func parse_logs(logs: Array, emitter: String, room: bool) -> Array:
	var out: Array = []
	var seen := {}
	for log in logs:
		if String(log.get("address", "")).to_lower() != emitter.to_lower():
			continue
		var k := LogScanner.log_key(log)
		if seen.has(k):
			continue
		seen[k] = true
		var l := parse_room(log) if room else parse_void(log)
		if l.is_empty() or (l["text"] == "" and l["name"] == ""):
			continue
		out.append(l)
	out.sort_custom(func(a, b): return a["block"] < b["block"] or (a["block"] == b["block"] and a["log_index"] < b["log_index"]))
	return out


static func format_line(l: Dictionary) -> String:
	var badge := ""
	if l.get("badge", "") == "og":
		badge = " ✓"
	elif l.get("badge", "") == "imposter":
		badge = " ⚠"
	var nm: String = l["name"] if l["name"] != "" else "?"
	return "[%d] %s%s: %s" % [l["block"], nm, badge, l["text"]]
