class_name NetBump
extends RefCounted
## Running into another player online (KnockWorld → NetPresence → the game
## server → everyone in the room): the bumped avatar stumbles on every screen,
## and its own player gets a brief stagger (≤ BumpMath.STAGGER_MAX_S, nobody is
## knocked down). Kept apart from NetProto's core types: its own message
## numbers, well away from the sequential ones, so other additions don't clash.
## Pure: the server, the client and the tests share it.
##
##   C_BUMP (client → server)  [40][target id u16][dir u8][level u8]          5 bytes
##   S_BUMP (server → room)    [104][from id u16][target id u16][dir u8][level u8]  7 bytes
##
## dir is the push's yaw (BumpMath.quant_dir); level is BumpMath.NUDGE or
## STUMBLE (anything higher is capped). The server checks both players are in
## the same room with known positions within MAX_DIST of each other, limits each
## sender (a token bucket) and each target (TARGET_COOLDOWN_S), and relays to
## the room except the sender, who already played it.

const C_BUMP := 40
const S_BUMP := 104
## Listed in S_WELCOME "features" by a server that relays bumps; a client sends
## C_BUMP only to such a server (an older one would count it as malformed).
const FEATURES := ["bump"]
const SIZES := {C_BUMP: 5}
const MAX_DIST := 3.5          ## m between their last reported positions (10 Hz at a run ≈ 1.4 m of lag)
const SENDER_RATE := 1.0       ## bumps a second a sender may make (burst SENDER_BURST)
const SENDER_BURST := 3.0
const TARGET_COOLDOWN_S := 1.5 ## a player is bumped at most this often
const CLIENT_COOLDOWN_S := 1.0 ## a client doesn't re-send for the same target sooner


static func size_ok(msg: PackedByteArray) -> bool:
	return not msg.is_empty() and SIZES.has(int(msg[0])) and msg.size() == int(SIZES[int(msg[0])])


static func bump_msg(target_id: int, yaw: float, level: int) -> PackedByteArray:
	var out := PackedByteArray([C_BUMP, 0, 0, 0, 0])
	out.encode_u16(1, target_id & 0xFFFF)
	out.encode_u8(3, BumpMath.quant_dir(yaw))
	out.encode_u8(4, clampi(level, BumpMath.NONE, BumpMath.STUMBLE))
	return out


## → {target, dir (yaw), level} or {} if malformed.
static func unpack_bump(msg: PackedByteArray) -> Dictionary:
	if msg.size() != 5 or msg[0] != C_BUMP:
		return {}
	var level: int = msg[4]
	if level < BumpMath.NUDGE or level > BumpMath.FALL:
		return {}
	return {"target": msg.decode_u16(1), "q": msg[3], "dir": BumpMath.dequant_dir(msg[3]), "level": mini(level, BumpMath.STUMBLE)}


## The server's relay of a checked bump from `from_id`.
static func relay(from_id: int, b: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([S_BUMP, 0, 0, 0, 0, 0, 0])
	out.encode_u16(1, from_id & 0xFFFF)
	out.encode_u16(3, int(b["target"]) & 0xFFFF)
	out.encode_u8(5, int(b["q"]) & 0xFF)
	out.encode_u8(6, clampi(int(b["level"]), BumpMath.NUDGE, BumpMath.STUMBLE))
	return out


## → {from, target, dir (yaw), level} or {}.
static func unpack_relay(msg: PackedByteArray) -> Dictionary:
	if msg.size() != 7 or msg[0] != S_BUMP:
		return {}
	return {"from": msg.decode_u16(1), "target": msg.decode_u16(3), "dir": BumpMath.dequant_dir(msg[5]),
		"level": clampi(msg[6], BumpMath.NUDGE, BumpMath.STUMBLE)}


## The server's check: "" if the bump stands, else why not.
static func check(from_id: int, target_id: int, same_room: bool, both_placed: bool, from_pos: Vector3, to_pos: Vector3,
		since_target_bumped: float) -> String:
	if from_id == target_id:
		return "self"
	if not same_room:
		return "not in the same room"
	if not both_placed:
		return "no position yet"
	if from_pos.distance_to(to_pos) > MAX_DIST:
		return "too far apart"
	if since_target_bumped < TARGET_COOLDOWN_S:
		return "cooldown"
	return ""
