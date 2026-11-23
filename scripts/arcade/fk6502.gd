class_name FK6502
extends RefCounted
## The Folklore CPU: a full NMOS 6502 that runs `.fkc` cartridges.
##
## A faithful GDScript port of entropy-ai-pulse `lib/folklore-cpu.js` (Maria's Folklore runtime; spec:
## `docs/FOLKLORE_CARTRIDGE_SPEC.md` there). All 151 official opcodes, flags, the stack and decimal
## mode, plus the two cartridge conventions:
##   - RTS with no JSR to return to ends the cartridge (sprite loaders end with a bare RTS), and BRK
##     ends it too;
##   - an unofficial opcode stops the run and sets `bad`, rather than guessing.
## `strict = true` gives plain-hardware BRK and RTS (as in the JS; used by the conformance test).
##
## Memory is one 64 KiB PackedByteArray. `burst(n)` is the hot loop: registers live in locals and the
## opcode is decoded from two lookup tables, so it costs a few microseconds per instruction.

const FB_W := 64
const FB_H := 64
const FB_BYTES := 512  # (64 / 8) × 64
const FB_BASE := 0xE000
const DEFAULT_COLOR := Color("#00f2fe")

# Addressing modes.
const IMP := 0
const ACC := 1
const IMM := 2
const ZP := 3
const ZPX := 4
const ZPY := 5
const ABS := 6
const ABX := 7
const ABY := 8
const IND := 9
const IZX := 10
const IZY := 11
const REL := 12
const MODE_NAMES := ["imp", "acc", "imm", "zp", "zpx", "zpy", "abs", "abx", "aby", "ind", "izx", "izy", "rel"]

# Mnemonics, numbered roughly by how often cartridges execute them (the dispatch `match` tests them in
# this order).
const LDA := 0
const STA := 1
const BNE := 2
const DEY := 3
const DEX := 4
const BPL := 5
const CLC := 6
const ADC := 7
const JMP := 8
const JSR := 9
const RTS := 10
const LDY := 11
const LDX := 12
const CMP := 13
const BEQ := 14
const INC := 15
const EOR := 16
const ORA := 17
const AND := 18
const LSR := 19
const ASL := 20
const ROR := 21
const ROL := 22
const BCC := 23
const BCS := 24
const TAX := 25
const INX := 26
const INY := 27
const SEC := 28
const SBC := 29
const STX := 30
const STY := 31
const CPX := 32
const CPY := 33
const BMI := 34
const BVC := 35
const BVS := 36
const DEC := 37
const BIT := 38
const TAY := 39
const TXA := 40
const TYA := 41
const TSX := 42
const TXS := 43
const PHA := 44
const PLA := 45
const PHP := 46
const PLP := 47
const CLD := 48
const SED := 49
const CLI := 50
const SEI := 51
const CLV := 52
const NOP := 53
const RTI := 54
const BRK := 55
const MNEMONICS := [
	"LDA", "STA", "BNE", "DEY", "DEX", "BPL", "CLC", "ADC", "JMP", "JSR", "RTS", "LDY", "LDX", "CMP",
	"BEQ", "INC", "EOR", "ORA", "AND", "LSR", "ASL", "ROR", "ROL", "BCC", "BCS", "TAX", "INX", "INY",
	"SEC", "SBC", "STX", "STY", "CPX", "CPY", "BMI", "BVC", "BVS", "DEC", "BIT", "TAY", "TXA", "TYA",
	"TSX", "TXS", "PHA", "PLA", "PHP", "PLP", "CLD", "SED", "CLI", "SEI", "CLV", "NOP", "RTI", "BRK",
]

# The opcode table, in the JS's own notation (folklore-cpu.js `def(...)` lines).
const DEFS := {
	"ADC": "69:imm 65:zp 75:zpx 6D:abs 7D:abx 79:aby 61:izx 71:izy",
	"AND": "29:imm 25:zp 35:zpx 2D:abs 3D:abx 39:aby 21:izx 31:izy",
	"ASL": "0A:acc 06:zp 16:zpx 0E:abs 1E:abx",
	"BCC": "90:rel", "BCS": "B0:rel", "BEQ": "F0:rel", "BMI": "30:rel",
	"BNE": "D0:rel", "BPL": "10:rel", "BVC": "50:rel", "BVS": "70:rel",
	"BIT": "24:zp 2C:abs",
	"BRK": "00:imp", "CLC": "18:imp", "CLD": "D8:imp", "CLI": "58:imp", "CLV": "B8:imp",
	"CMP": "C9:imm C5:zp D5:zpx CD:abs DD:abx D9:aby C1:izx D1:izy",
	"CPX": "E0:imm E4:zp EC:abs", "CPY": "C0:imm C4:zp CC:abs",
	"DEC": "C6:zp D6:zpx CE:abs DE:abx", "DEX": "CA:imp", "DEY": "88:imp",
	"EOR": "49:imm 45:zp 55:zpx 4D:abs 5D:abx 59:aby 41:izx 51:izy",
	"INC": "E6:zp F6:zpx EE:abs FE:abx", "INX": "E8:imp", "INY": "C8:imp",
	"JMP": "4C:abs 6C:ind", "JSR": "20:abs",
	"LDA": "A9:imm A5:zp B5:zpx AD:abs BD:abx B9:aby A1:izx B1:izy",
	"LDX": "A2:imm A6:zp B6:zpy AE:abs BE:aby",
	"LDY": "A0:imm A4:zp B4:zpx AC:abs BC:abx",
	"LSR": "4A:acc 46:zp 56:zpx 4E:abs 5E:abx",
	"NOP": "EA:imp",
	"ORA": "09:imm 05:zp 15:zpx 0D:abs 1D:abx 19:aby 01:izx 11:izy",
	"PHA": "48:imp", "PHP": "08:imp", "PLA": "68:imp", "PLP": "28:imp",
	"ROL": "2A:acc 26:zp 36:zpx 2E:abs 3E:abx", "ROR": "6A:acc 66:zp 76:zpx 6E:abs 7E:abx",
	"RTI": "40:imp", "RTS": "60:imp",
	"SBC": "E9:imm E5:zp F5:zpx ED:abs FD:abx F9:aby E1:izx F1:izy",
	"SEC": "38:imp", "SED": "F8:imp", "SEI": "78:imp",
	"STA": "85:zp 95:zpx 8D:abs 9D:abx 99:aby 81:izx 91:izy",
	"STX": "86:zp 96:zpy 8E:abs", "STY": "84:zp 94:zpx 8C:abs",
	"TAX": "AA:imp", "TAY": "A8:imp", "TSX": "BA:imp", "TXA": "8A:imp", "TXS": "9A:imp", "TYA": "98:imp",
}
const SIZE_BY_MODE := [1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 2, 2, 2]

static var _mn := PackedInt32Array()  # opcode → mnemonic id, or -1 (unofficial)
static var _mode := PackedInt32Array()  # opcode → addressing mode
static var _popcount := PackedInt32Array()
static var _l8 := PackedByteArray()  # byte → its 8 pixels as L8 (0 / 255), 8 bytes per entry

var mem := PackedByteArray()
var strict := false
var A := 0
var X := 0
var Y := 0
var SP := 0xFD
var C := 0
var Z := 0
var I := 1
var D := 0
var V := 0
var N := 0
var PC := 0x0200
var halted := false
var bad := false
var steps := 0
var depth := 0


static func _static_init() -> void:
	_mn.resize(256)
	_mode.resize(256)
	_mn.fill(-1)
	for name in DEFS:
		var id := MNEMONICS.find(name)
		for part in String(DEFS[name]).split(" "):
			var kv := part.split(":")
			var op := kv[0].hex_to_int()
			_mn[op] = id
			_mode[op] = MODE_NAMES.find(kv[1])
	_popcount.resize(256)
	_l8.resize(256 * 8)
	for b in 256:
		var c := 0
		for k in 8:
			c += (b >> k) & 1
			_l8[b * 8 + k] = 255 if b & (1 << (7 - k)) else 0
		_popcount[b] = c


## The 151 official opcodes, ascending.
static func official_opcodes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for op in 256:
		if _mn[op] >= 0:
			out.append(op)
	return out


static func is_official(op: int) -> bool:
	return _mn[op & 0xFF] >= 0


func _init() -> void:
	mem.resize(0x10000)
	reset(0x0200)


func reset(pc: int) -> void:
	A = 0
	X = 0
	Y = 0
	SP = 0xFD
	C = 0
	Z = 0
	I = 1
	D = 0
	V = 0
	N = 0
	PC = pc & 0xFFFF
	halted = false
	steps = 0
	bad = false
	depth = 0


func get_p() -> int:
	return (N << 7) | (V << 6) | 0x20 | (D << 3) | (I << 2) | (Z << 1) | C


func set_p(p: int) -> void:
	N = (p >> 7) & 1
	V = (p >> 6) & 1
	D = (p >> 3) & 1
	I = (p >> 2) & 1
	Z = (p >> 1) & 1
	C = p & 1


## Executes one instruction. Returns the address it ran from, or -1 when already halted.
func step() -> int:
	if halted:
		return -1
	var pc := PC
	burst(1)
	return pc


## Runs until halted or `max_steps` total instructions (the JS `run`, without the trace).
func run(max_steps: int = 200000) -> int:
	if steps < max_steps:
		burst(max_steps - steps)
	return steps


## Runs up to `n` more instructions; returns how many ran (the JS `burst`).
func burst(n: int) -> int:
	if halted or n <= 0:
		return 0
	var m := mem
	var mnt := _mn
	var mdt := _mode
	var a := A
	var x := X
	var y := Y
	var sp := SP
	var pc := PC
	var c := C
	var z := Z
	var v := V
	var nf := N
	var d := D
	var dep := depth
	var ran := 0
	while ran < n:
		var op: int = m[pc]
		pc = (pc + 1) & 0xFFFF
		ran += 1
		var mn: int = mnt[op]
		if mn < 0:
			halted = true
			bad = true
			break
		var mode: int = mdt[op]
		var addr := 0
		var b := 0
		match mode:
			IMM:
				addr = pc
				pc = (pc + 1) & 0xFFFF
			ABS:
				addr = m[pc] | (m[(pc + 1) & 0xFFFF] << 8)
				pc = (pc + 2) & 0xFFFF
			ZP:
				addr = m[pc]
				pc = (pc + 1) & 0xFFFF
			REL:
				b = m[pc]
				pc = (pc + 1) & 0xFFFF
				addr = (pc + (b - 256 if b & 0x80 else b)) & 0xFFFF
			IZY:
				b = m[pc]
				pc = (pc + 1) & 0xFFFF
				addr = ((m[b] | (m[(b + 1) & 0xFF] << 8)) + y) & 0xFFFF
			ABX:
				addr = ((m[pc] | (m[(pc + 1) & 0xFFFF] << 8)) + x) & 0xFFFF
				pc = (pc + 2) & 0xFFFF
			ZPX:
				addr = (m[pc] + x) & 0xFF
				pc = (pc + 1) & 0xFFFF
			ABY:
				addr = ((m[pc] | (m[(pc + 1) & 0xFFFF] << 8)) + y) & 0xFFFF
				pc = (pc + 2) & 0xFFFF
			IND:
				b = m[pc] | (m[(pc + 1) & 0xFFFF] << 8)
				pc = (pc + 2) & 0xFFFF
				addr = m[b] | (m[(b & 0xFF00) | ((b + 1) & 0xFF)] << 8)  # the 6502's page-wrap bug, kept
			IZX:
				b = (m[pc] + x) & 0xFF
				pc = (pc + 1) & 0xFFFF
				addr = m[b] | (m[(b + 1) & 0xFF] << 8)
			ZPY:
				addr = (m[pc] + y) & 0xFF
				pc = (pc + 1) & 0xFFFF
		var t := 0
		match mn:
			LDA:
				a = m[addr]
				z = 1 if a == 0 else 0
				nf = a >> 7
			STA:
				m[addr] = a
			BNE:
				if z == 0:
					pc = addr
			DEY:
				y = (y - 1) & 0xFF
				z = 1 if y == 0 else 0
				nf = y >> 7
			DEX:
				x = (x - 1) & 0xFF
				z = 1 if x == 0 else 0
				nf = x >> 7
			BPL:
				if nf == 0:
					pc = addr
			CLC:
				c = 0
			ADC:
				b = m[addr]
				if d:
					t = (a >> 4) * 10 + (a & 15) + (b >> 4) * 10 + (b & 15) + c
					c = 1 if t > 99 else 0
					t %= 100
					a = ((int(t / 10.0) << 4) | (t % 10)) & 0xFF
				else:
					t = a + b + c
					v = 1 if (~(a ^ b) & (a ^ t) & 0x80) != 0 else 0
					c = 1 if t > 0xFF else 0
					a = t & 0xFF
				z = 1 if a == 0 else 0
				nf = a >> 7
			JMP:
				pc = addr
			JSR:
				t = (pc - 1) & 0xFFFF
				m[0x100 | sp] = t >> 8
				sp = (sp - 1) & 0xFF
				m[0x100 | sp] = t & 0xFF
				sp = (sp - 1) & 0xFF
				pc = addr
				dep += 1
			RTS:
				if dep <= 0 and not strict:
					halted = true  # nothing to return to: the cartridge is done
					break
				sp = (sp + 1) & 0xFF
				t = m[0x100 | sp]
				sp = (sp + 1) & 0xFF
				t |= m[0x100 | sp] << 8
				pc = (t + 1) & 0xFFFF
				dep -= 1
			LDY:
				y = m[addr]
				z = 1 if y == 0 else 0
				nf = y >> 7
			LDX:
				x = m[addr]
				z = 1 if x == 0 else 0
				nf = x >> 7
			CMP:
				b = m[addr]
				t = (a - b) & 0xFF
				c = 1 if a >= b else 0
				z = 1 if t == 0 else 0
				nf = t >> 7
			BEQ:
				if z != 0:
					pc = addr
			INC:
				t = (m[addr] + 1) & 0xFF
				m[addr] = t
				z = 1 if t == 0 else 0
				nf = t >> 7
			EOR:
				a = a ^ m[addr]
				z = 1 if a == 0 else 0
				nf = a >> 7
			ORA:
				a = a | m[addr]
				z = 1 if a == 0 else 0
				nf = a >> 7
			AND:
				a = a & m[addr]
				z = 1 if a == 0 else 0
				nf = a >> 7
			LSR:
				b = a if mode == ACC else m[addr]
				c = b & 1
				t = b >> 1
				if mode == ACC:
					a = t
				else:
					m[addr] = t
				z = 1 if t == 0 else 0
				nf = 0
			ASL:
				b = a if mode == ACC else m[addr]
				c = (b >> 7) & 1
				t = (b << 1) & 0xFF
				if mode == ACC:
					a = t
				else:
					m[addr] = t
				z = 1 if t == 0 else 0
				nf = t >> 7
			ROR:
				b = a if mode == ACC else m[addr]
				t = ((b >> 1) | (c << 7)) & 0xFF
				c = b & 1
				if mode == ACC:
					a = t
				else:
					m[addr] = t
				z = 1 if t == 0 else 0
				nf = t >> 7
			ROL:
				b = a if mode == ACC else m[addr]
				t = ((b << 1) | c) & 0xFF
				c = (b >> 7) & 1
				if mode == ACC:
					a = t
				else:
					m[addr] = t
				z = 1 if t == 0 else 0
				nf = t >> 7
			BCC:
				if c == 0:
					pc = addr
			BCS:
				if c != 0:
					pc = addr
			TAX:
				x = a
				z = 1 if x == 0 else 0
				nf = x >> 7
			INX:
				x = (x + 1) & 0xFF
				z = 1 if x == 0 else 0
				nf = x >> 7
			INY:
				y = (y + 1) & 0xFF
				z = 1 if y == 0 else 0
				nf = y >> 7
			SEC:
				c = 1
			SBC:
				b = m[addr]
				if d:
					t = (a >> 4) * 10 + (a & 15) - ((b >> 4) * 10 + (b & 15)) - (1 - c)
					c = 1 if t >= 0 else 0
					if t < 0:
						t += 100
					# JS: ((r / 10) | 0) << 4 | r % 10, truncating toward zero for a negative r.
					a = ((int(t / 10.0) << 4) | (t % 10)) & 0xFF
				else:
					b = b ^ 0xFF
					t = a + b + c
					v = 1 if (~(a ^ b) & (a ^ t) & 0x80) != 0 else 0
					c = 1 if t > 0xFF else 0
					a = t & 0xFF
				z = 1 if a == 0 else 0
				nf = a >> 7
			STX:
				m[addr] = x
			STY:
				m[addr] = y
			CPX:
				b = m[addr]
				t = (x - b) & 0xFF
				c = 1 if x >= b else 0
				z = 1 if t == 0 else 0
				nf = t >> 7
			CPY:
				b = m[addr]
				t = (y - b) & 0xFF
				c = 1 if y >= b else 0
				z = 1 if t == 0 else 0
				nf = t >> 7
			BMI:
				if nf != 0:
					pc = addr
			BVC:
				if v == 0:
					pc = addr
			BVS:
				if v != 0:
					pc = addr
			DEC:
				t = (m[addr] - 1) & 0xFF
				m[addr] = t
				z = 1 if t == 0 else 0
				nf = t >> 7
			BIT:
				b = m[addr]
				z = 1 if (a & b) == 0 else 0
				nf = (b >> 7) & 1
				v = (b >> 6) & 1
			TAY:
				y = a
				z = 1 if y == 0 else 0
				nf = y >> 7
			TXA:
				a = x
				z = 1 if a == 0 else 0
				nf = a >> 7
			TYA:
				a = y
				z = 1 if a == 0 else 0
				nf = a >> 7
			TSX:
				x = sp
				z = 1 if x == 0 else 0
				nf = x >> 7
			TXS:
				sp = x
			PHA:
				m[0x100 | sp] = a
				sp = (sp - 1) & 0xFF
			PLA:
				sp = (sp + 1) & 0xFF
				a = m[0x100 | sp]
				z = 1 if a == 0 else 0
				nf = a >> 7
			PHP:
				m[0x100 | sp] = (nf << 7) | (v << 6) | 0x30 | (d << 3) | (I << 2) | (z << 1) | c
				sp = (sp - 1) & 0xFF
			PLP:
				sp = (sp + 1) & 0xFF
				t = m[0x100 | sp]
				nf = (t >> 7) & 1
				v = (t >> 6) & 1
				d = (t >> 3) & 1
				I = (t >> 2) & 1
				z = (t >> 1) & 1
				c = t & 1
			CLD:
				d = 0
			SED:
				d = 1
			CLI:
				I = 0
			SEI:
				I = 1
			CLV:
				v = 0
			NOP:
				pass
			RTI:
				sp = (sp + 1) & 0xFF
				t = m[0x100 | sp]
				nf = (t >> 7) & 1
				v = (t >> 6) & 1
				d = (t >> 3) & 1
				I = (t >> 2) & 1
				z = (t >> 1) & 1
				c = t & 1
				sp = (sp + 1) & 0xFF
				t = m[0x100 | sp]
				sp = (sp + 1) & 0xFF
				pc = t | (m[0x100 | sp] << 8)
			BRK:
				if not strict:
					halted = true  # cartridges end on BRK
					break
				t = (pc + 1) & 0xFFFF
				m[0x100 | sp] = t >> 8
				sp = (sp - 1) & 0xFF
				m[0x100 | sp] = t & 0xFF
				sp = (sp - 1) & 0xFF
				m[0x100 | sp] = (nf << 7) | (v << 6) | 0x30 | (d << 3) | (I << 2) | (z << 1) | c
				sp = (sp - 1) & 0xFF
				I = 1
				pc = m[0xFFFE] | (m[0xFFFF] << 8)
	A = a
	X = x
	Y = y
	SP = sp
	PC = pc
	C = c
	Z = z
	V = v
	N = nf
	D = d
	depth = dep
	steps += ran
	return ran


# ── cartridges ───────────────────────────────────────────────────────────────


## Parses `.fkc` bytes: the 16-byte FKC header when present, else a legacy bare-opcode sprite.
## Keys mirror the JS parseCartridge: has_header, ver, type, origin, entry, code_len, fb_base,
## fb_format, flags, code.
static func parse_cartridge(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() >= 16 and bytes[0] == 0x46 and bytes[1] == 0x4B and bytes[2] == 0x43:
		var code_len := bytes[10] | (bytes[11] << 8)
		return {
			"has_header": true, "ver": bytes[4], "type": bytes[5],
			"origin": bytes[6] | (bytes[7] << 8), "entry": bytes[8] | (bytes[9] << 8),
			"code_len": code_len, "fb_base": bytes[12] | (bytes[13] << 8),
			"fb_format": bytes[14], "flags": bytes[15],
			"code": bytes.slice(16, mini(16 + code_len, bytes.size())),
		}
	return {
		"has_header": false, "ver": 1, "type": 1, "origin": 0x0200, "entry": 0x0200,
		"code_len": bytes.size(), "fb_base": FB_BASE, "fb_format": 1, "flags": 1, "code": bytes,
	}


## Clears memory, copies a parsed cartridge's code to its origin and resets to its entry.
func load_cartridge(cart: Dictionary) -> void:
	mem.fill(0)
	var code: PackedByteArray = cart["code"]
	var origin: int = cart["origin"]
	for i in mini(code.size(), 0x10000 - origin):
		mem[origin + i] = code[i]
	reset(cart["entry"])


## The JS `execute`: parse, load and run to the end (or 200,000 steps).
static func execute(bytes: PackedByteArray, max_steps: int = 200000) -> FK6502:
	var cpu := FK6502.new()
	cpu.load_cartridge(parse_cartridge(bytes))
	cpu.run(max_steps)
	return cpu


## The 512 framebuffer bytes (1bpp, 64×64, row-major, MSB = leftmost).
func framebuffer(fb_base: int = FB_BASE) -> PackedByteArray:
	return mem.slice(fb_base, fb_base + FB_BYTES)


## Lit pixels in the framebuffer.
func lit_count(fb_base: int = FB_BASE) -> int:
	var n := 0
	for i in FB_BYTES:
		n += _popcount[mem[(fb_base + i) & 0xFFFF]]
	return n


## A framebuffer as 64×64 L8 pixels (lit = 255), ready for Image.FORMAT_L8.
static func to_l8(fb: PackedByteArray) -> PackedByteArray:
	var px := PackedByteArray()
	for b in fb:
		px.append_array(_l8.slice(b * 8, b * 8 + 8))
	return px


## One instruction as text, e.g. "LDA #$80" (for debugging; the JS step's `dis`).
func disassemble(addr: int) -> String:
	var op: int = mem[addr & 0xFFFF]
	var mn: int = _mn[op]
	if mn < 0:
		return "??? ($%02X)" % op
	var mode: int = _mode[op]
	var b1: int = mem[(addr + 1) & 0xFFFF]
	var w: int = b1 | (mem[(addr + 2) & 0xFFFF] << 8)
	var arg := ""
	match mode:
		IMM:
			arg = "#$%02X" % b1
		ZP:
			arg = "$%02X" % b1
		ZPX:
			arg = "$%02X,X" % b1
		ZPY:
			arg = "$%02X,Y" % b1
		ABS:
			arg = "$%04X" % w
		ABX:
			arg = "$%04X,X" % w
		ABY:
			arg = "$%04X,Y" % w
		IND:
			arg = "($%04X)" % w
		IZX:
			arg = "($%02X,X)" % b1
		IZY:
			arg = "($%02X),Y" % b1
		REL:
			arg = "$%04X" % ((addr + 2 + (b1 - 256 if b1 & 0x80 else b1)) & 0xFFFF)
		ACC:
			arg = "A"
	return MNEMONICS[mn] + ("" if arg == "" else " " + arg)
