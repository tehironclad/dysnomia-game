class_name TokenFormat
extends RefCounted
## Formats 18-decimal token amounts from wei (BigInt), without floats on the
## integer part: "1,234.5678", "0.000375", "12.3M".


static func group(int_str: String) -> String:
	var out := ""
	var n := int_str.length()
	for i in n:
		out += int_str[i]
		var rem := n - 1 - i
		if rem > 0 and rem % 3 == 0:
			out += ","
	return out


## wei → human string with up to `max_frac` fractional digits (trailing zeros cut).
static func wei_to_tokens(wei: PackedInt64Array, decimals: int = 18, max_frac: int = 4) -> String:
	var s := BigInt.to_decimal(wei)
	if s.length() <= decimals:
		s = s.lpad(decimals + 1, "0")
	var ip := s.substr(0, s.length() - decimals)
	var fp := s.substr(s.length() - decimals)
	if ip.length() > 6:
		# Compact: 1.23M, 45.6B, … (digits only, no float on the value).
		var d := ip.length()
		var groups := (d - 1) / 3
		if groups > 4:
			return "%s.%se%d" % [ip[0], ip.substr(1, 2), d - 1]
		var lead := d - groups * 3
		var suffix: String = ["", "K", "M", "B", "T"][groups]
		var frac := ip.substr(lead, 2).rstrip("0")
		return ip.substr(0, lead) + ("." + frac if frac != "" else "") + suffix
	if ip != "0" or max_frac == 0:
		var f := fp.substr(0, max_frac).rstrip("0")
		return group(ip) + ("." + f if f != "" else "")
	# Small amounts: show significant digits.
	var first := 0
	while first < fp.length() and fp[first] == "0":
		first += 1
	if first >= fp.length():
		return "0"
	return "0." + fp.substr(0, mini(fp.length(), first + max_frac)).rstrip("0")
