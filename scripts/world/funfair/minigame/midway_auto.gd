class_name MidwayAuto
extends RefCounted
## A skilled player for previews and probes (never for a paid round): given a MidwaySim that
## accepts a press, returns [ax, ay] to press now, or null to wait. It reads the sim the way a
## sharp human reads the stall (the meter, the sway, where a crystal will be), nothing more.


static func choose(s: MidwaySim) -> Variant:
	if not s.accepts():
		return null
	match s.game:
		"striker":
			return [0, 0] if s.meter >= 990 else null
		"entropy":
			var d := MidwaySim.TOSS_Z0 - s.target.y
			if absi(s.meter - (d - 400) * 1000 / 1600) > 25:
				return null
			var tx := s.target_x(s.tick + MidwaySim.TOSS_FLY + 1)
			return [(tx - s.wind * d / 1000) * 1000 * MidwaySim.AIM / (500 * d), 0]
		"regolith":
			var w := s.sway()
			if absi(w.x) > 25 or absi(w.y) > 25:
				return null
			var u := int(MidwaySim.PEGS_U[s.gold_peg % 3])
			var v := int(MidwaySim.PEGS_V[s.gold_peg / 3])
			return [u * MidwaySim.AIM / 900, (v - 500) * MidwaySim.AIM / 500]
		"crystal":
			if s.phase_t < 5:
				return null
			var row := s.round_i % 2
			for i in MidwaySim.RAIL_N:
				if (int(s.knocked[row]) >> i) & 1:
					continue
				var x := s.crystal_x(row, i, s.tick + MidwaySim.SHY_FLY[row])
				if absi(x) < 1500:
					return [x * MidwaySim.AIM / 1700, 300 if row == 1 else -300]
			return null
		"motzkin":
			for i in s.schedule.size():
				var e: Array = s.schedule[i]
				if s.target_up(i, s.tick) and s.tick - int(e[1]) > 10 and MidwaySim.is_prime(int(e[3])):
					return [int(MidwaySim.SLOTS_X[int(e[0]) % 4]) * MidwaySim.AIM / 1800, (int(MidwaySim.SLOTS_Y[int(e[0]) / 4]) - 1825) * MidwaySim.AIM / 700]
			return null
		"waat":
			# Brake when the stop (speed² / 2·decel ahead) lands on the jackpot (or the best nearby)
			if s.phase_t < 10:
				return null
			var stop := posmod(s.angle + s.speed * (s.speed + 2) / (2 * MidwaySim.WHEEL_DECEL), MidwaySim.TURN)
			var seg := (posmod(MidwaySim.TURN - stop, MidwaySim.TURN) * 12 / MidwaySim.TURN) % 12
			return [0, 0] if int(s.wheel[seg]) >= 150 or s.phase_t > 400 else null
		"saat":
			if s.phase_t < 12:
				return null
			return [-300 if int(s.cards[s.round_i]) > 7 else 300, 0]
	return null
