extends SceneTree
## Research harness: what keeps a mortar crew alive when a drone has it in view and an enemy mortar keeps firing at it? Uses the game's own
## numbers: flight 40 s, evasion radius 40 m, drone-corrected dispersion (base CEP 3% of range with a 15 m floor, decaying by 0.15 per corrected
## round to a 6 m floor), blast casualty chance halving every 26 m, cover multipliers (trees 0.5 against open 1.3), reload 30 s, a burst of 2,
## a crew of 5. Run (the folder is ignored by Godot; copy it under scripts/ first):
##   Godot_console.exe --headless --path . --script res://scripts/mortar_evasion_sim.gd
## Result of 2026-10-07 (3,000 trials each, mean casualties of 5): after 120 s open 5.00, cover 4.20, straight 5.00, jink3 0.26, jink5 0.45,
## jink10 1.20, jink20 2.19; after 240 s open 5.00, cover 4.97, straight 5.00, jink3 0.26, jink5 0.68, jink10 2.19, jink20 3.75; after 600 s
## jink3 0.41, jink5 1.34, jink10 3.91, jink20 4.88 (jinkN = a new random heading every N seconds at 2.2 m/s).
func _initialize():
	call_deferred("run")

const FLIGHT := 40.0
const EVADE := 40.0
const RELOAD := 30.0
const CREW := 5
const SPEED := 2.2
const RANGE_M := 3000.0
const DECAY := 0.15
const FLOOR_M := 6.0

func disp_sigma(k: int) -> float:
	var base: float = maxf(15.0, 0.03 * RANGE_M)
	var floor_d: float = minf(FLOOR_M, base)
	return (floor_d + (base - floor_d) * pow(DECAY, float(k))) / 1.1774

func casualty_chance(dist: float, cover: float) -> float:
	return clampf(exp(-log(2.0) * dist / 26.0) * cover, 0.0, 1.0)

func run_one(strategy: String, horizon: float, cover_mult: float) -> float:
	var pos := Vector2.ZERO
	var heading := randf() * TAU
	var next_turn := 0.0
	var crew := float(CREW)
	var t := 0.0
	var shots := 0
	var next_fire := 0.0
	var pending: Array = []
	var interval_turn: float = float(strategy.substr(4)) if strategy.begins_with("jink") else 0.0
	var moving: bool = strategy == "straight" or strategy.begins_with("jink")
	var cov: float = cover_mult if strategy == "cover" else 1.0
	while t < horizon and crew > 0.0:
		if moving:
			if strategy.begins_with("jink") and t >= next_turn:
				heading = randf() * TAU
				next_turn = t + interval_turn
			pos += Vector2(cos(heading), sin(heading)) * SPEED
		if t >= next_fire:
			for burst in 2:
				var aim: Vector2 = pos + (Vector2(cos(heading), sin(heading)) * SPEED * FLIGHT if moving else Vector2.ZERO)
				var sigma: float = disp_sigma(shots)
				shots += 1
				pending.append({"t": t + FLIGHT, "impact": aim + Vector2(randfn(0.0, sigma), randfn(0.0, sigma))})
			next_fire = t + RELOAD
		var keep: Array = []
		for p in pending:
			if t >= p.t:
				var drift: float = pos.distance_to(p.impact)
				if drift <= EVADE:
					crew -= float(CREW) * casualty_chance(drift, cov) * (crew / float(CREW))
			else:
				keep.append(p)
		pending = keep
		t += 1.0
	return float(CREW) - maxf(crew, 0.0)

func run():
	seed(1)
	var n := 3000
	for horizon in [120.0, 240.0, 600.0]:
		print("--- after %d tactical seconds" % int(horizon))
		for s in ["open", "cover", "straight", "jink3", "jink5", "jink10", "jink20"]:
			var sum := 0.0
			for i in n:
				sum += run_one(s, horizon, 0.5 / 1.3)
			print("%-9s mean casualties %.2f of 5" % [s, sum / float(n)])
	quit()
