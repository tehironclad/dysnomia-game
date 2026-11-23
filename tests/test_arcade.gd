extends TestCase
## The arcade: the catalog, the three games (deterministic from a seed, one game_over per credit) and
## the Folklore CPU against goldens from the site's real JS (entropy-ai-pulse lib/folklore-cpu.js).
## Goldens were made with node from that file: sha256 prefixes of the framebuffer / whole memory.

const CART_DIR := "res://assets/arcade/cartridges/"

# id → [steps run, framebuffer sha256 prefix, lit px, A, X, Y, SP, P, PC, steps, halted, bad]
# Sprites run to their bare RTS (200,000-step cap); games run 300,000 steps (as build.js does).
const CART_GOLDENS := {
	"corner": [200000, "898b7737d69e351e", 1, 128, 0, 0, 253, 164, 518, 3, true, false],
	"frame": [200000, "4506fdb5c0d47803", 252, 255, 0, 0, 253, 164, 1213, 281, true, false],
	"entropy-e": [200000, "7d1bab022b0da966", 415, 255, 0, 0, 253, 164, 1588, 431, true, false],
	"bolt": [200000, "cef7d200a9695c65", 1025, 248, 0, 0, 253, 164, 1363, 341, true, false],
	"heart": [200000, "1bc38267f0a59381", 1019, 192, 0, 0, 253, 164, 1378, 347, true, false],
	"target": [200000, "7bd0a61b49802b01", 737, 128, 0, 0, 253, 164, 1973, 585, true, false],
	"sweep": [300000, "be58a287f7371f38", 64, 255, 19, 66, 251, 36, 569, 300000, false, false],
	"bounce": [300000, "59c1f291a601b268", 316, 255, 12, 84, 251, 36, 682, 300000, false, false],
	"odometer": [300000, "0b533a6c54d7debc", 300, 16, 4, 7, 253, 37, 528, 300000, false, false],
	"static": [300000, "c3da0cdc0e54be80", 250, 210, 1, 0, 253, 164, 540, 300000, false, false],
}
# The same game cartridges after only 5,000 steps: [fb sha prefix, A, X, Y, SP, P, PC].
const CART_GOLDENS_5K := {
	"sweep": ["ee9c9b6861ea75ef", 255, 15, 80, 251, 36, 569],
	"bounce": ["d376fab88f7b3789", 255, 17, 155, 251, 164, 681],
	"odometer": ["70b7c392713aa88b", 57, 4, 7, 253, 37, 553],
	"static": ["4da83c7d8267bd45", 0, 0, 0, 253, 38, 543],
}


# ── helpers ──────────────────────────────────────────────────────────────────


static func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


static func _xs(x: int) -> int:
	x = (x ^ (x << 13)) & 0xFFFFFFFF
	x ^= x >> 17
	return (x ^ (x << 5)) & 0xFFFFFFFF


static func _reg_bytes(c: FK6502) -> PackedByteArray:
	return PackedByteArray([
		c.A, c.X, c.Y, c.SP, c.get_p(), c.PC & 255, c.PC >> 8, c.steps & 255, (c.steps >> 8) & 255,
		(c.steps >> 16) & 255, (c.steps >> 24) & 255, 1 if c.halted else 0, 1 if c.bad else 0, c.depth & 255,
	])


func _cart_bytes(id: String) -> PackedByteArray:
	var b := FileAccess.get_file_as_bytes(CART_DIR + id + ".fkc")
	check(not b.is_empty(), "%s.fkc readable" % id)
	return b


func _new_game(path: String) -> ArcadeGame:
	var g = load(path).new()
	return g


## Runs a game for n steps with a scripted input pattern; returns [score, game_over count].
func _play(path: String, seed: int, n: int, pattern: Callable) -> Array:
	var g := _new_game(path)
	var ends := [0]
	g.game_over.connect(func(_s): ends[0] += 1)
	g.start(seed)
	for i in n:
		g.scripted_input = pattern.call(i)
		g.step(ArcadeGame.DT)
	var out := [g.score, ends[0], g.lives]
	g.free()
	return out


static func _pattern(i: int) -> int:
	# A deterministic, busy input pattern: weave left/right/up/down, tap fire.
	var bits := 0
	match (i / 37) % 4:
		0:
			bits |= ArcadeGame.IN_LEFT | ArcadeGame.IN_UP
		1:
			bits |= ArcadeGame.IN_RIGHT
		2:
			bits |= ArcadeGame.IN_DOWN | ArcadeGame.IN_RIGHT
		3:
			bits |= ArcadeGame.IN_LEFT
	if (i % 23) < 9:
		bits |= ArcadeGame.IN_FIRE
	return bits


static func _pattern_hold(i: int) -> int:
	return ArcadeGame.IN_FIRE if i % 61 < 28 else 0


# ── the Folklore CPU ─────────────────────────────────────────────────────────


func test_cpu_opcode_table() -> void:
	eq(FK6502.official_opcodes().size(), 151, "151 official NMOS opcodes")
	check(not FK6502.is_official(0x02), "$02 is unofficial")
	check(FK6502.is_official(0x6C), "JMP (ind)")


func test_cpu_worked_example() -> void:
	# Spec §8: LDA #$80 ; STA $E000 ; RTS in an FKC header → one lit pixel, top-left.
	var fkc := PackedByteArray([0x46, 0x4B, 0x43, 0x01, 0x01, 0x01, 0x00, 0x02, 0x00, 0x02, 0x06, 0x00, 0x00, 0xE0, 0x01, 0x01, 0xA9, 0x80, 0x8D, 0x00, 0xE0, 0x60])
	var cart := FK6502.parse_cartridge(fkc)
	eq(cart["type"], 1)
	eq(cart["code_len"], 6)
	eq(cart["fb_base"], 0xE000)
	var cpu := FK6502.execute(fkc)
	eq(cpu.mem[0xE000], 0x80)
	eq(cpu.steps, 3)
	check(cpu.halted and not cpu.bad, "bare RTS ends the cartridge")
	eq(cpu.lit_count(), 1)
	eq(cpu.disassemble(0x0202), "STA $E000")
	# Legacy bare opcodes (no header) load at $0200 too.
	var legacy := FK6502.execute(fkc.slice(16))
	eq(legacy.mem[0xE000], 0x80)


func test_cpu_bad_and_brk() -> void:
	var cpu := FK6502.execute(PackedByteArray([0xA9, 0x01, 0x02]))
	check(cpu.halted and cpu.bad, "unofficial opcode stops with bad")
	eq(cpu.steps, 2)
	cpu = FK6502.execute(PackedByteArray([0xA9, 0x01, 0x00, 0xA9, 0x02]))
	check(cpu.halted and not cpu.bad, "BRK ends the cartridge")
	eq(cpu.A, 1)


func test_cpu_cartridge_goldens() -> void:
	var manifest = load_json(CART_DIR + "manifest.json")
	eq(manifest["cartridges"].size(), CART_GOLDENS.size(), "every manifest cartridge has a golden")
	for entry in manifest["cartridges"]:
		var id: String = entry["id"]
		var g: Array = CART_GOLDENS[id]
		var cart := FK6502.parse_cartridge(_cart_bytes(id))
		eq(cart["code_len"], int(entry["codeLen"]), id + " codeLen")
		eq(int(cart["type"]), 2 if entry["type"] == "game" else 1, id + " type")
		var cpu := FK6502.new()
		cpu.load_cartridge(cart)
		cpu.run(g[0])
		eq(_sha(cpu.framebuffer()).substr(0, 16), g[1], id + " framebuffer")
		eq(cpu.lit_count(), g[2], id + " lit")
		eq(cpu.lit_count(), int(entry["litPx"]), id + " lit vs manifest")
		eq([cpu.A, cpu.X, cpu.Y, cpu.SP, cpu.get_p(), cpu.PC, cpu.steps, cpu.halted, cpu.bad], g.slice(3), id + " registers")


func test_cpu_game_carts_short_run() -> void:
	for id in CART_GOLDENS_5K:
		var g: Array = CART_GOLDENS_5K[id]
		var cpu := FK6502.new()
		cpu.load_cartridge(FK6502.parse_cartridge(_cart_bytes(id)))
		# In uneven bursts, as the player steps it per frame.
		var sizes := [1, 7, 500, 3000, 1492]
		for s in sizes:
			cpu.burst(s)
		eq(cpu.steps, 5000)
		eq(_sha(cpu.framebuffer()).substr(0, 16), g[0], id + " framebuffer at 5k")
		eq([cpu.A, cpu.X, cpu.Y, cpu.SP, cpu.get_p(), cpu.PC], g.slice(1), id + " registers at 5k")


func test_cpu_fuzz_strict() -> void:
	# Memory filled with random official opcodes, plain-hardware BRK/RTS, 3,000 steps per seed:
	# every instruction, flag and decimal-mode path, compared with the JS byte for byte.
	var ops := FK6502.official_opcodes()
	var acc := PackedByteArray()
	for seed in range(1, 17):
		var cpu := FK6502.new()
		cpu.strict = true
		var x := seed
		for i in 65536:
			x = _xs(x)
			cpu.mem[i] = ops[x % ops.size()]
		cpu.reset(0x0200)
		cpu.run(3000)
		acc.append_array(_reg_bytes(cpu))
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		h.update(cpu.mem)
		acc.append_array(h.finish().slice(0, 8))
	eq(_sha(acc).substr(0, 16), "977312ada0fd878c")


func test_cpu_fuzz_raw_bytes() -> void:
	# Raw random memory, cartridge conventions: runs end on RTS/BRK or an unofficial opcode.
	var acc := PackedByteArray()
	for seed in range(1, 65):
		var cpu := FK6502.new()
		var x := (seed * 2654435761) & 0xFFFFFFFF
		for i in 65536:
			x = _xs(x)
			cpu.mem[i] = x & 255
		cpu.reset(0x0200)
		cpu.run(20000)
		acc.append_array(_reg_bytes(cpu))
	eq(_sha(acc).substr(0, 16), "4173cdfbd845cd49")


func test_cpu_adc_sbc_binary_and_decimal() -> void:
	var acc := PackedByteArray()
	var cpu := FK6502.new()
	for op in [0x69, 0xE9]:
		for d in 2:
			for c in 2:
				for a in range(0, 256, 5):
					for b in range(0, 256, 3):
						cpu.mem[0x200] = op
						cpu.mem[0x201] = b
						cpu.reset(0x200)
						cpu.A = a
						cpu.C = c
						cpu.D = d
						cpu.step()
						acc.append(cpu.A)
						acc.append(cpu.get_p())
	eq(acc.size(), 71552)
	eq(_sha(acc).substr(0, 16), "58147f8c93abe1a3")


# ── the catalog and the games ────────────────────────────────────────────────


func test_catalog_entries_load() -> void:
	var entries := ArcadeCatalog.games()
	check(entries.size() >= 3 + 10, "three games plus the ten cartridges")
	var ids := {}
	var games := 0
	for e in entries:
		check(not ids.has(e["id"]), "unique id " + e["id"])
		ids[e["id"]] = true
		check(e["title"] != "" and e["blurb"] != "", e["id"] + " has a title and blurb")
		check(e["kind"] in ["game", "cartridge"], e["id"] + " kind")
		var s = load(e["script"])
		check(s is GDScript and s.can_instantiate(), e["id"] + " script loads")
		var g = s.new()
		check(g is ArcadeGame, e["id"] + " is an ArcadeGame")
		if e["kind"] == "game":
			games += 1
			check(e["playable"], e["id"] + " playable")
			eq(g.title(), e["title"], e["id"] + " title matches")
		else:
			check(e["cart"].begins_with("res://assets/arcade/cartridges/"), e["id"] + " cart path")
			check(g.load_cart(e["cart"]), e["id"] + " cart loads")
			eq(g.title(), e["title"], e["id"] + " title from the manifest")
			eq(e["playable"], g.is_game(), e["id"] + " playable only for game cartridges")
		g.attract()
		for i in 30:
			g.step(ArcadeGame.DT)
		check(g.attract_mode and not g.playing, e["id"] + " attract runs")
		g.free()
	eq(games, 3)
	check(not ArcadeCatalog.find("bar_raiser").is_empty(), "find by id")
	check(ArcadeCatalog.playable().size() == 3 + 4, "3 games + 4 game cartridges are playable")


func test_games_deterministic() -> void:
	for e in ArcadeCatalog.GAMES:
		# Bar Raiser is one button: hold for 28 frames out of every 61.
		var p: Callable = _pattern_hold if e["id"] == "bar_raiser" else _pattern
		var a := _play(e["script"], 1234, 2400, p)
		var b := _play(e["script"], 1234, 2400, p)
		eq(a, b, e["id"] + " same seed + inputs → same run")
		check(a[0] > 0, e["id"] + " scores something")
		var c := _play(e["script"], 99, 2400, p)
		eq(c, _play(e["script"], 99, 2400, p), e["id"] + " another seed, also repeatable")


func test_game_over_once_on_loss() -> void:
	for e in ArcadeCatalog.GAMES:
		var g := _new_game(e["script"])
		var ends := []
		g.game_over.connect(func(s): ends.append(s))
		g.start(7)
		g.scripted_input = 0  # nobody at the controls
		var n := 0
		while g.playing and n < 60 * 600:
			g.step(ArcadeGame.DT)
			n += 1
		check(not g.playing and g.over, e["id"] + " an idle run is lost (after %d steps)" % n)
		eq(ends.size(), 1, e["id"] + " game_over once")
		if ends.size() == 1:
			eq(ends[0], g.score, e["id"] + " game_over carries the final score")
		for i in 120:
			g.step(ArcadeGame.DT)
		g.end_game()
		g.lose_life()
		eq(ends.size(), 1, e["id"] + " still once after more steps")
		# A new credit is a fresh run.
		g.start(8)
		check(g.playing and not g.over and g.lives == 3 and g.score == 0, e["id"] + " restarts")
		g.free()


func test_attract_never_ends() -> void:
	for e in ArcadeCatalog.GAMES:
		var g := _new_game(e["script"])
		var ends := [0]
		g.game_over.connect(func(_s): ends[0] += 1)
		g.attract()
		for i in 60 * 120:
			g.step(ArcadeGame.DT)
		eq(ends[0], 0, e["id"] + " attract emits nothing")
		check(g.attract_mode, e["id"] + " still in attract")
		g.free()


func test_cart_player() -> void:
	var g = load("res://scripts/arcade/folklore_cart.gd").new()
	check(not g.load_cart(CART_DIR + "missing.fkc"), "a missing cart fails")
	check(g.load_cart(CART_DIR + "bounce.fkc"), "bounce loads")
	check(g.is_game(), "bounce is a game cartridge")
	g.frame_budget_usec = 0
	var ends := []
	g.game_over.connect(func(s): ends.append(s))
	g.start(3)
	g.scripted_input = ArcadeGame.IN_FIRE | ArcadeGame.IN_LEFT
	for i in 100:
		g.step(ArcadeGame.DT)
	eq(g.cpu.steps, 100 * g.STEPS_PER_FRAME, "a fixed instruction budget per frame")
	eq(g.cpu.mem[g.IO_INPUT], ArcadeGame.IN_FIRE | ArcadeGame.IN_LEFT, "input register")
	eq(g.cpu.mem[g.IO_FRAME], 99, "frame counter")
	eq(g.cpu.mem[g.IO_SEED], 3, "seed register")
	check(g.lit > 0, "the court is drawn")
	g.time_limit = 2.0
	for i in 30:
		g.step(ArcadeGame.DT)
	eq(ends.size(), 1, "a game cartridge credit ends at its time limit")
	g.free()
	# A sprite draws itself in during attract, then holds the finished picture.
	var s = load("res://scripts/arcade/folklore_cart.gd").new()
	check(s.load_cart(CART_DIR + "heart.fkc"), "heart loads")
	check(s.is_sprite(), "heart is a sprite")
	s.attract()
	s.step(ArcadeGame.DT)
	check(s.lit < 1019, "drawing in")
	for i in 120:
		s.step(ArcadeGame.DT)
	eq(s.lit, 1019, "the whole heart")
	check(s.cpu.halted and not s.cpu.bad, "ended on its RTS")
	s.free()
