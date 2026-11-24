class_name TriviaBank
## Territory Trivia question generator. Questions are built from real data: QING names
## from assets/data/qing_names.json, this QING's live XIE charge and YUE bars, contract
## roles, the Motzkin prime, PulseChain's chain id, the fair's rides and the bar's drinks.
##
## Each question: {id, tpl, q, answers[4], correct, truth, difficulty 1-3, fact}.
## TriviaBank.session_seen keeps ids asked this session so nothing repeats until the
## whole bank has been used.

const RAMP := [1, 1, 1, 2, 2, 2, 2, 3, 3, 3]
const MAX_PER_TEMPLATE := 2

static var session_seen: Dictionary = {}


static func live_context() -> Dictionary:
	## Everything the generators need, read from the running game.
	return {
		"names": DysnomiaLore.qing_names(),
		"qing_name": GameManager.territory_name,
		"has_state": GameManager.has_territory_state,
		"charge": GameManager.territory_charge,
		"hypobar": GameManager.territory_hypobar,
		"epibar": GameManager.territory_epibar,
	}


static func build_game(ctx: Dictionary, rng: RandomNumberGenerator, ramp: Array = RAMP) -> Array:
	## A full game: questions ordered by the difficulty ramp, no repeats this session.
	var pool := all_questions(ctx, rng)
	var fresh := pool.filter(func(q): return not session_seen.has(q["id"]))
	if fresh.size() < ramp.size():
		session_seen.clear()
		fresh = pool
	var out: Array = []
	var per_tpl := {}
	for d in ramp:
		var pick := _pick(fresh, out, per_tpl, d, rng)
		if pick.is_empty():
			pick = _pick(fresh, out, per_tpl, -1, rng)
		if pick.is_empty():
			break
		out.append(pick)
		per_tpl[pick["tpl"]] = int(per_tpl.get(pick["tpl"], 0)) + 1
		session_seen[pick["id"]] = true
	return out


static func _pick(pool: Array, taken: Array, per_tpl: Dictionary, diff: int, rng: RandomNumberGenerator) -> Dictionary:
	var ids := {}
	for t in taken:
		ids[t["id"]] = true
	var cands: Array = []
	for q in pool:
		if ids.has(q["id"]) or int(per_tpl.get(q["tpl"], 0)) >= MAX_PER_TEMPLATE:
			continue
		if diff < 0 or int(q["difficulty"]) == diff:
			cands.append(q)
	if cands.is_empty():
		return {}
	return cands[rng.randi() % cands.size()]


static func all_questions(ctx: Dictionary, rng: RandomNumberGenerator) -> Array:
	var qs: Array = []
	var names: Array = ctx.get("names", [])
	var here: String = ctx.get("qing_name", "")

	# ── Chain & lore ──
	qs.append(_q("chain", "chain", "Dysnomia's contracts live on which chain?",
		"PulseChain", ["Ethereum", "Solana", "Base"], 1, "PulseChain, chain id 369."))
	qs.append(_q("chain_id", "chain", "PulseChain's chain id is…",
		"369", ["1", "943", "137"], 2, "369. (943 is the PulseChain testnet.)"))
	qs.append(_q("bears", "lore", "Dysnomia's astronauts are…",
		"Teddy bears", ["Robots", "Space cats", "Penguins"], 1, "Teddy-bear astronauts, every one a LAU."))
	qs.append(_q("motzkin", "lore", "Which number is Dysnomia's MOTZKIN_PRIME?",
		DysnomiaLore.MOTZKIN_PRIME_TEXT, _fake_motzkins(rng), 3, "953467954114363 — it seeds the terrain math."))
	qs.append(_q("map_count", "lore", "How many QINGs does the world map know about?",
		str(DysnomiaLore.QING_COUNT_ON_MAP), ["186", "369", "953"], 3, "263 QINGs, each a NewQing event on chain."))
	for k in [["0", "Pole"], ["1", "Soul"], ["2", "Aura"]]:
		var others := ["Pole", "Soul", "Aura", "Waat"].filter(func(x): return x != k[1])
		qs.append(_q("saat_" + k[0], "saat", "LAU.Saat(%s) is your…" % k[0], k[1], others, 3,
			"Saat: 0 = Pole, 1 = Soul (the CHO key), 2 = Aura."))

	# ── Contracts ──
	var cnames: Array = DysnomiaLore.CONTRACTS.keys()
	for c in cnames:
		var role: String = DysnomiaLore.CONTRACTS[c]["role"]
		var wrong := _sample(cnames.filter(func(x): return x != c), 3, rng)
		qs.append(_q("role_" + c, "contract_who", "Which contract is Dysnomia's %s?" % role, c, wrong,
			1 if c in ["LAU", "QING", "AFFECTION"] else 2, "%s — %s" % [c, DysnomiaLore.CONTRACTS[c]["flavour"]]))
		var wrong_roles: Array = []
		for o in _sample(cnames.filter(func(x): return x != c), 3, rng):
			wrong_roles.append(DysnomiaLore.CONTRACTS[o]["role"])
		qs.append(_q("what_" + c, "contract_what", "What is %s's job?" % c, role, wrong_roles,
			2 if c in ["LAU", "QING", "AFFECTION", "YUE"] else 3, "%s — %s" % [c, DysnomiaLore.CONTRACTS[c]["flavour"]]))
	qs.append(_q("next_door", "calls", "Which call finds the QING next door?",
		"MAP.GetMapQing", ["ZUO.GetQing", "HECKE.Compliment", "CHAN.Yan"], 3, "MAP.GetMapQing(lat ± 1, lon ± 1)."))
	qs.append(_q("compliment", "calls", "HECKE.Compliment() gives you a QING's…",
		"Longitude & latitude", ["Charge & omega", "Hypobar & Epibar", "Owner & name"], 3, "Its place on Eris."))
	qs.append(_q("beat_arg", "calls", "META.Beat() is fed this QING's…",
		"Waat", ["Entropy", "Cover charge", "Saat"], 3, "Beat(waat) — the Resonance Array shakes."))
	qs.append(_q("charge_src", "calls", "A QING's charge is read from…",
		"XIE.Power", ["YUE.Bar", "LAU.Saat", "AFFECTION.View"], 2, "XIE.Power: charge, omicron, omega."))

	# ── Bar menu & rides (from AttractionCatalog) ──
	var op_drinks := AttractionCatalog.DRINKS.filter(func(d): return d.get("kind", "") == AttractionCatalog.KIND_OP)
	var calls: Array = []
	for d in op_drinks:
		calls.append("AFFECTION.%s()" % str(d["op"]).capitalize())
	for d in op_drinks:
		var call := "AFFECTION.%s()" % str(d["op"]).capitalize()
		qs.append(_q("drink_" + d["id"], "drink_call", "Which AFFECTION call is the %s?" % d["name"], call,
			_sample(calls.filter(func(x): return x != call), 3, rng), 1, d["blurb"]))
		var dnames: Array = []
		for o in op_drinks:
			if o["id"] != d["id"]:
				dnames.append(o["name"])
		qs.append(_q("order_" + d["id"], "drink_order", "At the Cantina bar, %s is poured as…" % call, d["name"],
			_sample(dnames, 3, rng), 2, d["blurb"]))
	qs.append(_q("phi", "drink_trivia", "The Upsilon Fizz is served with…",
		"A twist of phi", ["A slice of pi", "Regolith ice", "Your lucky number"], 2, "AFFECTION.Upsilon(seed, phi)."))
	qs.append(_q("rocks", "drink_trivia", "What's the 'rocks' in a Rho on the Rocks?",
		"Regolith ice", ["Crystal shards", "Moon pebbles", "Frozen phi"], 2, "AFFECTION.Rho() over regolith ice."))
	var rides: Dictionary = AttractionCatalog.RIDES
	var rnames: Array = []
	for r in rides.values():
		rnames.append(r["name"])
	qs.append(_q("ride_400", "ride", "Which ride fires you 400 m straight up?", rides["rocket"]["name"],
		rnames.filter(func(x): return x != rides["rocket"]["name"]), 1, rides["rocket"]["blurb"]))
	qs.append(_q("ride_lantern", "ride", "Which ride is a slow orbit in a lantern gondola?", rides["wheel"]["name"],
		rnames.filter(func(x): return x != rides["wheel"]["name"]), 1, rides["wheel"]["blurb"]))
	qs.append(_q("drop_h", "ride", "How tall is the Pi Drop Tower?", "55 m", ["31 m", "100 m", "400 m"], 2,
		rides["drop"]["blurb"]))

	# ── Standing (QingStanding tiers) ──
	var fairs: Array = []
	for t in QingStanding.TIERS:
		fairs.append(t["fair"])
	for t in QingStanding.TIERS:
		qs.append(_q("tier_" + t["title"], "standing", "A QING at Standing '%s' has a…" % t["title"], t["fair"],
			fairs.filter(func(x): return x != t["fair"]), 2, "Standing comes from chain activity: visitors, chatter, charge, keeper's bars."))
	qs.append(_q("rocket_tier", "standing", "Which Standing tier unlocks the Upsilon Rocket?", "Capital",
		["Settlement", "Hub", "Outpost"], 2, "Capital: Upsilon Rocket + headliner nights."))

	# ── Real QINGs ──
	if names.size() >= 8:
		var used := {}
		for i in 4:
			var real: String = names[rng.randi() % names.size()]
			if used.has(real):
				continue
			used[real] = true
			var fakes: Array = []
			while fakes.size() < 3:
				var f := DysnomiaLore.fake_qing_name(rng, names)
				if not fakes.has(f):
					fakes.append(f)
			qs.append(_q("real_" + real, "real_qing", "Which of these is a real QING on PulseChain?", real, fakes, 2,
				"%s is one of the QINGs on the map." % real))
		for i in 2:
			var fake := DysnomiaLore.fake_qing_name(rng, names)
			var reals := _sample(names, 3, rng)
			qs.append(_q("fake_" + fake, "fake_qing", "Which of these QINGs does NOT exist?", fake, reals, 3,
				"%s is made up. The other three are real." % fake))
		if not here.is_empty() and names.has(here):
			qs.append(_q("here", "here", "Which QING are you drinking in right now?", here,
				_sample(names.filter(func(x): return x != here), 3, rng), 1, "Welcome to %s." % here))

	# ── This QING, live from chain ──
	if ctx.get("has_state", false):
		var hy: int = ctx.get("hypobar", 0)
		var ep: int = ctx.get("epibar", 0)
		if hy != ep:
			qs.append(_q("bars_here", "live", "In this QING right now, which YUE bar is higher?",
				"Hypobar" if hy > ep else "Epibar", ["Hypobar" if hy <= ep else "Epibar", "They're exactly equal", "Bars aren't on chain"],
				2, "Hypobar %s · Epibar %s (YUE.Bar, live)." % [_mag(hy), _mag(ep)]))
		var ch: int = ctx.get("charge", 0)
		if ch > 0:
			var e := int(floor(log(float(ch)) / log(10.0)))
			var opts: Array = [e]
			for off in [-6, -3, 3, 6, 9, -9]:
				if opts.size() >= 4:
					break
				if e + off >= 0:
					opts.append(e + off)
			if opts.size() == 4:
				var labels: Array = []
				for o in opts:
					labels.append(_bucket(o))
				qs.append(_q("charge_here", "live", "This QING's XIE charge is in which range?", labels[0],
					labels.slice(1), 3, "Charge %s, read live from XIE.Power." % _mag(ch)))
	return qs


static func _q(id: String, tpl: String, text: String, truth: String, wrong: Array, difficulty: int, fact: String) -> Dictionary:
	var answers: Array = [truth]
	for w in wrong:
		if answers.size() >= 4:
			break
		if not answers.has(str(w)):
			answers.append(str(w))
	answers.shuffle()
	return {"id": id, "tpl": tpl, "q": text, "answers": answers, "correct": answers.find(truth),
		"truth": truth, "difficulty": difficulty, "fact": fact}


static func shuffle_with(q: Dictionary, rng: RandomNumberGenerator) -> void:
	## Deterministic re-shuffle of a question's answers (keeps `correct` right).
	var a: Array = q["answers"]
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	q["correct"] = a.find(q["truth"])


static func _sample(arr: Array, n: int, rng: RandomNumberGenerator) -> Array:
	var c := arr.duplicate()
	var out: Array = []
	while out.size() < n and not c.is_empty():
		out.append(c.pop_at(rng.randi() % c.size()))
	return out


static func _fake_motzkins(rng: RandomNumberGenerator) -> Array:
	var real := DysnomiaLore.MOTZKIN_PRIME_TEXT
	var out: Array = []
	while out.size() < 3:
		var s := real
		for _k in 2:
			var i := rng.randi_range(1, s.length() - 1)
			var d := str((int(s[i]) + rng.randi_range(1, 8)) % 10)
			s = s.substr(0, i) + d + s.substr(i + 1)
		if s != real and not out.has(s):
			out.append(s)
	return out


static func _bucket(exp10: int) -> String:
	var names := {0: "1", 3: "1 thousand", 6: "1 million", 9: "1 billion", 12: "1 trillion", 15: "1 quadrillion", 18: "1 quintillion"}
	var base := (exp10 / 3) * 3
	var lead := int(pow(10, exp10 - base))
	var unit: String = names.get(base, "1e%d" % base)
	if base == 0:
		return "%d – %d" % [lead, lead * 10 - 1]
	return "%d – %d %s" % [lead, lead * 10, unit.substr(2)]


static func _mag(v: int) -> String:
	if v < 1000:
		return str(v)
	var e := int(floor(log(float(v)) / log(10.0)))
	return "%.2fe%d" % [float(v) / pow(10.0, e), e]
