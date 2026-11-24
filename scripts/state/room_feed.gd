class_name RoomFeed
extends Node
## One chat board kept live: a QING's room lines (LogEvent 0xb916… from that
## QING) or the Void (Fomalhaute's 0x6b81…). Shared by the HUD feed, the hall,
## the arcade/pub tables and the world (ChatFeed.feed_for), so a room is read
## and tailed once however many things show it.
##
## - History: the chain (ChatLog, newest `limit` lines scanning back from the
##   head). For a room the site accelerator (GET /api/qing-chat) may paint
##   first; the chain's copy of each line replaces it (ChatLines.merge).
## - Tail: every TAIL_S, the logs after the last block read.
## - read_back(hash, block): after a post, the lines that transaction wrote.
## - Speakers' wallets are tx.from (eth_getTransactionByHash), cached by tx.

signal lines_changed(lines: Array)  ## any change, history included
signal arrived(fresh: Array)  ## lines new since the feed started (not history)

const TAIL_S := 8.0
const SITE_LIMIT := 200
const RESOLVE_MAX := 40

var mode := "room"  # room | void
var qing := ""
var territory: Dictionary = {}
var lines: Array = []
var after := -1  # last block tailed (-1 until the head is known)
var loaded_limit := 0
var history_ok := false
var capped := false  # the history stopped at its line limit
var scanned_from := -1
var head_seen := -1
var site_note := ""  # what the accelerator did ("" = not asked)
var loading := false
var _polling := false
var _wanted := 0  # the largest history asked for (retried by the tail if the first read failed)
var _wallets := {}  # tx → wallet (immutable once mined)
var _timer: Timer


func setup(p_mode: String, q: Dictionary) -> void:
	mode = p_mode
	territory = q
	qing = String(q.get("address", "")).to_lower()
	name = "Feed_" + (qing.substr(2, 8) if mode == "room" else "void")


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TAIL_S
	_timer.timeout.connect(tail)
	add_child(_timer)
	_timer.start()


func emitter() -> String:
	return qing if mode == "room" else Contracts.FOMALHAUTE


func is_loaded() -> bool:
	return loaded_limit > 0


## Loads history covering at least `limit` lines (again only if more is asked
## than was read). Emits lines_changed, never arrived: history is not news.
func ensure_history(limit: int) -> void:
	_wanted = maxi(_wanted, limit)
	if limit <= loaded_limit:
		return
	while loading:
		await get_tree().create_timer(0.1).timeout
		if limit <= loaded_limit:
			return
	loading = true
	if mode == "room" and loaded_limit == 0:
		await _site_first(mini(limit, SITE_LIMIT))
	var head := await Chain.refresh_head()
	if head < 0:
		loading = false
		history_ok = false
		lines_changed.emit(lines)
		return
	head_seen = maxi(head_seen, head)
	var h: Dictionary
	if mode == "room":
		h = await ChatLog.room_history(qing, int(territory.get("block", Contracts.MAP_FIRST_BLOCK)), head, limit)
	else:
		h = await ChatLog.void_history(head, limit)
	var got: Array = h["lines"]
	for l in got:
		l["source"] = "chain"
	ChatLines.merge(lines, got)
	history_ok = h["ok"]
	capped = got.size() >= limit
	scanned_from = int(h["scanned_from"])
	loaded_limit = limit
	if after < 0:
		after = head
	loading = false
	lines_changed.emit(lines)


func _site_first(limit: int) -> void:
	var r: Dictionary = await Chain.site.qing_chat(qing, limit)
	if not r["ok"]:
		site_note = "site accelerator unavailable (%s)" % String(r.get("error", "—"))
		return
	var got: Array = []
	for m in r["data"].get("messages", []):
		if m is Dictionary:
			var l := ChatLines.from_site(m, qing)
			if not l.is_empty() and String(l["qing"]) == qing:
				got.append(l)
	site_note = "site accelerator: %d lines (chain-backed, block %s); replaced by the chain's copy" % [got.size(), str(int(r["data"]["block"])) if r["data"].get("block") is float or r["data"].get("block") is int else "—"]
	if not got.is_empty():
		ChatLines.merge(lines, got)
		lines_changed.emit(lines)


## New lines since the last block read.
func tail() -> void:
	if loaded_limit < _wanted and not loading:
		ensure_history(_wanted)  # the first read failed (no head): try again
	if _polling or after < 0:
		return
	_polling = true
	var head := await Chain.refresh_head()
	if head > after:
		head_seen = maxi(head_seen, head)
		var r: Dictionary = await ChatLog.tail(emitter(), mode == "room", after, head)
		if r["ok"]:
			after = head
			_take(r["lines"])
	_polling = false


## The lines transaction `hash` wrote in `block` (read from that block's logs),
## merged into the feed.
func read_back(hash: String, block: int) -> Array:
	var r: Dictionary = await ChatLog.tail(emitter(), mode == "room", block - 1, block)
	var mine: Array = r["lines"].filter(func(l): return String(l["tx"]).to_lower() == hash.to_lower())
	for l in mine:
		_wallets[String(l["tx"]).to_lower()] = Session.wallet  # we signed it: tx.from is this wallet
	_take(mine)
	return mine


func _take(got: Array) -> void:
	for l in got:
		l["source"] = "chain"
		var w: String = _wallets.get(String(l["tx"]).to_lower(), "")
		if w != "":
			l["wallet"] = w
	var fresh := ChatLines.merge(lines, got)
	if not fresh.is_empty():
		lines_changed.emit(lines)
		arrived.emit(fresh)


## A free line (no block) into this feed.
func add_say(l: Dictionary) -> void:
	var fresh := ChatLines.merge(lines, [l])
	if not fresh.is_empty():
		lines_changed.emit(lines)
		arrived.emit(fresh)


## Fills "wallet" (tx.from) on chain lines that lack it; at most RESOLVE_MAX
## reads, newest first. Returns how many lines now carry a wallet.
func resolve_wallets(subset: Array) -> int:
	var n := 0
	var reads := 0
	for i in range(subset.size() - 1, -1, -1):
		var l: Dictionary = subset[i]
		if not ChatLines.is_chain_shaped(l):
			continue
		var tx := String(l.get("tx", "")).to_lower()
		if not _wallets.has(tx) and reads < RESOLVE_MAX:
			reads += 1
			var w: String = await TableBook.tx_from(tx)
			if w != "":
				_wallets[tx] = w
		if _wallets.has(tx):
			l["wallet"] = _wallets[tx]
			n += 1
	return n


func describe() -> String:
	var src := "LogEvent(string,uint64,uint64,string) (topic 0xb916…) emitted by %s" % qing if mode == "room" \
		else "LogEvent(uint64,uint64,string) (topic 0x6b81…) emitted by Fomalhaute"
	var hist := ""
	if loaded_limit == 0:
		hist = "chain history: reading…" if loading or _wanted > 0 else "chain history: not read"
	elif not history_ok:
		hist = "chain history: — (the log scan stopped at block %d)" % scanned_from
	else:
		hist = "chain history: newest %d lines, scanned from block %d%s" % [loaded_limit, scanned_from, " (capped)" if capped else ""]
	return "%s\n%s · tailed to block %s every %d s%s" % [src, hist, str(after) if after >= 0 else "—", int(TAIL_S),
		("\n" + site_note) if site_note != "" else ""]
