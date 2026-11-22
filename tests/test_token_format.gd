extends TestCase


func _w(s: String) -> PackedInt64Array:
	return BigInt.from_decimal(s)


func test_formats() -> void:
	eq(TokenFormat.wei_to_tokens(_w("0")), "0")
	eq(TokenFormat.wei_to_tokens(_w("1000000000000000000")), "1")
	eq(TokenFormat.wei_to_tokens(_w("1234567800000000000000")), "1,234.5678")
	eq(TokenFormat.wei_to_tokens(_w("375000000000000")), "0.000375")
	eq(TokenFormat.wei_to_tokens(_w("1")), "0.000000000000000001")
	eq(TokenFormat.wei_to_tokens(_w("12345678000000000000000000")), "12.34M")
	eq(TokenFormat.wei_to_tokens(_w("438000000000000000000000000")), "438M")
	eq(TokenFormat.wei_to_tokens(_w("1111111111000000000000000000")), "1.11B")
	eq(TokenFormat.group("1234567"), "1,234,567")
