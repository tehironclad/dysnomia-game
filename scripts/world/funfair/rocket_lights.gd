class_name RocketLights
extends Node3D
## The board by the Upsilon Rocket's booth: seven lamps, one per fair game, lit for each game
## the connected wallet has a paid ticket for at this QING (FairProgress, read from the chain's
## AFFECTION Transfer logs). All seven unlock the rocket. Without a wallet it says the rocket
## runs as a free preview; while unread it shows "—", never a guess.

const W := 3.6
const H := 1.9

var _lamps: Array = []
var _names: Array = []
var _status: Label3D
var _source: Label3D
var _on: Material
var _off: Material
var _done: Material


func build() -> void:
	var post := FairKit.paint(Color(0.2, 0.21, 0.24), 0.45, 0.8)
	var panel := FairKit.paint(Color(0.04, 0.045, 0.07), 0.7, 0.2)
	for sx in [-1.0, 1.0]:
		FairKit.box(self, Vector3(0.1, 2.85, 0.1), Vector3(sx * (W * 0.5 - 0.1), 1.42, -0.06), post)
	FairKit.box(self, Vector3(W, H, 0.08), Vector3(0, 0.95 + H * 0.5, 0), panel)
	FairKit.box(self, Vector3(W + 0.06, 0.05, 0.12), Vector3(0, 0.95 + H + 0.02, 0), FairKit.glow(Color(1.0, 0.45, 0.25), 3.0, 1.0))
	FairKit.box(self, Vector3(W + 0.06, 0.05, 0.12), Vector3(0, 0.93, 0), FairKit.glow(Color(1.0, 0.45, 0.25), 3.0, 1.0))
	var t := FairKit.label(self, "UPSILON ROCKET · PLAY EVERY GAME", Vector3(0, 2.62, 0.05), 40, Color(1.0, 0.75, 0.45) * 1.6, 0.0, Color(0.02, 0.01, 0.03), 0.0045)
	t.width = 520
	_on = FairKit.glow(Color(0.4, 1.0, 0.55), 6.0, 3.0)
	_off = FairKit.paint(Color(0.16, 0.17, 0.2), 0.4, 0.4)
	_done = FairKit.glow(Color(1.0, 0.82, 0.35), 7.0, 3.5)
	for i in FairProgress.ORDER.size():
		var x := -W * 0.5 + 0.3 + i * (W - 0.6) / 6.0
		var lamp := FairKit.mesh(self, FairKit.sphere_mesh(0.09, 14), Vector3(x, 2.28, 0.08), _off, Vector3.ZERO, false)
		_lamps.append(lamp)
		var nm := String(MidwayGame.title(FairProgress.ORDER[i])).replace("MOTZKIN ", "").replace("REGOLITH ", "").replace(" OF FORTUNE", "").replace("SAAT ", "").replace("TEST YOUR AFFECTION", "STRIKER")
		var l := FairKit.label(self, nm.replace(" ", "\n"), Vector3(x, 2.0, 0.05), 26, Color(0.85, 0.9, 1.0), 0.0, Color(0.02, 0.01, 0.03), 0.0032)
		_names.append(l)
	_status = FairKit.label(self, "—", Vector3(0, 1.58, 0.05), 30, Color(1.0, 0.85, 0.5) * 1.4, 0.0, Color(0.02, 0.01, 0.03), 0.0044)
	_status.width = 740
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_source = FairKit.label(self, "", Vector3(0, 1.17, 0.05), 22, Color(0.6, 0.65, 0.75), 0.0, Color(0.02, 0.01, 0.03), 0.0034)
	_source.width = 960
	_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	FairKit.solid_box(self, Vector3(W, 2.85, 0.2), Vector3(0, 1.42, -0.03))


## codes: the game codes played (1..7); state: "nowallet" | "reading" | "ok" | "failed".
func show_progress(codes: Array, state: String, block: int) -> void:
	var all := FairProgress.unlocked(codes)
	for i in _lamps.size():
		var lit := state in ["ok", "failed"] and codes.has(i + 1)
		_lamps[i].material_override = (_done if all else _on) if lit else _off
	match state:
		"nowallet":
			_status.text = "Connect a wallet: each paid game lights its lamp. Until then the rocket is a free preview."
			_source.text = ""
		"reading":
			_status.text = "Reading your tickets from the chain… —"
			_source.text = ""
		"failed":
			_status.text = FairProgress.text(codes) + " (last read failed: —)" if not codes.is_empty() else "Your tickets could not be read: —"
			_source.text = "AFFECTION Transfer(you → this QING, 1 Ⓐ + the game's code) · retried after your next play"
		_:
			_status.text = ("ROCKET UNLOCKED · ride it at the booth" if all else FairProgress.text(codes))
			_source.text = "From AFFECTION Transfer(you → this QING) logs, blocks %s–%s · each ticket's last wei names its game" % [
				ArcadeScores.grouped(FairProgress.FROM_BLOCK), ArcadeScores.grouped(block)]
