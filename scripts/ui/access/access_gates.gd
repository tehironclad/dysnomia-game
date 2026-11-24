class_name AccessGates
extends RefCounted
## What stands between the player and a thing they want to do, as numbered steps.
## Pure: a snapshot of facts (already read from the chain, the wallet relay and
## Session) → the steps, each ✓ done, → the current one, ○ still to do, or
## "checking…" / "—" when the fact is not read yet / could not be read. Nothing
## here reads anything; AccessSteps gathers the facts and draws the result.
##
## Facts (every key optional; a missing key means "not read yet"):
##   wallet     Session.wallet ("" = none connected)
##   signer     Wallet.address: the account the wallet window is linked to ("" = none)
##   relay      true when the local wallet relay (the window's server) is running
##   linked     true when the wallet window is linked to the game right now (Wallet.is_linked)
##   chain_id   the chain the wallet window reports (0 = unknown)
##   identity   "none" | "reading" | "ok" | "failed"  (+ identity_error)
##   lau, yue, banned   bools from PlayerState (meaningful when identity == "ok")
##   aff        {state: reading|ok|failed, wallet: dec wei, lau: dec wei, fee: dec wei}
##   room       {state: reading|ok|failed, cover: bool, admitted: bool, afford: bool,
##               cover_text, balance_text, block, name}       (this room's door)
##   border     the same shape, for the territory across a border
##   fair       {state: reading|ok|failed|nowallet, have: int, need: int, missing: [titles], block}
##   ready      {state: reading|ok|failed, verdict: Readiness.state, reason, block}
##   tier       {state: reading|ok|failed, have: int, need: int, have_name, need_name,
##               total: dec, block, what}
##   extra      [{id, title, explain, status, detail, action, action_label}]: a host's own
##              gates (e.g. a vehicle's unlock), appended in order
##   provider_steps  the same shape, from AccessSteps providers (inserted after the chain step)
##   override   {gate id: {status?, detail?, action?, action_label?, explain?}}: a provider's
##              better diagnosis of a gate (e.g. the payment agent's wallet check)

const CHAIN_ID := 369

## status → the glyph drawn for a step that is not the current one
const MARKS := {"done": "✓", "todo": "○", "checking": "…", "unknown": "—"}

const GOALS := {
	"identity": {"title": "Play as yourself", "gates": ["wallet", "window", "chain", "lau", "yue"]},
	"sign": {"title": "Sign with your wallet", "gates": ["wallet", "window", "chain"]},
	"room_post": {"title": "Post a line in this room", "gates": ["wallet", "window", "chain", "lau", "unbanned", "room"]},
	"void_post": {"title": "Post a line in the Void", "gates": ["wallet", "window", "chain", "lau", "unbanned"]},
	"table": {"title": "Play at this table (every move is a room line)", "gates": ["wallet", "window", "chain", "lau", "unbanned", "room"]},
	"su": {"title": "Su: react with this territory", "gates": ["wallet", "window", "chain", "lau", "yue"]},
	"beat": {"title": "Beat the Heart", "gates": ["wallet", "window", "chain", "lau", "yue", "ready"]},
	"arcade": {"title": "Buy an arcade credit (1 Ⓐ)", "gates": ["wallet", "window", "chain", "affection"]},
	"fair_ticket": {"title": "Buy a fair ticket (1 Ⓐ)", "gates": ["wallet", "window", "chain", "affection"]},
	"fair_post": {"title": "Post your score to the room", "gates": ["wallet", "window", "chain", "lau", "unbanned", "room"]},
	"rocket": {"title": "Launch the Upsilon Rocket", "gates": ["wallet", "window", "chain", "fair", "affection"]},
	"drink": {"title": "Buy a round at the bar", "gates": ["wallet", "window", "chain", "affection"]},
	"border": {"title": "Cross the border", "gates": ["wallet", "window", "chain", "lau", "unbanned", "border"]},
	"swap": {"title": "Swap on PulseX", "gates": ["wallet", "window", "chain"]},
	"yue_trade": {"title": "Trade at the YUE desk", "gates": ["wallet", "window", "chain"]},
	"building": {"title": "Open this building", "gates": ["tier"]},
	"vehicle": {"title": "Drive this vehicle", "gates": []},
}

## Each gate: the step's title, a plain explanation, and the action that does it.
const GATES := {
	"wallet": {"title": "Connect a wallet",
		"explain": "Your wallet is who you are here. Connecting opens a small wallet window in your browser (MetaMask, Rabby…); nothing is signed yet.",
		"action": "connect", "action_label": "Connect wallet"},
	"window": {"title": "Keep the wallet window open and linked",
		"explain": "Every signature goes through that window. If you closed it, or it lost the game, open it again.",
		"action": "reopen", "action_label": "Open the wallet window"},
	"chain": {"title": "Switch the wallet to PulseChain (369)",
		"explain": "Dysnomia lives on PulseChain. The wallet asks you to switch (or to add the chain) once.",
		"action": "chain", "action_label": "Switch to PulseChain"},
	"lau": {"title": "Have a LAU (Enter the Void)",
		"explain": "Your LAU is your identity contract: your name, your Soul and Aura. You forge it once, in the Void.",
		"action": "void", "action_label": "Enter the Void"},
	"unbanned": {"title": "Not banned (no WITHOUT)",
		"explain": "WITHOUT is a soulbound ban: any balance blocks room lines, Join and the Void. Nothing in the game removes it.",
		"action": "", "action_label": ""},
	"yue": {"title": "Have a YUE (SEI.Start)",
		"explain": "Your YUE is your scoreboard: it holds your Hypobar and Epibar at every territory. Wake it once at the front door.",
		"action": "yue", "action_label": "Wake my YUE"},
	"affection": {"title": "Hold Ⓐ in your wallet",
		"explain": "A ticket is AFFECTION.transfer from the wallet itself, so the wallet must hold the Ⓐ (not only your LAU).",
		"action": "move_lau", "action_label": "Move Ⓐ from my LAU"},
	"room": {"title": "Join this room (cover charge)",
		"explain": "A room with a cover admits your LAU for a day once you pay it (approve, then Join). A room with no cover is open to all.",
		"action": "join", "action_label": "Join"},
	"border": {"title": "Admitted across the border",
		"explain": "The territory beyond the field charges a cover: Join it (a day's admission for your LAU) to cross.",
		"action": "join_border", "action_label": "Join and cross"},
	"fair": {"title": "Play all seven fair games here (7/7)",
		"explain": "Each midway game's 1 Ⓐ ticket at this QING lights a lamp by the rocket; the chain's Transfer logs are the record.",
		"action": "", "action_label": ""},
	"ready": {"title": "Ready to Beat (the four holdings)",
		"explain": "META.Beat needs Fomalhaute and Fornax on your LAU, Tethys and qZů anywhere; without all four it reverts.",
		"action": "front_door", "action_label": "See my holdings"},
	"tier": {"title": "This territory's development",
		"explain": "Buildings open as a territory develops. Every Su or room line here adds Hypobar, and the total sets the tier.",
		"action": "su", "action_label": "Su here"},
}


## Pure: facts → {goal, title, steps, ready, current, summary}. Each step:
## {n, id, title, explain, status, mark, detail, action, action_label, current}.
static func resolve(goal: String, f: Dictionary) -> Dictionary:
	var g: Dictionary = GOALS.get(goal, {"title": goal, "gates": ["wallet", "window", "chain"]})
	var raw: Array = []
	var overrides: Dictionary = f.get("override", {})
	for id in g["gates"]:
		var s := gate(id, f)
		if s.is_empty():
			continue
		if overrides.has(id):
			for k in overrides[id]:
				s[k] = overrides[id][k]
		raw.append(s)
		if id == "chain":
			for ps in f.get("provider_steps", []):
				raw.append(_custom(ps))
	for e in f.get("extra", []):
		raw.append(_custom(e))
	var current := -1
	for i in raw.size():
		var s: Dictionary = raw[i]
		s["n"] = i + 1
		s["current"] = false
		s["mark"] = MARKS.get(s["status"], "—")
		if s["status"] != "done" and current < 0:
			current = i
			s["current"] = true
			s["mark"] = "→"
		if s["status"] == "checking" and String(s.get("detail", "")) == "":
			s["detail"] = "checking…"
		elif s["status"] == "unknown" and String(s.get("detail", "")) == "":
			s["detail"] = "—"
	var out := {"goal": goal, "title": String(f.get("title", g["title"])), "steps": raw, "ready": current < 0 and not raw.is_empty(), "current": current}
	out["summary"] = summary(out)
	return out


## One line for a prompt or a ticker: "Step 2 of 4: Open the wallet window." / "Ready."
static func summary(r: Dictionary) -> String:
	var steps: Array = r.get("steps", [])
	if steps.is_empty():
		return ""
	var c := int(r.get("current", -1))
	if c < 0:
		return "Ready: every step is done."
	var s: Dictionary = steps[c]
	var d := String(s.get("detail", ""))
	return "Step %d of %d: %s%s" % [c + 1, steps.size(), String(s["title"]), (" (" + d + ")") if d != "" and s["status"] != "todo" else ""]


static func _step(id: String, status: String, detail: String, action: String = "-") -> Dictionary:
	var m: Dictionary = GATES.get(id, {})
	return {"id": id, "title": String(m.get("title", id)), "explain": String(m.get("explain", "")), "status": status,
		"detail": detail, "action": String(m.get("action", "")) if action == "-" else action,
		"action_label": String(m.get("action_label", ""))}


static func _custom(e: Dictionary) -> Dictionary:
	return {"id": String(e.get("id", "custom")), "title": String(e.get("title", "")), "explain": String(e.get("explain", "")),
		"status": String(e.get("status", "unknown")), "detail": String(e.get("detail", "")),
		"action": String(e.get("action", "")), "action_label": String(e.get("action_label", ""))}


static func short(a: String) -> String:
	return a if a.length() < 12 else "%s…%s" % [a.left(6), a.right(4)]


## Pure: one gate's status from the facts. {} = not applicable (hidden).
static func gate(id: String, f: Dictionary) -> Dictionary:
	var wallet := String(f.get("wallet", ""))
	var signer := String(f.get("signer", "")).to_lower()
	match id:
		"wallet":
			if wallet != "":
				return _step(id, "done", "Connected: %s" % short(wallet))
			return _step(id, "todo", "No wallet connected.")
		"window":
			if wallet == "" and signer == "":
				return _step(id, "todo", "Opens when you connect.", "")
			if not bool(f.get("relay", false)):
				var s := _step(id, "todo", "The wallet window is closed (its local relay is not running)." if wallet != "" else "Not open yet.", "connect")
				return s
			if f.has("linked") and not bool(f["linked"]):
				return _step(id, "todo", "The relay is running but no wallet window is linked to the game: open it again.")
			if signer == "":
				return _step(id, "todo", "The window is open but no account is linked: approve the connection there, or open it again.")
			if wallet != "" and signer != wallet.to_lower():
				return _step(id, "todo", "The window is linked to %s, not %s: pick that account in your wallet." % [short(signer), short(wallet)])
			return _step(id, "done", "Linked: %s" % short(signer))
		"chain":
			if signer == "":
				return _step(id, "unknown", "— (known once the wallet window is linked)")
			var cid := int(f.get("chain_id", 0))
			if cid == CHAIN_ID:
				return _step(id, "done", "PulseChain (369)")
			if cid <= 0:
				return _step(id, "unknown", "— (the window has not reported its chain)")
			return _step(id, "todo", "The wallet is on chain %d." % cid)
		"lau", "yue", "unbanned":
			return _identity_gate(id, f)
		"affection":
			return _affection_gate(f)
		"room", "border":
			return _door_gate(id, f)
		"fair":
			var fr: Dictionary = f.get("fair", {})
			match String(fr.get("state", "reading")):
				"nowallet":
					return _step(id, "unknown", "— (your tickets are read once a wallet is connected)")
				"reading":
					return _step(id, "checking", "Reading your tickets here from the chain…")
				"failed":
					return _step(id, "unknown", "— (the ticket logs could not be read)")
			var have := int(fr.get("have", 0))
			var need := int(fr.get("need", 7))
			if have >= need:
				return _step(id, "done", "%d/%d games played here (AFFECTION Transfer logs%s)." % [have, need, _blk(fr)])
			var miss: Array = fr.get("missing", [])
			return _step(id, "todo", "%d/%d played%s. Still to play: %s." % [have, need, _blk(fr), ", ".join(PackedStringArray(miss)) if not miss.is_empty() else "—"])
		"ready":
			var rd: Dictionary = f.get("ready", {})
			var idd := _identity_gate("lau", f)
			if String(f.get("identity", "")) != "ok" or idd.get("status", "") != "done":
				return _step(id, "unknown", "— (needs your identity first)", "")
			match String(rd.get("state", "reading")):
				"reading":
					return _step(id, "checking", "Probing Su + Beat from your wallet…")
				"failed":
					return _step(id, "unknown", "— (readiness could not be read)")
			var v := String(rd.get("verdict", ""))
			if v == "ready" or v == "fragile":
				return _step(id, "done", "Ready%s%s." % [" (fragile)" if v == "fragile" else "", _blk(rd)])
			return _step(id, "todo", "%s%s" % [String(rd.get("reason", "Not ready.")), _blk(rd)])
		"tier":
			var t: Dictionary = f.get("tier", {})
			match String(t.get("state", "reading")):
				"reading":
					return _step(id, "checking", "Reading this territory's bars…")
				"failed":
					return _step(id, "unknown", "— (the bars could not be read)")
			var have_t := int(t.get("have", 0))
			var need_t := int(t.get("need", 0))
			var name_have := String(t.get("have_name", str(have_t)))
			var name_need := String(t.get("need_name", str(need_t)))
			var s2 := _step(id, "done" if have_t >= need_t else "todo", "")
			s2["title"] = "This territory is %s or more" % name_need
			s2["detail"] = ("%s (Hypobar total %s%s)." % [name_have, String(t.get("total", "—")), _blk(t)]) if have_t >= need_t \
				else "It is %s (Hypobar total %s%s); %s opens at %s." % [name_have, String(t.get("total", "—")), _blk(t), String(t.get("what", "this building")), name_need]
			return s2
	return {}


## Pure: WalletDiagnosis.run() rows ([{id, step, ok, why}], ok true/false/null) → the
## facts a provider adds: a failed check becomes the matching gate's verdict (its
## reason is the payment layer's own), and checks with no gate of their own (a
## wallet extension in that browser, PLS for gas) become steps after the chain step.
static func from_diagnosis(rows: Array, goal: String) -> Dictionary:
	var o := {}
	var extra: Array = []
	var gates: Array = GOALS.get(goal, {}).get("gates", [])
	for r in rows:
		if r.get("ok") != false:
			continue
		var why := String(r.get("why", ""))
		match String(r.get("id", "")):
			"relay":
				o["window"] = {"status": "todo", "detail": why, "action": "connect"}
			"window", "account":
				if not o.has("window"):
					o["window"] = {"status": "todo", "detail": why, "action": "reopen"}
			"provider":
				extra.append({"id": "provider", "title": "A browser wallet in that window", "status": "todo", "detail": why,
					"explain": "The wallet window must open in the browser where your wallet extension lives.",
					"action": "reopen", "action_label": "Open the wallet window"})
			"chain":
				o["chain"] = {"status": "todo", "detail": why}
			"gas":
				if gates.has("chain"):
					extra.append({"id": "gas", "title": "PLS for gas", "status": "todo", "detail": why,
						"explain": "Every signature pays a little PLS for gas. Get PLS from an exchange or a friend; a Swap Hall turns Ⓐ into PLS too.", "action": ""})
	var out := {}
	if not o.is_empty():
		out["override"] = o
	if not extra.is_empty():
		out["provider_steps"] = extra
	return out


static func _blk(d: Dictionary) -> String:
	var b := int(d.get("block", -1))
	return ", block %d" % b if b > 0 else ""


static func _identity_gate(id: String, f: Dictionary) -> Dictionary:
	var st := String(f.get("identity", "none" if String(f.get("wallet", "")) == "" else "reading"))
	if id == "unbanned":
		return _step(id, "todo", "Your wallet holds WITHOUT.", "") if st == "ok" and bool(f.get("banned", false)) else {}
	match st:
		"none":
			return _step(id, "unknown", "— (needs a wallet)", "")
		"reading":
			return _step(id, "checking", "Reading your identity from the chain…", "")
		"failed":
			return _step(id, "unknown", "— (could not read your identity: %s)" % String(f.get("identity_error", "RPC error")), "")
	if id == "lau":
		return _step(id, "done", "Your LAU: %s" % short(String(f.get("lau_addr", "")))) if bool(f.get("lau", false)) \
			else _step(id, "todo", "No LAU registered for this wallet (CHO.GetUserTokenAddress).")
	if not bool(f.get("lau", false)):
		return _step(id, "todo", "Comes after your LAU.", "")
	return _step(id, "done", "Your YUE: %s" % short(String(f.get("yue_addr", "")))) if bool(f.get("yue", false)) \
		else _step(id, "todo", "No YUE for this wallet yet (CHAN.Yan).")


static func _affection_gate(f: Dictionary) -> Dictionary:
	var a: Dictionary = f.get("aff", {})
	if String(f.get("wallet", "")) == "":
		return _step("affection", "unknown", "— (needs a wallet)", "")
	match String(a.get("state", "reading")):
		"reading":
			return _step("affection", "checking", "Reading AFFECTION.balanceOf…", "")
		"failed":
			return _step("affection", "unknown", "— (AFFECTION balance could not be read)", "")
	var fee := BigInt.from_decimal(String(a.get("fee", "1000000000000000000")))
	var w := BigInt.from_decimal(String(a.get("wallet", "0")))
	var fee_t := _tok(fee)
	if BigInt.cmp(w, fee) >= 0:
		return _step("affection", "done", "Your wallet holds %s; this costs %s." % [_tok(w), fee_t])
	var has_lau_bal := String(a.get("lau", "")) != ""
	var l := BigInt.from_decimal(String(a.get("lau", "0"))) if has_lau_bal else BigInt.zero()
	var need := BigInt.sub(fee, w)
	if has_lau_bal and BigInt.cmp(l, need) >= 0:
		return _step("affection", "todo", "Your wallet holds %s and your LAU %s; this costs %s. Moving Ⓐ is LAU.Withdraw (one approval)." % [_tok(w), _tok(l), fee_t])
	var s := _step("affection", "todo", "Your wallet holds %s%s; this costs %s. Buy Ⓐ with PLS at a Swap Hall (every territory has one, east of the Core)." % [
		_tok(w), (" and your LAU %s" % _tok(l)) if has_lau_bal else "", fee_t], "get_affection")
	s["action_label"] = "Get Ⓐ"
	return s


static func _tok(wei: PackedInt64Array) -> String:
	return "%s Ⓐ" % TokenFormat.wei_to_tokens(wei)


static func _door_gate(id: String, f: Dictionary) -> Dictionary:
	var d: Dictionary = f.get(id, {})
	var nm := String(d.get("name", ""))
	var st := String(d.get("state", "reading"))
	var s: Dictionary
	if st == "reading":
		s = _step(id, "checking", "Reading the door (CoverCharge, Admitted)…", "")
	elif st == "failed":
		s = _step(id, "unknown", "— (the door could not be read)", "")
	elif not bool(d.get("cover", false)):
		s = _step(id, "done", "No cover here: the door is open to everyone%s." % _blk(d))
	elif bool(d.get("admitted", false)):
		s = _step(id, "done", "Admitted: Admitted(LAU) is true%s." % _blk(d))
	elif String(f.get("identity", "")) != "ok" or not bool(f.get("lau", false)):
		s = _step(id, "unknown", "The cover is %s; admission is keyed to your LAU, so it is checked once you have one." % String(d.get("cover_text", "—")), "")
	elif not bool(d.get("afford", true)):
		s = _step(id, "todo", "The cover is %s and you hold %s: get more first, then Join." % [String(d.get("cover_text", "—")), String(d.get("balance_text", "—"))])
	else:
		s = _step(id, "todo", "The cover is %s: Join pays it and admits your LAU for a day%s." % [String(d.get("cover_text", "—")), _blk(d)])
	if id == "border" and nm != "":
		s["title"] = "Admitted at %s" % nm
	if id == "room" and nm != "":
		s["title"] = ("Join %s (cover charge)" % nm) if not (st == "ok" and not bool(d.get("cover", false))) else "%s: no cover charge" % nm
	return s
