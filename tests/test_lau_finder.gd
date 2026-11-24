extends TestCase
## Finding a wallet's LAUs: candidates from OwnershipUpdate logs, proof by Saat(2).

const W := "0x18f621662d6a1f23700ea32d146b32195dc33111"


func test_candidates_are_unique_and_lowercase() -> void:
	var logs := [{"address": "0xCCE83CFF8B531EADDCF11AB414C59DC046D1AAC7"}, {"address": "0xcce83cff8b531eaddcf11ab414c59dc046d1aac7"},
		{"address": "0x3a1ecb9a93665661047456594f10b9919dc01fe4"}, {"address": "bad"}]
	eq(LauFinder.candidates(logs), ["0xcce83cff8b531eaddcf11ab414c59dc046d1aac7", "0x3a1ecb9a93665661047456594f10b9919dc01fe4"])


func test_saat2_proves_the_wallet() -> void:
	var want := BigInt.mod_int(BigInt.from_hex(W), Contracts.MOTZKIN_PRIME)
	var hex := "0x" + ("%x" % want).lpad(64, "0")
	check(LauFinder.proves(hex, W), "Saat(2) = wallet mod the Motzkin prime")
	check(not LauFinder.proves("0x" + "%x" % (want + 1), W), "any other value is not this wallet's LAU")
	check(not LauFinder.proves("", W), "an unread value proves nothing")


func test_labels() -> void:
	eq(LauFinder.label({"username": "kingg", "name": "king gizard", "address": "0x3a1e"}), "kingg · king gizard")
	eq(LauFinder.label({"username": "", "name": "chatlife", "address": "0x96885a2ef9f136591987a86546fce48af442166d"}), "chatlife")
	eq(LauFinder.label({"username": "", "name": "", "address": "0x96885a2ef9f136591987a86546fce48af442166d"}), "0x9688…166d")
	eq(Abi.encode_call("Enter(address)", ["0x3a1ecb9a93665661047456594f10b9919dc01fe4"]),
		"0x37a2e7520000000000000000000000003a1ecb9a93665661047456594f10b9919dc01fe4", "the call simulated live")
