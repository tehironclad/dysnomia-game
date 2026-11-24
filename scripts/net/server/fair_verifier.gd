class_name FairVerifier
extends RefCounted
## The leaderboard verifier for Affection Fair boards ("<qing>/fair:<game>").
## A fair round is seeded by its ticket's tx hash (MidwayGame.seed_from_tx), so
## a score can be checked by replaying (seed, input log):
##   1. entry {score, game, tx, inputs?}: the game must exist and the score be
##      within MidwayGame.max_score(game);
##   2. if MidwayGame has a static replay(game, seed, inputs) -> int (the fair
##      games' replay hook), the replayed score must equal the claimed one:
##      "verified: replayed";
##   3. the ticket: its receipt read from the chain must show status 0x1 and
##      `from` = the signed-in wallet. Unreachable chain → kept "unverified".
## Anything not checked is labelled so; nothing is assumed.

const MIDWAY := "res://scripts/world/funfair/midway_game.gd"


static func verify(board: String, entry: Dictionary, wallet: String) -> Dictionary:
	var game := String(entry.get("game", board.get_slice("fair:", 1)))
	var tx := String(entry.get("tx", "")).to_lower()
	var score := Leaderboards.score_of(entry.get("score"))
	var midway: GDScript = load(MIDWAY)
	if midway == null or not midway.call("has_game", game):
		return {"ok": false, "check": "unknown fair game '%s'" % game}
	if score > int(midway.call("max_score", game)):
		return {"ok": false, "check": "score above the game's maximum"}
	if not (tx.begins_with("0x") and tx.length() == 66 and tx.substr(2).is_valid_hex_number()):
		return {"ok": false, "check": "a fair score needs its ticket's tx hash"}
	var notes: PackedStringArray = []
	var verified := true
	var has_replay := false
	for m in midway.get_script_method_list():
		if m["name"] == "replay":
			has_replay = true
	if has_replay:
		var seed_v: int = midway.call("seed_from_tx", tx)
		var replayed := int(midway.call("replay", game, seed_v, entry.get("inputs", [])))
		if replayed != score:
			return {"ok": false, "check": "replay of the input log scores %d, not %d" % [replayed, score]}
		notes.append("replayed")
	else:
		verified = false
		notes.append("not replayed (no replay hook yet)")
	var rec: Dictionary = await Chain.rpc.get_receipt(tx)
	if rec.get("ok", false) and rec.get("result") is Dictionary:
		var r: Dictionary = rec["result"]
		if String(r.get("status", "")) != "0x1":
			return {"ok": false, "check": "the ticket's transaction reverted"}
		if String(r.get("from", "")).to_lower() != wallet:
			return {"ok": false, "check": "the ticket was bought by another wallet"}
		notes.append("ticket receipt checked (block %d)" % String(r.get("blockNumber", "0x0")).hex_to_int())
	else:
		verified = false
		notes.append("ticket not checked (chain unreachable)")
	return {"ok": true, "verified": verified, "check": ("verified: " if verified else "unverified: ") + ", ".join(notes)}
