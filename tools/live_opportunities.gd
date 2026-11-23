extends SceneTree
## Read-only: the Opportunities board and a wallet's record (streak, reactions).
##   godot --headless --path . -s res://tools/live_opportunities.gd [-- --wallet=0x…]
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var wallet := "0x18f621662d6a1f23700ea32d146b32195dc33111"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wallet="):
			wallet = a.substr(9).to_lower()
	var ps = await load("res://scripts/state/player_state.gd").read(wallet)
	root.get_node("Players").add_player(wallet, ps.yue)
	var o = await load("res://scripts/state/opportunities.gd").read(wallet)
	print("block %d · %d hot spots · gas/Su %d" % [o.block, o.hot.size(), o.gas_per_su])
	for e in o.hot.slice(0, 5):
		print("  hot  Ω %s  %s  you #%d" % [load("res://scripts/chain/bigint.gd").to_decimal(e["omega"]), e["name"], e["rank"]])
	for e in o.reach.slice(0, 5):
		print("  reach %s: %d Su to #1 (%s), %d Su to #%d" % [e["name"], e["su_top"], o.cost_of(e["su_top"]), e["su_next"], e["next_rank"]])
	for e in o.crowns:
		print("  crown %s: rival needs %d Su" % [e["name"], e["margin_su"]])
	for e in o.build.slice(0, 5):
		print("  build %s: %d Su to tier %d" % [e["name"], e["su"], e["next_tier"]])
	var t0 := Time.get_ticks_msec()
	var r = await load("res://scripts/state/player_record.gd").read(wallet, ps.yue)
	print("record (%d ms): %s · days %s" % [Time.get_ticks_msec() - t0, r.describe(), str(r.days.slice(maxi(0, r.days.size() - 10)))])
	quit()
