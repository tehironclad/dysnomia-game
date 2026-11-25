extends TestCase
## Pure parts of the RPC layer (no network).


func _body(d: Dictionary) -> PackedByteArray:
	return JSON.stringify(d).to_utf8_buffer()


func test_classify_ok_and_errors() -> void:
	var ok := Rpc.classify(HTTPRequest.RESULT_SUCCESS, 200, _body({"jsonrpc": "2.0", "id": 1, "result": "0x10"}))
	eq(ok, {"ok": true, "result": "0x10"})
	eq(Rpc.classify(HTTPRequest.RESULT_TIMEOUT, 0, PackedByteArray())["kind"], "transport")
	eq(Rpc.classify(HTTPRequest.RESULT_SUCCESS, 429, PackedByteArray())["kind"], "transport")
	eq(Rpc.classify(HTTPRequest.RESULT_SUCCESS, 200, "<html>busy</html>".to_utf8_buffer())["kind"], "transport")
	var rpc_err := Rpc.classify(HTTPRequest.RESULT_SUCCESS, 200, _body({"error": {"code": -32005, "message": "range too large"}}))
	eq(rpc_err["kind"], "rpc")


func test_classify_revert() -> void:
	var data := "0x12efd467000000000000000000000000d127839b83cbf537c29b7d268c135f745a0da2e8"
	var r := Rpc.classify(HTTPRequest.RESULT_SUCCESS, 200, _body({"error": {"code": 3, "message": "execution reverted", "data": data}}))
	eq(r["kind"], "revert")
	eq(r["revert"]["name"], "NotStarted")
	var bare := Rpc.classify(HTTPRequest.RESULT_SUCCESS, 200, _body({"error": {"code": -32000, "message": "execution reverted"}}))
	eq(bare["kind"], "revert")


func test_multicall_codec() -> void:
	var calls := [Multicall.make_call(Contracts.MAP, "Offset()"), Multicall.make_call(Contracts.CHO, "Saat(uint256)", [1], false)]
	var data := Multicall.encode(calls)
	check(data.begins_with("0x82ad56cb"), data.substr(0, 10))
	var back: Array = Abi.decode(["(address,bool,bytes)[]"], data.substr(10))[0]
	eq(back[0], [Contracts.MAP, true, "0x5261d74a"])
	eq(back[1][1], false)
	var ret := Abi.encode(["(bool,bytes)[]"], [[[true, "0x" + "0".repeat(62) + "2a"], [false, "0x"]]])
	var res := Multicall.decode(ret)
	eq(Multicall.value(res[0], ["uint256"]), ["0x2a"])
	eq(Multicall.value(res[1], ["uint256"]), null)


func test_block_param() -> void:
	eq(Rpc.block_param(28124253), "0x1ad245d")
	eq(Rpc.block_param("latest"), "latest")
	eq(Rpc.block_param({"blockHash": "0xab"}), {"blockHash": "0xab"})


## A request's timeout counts frames, capped: a long main-thread stall (a build stage) is
## the game being busy, not the node being unreachable.
func test_timeout_ignores_main_thread_stalls() -> void:
	near(Rpc.timeout_step(16000), 0.016, 1e-9, "a normal frame counts in full")
	near(Rpc.timeout_step(220000), 0.22, 1e-9, "a slow frame (4 fps) still counts")
	near(Rpc.timeout_step(9700000), Rpc.STALL_CAP_S, 1e-9, "a 9.7 s build stage counts as one capped frame")
	near(Rpc.timeout_step(-5), 0.0, 1e-9, "a clock step back counts nothing")
	check(Rpc.TIMEOUT_S / Rpc.STALL_CAP_S >= 30.0, "a timeout needs many frames, never one stall")
