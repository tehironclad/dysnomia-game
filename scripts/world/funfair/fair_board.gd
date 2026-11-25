class_name FairBoard
extends RefCounted
## The fair's shared leaderboards: one per stall per QING, read from the QING's room lines
## (CHOA.Chat) and checked by every reader. Nothing is trusted that the chain can't show.
##
## A score line (≤ MAX_LEN characters; the room's line limit is 280):
##   🎪 <game> <score> <ticket tx hash>[#<play>] v2:<compact input log>
##   🎪 motzkin 700 0x9f3c…5678 v2:1k2bxz.u2c3d…        a single ticket
##   🎪 crystal 950 0x77aa…01b2#3 v2:k2bxz.u2c3d…       play 3 (0-based) of a ticket strip
## A line counts when
##   (a) the ticket's receipt (read from the chain) has AFFECTION Transfer(signer → this QING)
##       whose amount (TicketCode) is a ticket for this game: a single ticket (no #), or a strip
##       for this game or for any fair game with 0 ≤ play < its size; paid in full (Prices.covers).
##       The signer is the line's own tx.from; and
##   (b) MidwaySim.replay(game, seed, log) gives exactly the claimed score, seed =
##       MidwayGame.seed_from_tx(TicketCode.seed_tx(ticket, play)) (the ticket's hash for a single).
## One play counts once: the first valid line naming ticket#play, across all the stalls (an
## any-game strip's play can't be posted at two stalls). Lines failing a check are dropped and
## counted as "unverified". Rows carry the line's block and the ticket's block.

const MARK := "🎪"
const MAX_LEN := 280
const TOP := 10
const FROM_BLOCK := FairProgress.FROM_BLOCK  ## the line format starts here

static var _re: RegEx
static var _state := {}     ## qing → {rows: Array, scanned_to: int, ok: bool, error}
static var _receipts := {}  ## ticket tx → receipt (immutable once mined)


## The room line for a finished paid round (index: the strip play, -1 for a single ticket).
static func line_text(game: String, score: int, ticket: String, log: Array, index: int = -1) -> String:
	return "%s %s %d %s%s v%d:%s" % [MARK, game, score, ticket.to_lower(), ("#%d" % index) if index >= 0 else "",
		MidwaySim.VERSION, MidwaySim.encode_log(game, log)]


## {} if the text isn't a score line; else {game, score, ticket, index, version, log_text, log, log_ok}.
static func parse(text: String) -> Dictionary:
	if _re == null:
		_re = RegEx.create_from_string("^🎪 (striker|entropy|regolith|crystal|motzkin|waat|saat) ([0-9]{1,6}) (0x[0-9a-fA-F]{64})(?:#([0-9]{1,2}))? v([0-9]+):([0-9a-z.]*)\\s*$")
	var m := _re.search(text.strip_edges())
	if m == null:
		return {}
	var game := m.get_string(1)
	var d := MidwaySim.decode_log(game, m.get_string(6))
	return {"game": game, "score": int(m.get_string(2)), "ticket": m.get_string(3).to_lower(),
		"index": int(m.get_string(4)) if m.get_string(4) != "" else -1,
		"version": int(m.get_string(5)), "log_text": m.get_string(6), "log": d["log"], "log_ok": d["ok"]}


## (a): the ticket's receipt pays this QING from the signer for this game (and, for a strip, the
## play index is one of its plays). Pure. {ok, why, block, plays, item}
static func ticket_check(receipt: Dictionary, signer: String, qing: String, game: String, index: int = -1) -> Dictionary:
	if receipt.is_empty():
		return {"ok": false, "why": "no receipt for that ticket"}
	if String(receipt.get("status", "0x1")) != "0x1":
		return {"ok": false, "why": "ticket transaction reverted"}
	var want_from := Abi.strip0x(signer).to_lower()
	var want_to := Abi.strip0x(qing).to_lower()
	for lg in receipt.get("logs", []):
		if String(lg.get("address", "")).to_lower() != Contracts.AFFECTION:
			continue
		var t: Array = lg.get("topics", [])
		if t.size() < 3 or String(t[0]).to_lower() != Contracts.TOPIC_TRANSFER:
			continue
		if String(t[2]).to_lower().right(40) != want_to:
			continue
		if String(t[1]).to_lower().right(40) != want_from:
			return {"ok": false, "why": "the ticket was paid by another wallet"}
		var d := TicketCode.decode(BigInt.from_hex(String(lg.get("data", "0x0"))))
		var item := int(d["item"])
		if not d["ok"] or not TicketCode.is_fair(item) or (item == TicketCode.FAIR_ANY and not d["strip"]):
			return {"ok": false, "why": "not a coded fair ticket"}
		if not TicketCode.fits_game(item, MidwaySim.code(game)):
			return {"ok": false, "why": "the ticket was for another stall"}
		if not Prices.covers(d):
			return {"ok": false, "why": "the ticket paid less than its price"}
		if not TicketCode.index_ok(int(d["plays"]), index):
			return {"ok": false, "why": ("play #%d is not one of the strip's %d" % [index, int(d["plays"])]) if d["strip"] else "a single ticket has no play number"}
		return {"ok": true, "why": "", "block": String(receipt.get("blockNumber", "0x0")).hex_to_int(), "plays": int(d["plays"]), "item": item}
	return {"ok": false, "why": "the ticket paid nothing to this QING"}


## The seed a line's round was played from: the ticket's hash, or its strip play's derived hash.
static func seed_of(p: Dictionary) -> int:
	return MidwayGame.seed_from_tx(TicketCode.seed_tx(String(p["ticket"]), int(p.get("index", -1))))


## (b): the claimed score replays from the ticket's seed. Pure.
static func replay_check(p: Dictionary) -> Dictionary:
	if int(p.get("version", 0)) != MidwaySim.VERSION:
		return {"ok": false, "why": "sim version v%d is not this game's v%d" % [int(p.get("version", 0)), MidwaySim.VERSION]}
	if not p.get("log_ok", false):
		return {"ok": false, "why": "malformed input log"}
	var s := MidwaySim.replay(String(p["game"]), seed_of(p), p["log"])
	if s < 0:
		return {"ok": false, "why": "the log does not replay"}
	if s != int(p["score"]):
		return {"ok": false, "why": "replays to %d, not %d" % [s, int(p["score"])]}
	return {"ok": true, "why": ""}


## A room line (with from = tx.from) + its ticket's receipt → a row with its verdict. Pure.
static func verify(line: Dictionary, receipt: Dictionary, qing: String) -> Dictionary:
	var p := parse(String(line.get("text", "")))
	if p.is_empty():
		return {}
	var row := {"game": p["game"], "score": int(p["score"]), "ticket": p["ticket"], "index": int(p["index"]),
		"play": TicketCode.play_key(p["ticket"], int(p["index"])), "wallet": String(line.get("from", "")),
		"name": String(line.get("name", "")), "line_block": int(line.get("block", 0)), "line_tx": String(line.get("tx", "")),
		"log_index": int(line.get("log_index", 0)), "verified": false, "why": ""}
	if row["wallet"] == "":
		row["why"] = "signer unreadable"
		return row
	var a := ticket_check(receipt, row["wallet"], qing, p["game"], int(p["index"]))
	if not a["ok"]:
		row["why"] = a["why"]
		return row
	row["ticket_block"] = int(a["block"])
	row["plays"] = int(a["plays"])
	var b := replay_check(p)
	if not b["ok"]:
		row["why"] = b["why"]
		return row
	row["verified"] = true
	return row


## Rows in chain order with each play's later lines marked: one play counts once, its first valid
## line, whatever stall it was posted at. Pure.
static func dedupe(rows: Array) -> Array:
	var seen := {}
	var out: Array = []
	for r in rows:
		var x: Dictionary = r.duplicate()
		if x.get("verified", false):
			var key := String(x.get("play", TicketCode.play_key(String(x.get("ticket", "")), int(x.get("index", -1)))))
			if seen.has(key):
				x["verified"] = false
				x["why"] = "that play was already posted"
			seen[key] = true
		out.append(x)
	return out


## One stall's board from verified rows (chain order in): one play counts once (its first valid
## line), best first (ties: the earlier line). {top, verified, unverified}.
static func compile(rows: Array, game: String, top: int = TOP) -> Dictionary:
	var good: Array = []
	var bad := 0
	for r in dedupe(rows):
		if String(r.get("game", "")) != game:
			continue
		if not r.get("verified", false):
			bad += 1
			continue
		good.append(r)
	good.sort_custom(func(x, y):
		if int(x["score"]) != int(y["score"]):
			return int(x["score"]) > int(y["score"])
		return int(x["line_block"]) < int(y["line_block"]) or (int(x["line_block"]) == int(y["line_block"]) and int(x["log_index"]) < int(y["log_index"])))
	return {"top": good.slice(0, top), "verified": good.size(), "unverified": bad}


## Board rows as text: "1    1,200  Name (0x12ab…cd34)  block 28,140,001".
static func lines(top: Array, n: int = TOP) -> PackedStringArray:
	var out := PackedStringArray()
	for i in mini(n, top.size()):
		var r: Dictionary = top[i]
		var who := ArcadeScores.short(String(r["wallet"]))
		if String(r.get("name", "")) != "":
			who = "%s %s" % [String(r["name"]).left(12), who]
		out.append("%2d %7s  %s  block %s" % [i + 1, ArcadeScores.grouped(int(r["score"])), who, ArcadeScores.grouped(int(r["line_block"]))])
	return out


## Where the numbers come from, for a board's footer.
static func source_text(st: Dictionary, board: Dictionary) -> String:
	if not st.get("ok", false) and st.get("rows", []).is_empty():
		return "Room board: — (the room's lines could not be read%s)" % (": " + String(st.get("error", "")) if String(st.get("error", "")) != "" else "")
	var s := "Room board: this QING's room lines, blocks %s–%s · each replayed from its ticket" % [
		ArcadeScores.grouped(FROM_BLOCK), ArcadeScores.grouped(int(st.get("scanned_to", 0)))]
	if int(board.get("unverified", 0)) > 0:
		s += " · %d unverified line%s dropped" % [int(board["unverified"]), "" if int(board["unverified"]) == 1 else "s"]
	if not st.get("ok", false):
		s += " · the last read failed: —"
	return s


# --- Reading the chain ------------------------------------------------------------------------

## The last read of a QING's score lines ({} before the first read).
static func state_of(qing: String) -> Dictionary:
	return _state.get(qing.to_lower(), {})


## Reads the newer room lines of `qing`, keeps the score lines and checks each one (signer,
## ticket receipt, replay). Earlier rows stay (past logs never change); a failed read is
## reported, not cached. Returns the QING's state {ok, rows, scanned_to, error}.
static func read(qing: String) -> Dictionary:
	qing = qing.to_lower()
	var st: Dictionary = _state.get(qing, {"rows": [], "scanned_to": FROM_BLOCK - 1, "ok": false, "error": "", "pending": []})
	_state[qing] = st
	var head: int = await Chain.refresh_head()
	if head < 0:
		st["ok"] = false
		st["error"] = "the chain head could not be read"
		return st
	var r: Dictionary = await ChatLog.tail(qing, true, int(st["scanned_to"]), head)
	if not r["ok"]:
		st["ok"] = false
		st["error"] = "eth_getLogs failed"
		return st
	var todo: Array = st["pending"]
	st["pending"] = []
	for l in r["lines"]:
		if not parse(String(l.get("text", ""))).is_empty():
			todo.append(l)
	var all_read := true
	for l in todo:
		var from := await TableBook.tx_from(String(l["tx"]))
		var p := parse(String(l["text"]))
		var rc := await receipt(String(p["ticket"]))
		if from == "" or (rc.is_empty() and not _receipts.has(String(p["ticket"]))):
			st["pending"].append(l)  # retried on the next read; not shown meanwhile
			all_read = false
			continue
		var line: Dictionary = l.duplicate()
		line["from"] = from
		st["rows"].append(verify(line, rc, qing))
	st["rows"].sort_custom(func(x, y): return int(x["line_block"]) < int(y["line_block"]) or (int(x["line_block"]) == int(y["line_block"]) and int(x["log_index"]) < int(y["log_index"])))
	st["scanned_to"] = head
	st["ok"] = true
	st["error"] = "" if all_read else "some lines are still being checked"
	return st


## A ticket's receipt ({} when it can't be read; a missing receipt — never mined — is cached as {}).
static func receipt(tx: String) -> Dictionary:
	if _receipts.has(tx):
		return _receipts[tx]
	var r: Dictionary = await Chain.rpc.get_receipt(tx)
	if not r["ok"]:
		return {}
	var rc = r["result"]
	_receipts[tx] = rc if rc is Dictionary else {}
	return _receipts[tx]


## The text of a stall's 3D board (top 10, or "—" when the room couldn't be read).
static func sign_text(game: String, st: Dictionary) -> String:
	var head := "ROOM BOARD · %s\nverified: room lines replayed from tickets\n" % MidwayGame.title(game)
	if st.is_empty():
		return head + "\nreading this QING's room lines…"
	if not st.get("ok", false) and st.get("rows", []).is_empty():
		return head + "\n—\n(the room's lines could not be read)"
	var b := compile(st.get("rows", []), game)
	var rows := lines(b["top"])
	var body := "\n".join(rows) if not rows.is_empty() else "no verified scores yet\nplay a paid round, then post it"
	var foot := "\nblocks %s–%s" % [ArcadeScores.grouped(FROM_BLOCK), ArcadeScores.grouped(int(st.get("scanned_to", 0)))]
	if int(b["unverified"]) > 0:
		foot += " · %d unverified dropped" % int(b["unverified"])
	return head + "\n" + body + "\n" + foot
