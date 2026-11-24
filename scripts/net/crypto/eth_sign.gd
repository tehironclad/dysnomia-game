class_name EthSign
extends RefCounted
## Ethereum personal_sign (EIP-191) on top of Keccak and Secp256k1:
## the game server checks that a client holds the wallet it claims.
## A signature here is free: it is not a transaction and moves nothing.


## keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)
static func personal_hash(message: String) -> PackedByteArray:
	var body := message.to_utf8_buffer()
	var prefix := ("\u0019Ethereum Signed Message:\n%d" % body.size()).to_utf8_buffer()
	return Keccak.digest(prefix + body)


## "0x" + 40 lowercase hex of a 64-byte public key; "" if malformed.
static func address_of_pubkey(pub: PackedByteArray) -> String:
	if pub.size() != 64:
		return ""
	return "0x" + Keccak.digest(pub).slice(12).hex_encode()


## The wallet that signed `message`, lowercase, or "" if the signature is not valid.
## `sig_hex`: 65 bytes r‖s‖v, v ∈ {0, 1, 27, 28}.
static func recover_personal(message: String, sig_hex: String) -> String:
	return recover_hash(personal_hash(message), sig_hex)


static func recover_hash(hash: PackedByteArray, sig_hex: String) -> String:
	var h := sig_hex.strip_edges().trim_prefix("0x")
	if h.length() != 130 or not h.is_valid_hex_number():
		return ""
	var sig := PackedByteArray(h.hex_decode())
	var v: int = sig[64]
	if v >= 27:
		v -= 27
	if v < 0 or v > 1:
		return ""
	return address_of_pubkey(Secp256k1.recover(hash, sig.slice(0, 32), sig.slice(32, 64), v))


## Signs like a wallet's personal_sign (RFC 6979, low-s, v = 27/28) → "0x…" (65 bytes).
## For scripted test wallets only.
static func sign_personal(message: String, priv_hex: String) -> String:
	var priv := PackedByteArray(priv_hex.trim_prefix("0x").hex_decode())
	var sg := Secp256k1.sign(personal_hash(message), priv)
	if sg.is_empty():
		return ""
	var out: PackedByteArray = sg["r"] + sg["s"]
	out.append(27 + (int(sg["recid"]) & 1))
	return "0x" + out.hex_encode()


static func address_of_private(priv_hex: String) -> String:
	return address_of_pubkey(Secp256k1.public_key(PackedByteArray(priv_hex.trim_prefix("0x").hex_decode())))
