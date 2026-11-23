class_name Acts
extends RefCounted
## Chain-verified acts (WP 7.1, plan §3.7), patterned on the site's /start.
## Each level is complete only when the chain says so, or, for "Arrive" and
## the two write-confirmed levels, a local flag set after a chain-verified
## event. Each carries its codex entry: the call it is about, then plain words.

const PROGRESS_PATH := "user://progress.cfg"

const LEVELS := [
	{"key": "arrive", "act": "Prologue", "title": "Arrive",
		"code": "—", "plain": "Walk a territory. Its ground is its own Julia set, computed from its numbers.",
		"how": "Enter any territory from the Field or the front door."},
	{"key": "forge", "act": "I · Identity", "title": "Forge",
		"code": "LAUFactory.New(string name, string symbol) → LAU", "plain": "Mint your LAU: the token that is your account in Dysnomia.",
		"how": "Front door → Enter the Void → Forge."},
	{"key": "bind", "act": "I · Identity", "title": "Bind",
		"code": "CHO.Enter(address LAU)", "plain": "Register the LAU with CHO, so the chain maps your wallet to it.",
		"how": "Enter the Void → Bind."},
	{"key": "name", "act": "I · Identity", "title": "Name",
		"code": "LAU.Username(string)", "plain": "Give it a name. Names are not unique: your Aura is what proves it is you.",
		"how": "Enter the Void → Name."},
	{"key": "wake", "act": "II · Territory", "title": "Wake",
		"code": "SEI.Start(address LAU, string name, string symbol) → YUE", "plain": "Wake your YUE, which holds your bars at every territory.",
		"how": "Enter the Void → Wake."},
	{"key": "play", "act": "II · Territory", "title": "Play",
		"code": "CHOA.Play(address LAU)", "plain": "Play mints 1 of your own YUE to your wallet; without it every reaction reverts (ZeroHoldings).",
		"how": "Enter the Void → Play."},
	{"key": "first_su", "act": "II · Territory", "title": "First Su",
		"code": "CHEON.Su(address QING) → (Charge, Hypobar, Epibar)", "plain": "React with a territory: your Hypobar there grows by its Ω, your Epibar by your own Fornax ÷ entropy, and +1 YUE.",
		"how": "At any territory, walk to a pylon and press the use key."},
	{"key": "open_door", "act": "II · Territory", "title": "Open a door",
		"code": "QING.Join(address LAU) · CHOA.Chat(address QING, string)", "plain": "Speak in a room: pay its cover if it has one (a day's admission), then write a line on chain.",
		"how": "At the Room's door, post a line (or Join a covered room)."},
	{"key": "gather", "act": "III · Power", "title": "Gather the four",
		"code": "META.Beat needs Fomalhaute + Fornax on the LAU, Tethys + qZů anywhere", "plain": "Hold the four bodies, in the right places. Missing any one, Beat panics (0x12).",
		"how": "See the identity card's four holdings and their verdicts."},
	{"key": "first_beat", "act": "III · Power", "title": "First Beat",
		"code": "META.Beat(uint256 Waat) → (Dione, Charge, Deimos, Yeo)", "plain": "The heart either beats or it doesn't. Readiness probes it from your wallet.",
		"how": "At a territory, stand at the centre of the Room; or just get READY."},
	{"key": "range", "act": "III · Power", "title": "Range",
		"code": "Yeo < Yuan(T) / Chao", "plain": "Range comes from holding a territory's own token, best on your YUE (×40). Yeo 0 = the centre cell only.",
		"how": "Readiness shows your Yeo at Phobos; the WORLD plinth shows it per territory."},
	{"key": "first_code", "act": "IV · WORLD (latent)", "title": "First Code",
		"code": "WORLD.Code(int256, int256, address Cause)", "plain": "Claim a cell around a territory. Not deployed yet: this unlocks when World watch verifies it.",
		"how": "Waits for WORLD."},
	{"key": "first_water", "act": "IV · WORLD (latent)", "title": "First water",
		"code": "WAR.Faa(address, uint256) → H2O", "plain": "Draw water where a creator stands. Not deployed yet.",
		"how": "Waits for WAR."},
]


## Pure: which levels are done. Inputs are already-read chain state.
## flags: {"arrived": bool, "door": bool, "beat": bool} (local, chain-confirmed).
static func evaluate(ps: PlayerState, rd: Readiness, bars: Dictionary, flags: Dictionary, forged: bool = false) -> Dictionary:
	var d := {}
	d["arrive"] = bool(flags.get("arrived", false))
	var has_ps := ps != null and ps.ok
	d["forge"] = forged or (has_ps and ps.has_lau())
	d["bind"] = has_ps and ps.has_lau()
	d["name"] = has_ps and ps.username != ""
	d["wake"] = has_ps and ps.has_yue()
	d["play"] = d["wake"] and rd != null and not (rd.state in ["no-account", "not-started", "blocked", "unknown"])
	d["first_su"] = not bars.is_empty()
	d["open_door"] = bool(flags.get("door", false))
	var four := rd != null
	if four:
		for k in ["fomalhaute", "fornax", "tethys", "qzu"]:
			if not (String(rd.holdings.get(k, {}).get("verdict", "missing")) in ["ok", "thin"]):
				four = false
	d["gather"] = four
	d["first_beat"] = bool(flags.get("beat", false)) or (rd != null and rd.state in ["ready", "fragile"])
	d["range"] = rd != null and not rd.beat.is_empty() and not BigInt.is_zero(BigInt.coerce(rd.beat["yeo"]))
	d["first_code"] = false
	d["first_water"] = false
	return d


## The first level not yet done ("" when all reachable ones are).
static func current(done: Dictionary) -> String:
	for l in LEVELS:
		if not done.get(l["key"], false) and not String(l["act"]).contains("latent"):
			return l["key"]
	return ""


# --- Local flags (keyed per wallet, except "arrived") --------------------------------

static func flags_for(wallet: String) -> Dictionary:
	var c := ConfigFile.new()
	c.load(PROGRESS_PATH)
	return {
		"arrived": bool(c.get_value("local", "arrived", false)),
		"door": bool(c.get_value(wallet, "door", false)) if wallet != "" else false,
		"beat": bool(c.get_value(wallet, "beat", false)) if wallet != "" else false,
	}


static func set_flag(wallet: String, flag: String) -> void:
	var c := ConfigFile.new()
	c.load(PROGRESS_PATH)
	c.set_value("local" if flag == "arrived" else wallet, flag, true)
	c.save(PROGRESS_PATH)
