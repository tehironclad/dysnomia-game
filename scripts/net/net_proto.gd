class_name NetProto
extends RefCounted
## The game server's wire protocol (docs/SERVER.md, LEARNINGS §16). One
## WebSocket binary message = [type u8][body]. The hot messages (presence and
## voice) are packed binary; the rare ones (hello, auth, chat, leaderboards)
## carry a small UTF-8 JSON object. Little-endian throughout. Pure: the
## server, the client and the tests share it.

const VERSION := 1

# client → server
const C_AUTH := 2       # json {wallet, sig} | {token}
const C_JOIN := 3       # json {room, name, head, acc, body}
const C_STATE := 4      # binary STATE (t u16 + 16 bytes)
const C_CHAT := 5       # json {text}
const C_VOICE := 6      # binary: seq u16, codec u8, data
const C_PING := 7       # binary: t u32
const C_LB_SUBMIT := 8  # json {req, board, entry}
const C_LB_TOP := 9     # json {req, board, n}
const C_LEAVE := 10     # (empty)
const C_PROFILE := 11   # json {name, head, acc, body}
const C_INFO := 12      # json {req}: what the server is doing (counts only; guests may ask)

# server → client
const S_WELCOME := 64      # json {id, nonce, server, v, login}
const S_AUTH := 65         # json {ok, wallet, name, token, reason}
const S_PEER := 66         # json {id, wallet, name, guest, head, acc, body}
const S_PEER_LEAVE := 67   # binary: id u16
const S_STATES := 68       # binary: n u8, n × (id u16, t u16, 16 bytes)
const S_CHAT := 69         # json {id, wallet, name, text, pos}
const S_VOICE := 70        # binary: id u16, seq u16, codec u8, data
const S_NOTICE := 71       # json {code, text}
const S_PONG := 72         # binary: t u32
const S_LB := 73           # json {req, ok, rows | entry | error}
const S_ROOM := 74         # json {room, peers}
const S_INFO := 75         # json {req, server, v, uptime_s, connections, players, signed_in, rooms, boards}

## What this server understands beyond v1, listed in S_WELCOME "features".
const FEATURES := ["info"]

## Per-type size limits (whole message, bytes). Anything else is refused.
const MAX_SIZE := {
	C_AUTH: 512, C_JOIN: 512, C_STATE: 19, C_CHAT: 1024, C_VOICE: 700, C_PING: 5,
	C_LB_SUBMIT: 16384, C_LB_TOP: 256, C_LEAVE: 1, C_PROFILE: 512, C_INFO: 64,
}
const MAX_MESSAGE := 16384

## State flags (u8).
const F_ON_FLOOR := 1
const F_FLYING := 2
const F_CROUCH := 4
const F_SEATED := 8     # in a vehicle, on a ride or at a table: drawn simplified
const F_SPEAKING := 16
const F_FIRST_PERSON := 32

## Held animation (u8): 0 = follow movement; else a clip HumanAvatar knows.
const ANIMS := ["", "Driving", "Sitting_Idle", "Sitting_Talking", "Idle_Talking", "Dance"]

## Positions are int32 centimetres (±21 km); yaw is u16 over a full turn.
const POS_SCALE := 100.0
const STATE_BYTES := 16

const CHAT_MAX_CHARS := 200
const NAME_MAX_CHARS := 24

const VOICE_RATE := 16000
const VOICE_FRAME := 320  # 20 ms at 16 kHz
const CODEC_ADPCM := 1
const CODEC_ULAW := 2


static func login_message(server_name: String, nonce_hex: String) -> String:
	return "Dysnomia game server login\nServer: %s\nNonce: %s\nThis signature is free: it is not a transaction and moves nothing." % [server_name, nonce_hex]


# ── framing ─────────────────────────────────────────────────────────────────

static func json_msg(type: int, body: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([type])
	out.append_array(JSON.stringify(body).to_utf8_buffer())
	return out


## The JSON body of a message ({} if it is not an object).
static func json_body(msg: PackedByteArray) -> Dictionary:
	if msg.size() < 2:
		return {}
	var j := JSON.new()
	if j.parse(msg.slice(1).get_string_from_utf8()) != OK or not (j.data is Dictionary):
		return {}
	return j.data


static func size_ok(msg: PackedByteArray) -> bool:
	if msg.is_empty() or msg.size() > MAX_MESSAGE:
		return false
	var t: int = msg[0]
	return MAX_SIZE.has(t) and msg.size() <= int(MAX_SIZE[t])


# ── presence ────────────────────────────────────────────────────────────────

static func quant_yaw(yaw: float) -> int:
	return int(round(fposmod(yaw, TAU) / TAU * 65536.0)) & 0xFFFF


static func dequant_yaw(q: int) -> float:
	return float(q) / 65536.0 * TAU


static func _q(v: float) -> int:
	return clampi(int(round(v * POS_SCALE)), -2147483647, 2147483647)


## 16 bytes: x, y, z (int32 cm), yaw (u16), flags (u8), anim (u8).
static func pack_state(pos: Vector3, yaw: float, flags: int, anim: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(STATE_BYTES)
	b.encode_s32(0, _q(pos.x))
	b.encode_s32(4, _q(pos.y))
	b.encode_s32(8, _q(pos.z))
	b.encode_u16(12, quant_yaw(yaw))
	b.encode_u8(14, flags & 0xFF)
	b.encode_u8(15, clampi(anim, 0, ANIMS.size() - 1))
	return b


static func unpack_state(b: PackedByteArray, off: int = 0) -> Dictionary:
	return {
		"pos": Vector3(b.decode_s32(off) / POS_SCALE, b.decode_s32(off + 4) / POS_SCALE, b.decode_s32(off + 8) / POS_SCALE),
		"yaw": dequant_yaw(b.decode_u16(off + 12)),
		"flags": b.decode_u8(off + 14),
		"anim": mini(b.decode_u8(off + 15), ANIMS.size() - 1),
	}


## Client → server: [C_STATE][t u16][state].
static func state_msg(t_ms: int, pos: Vector3, yaw: float, flags: int, anim: int) -> PackedByteArray:
	var out := PackedByteArray([C_STATE, 0, 0])
	out.encode_u16(1, t_ms & 0xFFFF)
	out.append_array(pack_state(pos, yaw, flags, anim))
	return out


## Server → client: [S_STATES][n][n × (id u16, t u16, state)]; entries are
## [id, raw 18 bytes (t + state)] as the server stored them.
static func states_msg(entries: Array) -> PackedByteArray:
	var n := mini(entries.size(), 255)
	var out := PackedByteArray([S_STATES, n])
	for i in n:
		var head := PackedByteArray([0, 0])
		head.encode_u16(0, int(entries[i][0]))
		out.append_array(head)
		out.append_array(entries[i][1])
	return out


## → [{id, t, pos, yaw, flags, anim}]
static func unpack_states(msg: PackedByteArray) -> Array:
	var out: Array = []
	if msg.size() < 2:
		return out
	var n: int = msg[1]
	var off := 2
	for i in n:
		if off + 4 + STATE_BYTES > msg.size():
			break
		var d := unpack_state(msg, off + 4)
		d["id"] = msg.decode_u16(off)
		d["t"] = msg.decode_u16(off + 2)
		out.append(d)
		off += 4 + STATE_BYTES
	return out


# ── voice ───────────────────────────────────────────────────────────────────

static func voice_msg(seq: int, codec: int, data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([C_VOICE, 0, 0, codec])
	out.encode_u16(1, seq & 0xFFFF)
	out.append_array(data)
	return out


## Server relays [C_VOICE …] from peer `id` as [S_VOICE][id u16][seq u16][codec][data].
static func voice_relay(id: int, client_msg: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([S_VOICE, 0, 0])
	out.encode_u16(1, id)
	out.append_array(client_msg.slice(1))
	return out


## → {id, seq, codec, data}
static func unpack_voice(msg: PackedByteArray) -> Dictionary:
	if msg.size() < 7:
		return {}
	return {"id": msg.decode_u16(1), "seq": msg.decode_u16(3), "codec": msg[5], "data": msg.slice(6)}


static func id_msg(type: int, id: int) -> PackedByteArray:
	var out := PackedByteArray([type, 0, 0])
	out.encode_u16(1, id)
	return out


static func ping_msg(type: int, t: int) -> PackedByteArray:
	var out := PackedByteArray([type, 0, 0, 0, 0])
	out.encode_u32(1, t & 0xFFFFFFFF)
	return out


# ── text hygiene ────────────────────────────────────────────────────────────

## Printable, single line, trimmed, at most `max_chars`.
static func clean_text(s: String, max_chars: int) -> String:
	var out := ""
	for ch in s.strip_edges():
		var c := ch.unicode_at(0)
		if c < 32 or (c >= 0x7F and c < 0xA0) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069):
			out += " " if c == 10 or c == 9 else ""
			continue
		out += ch
	return out.strip_edges().left(max_chars)


## 0x + 40 hex, lowercase; "" otherwise.
static func clean_wallet(s: String) -> String:
	s = s.strip_edges().to_lower()
	if s.length() == 42 and s.begins_with("0x") and s.substr(2).is_valid_hex_number():
		return s
	return ""


## Room keys: "<qing 0x…>" or "<qing>/<place>" (lowercase); "" if malformed.
static func clean_room(s: String) -> String:
	s = s.strip_edges().to_lower()
	var parts := s.split("/", false)
	if parts.is_empty() or parts.size() > 2 or clean_wallet(parts[0]) == "":
		return ""
	if parts.size() == 2:
		var place := parts[1]
		if place.length() > 24 or not place.is_valid_identifier():
			return ""
	return s


static func short_wallet(w: String) -> String:
	return w.left(6) + "…" + w.right(4) if w.length() == 42 else w
