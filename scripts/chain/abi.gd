class_name Abi
extends RefCounted
## Solidity ABI encoding/decoding for the types Dysnomia uses.
##
## Value conventions (never floats):
## - uintN  → decoded as a "0x" hex String ("0x0" for zero), so it can be
##            fed straight back into encode(). Encoded from int,
##            PackedInt64Array, "0x…" or a decimal String.
## - intN   → decoded as "0x2a" / "-0x1f". Encoded from int or a signed
##            String ("-0x1f", "-31").
## - address→ "0x" + 40 lower-case hex chars.
## - bool   → bool. string → String (UTF-8). bytes/bytesN → "0x…".
## - T[] and (A,B,…) tuples → Array.


static func strip0x(s: String) -> String:
	return s.substr(2) if s.begins_with("0x") or s.begins_with("0X") else s


# --- Encoding ------------------------------------------------------------------

static func is_dynamic(t: String) -> bool:
	if t == "string" or t == "bytes" or t.ends_with("[]"):
		return true
	if t.begins_with("("):
		for sub in Contracts.split_types(t.substr(1, t.length() - 2)):
			if is_dynamic(sub):
				return true
	return false


static func _pad_right(h: String) -> String:
	var rem := h.length() % 64
	if rem == 0 and not h.is_empty():
		return h
	return h + "0".repeat(64 - rem)


static func _encode_static(t: String, v) -> String:
	if t == "address":
		var a := strip0x(String(v)).to_lower()
		assert(a.length() == 40, "Abi: bad address %s" % v)
		return a.lpad(64, "0")
	if t == "bool":
		return ("1" if v else "0").lpad(64, "0")
	if t.begins_with("uint"):
		return BigInt.to_word(BigInt.coerce(v))
	if t.begins_with("int"):
		return BigInt.signed_to_word(v)
	if t.begins_with("bytes"):  # bytesN (static)
		return _pad_right(strip0x(String(v)).to_lower()).substr(0, 64)
	if t.begins_with("("):
		return encode(Contracts.split_types(t.substr(1, t.length() - 2)), v)
	assert(false, "Abi: unsupported static type %s" % t)
	return ""


static func _encode_dynamic(t: String, v) -> String:
	if t == "string":
		var b: PackedByteArray = String(v).to_utf8_buffer()
		return BigInt.to_word(BigInt.from_int(b.size())) + (_pad_right(b.hex_encode()) if b.size() > 0 else "")
	if t == "bytes":
		var h := strip0x(String(v)).to_lower()
		var n := h.length() / 2
		return BigInt.to_word(BigInt.from_int(n)) + (_pad_right(h) if n > 0 else "")
	if t.ends_with("[]"):
		var inner := t.substr(0, t.length() - 2)
		var arr: Array = v
		var types: Array = []
		for i in arr.size():
			types.append(inner)
		return BigInt.to_word(BigInt.from_int(arr.size())) + encode(types, arr)
	if t.begins_with("("):
		return encode(Contracts.split_types(t.substr(1, t.length() - 2)), v)
	assert(false, "Abi: unsupported dynamic type %s" % t)
	return ""


## Head/tail encodes `values` as the tuple `types`. Returns hex without 0x.
static func encode(types: Array, values: Array) -> String:
	assert(types.size() == values.size(), "Abi.encode: %d types vs %d values" % [types.size(), values.size()])
	var head_size := 0
	for t in types:
		head_size += 32 if is_dynamic(t) else _static_size(t)
	var heads := ""
	var tails := ""
	for i in types.size():
		var t: String = types[i]
		if is_dynamic(t):
			heads += BigInt.to_word(BigInt.from_int(head_size + tails.length() / 2))
			tails += _encode_dynamic(t, values[i])
		else:
			heads += _encode_static(t, values[i])
	return heads + tails


static func _static_size(t: String) -> int:
	if t.begins_with("("):
		var n := 0
		for sub in Contracts.split_types(t.substr(1, t.length() - 2)):
			n += _static_size(sub)
		return n
	return 32


## Full calldata ("0x…") for a known signature.
static func encode_call(signature: String, values: Array = []) -> String:
	return Contracts.selector(signature) + encode(Contracts.arg_types(signature), values)


# --- Decoding ------------------------------------------------------------------

static func word_at(data: String, byte_offset: int) -> String:
	return data.substr(byte_offset * 2, 64)


static func _word_int(data: String, byte_offset: int) -> int:
	var v := BigInt.from_hex(word_at(data, byte_offset))
	assert(BigInt.fits_int(v), "Abi: offset/length too large")
	return BigInt.to_int(v)


static func _decode_one(t: String, data: String, base: int, head_pos: int):
	# `base` is where this tuple's encoding starts; `head_pos` is this value's head slot.
	if is_dynamic(t):
		var off := base + _word_int(data, head_pos)
		if t == "string":
			var n := _word_int(data, off)
			return data.substr((off + 32) * 2, n * 2).hex_decode().get_string_from_utf8()
		if t == "bytes":
			var n2 := _word_int(data, off)
			return "0x" + data.substr((off + 32) * 2, n2 * 2)
		if t.ends_with("[]"):
			var inner := t.substr(0, t.length() - 2)
			var count := _word_int(data, off)
			var types: Array = []
			for i in count:
				types.append(inner)
			return _decode_tuple(types, data, off + 32)
		if t.begins_with("("):
			return _decode_tuple(Contracts.split_types(t.substr(1, t.length() - 2)), data, off)
	if t.begins_with("("):
		return _decode_tuple(Contracts.split_types(t.substr(1, t.length() - 2)), data, head_pos)
	var w := word_at(data, head_pos)
	assert(w.length() == 64, "Abi: data too short for %s" % t)
	if t == "address":
		return "0x" + w.substr(24)
	if t == "bool":
		return not BigInt.is_zero(BigInt.from_hex(w))
	if t.begins_with("uint"):
		return "0x" + BigInt.to_hex(BigInt.from_hex(w))
	if t.begins_with("int"):
		return BigInt.word_to_signed_hex(w)
	if t.begins_with("bytes"):
		var n3 := t.substr(5).to_int()
		return "0x" + w.substr(0, n3 * 2)
	assert(false, "Abi: unsupported type %s" % t)
	return null


static func _decode_tuple(types: Array, data: String, base: int) -> Array:
	var out: Array = []
	var pos := base
	for t in types:
		out.append(_decode_one(t, data, base, pos))
		pos += 32 if is_dynamic(t) else _static_size(t)
	return out


## Decodes return data ("0x…") as the tuple `types`. Returns [] on empty data.
static func decode(types: Array, data_hex: String) -> Array:
	var data := strip0x(data_hex)
	if data.is_empty():
		return []
	return _decode_tuple(types, data, 0)


## Decodes revert data into {selector, name, args, message}. Unknown selectors
## keep name "" and the raw data in args.
static func decode_revert(data_hex: String) -> Dictionary:
	var data := strip0x(data_hex).to_lower()
	if data.length() < 8:
		return {"selector": "", "name": "", "args": [], "message": "reverted without a reason"}
	var sel := "0x" + data.substr(0, 8)
	if not Contracts.ERRORS.has(sel):
		return {"selector": sel, "name": "", "args": [data_hex], "message": "unknown error %s" % sel}
	var spec: Array = Contracts.ERRORS[sel]
	var args := _decode_tuple(spec[1], data.substr(8), 0)
	var name: String = spec[0]
	var key := name
	var message := name
	if name == "Panic":
		var code: String = BigInt.to_hex(BigInt.from_hex(args[0]))
		key = "Panic(0x%s)" % code
		message = "Panic 0x%s (%s)" % [code, Contracts.PANIC_CODES.get(code, "unknown")]
	elif name == "Error":
		message = String(args[0])
	if Contracts.ERROR_HINTS.has(key):
		message += ": " + Contracts.ERROR_HINTS[key]
	return {"selector": sel, "name": name, "args": args, "message": message}
