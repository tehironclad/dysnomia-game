class_name RoomState
extends RefCounted
## One room's door as it applies to one player (WP 5.3), pinned to one block:
## CoverCharge, Asset (+ symbol, decimals), Admitted(LAU), the wallet's asset
## balance and its allowance to the QING, and WITHOUT (a ban).
##
## Rules (verified, LEARNINGS §5): Admitted() is always true when the cover is
## 0; Join needs allowance STRICTLY GREATER than the cover (exactly the cover
## is refused); admission lasts one day and is keyed to the LAU; WITHOUT
## blocks Join and QING.Chat; Join does not check bouncers.

var qing := ""
var block := -1
var ok := false
var error := ""
var cover := PackedInt64Array()
var asset := ""
var asset_symbol := ""
var asset_decimals := 18
var admitted := false
var balance := PackedInt64Array()
var allowance := PackedInt64Array()
var banned := false
var lau := ""


static func read(p_qing: String, ps: PlayerState) -> RoomState:
	var r := RoomState.new()
	r.qing = p_qing.to_lower()
	var head := await Chain.refresh_head()
	if head < 0:
		r.error = "chain head unavailable"
		return r
	r.block = head
	var c1: Array = [Multicall.make_call(r.qing, "CoverCharge()"), Multicall.make_call(r.qing, "Asset()")]
	var res: Array = await Chain.multicall.run(c1, "", head)
	var cv = Multicall.value(res[0], ["uint256"])
	var av = Multicall.value(res[1], ["address"])
	if cv == null or av == null:
		r.error = "door read failed"
		return r
	r.cover = BigInt.from_hex(cv[0])
	r.asset = String(av[0]).to_lower()
	var wallet := ps.wallet if ps != null else ""
	r.lau = ps.lau if ps != null and ps.has_lau() else ""
	r.banned = ps != null and ps.is_banned()
	var c2: Array = [Multicall.make_call(r.asset, "symbol()"), Multicall.make_call(r.asset, "decimals()")]
	if r.lau != "":
		c2.append(Multicall.make_call(r.qing, "Admitted(address)", [r.lau]))
	if wallet != "":
		c2.append(Multicall.make_call(r.asset, "balanceOf(address)", [wallet]))
		c2.append(Multicall.make_call(r.asset, "allowance(address,address)", [wallet, r.qing]))
	var res2: Array = await Chain.multicall.run(c2, wallet, head)
	var sv = Multicall.value(res2[0], ["string"])
	r.asset_symbol = sv[0] if sv != null else ""
	var dv = Multicall.value(res2[1], ["uint8"])
	r.asset_decimals = BigInt.to_int(BigInt.from_hex(dv[0])) if dv != null else 18
	var i := 2
	if r.lau != "":
		var ad = Multicall.value(res2[i], ["bool"])
		r.admitted = ad != null and ad[0]
		i += 1
	if wallet != "":
		var bv = Multicall.value(res2[i], ["uint256"])
		var lv = Multicall.value(res2[i + 1], ["uint256"])
		r.balance = BigInt.from_hex(bv[0]) if bv != null else PackedInt64Array()
		r.allowance = BigInt.from_hex(lv[0]) if lv != null else PackedInt64Array()
	r.ok = true
	return r


func has_cover() -> bool:
	return not BigInt.is_zero(cover)


## What a Join needs: the allowance must exceed the cover.
func needs_approve() -> bool:
	return has_cover() and BigInt.cmp(allowance, cover) <= 0


## The approve amount: cover + 1 wei (strictly greater, nothing more).
func approve_amount() -> PackedInt64Array:
	return BigInt.add(cover, BigInt.from_int(1))


func can_afford() -> bool:
	return BigInt.cmp(balance, cover) >= 0


func fmt(wei: PackedInt64Array) -> String:
	return "%s %s" % [TokenFormat.wei_to_tokens(wei, asset_decimals), asset_symbol]


## Why this player cannot post here ("" = they can).
func chat_blocker() -> String:
	if lau == "":
		return "You need a LAU to speak (Enter the Void at the front door)."
	if banned:
		return "Your wallet holds WITHOUT (a ban): QING.Chat reverts for it."
	if not admitted:
		return "The cover here is %s: Join first (a 1-day admission keyed to your LAU)." % fmt(cover)
	return ""


## Join steps still to do, in order: [{label, to, data}].
func join_steps() -> Array:
	var steps: Array = []
	if lau == "" or banned or admitted:
		return steps
	if needs_approve():
		steps.append({"label": "Approve %s for the door" % fmt(approve_amount()), "to": asset,
			"data": Abi.encode_call("approve(address,uint256)", [qing, approve_amount()])})
	steps.append({"label": "Join (pay %s, admitted for a day)" % fmt(cover) if has_cover() else "Join",
		"to": qing, "data": Abi.encode_call("Join(address)", [lau])})
	return steps


func describe() -> String:
	if not ok:
		return "Door: — (%s)" % error
	var lines: PackedStringArray = []
	lines.append("Cover charge: %s" % (fmt(cover) if has_cover() else "none — the door is open"))
	if lau != "":
		lines.append("You: %s" % ("admitted" if admitted else "not admitted"))
	if has_cover() and lau != "":
		lines.append("Your %s: %s · allowance to this room: %s" % [asset_symbol, TokenFormat.wei_to_tokens(balance, asset_decimals), TokenFormat.wei_to_tokens(allowance, asset_decimals)])
	if banned:
		lines.append("WITHOUT held: banned from Join and QING.Chat.")
	lines.append("block %d" % block)
	return "\n".join(lines)
