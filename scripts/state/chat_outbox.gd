class_name ChatOutbox
extends RefCounted
## Lines on their way to the chain, with no network (ChatFeed runs it).
##
## Each entry: {id, text, qing, state, message, kind, block, tx}
##   state: queued → signing → posted | failed
##   kind (failed only): join | identity | signer | declined | door | funds | other
##
## One line goes as CHOA.Chat(qing, text). Lines typed while another is being
## signed wait, then go together in ONE transaction: Multicall3.aggregate3
## with allowFailure = false, so it is one approval and all of them post or
## none do. CHOA keys the speaker on tx.origin, so a line sent through
## Multicall3 is still yours (checked live, 2026-11-24: a 3-line batch
## simulates fine from a player wallet; a wallet with no YUE reverts the same
## way through Multicall3 as directly).

signal changed

const MAX_BATCH := 5
const KEEP_DONE := 6  # posted/failed entries kept for the bar to show

var entries: Array = []
var _next_id := 1


func add(text: String, qing: String) -> int:
	var e := {"id": _next_id, "text": text.strip_edges(), "qing": qing.to_lower(), "state": "queued",
		"message": "queued", "kind": "", "block": -1, "tx": ""}
	_next_id += 1
	entries.append(e)
	_trim()
	changed.emit()
	return e["id"]


func get_entry(id: int) -> Dictionary:
	for e in entries:
		if e["id"] == id:
			return e
	return {}


func is_signing() -> bool:
	return entries.any(func(e): return e["state"] == "signing")


func queued() -> Array:
	return entries.filter(func(e): return e["state"] == "queued")


func in_flight() -> Array:
	return entries.filter(func(e): return e["state"] == "queued" or e["state"] == "signing")


## The next transaction's lines: the oldest queued line and the queued lines
## after it for the same room, up to MAX_BATCH. Marks them signing. [] when a
## transaction is already being signed or nothing waits.
func take_batch() -> Array:
	if is_signing():
		return []
	var q := queued()
	if q.is_empty():
		return []
	var room: String = q[0]["qing"]
	var batch: Array = []
	for e in q:
		if e["qing"] == room and batch.size() < MAX_BATCH:
			batch.append(e)
	for e in batch:
		e["state"] = "signing"
		e["message"] = "signing…"
	changed.emit()
	return batch


func set_stage(batch: Array, message: String) -> void:
	for e in batch:
		e["message"] = message
	changed.emit()


func confirm(batch: Array, block: int, tx: String, message: String) -> void:
	for e in batch:
		e["state"] = "posted"
		e["block"] = block
		e["tx"] = tx
		e["message"] = message
	_trim()
	changed.emit()


func fail(batch: Array, message: String, kind: String) -> void:
	for e in batch:
		e["state"] = "failed"
		e["message"] = message
		e["kind"] = kind
	_trim()
	changed.emit()


## Every queued line fails with the same reason (e.g. the door is closed).
func fail_queued(message: String, kind: String) -> void:
	fail(queued(), message, kind)


func dismiss(id: int) -> void:
	entries = entries.filter(func(e): return e["id"] != id)
	changed.emit()


func _trim() -> void:
	var done := entries.filter(func(e): return e["state"] == "posted" or e["state"] == "failed")
	var extra := done.size() - KEEP_DONE
	if extra <= 0:
		return
	var drop := {}
	for i in extra:
		drop[done[i]["id"]] = true
	entries = entries.filter(func(e): return not drop.has(e["id"]))


## The transaction for a batch: {to, data, label}. One line → CHOA directly;
## several → Multicall3.aggregate3, every call allowFailure = false.
static func encode_batch(qing: String, texts: Array, place: String = "") -> Dictionary:
	var where := place if place != "" else qing
	if texts.size() == 1:
		return {"to": Contracts.CHOA, "data": Abi.encode_call("Chat(address,string)", [qing, texts[0]]),
			"label": "Room line at %s" % where}
	var calls: Array = []
	for t in texts:
		calls.append({"target": Contracts.CHOA, "data": Abi.encode_call("Chat(address,string)", [qing, t]), "allow_failure": false})
	return {"to": Contracts.MULTICALL3, "data": Multicall.encode(calls), "label": "%d room lines at %s (one transaction)" % [texts.size(), where]}


## What a failed Wallet.send / precondition means for the player.
static func classify(res: Dictionary) -> String:
	var stage := String(res.get("stage", ""))
	var name := String(res.get("revert", {}).get("name", ""))
	var msg := String(res.get("message", "")).to_lower()
	if name in ["NotAdmitted", "PayCover", "CoverChargeUnauthorized"]:
		return "join"
	if name in ["NotStarted", "UserNotEntered", "SoulNotEntered", "ZeroHoldings", "Forbidden"]:
		return "identity"
	if name in ["DysnomiaInsufficientBalance", "ERC20InsufficientBalance"] or msg.contains("insufficient funds"):
		return "funds"
	if stage == "precondition":
		return "signer"
	if stage == "sign" and (msg.contains("reject") or msg.contains("denied") or msg.contains("4001") or msg.contains("cancel")):
		return "declined"
	return "other"


## The bar's short text for an entry.
static func status_text(e: Dictionary) -> String:
	match String(e.get("state", "")):
		"queued": return "queued: goes with the next approval"
		"signing": return String(e.get("message", "signing…"))
		"posted": return String(e.get("message", "on chain · block %d" % int(e.get("block", -1))))
		"failed": return "not posted: " + String(e.get("message", "—"))
	return String(e.get("message", ""))
