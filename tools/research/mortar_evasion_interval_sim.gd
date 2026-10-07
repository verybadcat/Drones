extends SceneTree
## Result of 2026-10-07 (1,500 trials each; mean casualties of 5; shooter "lead" = aims along its present heading, as the game does,
## "current" = aims at where it stands, "observed" = at its mean velocity over the last 20 s):
##   after 120 s    lead  current observed          after 300 s    lead  current observed
##   interval  3- 5 s  0.21  4.41  3.29                 3- 5 s  0.28  5.00  4.75
##   interval  8-12 s  0.66  3.31  2.10                 8-12 s  1.43  4.84  3.82
##   interval 10-20 s  1.16  2.50  1.72                10-20 s  2.44  4.50  3.36
##   interval 15-30 s  2.00  1.94  1.63                15-30 s  3.78  3.84  3.28
##   interval 20-40 s  3.16  1.06  1.29                20-40 s  4.54  2.60  3.39
##   interval 25-50 s  3.77  0.83  1.63                25-50 s  4.91  2.19  3.83
##   interval 30-60 s  4.11  0.81  1.86                30-60 s  4.98  1.92  4.20
##   interval 45-90 s  4.87  0.63  3.54                45-90 s  5.00  1.48  4.96
## Turning every few seconds only beats a shooter who leads along the heading: a shooter who aims at where the crew stands wins, because a
## crew that turns every 3-5 s never gets 40 m from its starting point in the 40 s a round is in the air. Against all three shooters the
## best worst case is a random 15-30 s between turns. Slowing down at random (speed 0-100% per leg) is worse (2.3-3.8 after 120 s at 15-30 s).
## Nothing saves a crew a drone keeps correcting fire onto for five minutes: it buys time, no more.
## Research harness (copied from tools/research/mortar_evasion_interval_sim.gd to run): how often should a mortar crew that a drone
## is watching change direction, if the shooter may aim at its current position or at where its recent movement says it is going,
## not only along its present heading? Game numbers: flight 40 s, evasion radius 40 m, drone-corrected dispersion to a 6 m floor,
## blast casualty chance halving every 26 m, 2 rounds every 30 s from 3 km, a crew of 5, urgent relocation speed 2.6 m/s.
func _initialize():
	call_deferred("run")

const FLIGHT := 40.0
const EVADE := 40.0
const RELOAD := 30.0
const CREW := 5
const SPEED := 2.6
const RANGE_M := 3000.0
const DECAY := 0.15
const FLOOR_M := 6.0

func disp_sigma(k: int) -> float:
	var base: float = maxf(15.0, 0.03 * RANGE_M)
	var floor_d: float = minf(FLOOR_M, base)
	return (floor_d + (base - floor_d) * pow(DECAY, float(k))) / 1.1774

func casualty_chance(dist: float) -> float:
	return clampf(exp(-log(2.0) * dist / 26.0), 0.0, 1.0)

# shooter: "lead" (along the present heading, as the game does), "current" (at where it stands), "observed" (its mean velocity over the last 20 s)
func run_one(lo: float, hi: float, shooter: String, horizon: float, vary: bool = false) -> float:
	# vary: also a random speed (0-100%) per leg
	var pos := Vector2.ZERO
	var heading := randf() * TAU
	var next_turn := randf_range(lo, hi)
	var speed_k := 1.0
	var crew := float(CREW)
	var t := 0.0
	var shots := 0
	var next_fire := 0.0
	var pending: Array = []
	var trail: Array = [] # positions each second
	while t < horizon and crew > 0.0:
		if t >= next_turn:
			heading = randf() * TAU
			next_turn = t + randf_range(lo, hi)
			if vary:
				speed_k = randf_range(0.0, 1.0)
		pos += Vector2(cos(heading), sin(heading)) * SPEED * speed_k
		trail.append(pos)
		if t >= next_fire:
			for burst in 2:
				var aim: Vector2 = pos
				if shooter == "lead":
					aim = pos + Vector2(cos(heading), sin(heading)) * SPEED * speed_k * FLIGHT
				elif shooter == "observed" and trail.size() > 20:
					var vel: Vector2 = (pos - trail[trail.size() - 21]) / 20.0
					aim = pos + vel * FLIGHT
				var sigma: float = disp_sigma(shots)
				shots += 1
				pending.append({"t": t + FLIGHT, "impact": aim + Vector2(randfn(0.0, sigma), randfn(0.0, sigma))})
			next_fire = t + RELOAD
		var keep: Array = []
		for p in pending:
			if t >= p.t:
				var drift: float = pos.distance_to(p.impact)
				if drift <= EVADE:
					crew -= float(CREW) * casualty_chance(drift) * (crew / float(CREW))
			else:
				keep.append(p)
		pending = keep
		t += 1.0
	return float(CREW) - maxf(crew, 0.0)

func run():
	seed(1)
	var n := 1500
	for horizon in [120.0, 300.0]:
		print("--- after %d tactical seconds (mean casualties of 5; shooter: lead / current / observed-20s)" % int(horizon))
		for iv in [[3.0, 5.0], [8.0, 12.0], [10.0, 20.0], [15.0, 30.0], [20.0, 40.0], [25.0, 50.0], [30.0, 60.0], [45.0, 90.0]]:
			var row := "interval %2d-%2d s:" % [int(iv[0]), int(iv[1])]
			for shooter in ["lead", "current", "observed"]:
				var sum := 0.0
				for i in n:
					sum += run_one(iv[0], iv[1], shooter, horizon)
				row += "  %-8s %.2f" % [shooter, sum / float(n)]
			print(row)
	quit()
