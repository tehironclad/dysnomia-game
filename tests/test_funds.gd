extends TestCase
## Paying 1 Ⓐ: the wallet must hold it; Ⓐ on the LAU is moved with LAU.Withdraw.


func test_insufficient_balance_revert_is_named() -> void:
	# The real revert of the 1 Ⓐ ticket from a wallet holding 0 Ⓐ (eth_call, block ≈28,137,000)
	var data := "0xe450d38c00000000000000000000000018f621662d6a1f23700ea32d146b32195dc3311100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
	var r := Abi.decode_revert(data)
	eq(r.get("name", ""), "ERC20InsufficientBalance")
	check(String(r.get("message", "")).contains("LAU"), "the hint mentions the LAU: %s" % r.get("message", ""))


func test_withdraw_call_matches_the_simulated_one() -> void:
	# Simulated from the owner wallet and traced: the LAU calls AFFECTION.transfer(owner, amount)
	eq(Abi.encode_call("Withdraw(address,uint256)", [Contracts.AFFECTION, "1000000000000000000"]),
		"0x884edad900000000000000000000000024f0154c1dce548adf15da2098fdd8b8a3b8151d0000000000000000000000000000000000000000000000000de0b6b3a7640000")
	check(BigInt.cmp(BigInt.from_decimal(ArcadePay.TOPUP_WEI), BigInt.from_decimal(ArcadePay.FEE_WEI)) > 0, "a top-up covers several plays")
