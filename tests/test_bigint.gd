extends TestCase


func test_hex_roundtrip() -> void:
	for h in ["0", "1", "ff", "1000000", "ffffff", "123456789abcdef0123456789abcdef", "f".repeat(64)]:
		eq(BigInt.to_hex(BigInt.from_hex(h)), h, "roundtrip " + h)
	eq(BigInt.to_hex(BigInt.from_hex("0x000abc")), "abc")
	eq(BigInt.to_word(BigInt.from_int(1)), "0".repeat(63) + "1")


func test_decimal_matches_hex_for_real_waats() -> void:
	# Independent sources: registry decimal Waat vs the old map's hex Waat.
	var reg = load_json("res://assets/data/territories.json")
	var old = load_json("res://assets/data/qing_map.json")
	if reg == null or old == null:
		return
	var by_addr := {}
	for q in reg["territories"]:
		by_addr[q["address"]] = q["waat"]
	var checked := 0
	for o in old["qings"]:
		var dec = by_addr.get(String(o["address"]).to_lower())
		if dec == null:
			continue
		var from_dec := BigInt.from_decimal(dec)
		eq(BigInt.to_hex(from_dec), BigInt.to_hex(BigInt.from_hex(o["waat_hex"])), "waat " + o["address"])
		eq(BigInt.to_decimal(from_dec), dec, "decimal roundtrip")
		checked += 1
	check(checked >= 250, "checked %d waats" % checked)


func test_arithmetic() -> void:
	var a := BigInt.from_decimal("340282366920938463463374607431768211456")  # 2^128
	eq(BigInt.to_hex(a), "1" + "0".repeat(32))
	eq(BigInt.cmp(a, BigInt.pow2(128)), 0)
	eq(BigInt.to_decimal(BigInt.sub(a, BigInt.from_int(1))), "340282366920938463463374607431768211455")
	eq(BigInt.to_hex(BigInt.add(BigInt.from_hex("ffffff"), BigInt.from_int(1))), "1000000")
	eq(BigInt.to_hex(BigInt.mul(BigInt.from_hex("ffffffffffff"), BigInt.from_hex("ffffffffffff"))), "fffffffffffe000000000001")
	var qr := BigInt.divmod_small(BigInt.from_decimal("1000000000000000000007"), 10)
	eq(BigInt.to_decimal(qr[0]), "100000000000000000000")
	eq(qr[1], 7)
	eq(BigInt.cmp(BigInt.from_int(5), BigInt.from_int(7)), -1)
	check(BigInt.is_zero(BigInt.from_hex("0x0000")))


func test_bitwise() -> void:
	eq(BigInt.to_hex(BigInt.xor(BigInt.from_hex("f0f0"), BigInt.from_hex("0ff0ff"))), "f000f")
	eq(BigInt.to_hex(BigInt.shr(BigInt.from_hex("123456789abcdef"), 7)), "2468acf13579b")
	eq(BigInt.to_hex(BigInt.shl(BigInt.from_hex("1"), 100)), "1" + "0".repeat(25))
	eq(BigInt.to_hex(BigInt.low_bits(BigInt.from_hex("123456789"), 12)), "789")
	eq(BigInt.bit_length(BigInt.from_hex("80")), 8)


func test_mod_and_int() -> void:
	# (entropy * 369) mod P, as Deep Field does; small enough to check with int64.
	var e := 393752164582214
	var expected := (e * 369) % Contracts.MOTZKIN_PRIME
	eq(BigInt.mod_int(BigInt.mul_small(BigInt.from_int(e), 369), Contracts.MOTZKIN_PRIME), expected)
	eq(BigInt.mod_int(BigInt.from_hex("f".repeat(64)), 1000), 935)  # 2^256-1 ≡ 935 (mod 1000)
	check(BigInt.fits_int(BigInt.from_hex("7fffffffffffffff")))
	check(not BigInt.fits_int(BigInt.from_hex("8000000000000000")))
	eq(BigInt.to_int(BigInt.from_hex("7fffffffffffffff")), 9223372036854775807)


func test_signed() -> void:
	eq(BigInt.word_to_signed_hex("f".repeat(64)), "-0x1")
	eq(BigInt.word_to_signed_hex("0".repeat(62) + "2a"), "0x2a")
	eq(BigInt.signed_to_word(-1), "f".repeat(64))
	eq(BigInt.signed_to_word("-0x2"), "f".repeat(63) + "e")
	eq(BigInt.signed_to_word("-0"), "0".repeat(64))
	eq(BigInt.word_to_signed_hex(BigInt.signed_to_word("-0x123456789abcdef0123456789")), "-0x123456789abcdef0123456789")


func test_log10() -> void:
	near(BigInt.log10(BigInt.from_int(1000)), 3.0, 1e-9)
	near(BigInt.log10(BigInt.from_decimal("378814830703436350975436945425663138519237484768630413256454076449062763743")), 74.578, 0.001)
	check(is_inf(BigInt.log10(BigInt.zero())))
