extends Node
## Client for the emote / presence system via the entropy API.
## POST /api/presence {wallet, emote, territory}  — broadcast an emote to other players.

signal emote_sent(emote_id: int)
signal emote_received(wallet: String, emote_id: int)

const ENTROPY_API_BASE: String = "https://entropy-dysnomia.vercel.app"

const EMOTES: Array[String] = [
	"wave", "salute", "dance", "sit",
	"point", "laugh", "shrug", "clap",
]

const EMOTE_LABELS: Array[String] = [
	"Wave", "Salute", "Dance", "Sit",
	"Point", "Laugh", "Shrug", "Clap",
]

const EMOTE_ICONS: Array[String] = [
	"\ud83d\udc4b", "\ud83e\udee1", "\ud83d\udc83", "\ud83e\ude91",
	"\ud83d\udc49", "\ud83d\ude02", "\ud83e\udd37", "\ud83d\udc4f",
]

# ── State ───────────────────────────────────────────────────────────────
var _http: HTTPRequest
var _is_sending: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "EmoteHTTP"
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_send_response)


# ── Public API ──────────────────────────────────────────────────────────

func send_emote(wallet: String, emote_id: int, territory: String = "") -> void:
	## Send an emote to the presence API.  emote_id is index into EMOTES array.
	if wallet.is_empty():
		print("[EmoteClient] send_emote called with empty wallet")
		return
	if emote_id < 0 or emote_id >= EMOTES.size():
		print("[EmoteClient] Invalid emote_id: %d" % emote_id)
		return
	if _is_sending:
		print("[EmoteClient] Already sending an emote, skipping")
		return

	_is_sending = true
	var payload := {
		"wallet": wallet.to_lower(),
		"emote": EMOTES[emote_id],
		"territory": territory.to_lower(),
	}
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := ENTROPY_API_BASE + "/api/presence"
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[EmoteClient] POST HTTP error: %d" % err)
		_is_sending = false


# ── Response handler ────────────────────────────────────────────────────

var _last_emote_id: int = -1

func _on_send_response(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_is_sending = false
	if code == 200:
		# Determine which emote was just sent from the last request
		# We track it via the payload we built
		emote_sent.emit(_last_emote_id)
	else:
		print("[EmoteClient] POST /api/presence returned HTTP %d" % code)


func send_emote_tracked(wallet: String, emote_id: int, territory: String = "") -> void:
	## Same as send_emote but tracks the emote_id for the response signal.
	_last_emote_id = emote_id
	send_emote(wallet, emote_id, territory)


# ── Helpers ─────────────────────────────────────────────────────────────

static func get_emote_name(emote_id: int) -> String:
	if emote_id >= 0 and emote_id < EMOTE_LABELS.size():
		return EMOTE_LABELS[emote_id]
	return "Unknown"


static func get_emote_icon(emote_id: int) -> String:
	if emote_id >= 0 and emote_id < EMOTE_ICONS.size():
		return EMOTE_ICONS[emote_id]
	return "?"
