class_name EightBall
extends RefCounted
## Eight-ball rules over PoolSim, for two players (0 = the challenger, who
## breaks; 1 = the one who accepted). Kept simple and explicit:
##   - groups (solids 1–7 / stripes 9–15) go to the first player to pocket an
##     object ball legally; until then the table is open;
##   - a foul (cue ball pocketed, nothing hit, or hitting the other group or the
##     eight first once groups are set) passes the turn; a pocketed cue ball
##     comes back to the head spot;
##   - pocketing one of your own balls (any ball while open) without a foul
##     keeps the turn;
##   - the eight wins it once your group is cleared and the shot is clean, and
##     loses it any other time.

var sim := PoolSim.new()
var turn := 0
var groups := ["", ""]  # "solids" | "stripes"
var winner := -1
var shots := 0
var last := {}  # the last shot's outcome, for the HUD


static func group_of(b: int) -> String:
	if b >= 1 and b <= 7:
		return "solids"
	if b >= 9 and b <= 15:
		return "stripes"
	return ""


func cleared(player: int) -> bool:
	var g: String = groups[player]
	if g == "":
		return false
	for b in range(1, 16):
		if group_of(b) == g and sim.on_table(b):
			return false
	return true


func over() -> bool:
	return winner >= 0


## Plays a shot for `player`. Returns the outcome ({ok:false, why} if it was
## not that player's turn or the game is over). frame_every > 0 records frames.
func shot(player: int, dx: int, dy: int, power: int, frame_every: int = 0) -> Dictionary:
	if over():
		return {"ok": false, "why": "the game is over"}
	if player != turn:
		return {"ok": false, "why": "not this player's turn"}
	var was_cleared := cleared(player)
	var r := sim.shoot(dx, dy, power, frame_every)
	shots += 1
	var potted: Array = r["pocketed"]
	var scratch := potted.has(0)
	var first: int = r["first_contact"]
	var mine: String = groups[player]
	var foul := scratch or first == -1
	if mine != "" and first != -1:
		if was_cleared:
			foul = foul or first != 8
		else:
			foul = foul or group_of(first) != mine
	var out := {"ok": true, "player": player, "pocketed": potted, "first_contact": first, "scratch": scratch, "foul": foul}
	if r.has("frames"):
		out["frames"] = r["frames"]
	if potted.has(8):
		winner = player if (was_cleared and not foul) else 1 - player
		out["result"] = "won" if winner == player else "lost on the eight"
		last = out
		return out
	if scratch:
		sim.spot_cue()
	# Groups go to the first clean pocket of an object ball.
	if groups[0] == "" and not foul:
		for b in potted:
			if group_of(b) != "":
				groups[player] = group_of(b)
				groups[1 - player] = "stripes" if group_of(b) == "solids" else "solids"
				out["assigned"] = groups[player]
				break
	mine = groups[player]
	var keep := false
	if not foul:
		for b in potted:
			if b != 0 and (mine == "" or group_of(b) == mine):
				keep = true
	if not keep:
		turn = 1 - player
	out["next"] = turn
	last = out
	return out
