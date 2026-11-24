extends TestCase
## The Affection Fair's midway games: titles, seeding by the ticket's tx hash, prizes.

const TX := "0x9f3c2b1a00000000000000000000000000000000000000000000000012345678"


func test_every_stall_kind_with_a_sign_is_playable_or_food() -> void:
	for k in Funfair.STALL_TITLES:
		check(MidwayGame.has_game(k) or k in ["pulse", "eris"], "%s has a game (or is a food stall)" % k)
	check(MidwayGame.has_game("striker"), "the high striker plays")
	for k in MidwayGame.GAMES:
		check(MidwaySim.SPEC.has(k), "%s has a sim" % k)
		check(MidwayStage.create(k) != null, "%s has a 3D stage" % k)


func test_seed_from_tx_is_deterministic() -> void:
	eq(MidwayGame.seed_from_tx(TX), 0x12345678)
	eq(MidwayGame.seed_from_tx("nope"), 0)


func test_primes() -> void:
	for n in [2, 3, 5, 7, 11, 13, 97, 199]:
		check(MidwayGame.is_prime(n), "%d is prime" % n)
	for n in [0, 1, 4, 9, 15, 91, 121, 200]:
		check(not MidwayGame.is_prime(n), "%d is not prime" % n)


func test_prizes() -> void:
	check(MidwayGame.prize("striker", 300).begins_with("GRAND"))
	check(not MidwayGame.prize("striker", 0).begins_with("GRAND"))
	eq(MidwayGame.prize("saat", 0), "", "the fortune teller has no score")
	eq(MidwayGame.max_score("motzkin"), 1500)
