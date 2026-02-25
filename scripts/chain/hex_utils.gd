class_name HexUtils
## Utility functions for hex string operations.
## Handles uint256 values that exceed GDScript's 64-bit int range
## by keeping them as hex strings and operating digit-by-digit.

const HEX_CHARS: String = "0123456789abcdef"


static func strip_0x(hex_str: String) -> String:
	var s := hex_str.strip_edges().to_lower()
	if s.begins_with("0x"):
		s = s.substr(2)
	return s


static func hex_char_to_int(c: String) -> int:
	match c:
		"0": return 0
		"1": return 1
		"2": return 2
		"3": return 3
		"4": return 4
		"5": return 5
		"6": return 6
		"7": return 7
		"8": return 8
		"9": return 9
		"a": return 10
		"b": return 11
		"c": return 12
		"d": return 13
		"e": return 14
		"f": return 15
		_: return -1


static func hex_mod(hex_str: String, divisor: int) -> int:
	## Compute uint256_value % divisor without overflow.
	## Processes hex digits left-to-right: acc = (acc * 16 + digit) % divisor.
	## Safe because max intermediate: (MOTZKIN_PRIME-1)*16+15 ≈ 1.5e16 < 2^63.
	var hex := strip_0x(hex_str)
	if hex.is_empty():
		return 0
	var acc: int = 0
	for i in range(hex.length()):
		var digit := hex_char_to_int(hex[i])
		if digit < 0:
			continue
		acc = (acc * 16 + digit) % divisor
	return acc


static func hex_to_int(hex_str: String) -> int:
	## Convert hex string to int. Only safe for values fitting in 63 bits.
	var hex := strip_0x(hex_str)
	if hex.is_empty():
		return 0
	# Use GDScript's built-in hex conversion
	return ("0x" + hex).hex_to_int()


static func is_valid_hex(s: String) -> bool:
	for i in range(s.length()):
		if hex_char_to_int(s[i]) < 0:
			return false
	return true


static func is_valid_address(address: String) -> bool:
	## Check that string is a valid Ethereum address: 0x + 40 hex chars.
	var s := address.strip_edges()
	if not s.to_lower().begins_with("0x"):
		return false
	var hex_part := s.substr(2).to_lower()
	if hex_part.length() != 40:
		return false
	return is_valid_hex(hex_part)


static func pad_uint256(value: int) -> String:
	## Convert int to 64-char zero-padded hex string (32 bytes) for ABI encoding.
	var hex := "%x" % value
	while hex.length() < 64:
		hex = "0" + hex
	return hex


static func pad_address(address: String) -> String:
	## Left-pad an address to 32 bytes (64 hex chars) for ABI encoding.
	var hex := strip_0x(address)
	while hex.length() < 64:
		hex = "0" + hex
	return hex


static func parse_abi_string(hex_result: String) -> String:
	## Decode an ABI-encoded string return value.
	## Layout: [32B offset][32B length][data padded to 32B boundary]
	var hex := strip_0x(hex_result)
	if hex.length() < 128: # Need at least offset + length
		return ""
	# Read string length from second 32-byte word (chars 64..127)
	var len_hex := hex.substr(64, 64)
	var str_len := hex_to_int("0x" + len_hex)
	if str_len == 0 or str_len > 500:
		return ""
	# Read string data starting at char 128
	var data_hex := hex.substr(128, str_len * 2)
	var bytes := PackedByteArray()
	for i in range(0, data_hex.length(), 2):
		if i + 1 >= data_hex.length():
			break
		var byte_val := hex_char_to_int(data_hex[i]) * 16 + hex_char_to_int(data_hex[i + 1])
		bytes.append(byte_val)
	return bytes.get_string_from_utf8()


static func parse_uint64_result(hex_result: String) -> int:
	## Parse a uint64 return value from a 32-byte ABI/storage result.
	var hex := strip_0x(hex_result)
	if hex.is_empty():
		return 0
	# Take last 16 hex chars (8 bytes = uint64)
	if hex.length() > 16:
		hex = hex.right(16)
	return hex_to_int("0x" + hex)


static func parse_int256_result(hex_result: String) -> int:
	## Parse a signed int256 return value from a 32-byte ABI result.
	## Only safe for values fitting in GDScript's 63-bit signed range.
	## Handles two's complement: if high nibble >= 8, the value is negative.
	var hex := strip_0x(hex_result)
	if hex.is_empty():
		return 0
	# Pad to 64 chars for consistent handling
	while hex.length() < 64:
		hex = "0" + hex
	# Check sign bit (first nibble >= 8 means negative in two's complement)
	var first_nibble := hex_char_to_int(hex[0])
	if first_nibble >= 8:
		# Negative value — take lower 16 hex chars (64 bits) and interpret as signed
		# GDScript's hex_to_int returns signed int, so 0xFFFF...FFFF = -1
		var lower := hex.right(16)
		return ("0x" + lower).hex_to_int()
	else:
		# Positive value — take lower 16 hex chars
		var lower := hex.right(16)
		return ("0x" + lower).hex_to_int()


static func build_keccak256_calldata(padded_key: String, padded_slot: String) -> String:
	## Build eth_call data that computes keccak256(key ++ slot) via EVM bytecode.
	## Both padded_key and padded_slot must be 64-char hex strings (32 bytes each, no 0x).
	## Used for computing Solidity mapping storage keys on the RPC node:
	##   storage_key = keccak256(abi.encode(address, mapping_slot))
	##
	## The bytecode: CODECOPY 64 bytes from offset 20 into memory,
	## SHA3 over memory[0:64], MSTORE result, RETURN 32 bytes.
	const KECCAK_BYTECODE: String = "60406014600039604060002060005260206000f3"
	return "0x" + KECCAK_BYTECODE + padded_key + padded_slot


static func int256_compare(a_hex64: String, b_hex64: String) -> int:
	## Compare two 64-char hex int256 values in two's complement.
	## Returns -1 if a < b, 0 if a == b, 1 if a > b.
	## Handles sign correctly: positive > negative.
	var a := a_hex64.to_lower()
	var b := b_hex64.to_lower()
	var a_neg := hex_char_to_int(a[0]) >= 8
	var b_neg := hex_char_to_int(b[0]) >= 8

	# Different signs: positive > negative
	if a_neg and not b_neg:
		return -1
	if not a_neg and b_neg:
		return 1

	# Same sign: lexicographic comparison works for both cases
	# (for positive: larger hex = larger value; for negative: larger hex = larger/less-negative value)
	if a < b:
		return -1
	elif a > b:
		return 1
	return 0


static func int256_is_negative(hex64: String) -> bool:
	## Check if a 64-char hex int256 value is negative (two's complement).
	return hex_char_to_int(hex64.to_lower()[0]) >= 8


static func parse_address_result(hex_result: String) -> String:
	## Extract an address from a 32-byte ABI-encoded response.
	## The address occupies the last 20 bytes (40 hex chars).
	var hex := strip_0x(hex_result)
	if hex.length() < 40:
		return ""
	var addr_hex := hex.right(40)
	# Check for zero address
	if addr_hex == "0000000000000000000000000000000000000000":
		return ""
	return "0x" + addr_hex
