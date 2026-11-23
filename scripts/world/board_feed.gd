class_name BoardFeed
extends Node
## Community media boards: what's posted on each wing's board in this QING, verified
## from chain data by every visitor — no server.
##
## A post is a QING chat line (CHOA.Chat) in this exact form:
##   [[BOARD v1 wing=<wing> pay=<0xPaymentTxHash|keeper>]] <caption> || <https image url>
## It is shown only if:
##   • pay tx succeeded and contains an AFFECTION Transfer to this QING's keeper ≥ price,
##   • the chat line was sent by the same wallet that paid (or by the keeper with pay=keeper),
##   • the payment is < 24 h old (block timestamp), and
##   • no earlier post already used that payment.
## The keeper can take a post down with:  [[BOARD-HIDE pay=<0xPaymentTxHash|chatTxHash>]]

signal posts_changed(wing: String)

const LIFETIME := 86400
const TRANSFER_TOPIC := "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
const MAX_CAPTION := 120
const MAX_URL := 240
const WINGS := ["cantina", "fair", "beat", "pad", "comm"]

var _seen: Dictionary = {}        # message key -> true (already processed)
var _used_payments: Dictionary = {}  # pay tx -> post key
var _hidden: Dictionary = {}      # pay tx or chat tx -> true (keeper takedowns)
var _posts: Array = []            # verified posts
var _pending_local: Array = []    # optimistic posts from this player awaiting chain
var _muted: Dictionary = {}       # per-viewer local mutes (pay tx)
var _re: RegEx
var _re_hide: RegEx


func _ready() -> void:
	_re = RegEx.new()
	_re.compile("^\\[\\[BOARD v1 wing=([a-z]+) pay=(0x[0-9a-fA-F]{64}|keeper)\\]\\]\\s*(.*)$")
	_re_hide = RegEx.new()
	_re_hide.compile("^\\[\\[BOARD-HIDE pay=(0x[0-9a-fA-F]{64})\\]\\]")
	ChainManager.chat_messages_received.connect(ingest)
	_muted = _load_mutes()


# ─── Public ─────────────────────────────────────────────────────────────

static func format_post(wing: String, pay: String, caption: String, url: String) -> String:
	var c := caption.strip_edges().replace("||", "|").replace("[[", "[").left(MAX_CAPTION)
	var u := url.strip_edges()
	return "[[BOARD v1 wing=%s pay=%s]] %s%s" % [wing, pay, c, (" || " + u) if not u.is_empty() else ""]


static func valid_image_url(url: String) -> bool:
	var u := url.strip_edges()
	return u.is_empty() or (u.begins_with("https://") and u.length() <= MAX_URL and not u.contains(" "))


func active_posts(wing: String) -> Array:
	## Newest first. Includes this player's not-yet-confirmed post, flagged pending.
	var now := int(Time.get_unix_time_from_system())
	var out := []
	for p in _pending_local:
		if p["wing"] == wing and now - int(p["paid_at"]) < LIFETIME:
			out.append(p)
	for p in _posts:
		if p["wing"] != wing or now >= int(p["expires"]):
			continue
		if _hidden.has(p["pay"]) or _hidden.has(p["chat_tx"]) or _muted.has(p["pay"]):
			continue
		out.append(p)
	out.sort_custom(func(a, b): return int(a["paid_at"]) > int(b["paid_at"]))
	return out


func add_local_pending(wing: String, caption: String, url: String, pay: String) -> void:
	_pending_local.append({"wing": wing, "caption": caption, "url": url, "pay": pay,
		"poster": GameManager.player_identity, "paid_at": int(Time.get_unix_time_from_system()),
		"expires": int(Time.get_unix_time_from_system()) + LIFETIME, "pending": true, "chat_tx": ""})
	posts_changed.emit(wing)


func mute(post: Dictionary) -> void:
	## This viewer never sees that post again (local only).
	_muted[post.get("pay", "")] = true
	_save_mutes()
	posts_changed.emit(post.get("wing", ""))


func ingest(messages: Array) -> void:
	## Feed every chat line for this QING; board lines get verified in the background.
	for m in messages:
		if not (m is Dictionary):
			continue
		var text := str(m.get("message", ""))
		if not text.begins_with("[[BOARD"):
			continue
		var tx := str(m.get("tx_hash", ""))
		if tx.is_empty():
			continue  # local echo — the chain copy will arrive with a tx hash
		var key := tx + "|" + text
		if _seen.has(key):
			continue
		_seen[key] = true
		var hm := _re_hide.search(text)
		if hm:
			_verify_hide(hm.get_string(1).to_lower(), tx)
			continue
		var pm := _re.search(text)
		if pm == null:
			continue
		var wing := pm.get_string(1)
		if not wing in WINGS:
			continue
		var body := pm.get_string(3)
		var caption := body
		var url := ""
		var sep := body.find("||")
		if sep >= 0:
			caption = body.left(sep).strip_edges()
			url = body.substr(sep + 2).strip_edges()
		if not valid_image_url(url):
			url = ""
		_verify_post({
			"wing": wing, "pay": pm.get_string(2).to_lower(), "caption": caption.left(MAX_CAPTION),
			"url": url, "poster": str(m.get("username", "Anon")), "chat_tx": tx.to_lower(),
			"block": int(m.get("block", 0)),
		})


# ─── Verification ───────────────────────────────────────────────────────

func _keeper() -> String:
	return GameManager.territory_owner.to_lower()


func _verify_post(p: Dictionary) -> void:
	var keeper := _keeper()
	if not HexUtils.is_valid_address(keeper):
		return
	# Who sent the chat line?
	ChainManager.get_receipt(p["chat_tx"], func(chat_r: Dictionary) -> void:
		var sender := str(chat_r.get("from", "")).to_lower()
		if sender.is_empty() or str(chat_r.get("status", "")) != "0x1":
			return
		if p["pay"] == "keeper":
			if sender != keeper:
				return
			ChainManager.get_block_time(str(chat_r.get("blockNumber", "0x0")), func(ts: int) -> void:
				_accept(p, sender, ts))
			return
		ChainManager.get_receipt(p["pay"], func(pay_r: Dictionary) -> void:
			var payer := _paid_keeper(pay_r, keeper)
			if payer.is_empty() or payer != sender:
				return
			ChainManager.get_block_time(str(pay_r.get("blockNumber", "0x0")), func(ts: int) -> void:
				_accept(p, payer, ts))))


func _paid_keeper(r: Dictionary, keeper: String) -> String:
	## Returns the payer if the receipt holds an AFFECTION Transfer to keeper ≥ price.
	if str(r.get("status", "")) != "0x1":
		return ""
	var token := ChainManager.AFFECTION_TOKEN_ADDRESS.to_lower()
	var need := _price_hex()
	for lg in r.get("logs", []):
		if not (lg is Dictionary) or str(lg.get("address", "")).to_lower() != token:
			continue
		var topics: Array = lg.get("topics", [])
		if topics.size() < 3 or str(topics[0]).to_lower() != TRANSFER_TOPIC:
			continue
		if not str(topics[2]).to_lower().ends_with(HexUtils.strip_0x(keeper)):
			continue
		var amount := HexUtils.strip_0x(str(lg.get("data", "0x0"))).to_lower().lpad(64, "0")
		if amount >= need:  # equal-length hex compares like the numbers
			return "0x" + str(topics[1]).to_lower().right(40)
	return ""


func _price_hex() -> String:
	var dec: int = ChainManager.economy.decimals if ChainManager.economy else 18
	var base := AffectionEconomy_to_units(str(AttractionCatalog.BOARD["price"]), dec)
	return _dec_to_hex(base).lpad(64, "0")


func _accept(p: Dictionary, payer: String, ts: int) -> void:
	if ts <= 0:
		return
	var now := int(Time.get_unix_time_from_system())
	if now - ts >= LIFETIME:
		return
	var use_key: String = p["pay"] if p["pay"] != "keeper" else p["chat_tx"]
	if _used_payments.has(use_key):
		return  # One post per payment, first on chain wins (chat arrives in block order)
	_used_payments[use_key] = p["chat_tx"]
	p["pay"] = use_key
	p["payer"] = payer
	p["paid_at"] = ts
	p["expires"] = ts + LIFETIME
	p["pending"] = false
	_posts.append(p)
	# Drop this player's optimistic copy now that the real one is in
	for lp in _pending_local.duplicate():
		if lp["pay"] == p["pay"] or (lp["wing"] == p["wing"] and lp["caption"] == p["caption"]):
			_pending_local.erase(lp)
	posts_changed.emit(p["wing"])


func _verify_hide(target: String, chat_tx: String) -> void:
	ChainManager.get_receipt(chat_tx, func(r: Dictionary) -> void:
		if str(r.get("from", "")).to_lower() != _keeper():
			return
		_hidden[target] = true
		for w in WINGS:
			posts_changed.emit(w))


# ─── Helpers ────────────────────────────────────────────────────────────

static func AffectionEconomy_to_units(amount: String, dec: int) -> String:
	return load("res://scripts/chain/affection_economy.gd").to_base_units(amount, dec)


static func _dec_to_hex(dec: String) -> String:
	## Arbitrary-size decimal string → lowercase hex (no 0x).
	var digits := dec.strip_edges()
	if digits.is_empty() or digits == "0":
		return "0"
	var out := ""
	while not (digits.is_empty() or digits == "0"):
		var rem := 0
		var q := ""
		for ch in digits:
			var cur := rem * 10 + int(ch)
			var d := cur / 16
			rem = cur % 16
			if not (q.is_empty() and d == 0):
				q += str(d)
		out = "0123456789abcdef"[rem] + out
		digits = q if not q.is_empty() else "0"
	return out


func _load_mutes() -> Dictionary:
	var f := FileAccess.open("user://board_mutes.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _save_mutes() -> void:
	var f := FileAccess.open("user://board_mutes.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_muted))
