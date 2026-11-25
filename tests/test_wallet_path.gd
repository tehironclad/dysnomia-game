extends TestCase
## The payment path's pure parts (the whole path runs in tools/e2e_wallet.sh).

const BRIDGE := "res://scripts/chain/wallet_bridge.gd"


func test_quantity_is_canonical_hex() -> void:
	var W = load("res://scripts/core/wallet.gd")
	eq(W.quantity("0x0"), "0x0")
	eq(W.quantity(""), "0x0")
	eq(W.quantity("0x"), "0x0")
	eq(W.quantity("0x000de0b6b3a7640000"), "0xde0b6b3a7640000", "leading zeros dropped")
	eq(W.quantity("0xDE0B6B3A7640000"), "0xde0b6b3a7640000", "lower case")
	eq(W.quantity("1000000000000000003"), "0xde0b6b3a7640003", "decimal → hex, no float")
	eq(W.quantity("115792089237316195423570985008687907853269984665640564039457584007913129639935"), "0x" + "f".repeat(64), "2^256-1 exact")
	eq(W.quantity("-1"), "")
	eq(W.quantity("1e18"), "")
	eq(W.quantity("0xzz"), "")


func test_tx_hash_shape() -> void:
	var W = load("res://scripts/core/wallet.gd")
	check(W.is_tx_hash("0x4a556d285461e5a01d1c857b12efcc5d6f13ce6ae9daaf44b8a7fbb6c0658f3b"))
	check(not W.is_tx_hash("0x4a556d"), "short")
	check(not W.is_tx_hash(""), "empty")
	check(not W.is_tx_hash("4a556d285461e5a01d1c857b12efcc5d6f13ce6ae9daaf44b8a7fbb6c0658f3b00"), "no 0x")


func test_stage_words() -> void:
	var W = load("res://scripts/core/wallet.gd")
	eq(W.stage_text("sign"), "your wallet's approval")
	eq(W.stage_text("simulate"), "the chain check (nothing was sent)")
	eq(W.stage_text("funds · sign"), "moving Ⓐ from your LAU: your wallet's approval")
	eq(W.stage_text("mystery"), "mystery")


func test_fair_fee_code_in_the_last_wei() -> void:
	# The fair's ticket: 1 Ⓐ + k wei, encoded exactly (never through a float)
	var fee := FairProgress.fee_wei("regolith")
	eq(fee, "1000000000000000003")
	var data := Abi.encode_call("transfer(address,uint256)", ["0x299c56d1e1efa1d662823faa7fe7ccda6a4f35eb", fee])
	eq(data, "0xa9059cbb000000000000000000000000299c56d1e1efa1d662823faa7fe7ccda6a4f35eb0000000000000000000000000000000000000000000000000de0b6b3a7640003")
	eq(FairProgress.code_of(BigInt.from_decimal(fee)), 3)


func test_hello_verdict() -> void:
	var B = load(BRIDGE)
	var tok := "00112233445566778899aabbccddeeff"
	eq(B.hello_verdict('{"type":"hello","token":"%s"}' % tok, tok), "ok")
	eq(B.hello_verdict('{"type":"hello","token":"ffff"}', tok), "stale", "an old page reloads")
	eq(B.hello_verdict('{"type":"hello"}', tok), "bad")
	eq(B.hello_verdict('{"type":"tx_result","id":1}', tok), "bad", "nothing before hello")
	eq(B.hello_verdict("not json", tok), "bad")
	eq(B.hello_verdict('{"type":"hello","token":""}', ""), "bad", "no token, no link")


func test_http_host_check_stops_dns_rebinding() -> void:
	var B = load(BRIDGE)
	var req := func(host: String, method: String = "GET") -> String:
		return "%s / HTTP/1.1\r\nHost: %s\r\nUser-Agent: x\r\n\r\n" % [method, host]
	eq(B.http_verdict(req.call("localhost:38420"), 38420), "ok")
	eq(B.http_verdict(req.call("127.0.0.1:38420"), 38420), "ok")
	eq(B.http_verdict(req.call("LOCALHOST:38420"), 38420), "ok", "host names are case-insensitive")
	eq(B.http_verdict(req.call("evil.example:38420"), 38420), "bad_host", "a rebinding site sends its own name: no page, no token")
	eq(B.http_verdict(req.call("localhost:38421"), 38420), "bad_host", "another port")
	eq(B.http_verdict(req.call("localhost"), 38420), "bad_host", "no port")
	eq(B.http_verdict(req.call("localhost.evil.example:38420"), 38420), "bad_host")
	eq(B.http_verdict(req.call("127.0.0.1:38420@evil.example"), 38420), "bad_host")
	eq(B.http_verdict(req.call("localhost:38420", "POST"), 38420), "bad_method")
	eq(B.http_verdict("GET / HTTP/1.1\r\nUser-Agent: x\r\n\r\n", 38420), "bad_request", "no Host header")
	eq(B.http_verdict("garbage\r\n\r\n", 38420), "bad_request")
	eq(B.header_value("GET / HTTP/1.1\r\nhOsT:  localhost:1 \r\n\r\n", "Host"), "localhost:1")


func test_page_security_headers() -> void:
	var B = load(BRIDGE)
	var h: String = "\n".join(B.security_headers(38421))
	check(h.contains("frame-ancestors 'none'"), "no framing (clickjacking)")
	check(h.contains("X-Frame-Options: DENY"))
	check(h.contains("object-src 'none'") and h.contains("base-uri 'none'") and h.contains("form-action 'none'"))
	check(h.contains("connect-src 'self' ws://127.0.0.1:38421 https://rpc.pulsechain.com https://pulsechain-rpc.publicnode.com"), "the page talks only to the game and the relay nodes")
	check(h.contains("Referrer-Policy: no-referrer") and h.contains("X-Content-Type-Options: nosniff"))
	check(h.contains("Cross-Origin-Opener-Policy: same-origin"), "a site that opened the page keeps no handle on it")
	check(h.contains("Cache-Control: no-store"), "the token is never cached")
	var html := FileAccess.get_file_as_string("res://assets/web/wallet.html")
	check(not html.contains("<script src") and not html.contains("<link"), "no external scripts or stylesheets in the signing page")
	for node in B.RELAY_NODES:
		check(html.contains("'%s'" % node), "the page's relay nodes are the CSP's: %s" % node)


func test_unlimited_approvals_never_sent() -> void:
	var W = load("res://scripts/core/wallet.gd")
	var spender := "0x165c3410fc91ef562c50559f7d2289febed552d9"
	eq(W.call_refusal(Abi.encode_call("approve(address,uint256)", [spender, "1000000000000000001"])), "", "an exact approve goes")
	eq(W.call_refusal(Abi.encode_call("approve(address,uint256)", [spender, BigInt.to_decimal(BigInt.sub(BigInt.pow2(128), BigInt.from_int(1)))])), "", "2^128 - 1 is the ceiling")
	check(W.call_refusal(Abi.encode_call("approve(address,uint256)", [spender, BigInt.to_decimal(BigInt.pow2(128))])) != "", "2^128 is refused")
	var maxu := "115792089237316195423570985008687907853269984665640564039457584007913129639935"
	check(W.call_refusal(Abi.encode_call("approve(address,uint256)", [spender, maxu])).contains("unlimited"), "type(uint256).max is refused")
	check(W.call_refusal(Abi.encode_call("approve(address,uint256)", [spender, maxu]).to_upper().replace("0X", "0x")) != "", "upper-case calldata too")
	check(W.call_refusal("0x39509351" + Abi.encode(["address", "uint256"], [spender, maxu]).substr(2)) != "", "increaseAllowance(max) is refused")
	check(W.call_refusal("0xa22cb465" + Abi.encode(["address", "bool"], [spender, true]).substr(2)) != "", "setApprovalForAll is refused")
	check(W.call_refusal("0x095ea7b3") != "", "a malformed approve is refused")
	eq(W.call_refusal(Abi.encode_call("transfer(address,uint256)", [spender, maxu])), "", "transfers are bounded by the simulation and the balance, not here")


func test_only_the_games_own_texts_are_signed() -> void:
	var W = load("res://scripts/core/wallet.gd")
	eq(W.sign_refusal("Dysnomia wallet test (free, not a transaction)\nwallet: 0x1\ntime: 1"), "")
	eq(W.sign_refusal("Dysnomia game server sign-in\nServer: x\nHost: y\nNonce: z"), "")
	check(W.sign_refusal("opensea.io wants you to sign in with your Ethereum account:\n0x…") != "", "another site's login is refused")
	check(W.sign_refusal("0x" + "ab".repeat(32)) != "", "a hash (an order, a permit) is refused")
	check(W.sign_refusal(" Dysnomia wallet test (free, not a transaction)\n") != "", "the prefix must be at the start")
	check(W.sign_refusal("Dysnomia wallet test (free, not a transaction)\n" + "x".repeat(700)) != "", "too long")


func test_a_tampered_transaction_is_named() -> void:
	var W = load("res://scripts/core/wallet.gd")
	var q := "0x299c56d1e1efa1d662823faa7fe7ccda6a4f35eb"
	var data := Abi.encode_call("transfer(address,uint256)", [q, "1000000000000000003"])
	var want := {"from": "0xb644ba4797c8eab1c5a33c41e00096eb4e06d465", "to": Contracts.AFFECTION, "data": data, "value": "0x0"}
	var sent := {"from": want["from"].to_upper().replace("0X", "0x"), "to": Contracts.AFFECTION, "input": data.to_upper().replace("0X", "0x"), "value": "0x0"}
	eq(W.tx_mismatch(sent, want), "", "the same transaction (any letter case) matches")
	var evil := "0x" + "de".repeat(20)
	check(W.tx_mismatch(sent.merged({"input": Abi.encode_call("transfer(address,uint256)", [evil, "1000000000000000003"])}, true), want).contains("arguments"), "another recipient")
	check(W.tx_mismatch(sent.merged({"to": evil}, true), want).contains("went to"), "another contract")
	check(W.tx_mismatch(sent.merged({"value": "0xde0b6b3a7640000"}, true), want).contains("value"), "PLS added")
	check(W.tx_mismatch(sent.merged({"input": "0x095ea7b3" + data.substr(10)}, true), want).contains("0x095ea7b3"), "another function")
	check(W.tx_mismatch(sent.merged({"from": evil}, true), want).contains("sent from"), "another sender")


func test_call_summary_names_the_call() -> void:
	var W = load("res://scripts/core/wallet.gd")
	var q := "0x299c56d1e1efa1d662823faa7fe7ccda6a4f35eb"
	var s: String = W.call_summary(Contracts.AFFECTION, Abi.encode_call("transfer(address,uint256)", [q, "1000000000000000003"]))
	eq(s, "AFFECTION.transfer(address,uint256) to %s, 1000000000000000003 wei" % q)
	check(W.call_summary(q, "0x12345678").begins_with("contract %s.call 0x12345678" % q), "unknown contract and selector say so")
	check(W.call_summary(Contracts.PULSEX_V2_ROUTER, "0x7ff36ab5", "0x10").contains("paying 16 wei of PLS"))


func test_default_browser() -> void:
	var B = load(BRIDGE)
	var out := "\r\nHKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\Shell\\Associations\\UrlAssociations\\http\\UserChoice\r\n    ProgId    REG_SZ    BraveHTML\r\n\r\n"
	eq(B.parse_reg_progid(out), "BraveHTML")
	eq(B.parse_reg_progid("ERROR: The system was unable to find the specified registry key or value."), "")
	eq(B.browser_kind("BraveHTML"), "brave")
	eq(B.browser_kind("ChromeHTML"), "chrome")
	eq(B.browser_kind("MSEdgeHTM"), "edge")
	eq(B.browser_kind("FirefoxURL-308046B0AF4A39CB"), "other", "non-Chromium: open in the default browser")
	eq(B.browser_kind(""), "")
	var paths: Array = B.windows_paths("brave", "C:/Users/x/AppData/Local")
	eq(paths[0], "C:/Users/x/AppData/Local/BraveSoftware/Brave-Browser/Application/brave.exe")
	check(paths.has("C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"), "system-wide Brave")


func test_chip_states() -> void:
	var none := WalletChip.chip_state("", 0, false, false, {})
	check(String(none["text"]).contains("not connected"), none["text"])
	var no_ext := WalletChip.chip_state("", 0, true, true, {"hasProvider": false})
	check(String(no_ext["text"]).contains("no wallet extension"), no_ext["text"])
	var good := WalletChip.chip_state("0x18f621662d6a1f23700ea32d146b32195dc33111", 369, true, true, {"hasProvider": true})
	check(String(good["text"]).contains("0x18f6…3111") and String(good["text"]).contains("PulseChain") and String(good["text"]).contains("linked"), good["text"])
	var closed := WalletChip.chip_state("0x18f621662d6a1f23700ea32d146b32195dc33111", 369, false, true, {})
	check(String(closed["text"]).contains("closed"), closed["text"])
	var wrong := WalletChip.chip_state("0x18f621662d6a1f23700ea32d146b32195dc33111", 1, true, true, {})
	check(String(wrong["text"]).contains("chain 1"), wrong["text"])


func test_diagnosis_lines() -> void:
	var steps := [{"id": "relay", "step": "Local wallet relay", "ok": true, "why": "up"},
		{"id": "window", "step": "Wallet window linked", "ok": false, "why": "closed"},
		{"id": "chain", "step": "Wallet on PulseChain (369)", "ok": null, "why": "skipped"}]
	var l := WalletDiagnosis.lines(steps)
	eq(l[0], "✓ Local wallet relay — up")
	eq(l[1], "✗ Wallet window linked — closed")
	eq(l[2], "– Wallet on PulseChain (369) — skipped")
	eq(WalletDiagnosis.first_failure(steps).get("id", ""), "window")
	check(WalletDiagnosis.first_failure([steps[0]]).is_empty(), "no failure")
