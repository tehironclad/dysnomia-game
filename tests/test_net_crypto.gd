extends TestCase
## Keccak-256, secp256k1 ecrecover and personal_sign against ethers v6 goldens
## (tests/golden/ecrecover.json, made by tools/golden/ecrecover.js).

const GOLDEN := "res://tests/golden/ecrecover.json"


func test_keccak_against_ethers() -> void:
	var g = load_json(GOLDEN)
	for v in g["keccak"]:
		eq(Keccak.hash_hex(String(v["text"]).to_utf8_buffer()), String(v["hash"]), "keccak(%s…)" % String(v["text"]).left(12))


func test_keccak_matches_selector_goldens() -> void:
	var g = load_json("res://tests/golden/selectors.json")
	var n := 0
	for sig in g["selectors"]:
		eq("0x" + Keccak.hash_text(String(sig)).slice(0, 4).hex_encode(), String(g["selectors"][sig]), sig)
		n += 1
	check(n > 10, "selectors checked")


func test_personal_hash() -> void:
	var g = load_json(GOLDEN)
	for v in g["signatures"].slice(0, 3):
		eq("0x" + EthSign.personal_hash(String(v["message"])).hex_encode(), String(v["hash"]), "hashMessage")


func test_address_of_private_key() -> void:
	eq(EthSign.address_of_private("0x" + "0".repeat(63) + "1"), "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf", "key 1")
	var g = load_json(GOLDEN)
	var seen := {}
	for v in g["signatures"]:
		if seen.has(v["key"]):
			continue
		seen[v["key"]] = true
		eq(EthSign.address_of_private(String(v["key"])), String(v["address"]), "address of %s" % String(v["key"]).left(10))


func test_ecrecover_against_ethers() -> void:
	var g = load_json(GOLDEN)
	var t0 := Time.get_ticks_msec()
	var n := 0
	for v in g["signatures"]:
		eq(EthSign.recover_personal(String(v["message"]), String(v["signature"])), String(v["address"]), "recover %s / %s" % [String(v["key"]).left(10), String(v["message"]).left(8)])
		n += 1
	print("     ecrecover: %d vectors, %.0f ms each" % [n, float(Time.get_ticks_msec() - t0) / n])


func test_sign_matches_ethers_rfc6979() -> void:
	var g = load_json(GOLDEN)
	for v in g["signatures"].slice(0, 9):
		eq(EthSign.sign_personal(String(v["message"]), String(v["key"])), String(v["signature"]), "deterministic signature")


func test_ecrecover_rejects_tampering() -> void:
	var g = load_json(GOLDEN)
	var v = g["signatures"][7]
	var sig := String(v["signature"])
	var addr := String(v["address"])
	check(EthSign.recover_personal(String(v["message"]) + "!", sig) != addr, "another message")
	# flip a bit of s
	var b := PackedByteArray(sig.substr(2).hex_decode())
	b[40] ^= 0x10
	check(EthSign.recover_personal(String(v["message"]), "0x" + b.hex_encode()) != addr, "tampered s")
	eq(EthSign.recover_personal("x", "0x1234"), "", "short signature")
	eq(EthSign.recover_personal("x", "0x" + "0".repeat(130)), "", "zero r/s")
	eq(EthSign.recover_personal("x", "0x" + "f".repeat(128) + "1b"), "", "r ≥ n")
	var bad_v := PackedByteArray(sig.substr(2).hex_decode())
	bad_v[64] = 30
	eq(EthSign.recover_personal(String(v["message"]), "0x" + bad_v.hex_encode()), "", "bad v")
