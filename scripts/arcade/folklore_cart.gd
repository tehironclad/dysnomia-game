extends ArcadeGame
## Folklore cartridge player: runs a `.fkc` cartridge on the Folklore CPU (FK6502) and shows its
## $E000 64×64 one-bit framebuffer, scaled up, in the default Folklore colour.
##
## The cabinet calls `load_cart("res://assets/arcade/cartridges/<file>.fkc")` BEFORE `start(seed)` or
## `attract()`. Titles and themes come from that folder's manifest.json.
##
## Sprite cartridges (type 01) are art: they run once and stop on their bare RTS. In attract the
## sprite draws itself in a few instructions per frame, holds, and repeats. They are not playable
## (ArcadeCatalog marks them `playable: false`); a start() on one shows it and ends after HOLD_SECONDS.
##
## Game cartridges (type 02) loop forever. They are stepped STEPS_PER_FRAME instructions per 60 Hz
## frame (the site's "normal" speed in cartridge.html; 1,000 in attract), capped at `frame_budget_usec`
## of wall-clock CPU time so a slow PC slows the cartridge rather than the game.
## Maria's spec defines no input or score registers and today's carts read none, so this player adds
## a small I/O page right after the framebuffer (the cabinet's own convention, documented in
## assets/arcade/cartridges/README.md):
##   $E200  input, written before every frame: bit0 left, bit1 right, bit2 up, bit3 down, bit4 fire
##   $E201  frame counter (wraps at 256)
##   $E202  score, 16-bit little-endian, written by the cartridge (reported with game_over)
##   $E204  the credit's seed, 16-bit little-endian
## A game cartridge's credit ends when it halts (RTS/BRK/bad opcode) or after `time_limit` seconds.

const IO_INPUT := 0xE200
const IO_FRAME := 0xE201
const IO_SCORE := 0xE202
const IO_SEED := 0xE204
const STEPS_PER_FRAME := 3000
const SPRITE_STEPS_PER_FRAME := 6  # the attract "draw-in"
const HOLD_SECONDS := 6.0
const SESSION_SECONDS := 120.0
const SCALE := 3
const FB_ORIGIN := Vector2(64, 26)  # 192×192 picture, centred

var cart: Dictionary = {}  ## the parsed cartridge (FK6502.parse_cartridge), empty until load_cart
var cart_path := ""
var cart_id := ""
var cart_title := "Folklore"
var cart_theme := ""
var cpu: FK6502
var steps_per_frame := STEPS_PER_FRAME
var attract_steps_per_frame := 1000  ## the idle demo on the 3D screen runs slower and cheaper
var frame_budget_usec := 3000  ## 0 = no wall-clock cap (tests, for determinism)
var time_limit := SESSION_SECONDS  ## seconds per game-cartridge credit; 0 = until it halts
var color := FK6502.DEFAULT_COLOR
var lit := 0

var _img: Image
var _tex: ImageTexture
var _fb_last := PackedByteArray()
var _frame := 0
var _halted_t := -1.0


func title() -> String:
	return cart_title


func blurb() -> String:
	if cart.is_empty():
		return "No cartridge loaded."
	if is_sprite():
		return cart_theme if cart_theme != "" else "A Folklore sprite cartridge."
	return "A Folklore 6502 game cartridge. Arrows and fire are on $E200."


## Loads a cartridge file. Returns false (and keeps the slot empty) if it can't be read.
func load_cart(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		cart = {}
		return false
	cart_path = path
	cart_id = path.get_file().get_basename()
	cart_title = cart_id.capitalize()
	cart_theme = ""
	var manifest = _manifest(path.get_base_dir())
	for entry in manifest:
		if entry.get("file", "") == path.get_file():
			cart_id = entry.get("id", cart_id)
			cart_title = entry.get("title", cart_title)
			cart_theme = entry.get("theme", "")
	load_bytes(bytes)
	return true


## Loads cartridge bytes directly (a .fkc, or legacy bare opcodes).
func load_bytes(bytes: PackedByteArray) -> void:
	cart = FK6502.parse_cartridge(bytes)
	cpu = FK6502.new()
	cpu.load_cartridge(cart)
	_fb_last = PackedByteArray()
	_refresh_picture()


func is_sprite() -> bool:
	return int(cart.get("type", 1)) == 1


func is_game() -> bool:
	return int(cart.get("type", 0)) == 2


func fb_base() -> int:
	return int(cart.get("fb_base", FK6502.FB_BASE))


func _reset() -> void:
	_frame = 0
	_halted_t = -1.0
	if cart.is_empty():
		return
	cpu = FK6502.new()
	cpu.load_cartridge(cart)
	var seed := rng.seed & 0xFFFF
	cpu.mem[IO_SEED] = seed & 0xFF
	cpu.mem[IO_SEED + 1] = seed >> 8
	_fb_last = PackedByteArray()
	_refresh_picture()


func _tick(dt: float) -> void:
	if cpu == null:
		return
	if cpu.halted:
		if _halted_t < 0.0:
			_halted_t = t
		if t - _halted_t >= HOLD_SECONDS:
			if attract_mode:
				_reset()  # the demo: run it again
			else:
				score = cpu.mem[IO_SCORE] | (cpu.mem[IO_SCORE + 1] << 8)
				end_game()
		return
	if is_game():
		cpu.mem[IO_INPUT] = held & 0x1F
		cpu.mem[IO_FRAME] = _frame & 0xFF
		_frame += 1
		var per_frame := attract_steps_per_frame if attract_mode else steps_per_frame
		_run(maxi(1, int(round(per_frame * dt * 60.0))))
		score = cpu.mem[IO_SCORE] | (cpu.mem[IO_SCORE + 1] << 8)
		if playing and time_limit > 0.0 and t >= time_limit:
			end_game()
			return
	else:
		# A sprite: draw in slowly for the demo, at once for a (non-playable) credit.
		_run(SPRITE_STEPS_PER_FRAME if attract_mode else 200000)
	_refresh_picture()


func _run(n: int) -> void:
	if frame_budget_usec <= 0:
		cpu.burst(n)
		return
	var t0 := Time.get_ticks_usec()
	var left := n
	while left > 0 and not cpu.halted:
		left -= cpu.burst(mini(left, 500))
		if Time.get_ticks_usec() - t0 > frame_budget_usec:
			break


func _refresh_picture() -> void:
	if cpu == null:
		return
	var fb := cpu.framebuffer(fb_base())
	if fb == _fb_last:
		return
	_fb_last = fb
	lit = cpu.lit_count(fb_base())
	var px := FK6502.to_l8(fb)
	if _img == null:
		_img = Image.create_from_data(FK6502.FB_W, FK6502.FB_H, false, Image.FORMAT_L8, px)
		_tex = ImageTexture.create_from_image(_img)
	else:
		_img.set_data(FK6502.FB_W, FK6502.FB_H, false, Image.FORMAT_L8, px)
		_tex.update(_img)
	queue_redraw()


func _manifest(dir: String) -> Array:
	var f := FileAccess.open(dir.path_join("manifest.json"), FileAccess.READ)
	if f == null:
		return []
	var j = JSON.parse_string(f.get_as_text())
	if j is Dictionary and j.get("cartridges") is Array:
		return j["cartridges"]
	return []


# ── drawing ──────────────────────────────────────────────────────────────────


func _draw_game() -> void:
	var size := Vector2(FK6502.FB_W * SCALE, FK6502.FB_H * SCALE)
	var r := Rect2(FB_ORIGIN, size)
	draw_rect(r.grow(3), Color(color, 0.08))
	draw_rect(r.grow(3), Color(color, 0.35), false, 1.0)
	if _tex != null:
		draw_texture_rect(_tex, r, false, color)
	# Scanlines: a dark line between every pixel row.
	for row in range(1, FK6502.FB_H):
		var y := FB_ORIGIN.y + row * SCALE - 0.5
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0, 0, 0, 0.22), 1.0)
	text_centered(16, cart_title.to_upper(), 11, color)
	var foot := "FOLKLORE CPU"
	if cpu != null:
		foot += "  ·  %s STEPS  ·  %d PX" % [_grouped(cpu.steps), lit]
		if cpu.bad:
			foot += "  ·  BAD OPCODE"
	text_centered(234, foot, 8, DIM)


func _draw_hud() -> void:
	if is_game() and playing and time_limit > 0.0:
		text(Vector2(6, 12), "TIME %d" % maxi(0, int(ceil(time_limit - t))), 9, MUTED)
	if score > 0:
		text(Vector2(SIZE.x - 60, 12), "%05d" % score, 10, INK)


func _draw_attract() -> void:
	if int(t * 1.6) % 2 == 0:
		var prompt := "INSERT CREDIT" if is_game() else "FOLKLORE CARTRIDGE"
		text(Vector2(6, 12), prompt, 8, GOLD)


func _draw_title_card() -> void:
	if cart.is_empty():
		text_centered(124, "NO CARTRIDGE", 12, DIM)


static func _grouped(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
