class_name NetNames
extends RefCounted
## Which name to show for another player online (name tags, chat, the activity
## feed). Pure: LauNames does the chain reads, this decides.
##
## The server proves the WALLET (the sign-in signature); the name a player's game
## sends is only a claim, so it is never shown as theirs. Each machine reads the
## wallet's own LAU from the chain (CHO.GetUserTokenAddress → LAU.Username, name)
## and shows that: the Username, else the LAU's name, else the short wallet. Until
## the read lands, or if it fails, the short wallet alone (verified) is shown.
## A name tag always carries the short wallet too: "enteh · 0x1a2b…3c4d".
## Guests (no signature) are "guest": nobody can claim a name without signing.
##
## A chain record: {state: "ok"|"none"|"failed"|"reading", username, lau_name, lau_symbol, lau, block}
## ("none" = the read worked and the wallet has no LAU).


## The name for `wallet` from its chain record (the short wallet when there is none).
static func shown(wallet: String, rec: Dictionary) -> String:
	if wallet == "":
		return "guest"
	if String(rec.get("state", "")) == "ok":
		var u := NetProto.clean_text(String(rec.get("username", "")), NetProto.NAME_MAX_CHARS)
		if u != "":
			return u
		var n := NetProto.clean_text(String(rec.get("lau_name", "")), NetProto.NAME_MAX_CHARS)
		if n != "":
			return n
	return NetProto.short_wallet(wallet)


## A name tag: "guest", "0x1a2b…3c4d" (no LAU, or not read yet) or "enteh · 0x1a2b…3c4d".
static func tag(wallet: String, guest: bool, rec: Dictionary) -> String:
	if guest or wallet == "":
		return "guest"
	var short := NetProto.short_wallet(wallet)
	var nm := shown(wallet, rec)
	return short if nm == short else "%s · %s" % [nm, short]


## True when the chain has a name for this wallet (the tag is more than the address).
static func has_name(wallet: String, rec: Dictionary) -> bool:
	return wallet != "" and shown(wallet, rec) != NetProto.short_wallet(wallet)


## The head drawn for a remote player: the one their game sends (their own pick,
## or their LAU's) when it is a head this game knows; else the LAU's own
## (AvatarHeads rules, from the chain record); else a bear.
static func head(claimed: String, rec: Dictionary, known: Callable = Callable()) -> String:
	var ok_claim := claimed != "" and claimed.is_valid_identifier() and claimed.length() <= 16
	if ok_claim and (not known.is_valid() or bool(known.call(claimed))):
		return claimed
	if String(rec.get("state", "")) == "ok":
		var k := String(rec.get("head", ""))
		if k != "":
			return k
	return "bear"
