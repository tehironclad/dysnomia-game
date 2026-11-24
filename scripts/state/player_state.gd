class_name PlayerState
extends RefCounted
## A wallet's Dysnomia identity and holdings (WP 4.2), read in one Multicall
## pinned to one block. The connected wallet is the identity root:
## wallet → CHO.GetUserTokenAddress → LAU → Username, Saat(0..2) (Pole, Soul,
## Aura) ; wallet → CHAN.Yan → YUE. Holdings of the four Beat tokens, CROWS
## and WITHOUT on wallet, LAU and YUE.

const ONE := "1000000000000000000"

var wallet := ""
var block := -1
var ok := false
var error := ""
var lau := ""  # "" = none registered
var yue := ""
var username := ""
var lau_name := ""  # LAU name() (ERC-20, fixed at New)
var lau_symbol := ""  # LAU symbol()
var pole := ""  # Saat(0): the same for every LAU
var soul := ""  # Saat(1)
var aura := ""  # Saat(2) = uint160(wallet) % MotzkinPrime
var pls := PackedInt64Array()
## token key → {wallet, lau, yue}: PackedInt64Array balances (wei)
var holdings := {}

const TOKENS := {
	"fomalhaute": Contracts.FOMALHAUTE, "fornax": Contracts.FORNAX, "tethys": Contracts.TETHYS,
	"qzu": Contracts.PHOBOS_QING, "crows": Contracts.CROWS, "without": Contracts.WITHOUT,
}


func has_lau() -> bool:
	return lau != ""


func has_yue() -> bool:
	return yue != ""


func balance(token: String, where: String) -> PackedInt64Array:
	return holdings.get(token, {}).get(where, PackedInt64Array())


func total(token: String) -> PackedInt64Array:
	var t := PackedInt64Array()
	for w in ["wallet", "lau", "yue"]:
		t = BigInt.add(t, balance(token, w))
	return t


## Yuan(X) = wallet + 10·LAU + 40·YUE (CHOA.Yuan's weighting).
func yuan(token: String) -> PackedInt64Array:
	return BigInt.add(BigInt.add(balance(token, "wallet"), BigInt.mul_small(balance(token, "lau"), 10)),
		BigInt.mul_small(balance(token, "yue"), 40))


func is_bouncer() -> bool:
	return BigInt.cmp(total("crows"), BigInt.mul_small(BigInt.from_decimal(ONE), 25)) >= 0


## The avatar head this LAU's own on-chain text asks for (AvatarHeads rules).
func head_kind() -> String:
	return AvatarHeads.kind_for(username, lau_name, lau_symbol)


func is_banned() -> bool:
	return not BigInt.is_zero(total("without"))


static func _addr(v) -> String:
	if v == null:
		return ""
	var a := String(v[0])
	return "" if a == "0x0000000000000000000000000000000000000000" else a


## Reads everything for `wallet`. Two Multicall rounds (identity, then
## holdings that need the LAU/YUE addresses), both pinned to the same block.
static func read(p_wallet: String) -> PlayerState:
	var st := PlayerState.new()
	st.wallet = p_wallet.to_lower()
	var head: int = await Chain.refresh_head()
	if head < 0:
		st.error = "chain head unavailable"
		return st
	st.block = head
	var r1: Array = await Chain.multicall.run([
		Multicall.make_call(Contracts.CHO, "GetUserTokenAddress(address)", [st.wallet]),
		Multicall.make_call(Contracts.CHAN, "Yan(address)", [st.wallet]),
	], st.wallet, head)
	st.lau = _addr(Multicall.value(r1[0], ["address"]))
	st.yue = _addr(Multicall.value(r1[1], ["address"]))
	# A failed read is not "no LAU": say so, never show an empty identity as a fact.
	if not r1[0].get("ok", false):
		var ce: Dictionary = r1[0].get("chunk_error", {})
		st.error = "CHO.GetUserTokenAddress could not be read (%s)" % String(ce.get("message", ce.get("error", "RPC failed")))
		return st
	var calls: Array = []
	if st.has_lau():
		calls.append(Multicall.make_call(st.lau, "Username()"))
		for i in 3:
			calls.append(Multicall.make_call(st.lau, "Saat(uint256)", [i]))
		calls.append(Multicall.make_call(st.lau, "name()"))
		calls.append(Multicall.make_call(st.lau, "symbol()"))
	var holders := {"wallet": st.wallet}
	if st.has_lau():
		holders["lau"] = st.lau
	if st.has_yue():
		holders["yue"] = st.yue
	var order: Array = []
	for tk in TOKENS:
		for w in holders:
			calls.append(Multicall.make_call(TOKENS[tk], "balanceOf(address)", [holders[w]]))
			order.append([tk, w])
	var r2: Array = await Chain.multicall.run(calls, st.wallet, head)
	var k := 0
	if st.has_lau():
		var un = Multicall.value(r2[0], ["string"])
		st.username = String(un[0]) if un != null else ""
		var saat: Array = []
		for i in 3:
			var v = Multicall.value(r2[1 + i], ["uint256"])
			saat.append(BigInt.to_decimal(BigInt.from_hex(v[0])) if v != null else "")
		st.pole = saat[0]
		st.soul = saat[1]
		st.aura = saat[2]
		var nm = Multicall.value(r2[4], ["string"])
		var sy = Multicall.value(r2[5], ["string"])
		st.lau_name = String(nm[0]) if nm != null else ""
		st.lau_symbol = String(sy[0]) if sy != null else ""
		k = 6
	for o in order:
		var v = Multicall.value(r2[k], ["uint256"])
		if not st.holdings.has(o[0]):
			st.holdings[o[0]] = {}
		st.holdings[o[0]][o[1]] = BigInt.from_hex(v[0]) if v != null else PackedInt64Array()
		k += 1
	var bal := await Chain.rpc.request("eth_getBalance", [st.wallet, Rpc.block_param(head)])
	if bal["ok"]:
		st.pls = BigInt.from_hex(bal["result"])
	st.ok = true
	return st
