extends TestCase
## The activity feed and online names, with no network: NetEvents (wire, cleaning,
## lines, relevance, the gate), NetNames (what a tag shows), InviteBook "Join me",
## the feed's header.

const A := "0x1111111111111111111111111111111111111111"
const B := "0x2222222222222222222222222222222222222222"
const Q := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"


func _ctx(me: String = "") -> Dictionary:
	return {"me": me, "name": func(w, _c): return {A: "enteh", B: "Bob"}.get(w, NetProto.short_wallet(w)),
		"place": func(r): return "Zürich QING" if r == Q else r, "game": func(g): return {"pool": "pool", "striker": "Test Your Affection"}.get(g, g)}


func test_lines_read_like_the_spec() -> void:
	var c := _ctx()
	eq(NetEvents.format({"k": "online", "w": A, "n": "liar"}, c), "enteh came online", "the chain's name, not the claimed one")
	eq(NetEvents.format({"k": "arrive", "w": A, "room": Q}, c), "enteh arrived in Zürich QING")
	eq(NetEvents.format({"k": "place", "w": B, "room": Q, "place": "arcade"}, c), "Bob entered the arcade")
	eq(NetEvents.format({"k": "result", "w": A, "w2": B, "game": "pool", "stake": "2", "room": Q}, c), "enteh beat Bob at pool (2 Ⓐ stake, honour-bound)")
	eq(NetEvents.format({"k": "result", "w": A, "w2": B, "game": "pool", "push": true}, c), "enteh and Bob drew at pool")
	eq(NetEvents.format({"k": "fair", "w": B, "game": "striker", "score": 1240}, c), "Bob posted 1,240 at Test Your Affection")
	eq(NetEvents.format({"k": "record", "w": A, "board": Q + "/arcade:void_lanes", "score": 4200, "verified": false}, c), "enteh set a new #1 on Void Lanes: 4,200")
	eq(NetEvents.format({"k": "claim", "claim": "rocket", "w": B, "room": Q}, c), "Bob unlocked the Upsilon Rocket at Zürich QING")
	eq(NetEvents.format({"k": "guest", "room": Q}, c), "A guest arrived in Zürich QING")
	eq(NetEvents.format({"k": "join", "w": B, "w2": A, "room": Q, "place": "arcade"}, c), "Bob is on the way to join enteh at Zürich QING · the arcade")
	eq(NetEvents.format({"k": "paid", "w": B, "w2": A, "stake": "2", "block": 28151102}, c), "Bob paid enteh 2 Ⓐ ✓ (Transfer log, block 28,151,102)")
	eq(NetEvents.format({"k": "result", "w": A, "w2": B, "game": "pool"}, _ctx(A)), "You beat Bob at pool", "you, when it is you")
	eq(NetEvents.format({"k": "result", "w": B, "w2": A, "game": "pool"}, _ctx(A)), "Bob beat you at pool")
	eq(NetEvents.format({"k": "join", "w": A, "w2": B, "room": Q, "place": ""}, _ctx(A)), "You are on the way to join Bob at Zürich QING")
	eq(NetEvents.format({"k": "hypobar", "w": A, "amount": "26", "block": 5}, _ctx(A)), "Your Hypobar here rose by 26 (block 5)")
	eq(NetEvents.format({"k": "online", "w": A}), NetProto.short_wallet(A) + " came online", "no names known: the short wallet")
	eq(NetEvents.format({"k": "nonsense", "w": A}, c), "", "an unknown kind says nothing")
	eq(NetEvents.format({"k": "invite", "w": B, "state": "pending", "mine": false, "what": "Pool at Zürich QING", "key": "N"}, c), "Bob invites you: Pool at Zürich QING (N)")
	eq(NetEvents.format({"k": "invite", "w": B, "state": "accepted", "mine": true, "what": "join you"}, c), "Bob accepted your invite: join you")


func test_cleaning_a_servers_event() -> void:
	eq(NetEvents.clean_event({"k": "online", "w": "0xZZ"}), {}, "a malformed wallet is no event")
	eq(NetEvents.clean_event({"k": "hack", "w": A}), {}, "an unknown kind is dropped")
	eq(NetEvents.clean_event({"k": "fair", "w": A}), {}, "chain facts never come from the server")
	eq(NetEvents.clean_event({"k": "result", "w": A}), {}, "a result names two players")
	eq(NetEvents.clean_event({"k": "place", "w": A, "place": "bank", "room": Q}), {}, "an unknown place is dropped")
	var ev := NetEvents.clean_event({"k": "online", "w": A.to_upper().replace("0X", "0x"), "n": "en\u202Eteh\n", "t": 5})
	eq(ev.get("w"), A, "wallets lowercased")
	eq(ev.get("n"), "enteh", "names lose control and direction characters")
	var g := NetEvents.clean_event({"k": "guest", "room": Q})
	check(not g.is_empty() and g["w"] == "", "a guest event has no wallet")
	eq(NetEvents.clean_event({"k": "result", "w": A, "w2": B, "stake": "1e99; drop"}).get("stake"), "", "a stake must be a number")


func test_wire_and_sizes() -> void:
	var m := NetEvents.place_msg("arcade", Q)
	check(NetProto.size_ok(m), "C_PLACE fits its limit")
	eq(NetEvents.parse_place(m), {"place": "arcade", "room": Q})
	eq(NetEvents.parse_place(NetEvents.place_msg("bank", Q)), {}, "only known places")
	eq(NetEvents.parse_place(NetEvents.place_msg("arcade", Q + "/x")), {}, "a QING, not a sub-room")
	eq(NetEvents.parse_claim(NetEvents.claim_msg("rocket", Q)), {"claim": "rocket", "room": Q})
	eq(NetEvents.parse_claim(NetEvents.claim_msg("billionaire", Q)), {}, "only claims the chain can check")
	var big := PackedByteArray([NetEvents.C_PLACE])
	big.resize(400)
	check(not NetProto.size_ok(big), "an oversize C_PLACE is refused")
	var ev := NetProto.json_body(NetEvents.event_msg({"k": "online", "w": A}))
	eq(ev["ev"]["w"], A)
	check(not NetEvents.SIZES.has(NetBump.C_BUMP) and NetEvents.S_EVENT != NetBump.S_BUMP, "its own message numbers")


func test_relevance() -> void:
	check(not NetEvents.relevant({"k": "online", "w": A}, A, Q), "your own sign-in is not news to you")
	check(NetEvents.relevant({"k": "result", "w": A, "w2": B}, A, Q), "your own game's result is")
	check(NetEvents.relevant({"k": "place", "w": B, "room": Q}, A, Q), "someone entering a place of this QING")
	check(not NetEvents.relevant({"k": "place", "w": B, "room": "0x" + "9".repeat(40)}, A, Q), "…not of another QING")
	check(not NetEvents.relevant({"k": "guest", "room": Q}, A, ""), "between places, no guest arrivals")


func test_gate_drops_repeats_and_floods() -> void:
	var g := NetEvents.Gate.new()
	var ev := {"k": "online", "w": A}
	check(g.admit(NetEvents.dedupe_key(ev), 100.0), "first time: shown")
	check(not g.admit(NetEvents.dedupe_key(ev), 110.0), "the same line 10 s later: dropped")
	check(g.admit(NetEvents.dedupe_key(ev), 100.0 + NetEvents.DEDUPE_S + 1.0), "after the window: shown again")
	var shown := 0
	for i in 50:
		if g.admit(NetEvents.dedupe_key({"k": "arrive", "w": A, "room": "0x%040d" % i}), 200.0):
			shown += 1
	check(shown <= 7, "a flood at one instant shows a few lines (%d)" % shown)
	check(NetEvents.dedupe_key({"k": "arrive", "w": A, "room": Q}) != NetEvents.dedupe_key({"k": "arrive", "w": B, "room": Q}), "different players differ")


func test_names_are_the_chains_not_the_claim() -> void:
	eq(NetNames.tag(A, true, {}), "guest", "a guest is a guest")
	eq(NetNames.tag(A, false, {}), NetProto.short_wallet(A), "not read yet: the verified address")
	eq(NetNames.tag(A, false, {"state": "failed"}), NetProto.short_wallet(A), "read failed: the address, nothing guessed")
	eq(NetNames.tag(A, false, {"state": "none"}), NetProto.short_wallet(A), "no LAU: the address")
	eq(NetNames.tag(A, false, {"state": "ok", "username": "enteh", "lau_name": "Ent"}), "enteh · " + NetProto.short_wallet(A))
	eq(NetNames.tag(A, false, {"state": "ok", "username": "", "lau_name": "Ent LAU"}), "Ent LAU · " + NetProto.short_wallet(A), "no Username: the LAU's name")
	eq(NetNames.shown(A, {"state": "ok", "username": "x\u200Bevil\u202E"}), "xevil", "a chain name is cleaned too")
	eq(NetNames.head("fox", {}, func(k): return k == "fox"), "fox", "their own pick")
	eq(NetNames.head("nonsense", {"state": "ok", "head": "rat"}, func(k): return k == "fox"), "rat", "an unknown head: the LAU's")
	eq(NetNames.head("", {}), "bear")


func test_join_requests_in_the_invite_book() -> void:
	var book := InviteBook.new()
	var r := book.create("j1", A, "", B, "", InviteBook.JOIN, "", Q, "arcade", 1000)
	check(r["ok"], "a join request at the arcade: %s" % r.get("error", ""))
	check(not book.create("j2", A, "", B, "", InviteBook.JOIN, "", Q, "arcade", 1001)["ok"], "not twice to the same player")
	check(not book.create("j3", A, "", "0x" + "3".repeat(40), "", InviteBook.JOIN, "5", Q, "", 1001)["ok"], "no stake on a join")
	check(not book.create("j4", A, "", "0x" + "3".repeat(40), "", InviteBook.JOIN, "", Q, "bank", 1001)["ok"], "only known doors")
	check(book.create("j5", A, "", "0x" + "3".repeat(40), "", InviteBook.JOIN, "", Q, "", 1001)["ok"], "the territory itself")
	eq(book.answer("j1", B, "accept", 1010)["invite"]["state"], "accepted")
	eq(book.expire(1001 + InviteBook.TTL_S).size(), 1, "the same expiry as games")
	eq(InviteBook.title_of(InviteBook.JOIN), "Join me")
	eq(InviteBook.join_place("room"), "hall")
	eq(Invites.join_where("Zürich QING", "arcade"), "the arcade of Zürich QING")


func test_feed_header() -> void:
	eq(ActivityFeed.header_text(false, "", false, [], "N", "K", false, 0), "", "offline: nothing")
	check(ActivityFeed.header_text(true, "", true, [], "N", "K", false, 0).contains("guest"), "a guest is told")
	check(ActivityFeed.header_text(true, "prompt", false, [], "N", "K", false, 0).contains("free signature"), "signing in: says it is free")
	eq(ActivityFeed.header_text(true, "signed", false, [{"wallet": A}, {"wallet": B, "busy": true}], "N", "K", false, 0), "2 others online · 1 to invite (N)")
	check(ActivityFeed.header_text(true, "signed", false, [], "N", "K", true, 3).begins_with("▸ activity (3 new) · K"), "folded: a count")


func test_activity_slot_fits_between_the_card_and_the_dock() -> void:
	var s := HudLayout.slots()
	check(s["activity"].position.y >= s["where"].end.y, "under the territory card")
	check(s["activity"].end.y <= s["room"].position.y, "above the chat dock")
	check(s["activity"].end.x <= s["ticker"].position.x, "left of the ticker")
	check(InputMap.has_action("activity_feed"), "the fold key is bound")
