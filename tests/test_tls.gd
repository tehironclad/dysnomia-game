extends TestCase
## TLS fallback for antivirus/proxy HTTPS scanning (LEARNINGS §9). No network.


func test_system_ca_options_load() -> void:
	var R = load("res://scripts/chain/rpc.gd")
	R.use_system_ca = false
	check(R.tls_options() == null, "bundled certificates by default")
	R.use_system_ca = true
	var o = R.tls_options()
	check(o != null, "system certificate store loads into TLSOptions")
	R.use_system_ca = false


func test_tls_error_is_named() -> void:
	var R = load("res://scripts/chain/rpc.gd")
	var r: Dictionary = R.classify(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, PackedByteArray())
	check(String(r["error"]["message"]).begins_with("TLS handshake"), "the retry keys on this prefix")
