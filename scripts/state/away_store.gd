class_name AwayStore
extends RefCounted
## The "while you were away" baselines, one per wallet, on this computer only
## (user://away.cfg). What a visit saw: the block, your rooms' lines read up to,
## your QINGs' Hypobar and tier, your bars, the registry (AwayDiff describes the
## shape). Nothing here leaves the machine.

const PATH := "user://away.cfg"
const SECTION := "away"


static func load_for(wallet: String, path: String = PATH) -> Dictionary:
	wallet = wallet.to_lower()
	if wallet == "":
		return {}
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return {}
	var d = c.get_value(SECTION, wallet, {})
	if not (d is Dictionary) or int(d.get("v", 0)) != AwayDiff.VERSION or int(d.get("block", -1)) <= 0:
		return {}  # damaged or from another version: start again (first visit)
	return d


static func save_for(wallet: String, base: Dictionary, path: String = PATH) -> bool:
	wallet = wallet.to_lower()
	if wallet == "" or base.is_empty() or int(base.get("block", -1)) <= 0 or base.get("preview", false):
		return false
	var c := ConfigFile.new()
	c.load(path)
	c.set_value(SECTION, wallet, base)
	return c.save(path) == OK


static func forget(wallet: String, path: String = PATH) -> void:
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return
	if c.has_section_key(SECTION, wallet.to_lower()):
		c.erase_section_key(SECTION, wallet.to_lower())
		c.save(path)
