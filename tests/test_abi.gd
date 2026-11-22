extends TestCase

const ADDR := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"


func test_simple_calls() -> void:
	eq(Abi.encode_call("Entropy()"), "0x40c48dfa")
	eq(Abi.encode_call("Su(address)", [ADDR]),
		"0x753a0c09" + "000000000000000000000000d127839b83cbf537c29b7d268c135f745a0da2e8")
	eq(Abi.encode_call("Saat(uint256)", [2]), "0x088aee78" + "0".repeat(63) + "2")
	eq(Abi.encode_call("Beat(uint256)", [Contracts.PHOBOS_WAAT]),
		"0xd5215e06" + "0116ffdf05f579f35879129076ff12f3c18bc4a0b85bda626f6bf7f2fcb7fafc")


func test_dynamic_string() -> void:
	var data := Abi.encode_call("Chat(address,string)", [ADDR, "hi"])
	var expected := "0xb340a780" \
		+ "000000000000000000000000d127839b83cbf537c29b7d268c135f745a0da2e8" \
		+ "0".repeat(62) + "40" \
		+ "0".repeat(63) + "2" \
		+ "6869" + "0".repeat(60)
	eq(data, expected)
	var dec := Abi.decode(["address", "string"], data.substr(10))
	eq(dec, [ADDR, "hi"])
	# Two strings (SEI.Start), including UTF-8.
	var enc := Abi.encode(["address", "string", "string"], [ADDR, "Zürich", ""])
	eq(Abi.decode(["address", "string", "string"], enc), [ADDR, "Zürich", ""])


func test_int256_roundtrip() -> void:
	var lon := "-0x1a2b3c4d5e6f708192a3b4c5d6e7f80910a1b2c3d4e5f60718293a4b5c6d"
	var enc := Abi.encode_call("Code(int256,int256,address)", [lon, "0x2a", ADDR])
	eq(Abi.decode(["int256", "int256", "address"], enc.substr(10)), [lon, "0x2a", ADDR])


func test_aggregate3_roundtrip() -> void:
	var calls := [
		[ADDR, true, Abi.encode_call("Entropy()")],
		[Contracts.MAP, false, Abi.encode_call("Saat(uint256)", [1])],
	]
	var enc := Abi.encode(["(address,bool,bytes)[]"], [calls])
	var dec := Abi.decode(["(address,bool,bytes)[]"], enc)
	eq(dec[0][0], calls[0])
	eq(dec[0][1], calls[1])
	# Results shape: (bool success, bytes returnData)[]
	var results := [[true, "0x" + "0".repeat(63) + "7"], [false, "0x"]]
	var renc := Abi.encode(["(bool,bytes)[]"], [results])
	eq(Abi.decode(["(bool,bytes)[]"], renc)[0], results)


func test_decode_uint_and_bool() -> void:
	var data := "0x" + "0".repeat(63) + "1" + "0".repeat(48) + "0123456789abcdef"
	eq(Abi.decode(["bool", "uint256"], data), [true, "0x123456789abcdef"])
	eq(Abi.decode(["uint256"], "0x"), [])


func test_revert_decoding() -> void:
	var panic := Abi.decode_revert("0x4e487b71" + "0".repeat(62) + "12")
	eq(panic["name"], "Panic")
	check(String(panic["message"]).contains("division by zero"), panic["message"])
	check(String(panic["message"]).contains("four holdings"), "panic hint")
	var zh := Abi.decode_revert("0x98aaa293" + "000000000000000000000000" + ADDR.substr(2))
	eq(zh["name"], "ZeroHoldings")
	eq(zh["args"], [ADDR])
	var err := Abi.decode_revert("0x08c379a0" + Abi.encode(["string"], ["nope"]))
	eq(err["message"], "nope")
	eq(Abi.decode_revert("0xdeadbeef")["name"], "")
	eq(Abi.decode_revert("0x")["message"], "reverted without a reason")
