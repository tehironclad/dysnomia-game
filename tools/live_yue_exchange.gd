extends SceneTree
## Read-only: the YUE exchange desks (YUE.Hong / YUE.Hung). Nothing is signed.
##   godot --headless --path . -s res://tools/live_yue_exchange.gd [-- --wallet=0x… --qing=0x…,0x…]
## 1. Scans every territory for a market rate on its own asset (QING.GetMarketRate(Asset())).
## 2. For a few territories: QING.Asset(), the rate (GetAssetRate and IsValidAsset on a YUE),
##    every known YUE's stock of the QING token and the asset, the wallet's balances.
## 3. Simulates, from --wallet, Hong and Hung against the best desk: a plain eth_call
##    (shows the approval the YUE still needs, decoded), and approve + trade together
##    with trace_callMany (state carried between the two calls), with the token moves.

const DEFAULT_QINGS := ["0xd127839b83cbf537c29b7d268c135f745a0da2e8", "0xb0ba7d36b7f0505879179ece7401f24eb653c6e1",
	"0x400b55bd0859954d673aba0f5e350d78d8a885ac", "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var wallet := "0x18f621662d6a1f23700ea32d146b32195dc33111"
	var qings: Array = DEFAULT_QINGS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wallet="):
			wallet = a.substr(9).to_lower()
		elif a.begins_with("--qing="):
			qings = Array(a.substr(7).to_lower().split(","))
	var YX = load("res://scripts/chain/yue_exchange.gd")
	var PX = load("res://scripts/chain/pulsex.gd")
	var BI = load("res://scripts/chain/bigint.gd")
	var AB = load("res://scripts/chain/abi.gd")
	var reg = root.get_node("Registry")
	var chain = root.get_node("Chain")
	var rated = await YX.rated_scan()
	if rated == null:
		print("rate scan failed (chain unavailable)")
		quit(1)
		return
	print("-- market rates: %d of %d territories have one for their own asset (block %d) --" % [rated.size(), reg.all().size(), YX.rated_block()])
	for r in rated:
		print("  %s %-26s asset %s  rate %s (= %s asset per token)" % [r["qing"], String(r["name"]).left(26), r["asset"], BI.to_decimal(r["rate"]), PX.fmt(r["rate"], 18, 6)])
	var nested := 0
	for q in reg.all():
		if reg.has_territory(String(q.get("asset", ""))):
			nested += 1
	print("territories whose asset is itself a QING (a hierarchy to walk): %d" % nested)
	var yue_r: Dictionary = await chain.rpc.call_decoded("0xe250bf9729076b14a8399794b61c72d0f4aefcd8", "Yan(address)", [wallet], ["address"])
	var own: String = String(yue_r["values"][0]) if yue_r["ok"] else ""
	print("\nwallet %s · own YUE (CHAN.Yan) %s" % [wallet, own if own != "" else "—"])
	for qing in qings:
		var q: Dictionary = reg.get_territory(qing)
		var d: Dictionary = await YX.read_desk(qing, String(q.get("asset", "")), wallet, own)
		print("\n-- %s (%s) · block %d --" % [q.get("name", "?"), qing, d.get("block", -1)])
		if not d["ok"]:
			print("  ", d.get("error", "failed"))
			continue
		for p in d["pairs"]:
			print("  pair %s/%s: QING.GetMarketRate %s · YUE.GetAssetRate %s · IsValidAsset %s" % [d["qing_symbol"], p["symbol"],
				BI.to_decimal(p["market_rate"]) if p["market_rate"] != null else "—", BI.to_decimal(p["rate"]) if p["rate"] != null else "—", str(p["valid"])])
		var stocked := 0
		for k in d["desks"]:
			var sq = k["stock_qing"]
			var sa = k["stock_asset"]
			if (sq != null and not BI.is_zero(sq)) or (sa != null and not BI.is_zero(sa)) or k["own"]:
				stocked += 1
				print("  desk YUE %s%s (wallet %s): %s %s · %s %s" % [k["yue"], " (yours)" if k["own"] else "", k["wallet"],
					PX.fmt(sq, 18, 6) if sq != null else "—", d["qing_symbol"], PX.fmt(sa, 18, 6) if sa != null else "—", d["pairs"][0]["symbol"]])
		print("  %d of %d known YUEs hold some stock" % [stocked, d["desks"].size()])
		print("  wallet holds %s %s · %s %s" % [PX.fmt(d["wallet"]["qing"], 18, 6) if d["wallet"]["qing"] != null else "—", d["qing_symbol"],
			PX.fmt(d["wallet"]["asset"], 18, 6) if d["wallet"]["asset"] != null else "—", d["pairs"][0]["symbol"]])
		var rate = d["pairs"][0]["rate"]
		if rate == null or BI.is_zero(rate):
			print("  no rate: Hong/Hung here would revert ExchangeRateNotFound")
			var probe: Dictionary = await chain.rpc.eth_call(d["probe_yue"], YX.hong_call(d["asset"], qing, BI.from_decimal("1000000000000000000")), wallet)
			print("  simulated Hong: %s" % (probe["revert"]["message"] if probe.get("kind") == "revert" else "ok" if probe["ok"] else "—"))
			continue
		for kind in ["hong", "hung"]:
			# A small amount the wallet can pay and some desk can cover
			var amount = BI.from_decimal("100000000000000")  # 0.0001 token
			var l: Dictionary = YX.legs(kind, qing, d["asset"], amount, rate)
			var desk: Dictionary = YX.pick_desk(d["desks"], kind, l["get"])
			if desk.is_empty():
				print("  %s 0.0001: no known YUE holds %s to pay out" % [kind, PX.fmt(l["get"], 18, 6)])
				continue
			var data: String = YX.hong_call(d["asset"], qing, amount) if kind == "hong" else YX.hung_call(qing, d["asset"], amount)
			var plain: Dictionary = await chain.rpc.eth_call(desk["yue"], data, wallet)
			var approve: String = AB.encode_call("approve(address,uint256)", [desk["yue"], BI.to_decimal(l["pay"])])
			var tm: Dictionary = await chain.rpc.request("trace_callMany", [[[{"from": wallet, "to": l["pay_token"], "data": approve}, ["trace"]],
				[{"from": wallet, "to": desk["yue"], "data": data}, ["trace"]]], "latest"])
			var outcome := "—"
			var moves: Array = []
			if tm["ok"] and tm["result"] is Array and tm["result"].size() == 2:
				var top: Dictionary = tm["result"][1]["trace"][0]
				outcome = "WOULD SUCCEED" if not top.has("error") else "would fail: " + String(top["error"])
				for t in tm["result"][1]["trace"]:
					var inp := String(t["action"].get("input", ""))
					if t.has("error") or inp.length() < 10:
						continue
					if inp.begins_with("0xa9059cbb"):
						var a2: Array = AB.decode(["address", "uint256"], "0x" + inp.substr(10))
						moves.append("%s %s → %s" % [PX.fmt(BI.coerce(a2[1]), 18, 6), String(t["action"]["to"]).left(10), String(a2[0]).left(10)])
					elif inp.begins_with("0x23b872dd"):
						var a3: Array = AB.decode(["address", "address", "uint256"], "0x" + inp.substr(10))
						moves.append("%s %s → %s" % [PX.fmt(BI.coerce(a3[2]), 18, 6), String(a3[0]).left(10), String(a3[1]).left(10)])
			else:
				outcome = "trace_callMany unavailable: " + str(tm.get("error", {}))
			print("  %s 0.0001 %s at desk %s: pay %s, get %s · plain eth_call: %s · approve+%s (trace_callMany): %s %s" % [kind.to_upper(), d["qing_symbol"], desk["yue"],
				PX.fmt(l["pay"], 18, 6), PX.fmt(l["get"], 18, 6),
				plain["revert"]["message"] if plain.get("kind") == "revert" else ("ok" if plain["ok"] else "—"), kind, outcome, "[" + "; ".join(moves) + "]"])
	quit(0)
