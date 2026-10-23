extends SceneTree
## Fragments as three classes with a hit roll each. User, 2026-10-22/23: "for people standing and without cover, let's use three radii. R1 for potential lethal wounds, R2 for
## potential serious wounds, and R3 for potential light wounds. However, an actual hit should sometimes be less serious than the potential. Give it a 40%
## chance to be at its potential level, 30% to be one level lower, and 30% to be two levels lower ... For each person inside of any radius, roll everything
## that might apply, then take only the worst outcome that actually applies. For example, if a person is hit by a 'potentially lethal' fragment that gets
## reduced two levels, and a 'potentially serious' fragment that is not reduced, they would end up with a serious wound only. For now, try R1=20 meters,
## R2=2R1, and R3=3R1." Then: "Even an exposed person may not be hit ... one roll per class per person. But the exposure check comes prior to any of that.
## So if a tree happens to block exposure, it blocks it for all types of fragments. Similarly for the person lying down. Make R1 the radius with 50% probability
## of a hit." (1/r^2 beyond; certain at the burst; none past 100 m.)
##
## (The user's own example of a light-only person, "a 70% chance of not hurting the person at all", does not follow from 40/30/30: a potential light wound
## is as it is 40 percent of the time and is none otherwise, so 60 percent. The 40/30/30 rule is what is built.)
##
## Run: godot --headless --path . --script scripts/tests/test_fragment_radii.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance

## [none, walking, serious, dead] frequencies of fragment_severity over many rolls.
func sampled(distance_m: float, exposure: float, trials: int) -> Array[float]:
	var counts: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in trials:
		counts[CombatResolver.fragment_severity(distance_m, exposure)] += 1.0
	for k in 4:
		counts[k] /= float(trials)
	return counts

## The chance that one person, standing at a uniformly random place on a disc of radius `spread_m` round the burst, is hurt at all by the fragments
## (worked out by quadrature over the disc, so the tests follow GameConfig.FRAGMENT_R1_M).
func disc_mean_chance(spread_m: float, exposure: float) -> float:
	var total := 0.0
	var n := 200
	for i in n:
		var rho: float = spread_m * sqrt((float(i) + 0.5) / float(n)) # equal-area rings
		total += CombatResolver.fragment_casualty_chance(rho, exposure)
	return total / float(n)

func run() -> void:
	# --- the hit roll per class: 50 percent at the class's own radius (lethal R1 20 m, serious R2 40 m, light R3 60 m), 1/r^2 beyond, certain at the burst
	var r1: float = GameConfig.FRAGMENT_R1_M # the tests follow it; the figures worked out below are in units of R1
	check(near(CombatResolver.fragment_hit_chance(r1, 3), 0.5, 1e-9), "lethal class: 50 percent at R1")
	check(near(CombatResolver.fragment_hit_chance(2.0 * r1, 2), 0.5, 1e-9), "serious class: 50 percent at R2 = 2 R1")
	check(near(CombatResolver.fragment_hit_chance(3.0 * r1, 1), 0.5, 1e-9), "light class: 50 percent at R3 = 3 R1")
	check(CombatResolver.fragment_hit_chance(0.0, 3) == 1.0 and CombatResolver.fragment_hit_chance(0.0005, 1) == 1.0, "certain at the burst")
	check(CombatResolver.fragment_hit_chance(0.5 * r1, 3) > 0.9 and CombatResolver.fragment_hit_chance(0.5 * r1, 3) < CombatResolver.fragment_hit_chance(0.25 * r1, 3), "more likely the nearer")
	# the hits expected (the Poisson mean, minus log2 of the chance of no hit) fall as 1/r^2: a quarter at twice the distance
	var mean_30: float = -log(1.0 - CombatResolver.fragment_hit_chance(1.5 * r1, 3)) / log(2.0)
	var mean_60: float = -log(1.0 - CombatResolver.fragment_hit_chance(3.0 * r1, 3)) / log(2.0)
	check(near(mean_30 / mean_60, 4.0, 1e-6), "the expected hits fall as 1/r^2 (%.4f against %.4f)" % [mean_30, mean_60])
	check(CombatResolver.fragment_hit_chance(99.0, 1) > 0.05 and CombatResolver.fragment_hit_chance(101.0, 1) == 0.0, "beyond R3 the light class still hits, until the reach of 100 m")

	# --- one fragment of a class that hit, reduced: 40 percent as it is, 30 one lower, 30 two lower
	for level in [1, 2, 3]:
		check(CombatResolver.fragment_reduced(level, 0.0) == level and CombatResolver.fragment_reduced(level, 0.399) == level, "level %d: as it is below 0.4" % level)
		check(CombatResolver.fragment_reduced(level, 0.4) == level - 1 and CombatResolver.fragment_reduced(level, 0.699) == level - 1, "level %d: one lower from 0.4 to 0.7" % level)
		check(CombatResolver.fragment_reduced(level, 0.7) == maxi(level - 2, 0) and CombatResolver.fragment_reduced(level, 0.999) == maxi(level - 2, 0), "level %d: two lower from 0.7 (never below none)" % level)

	# --- the worst outcome of the three classes, worked out for an exposed person (none, walking, serious, dead)
	# (the chances depend on the distance only in units of R1, worked out by hand for the distances 0.05, 0.5, 1, 1.5, 2.5 and 5 R1; past the 100 m reach none)
	var expected_by_distance := {
		0.05 * r1: [0.0, 0.18, 0.42, 0.40], 0.5 * r1: [0.011, 0.195, 0.419, 0.375], r1: [0.103, 0.303, 0.394, 0.200], 1.5 * r1: [0.232, 0.352, 0.310, 0.106],
		2.5 * r1: [0.501, 0.293, 0.164, 0.042], 5.0 * r1: [0.822, 0.118, 0.049, 0.011], 101.0: [1.0, 0.0, 0.0, 0.0],
	}
	for d in expected_by_distance:
		var worked := CombatResolver.fragment_distribution(d)
		var exp: Array = expected_by_distance[d]
		var same := true
		for k in 4:
			if absf(worked[k] - float(exp[k])) > 0.0015:
				same = false
		check(same, "%.0f m: none, walking, serious, dead worked out %s against %s" % [d, str(worked), str(exp)])
	check(near(CombatResolver.fragment_casualty_chance(0.5 * r1, 0.5), 0.5 * 0.989, 0.001), "half exposed: half the chance of any wound")
	# the worst of everything that hit: a lethal fragment reduced two levels is a light wound, a serious one not reduced is serious, so serious
	check(maxi(CombatResolver.fragment_reduced(3, 0.9), CombatResolver.fragment_reduced(2, 0.1)) == 2, "the user's example: lethal reduced two levels with serious not reduced is serious")

	# --- the rolled outcome agrees with the worked-out one; with a share exposed the single exposure roll is for all the classes
	seed(31)
	for case in [{"d": 10.0, "x": 1.0}, {"d": 30.0, "x": 1.0}, {"d": 50.0, "x": 1.0}, {"d": 10.0, "x": 0.3}, {"d": 30.0, "x": 0.5}, {"d": 80.0, "x": 1.0}]:
		var rolled := sampled(case.d, case.x, 20000)
		var worked2 := CombatResolver.fragment_distribution(case.d, case.x)
		var agree := true
		for k in 4:
			if absf(rolled[k] - worked2[k]) > 0.015:
				agree = false
		check(agree, "%.0f m, exposure %.1f: rolled %s against worked out %s" % [case.d, case.x, str(rolled), str(worked2)])
	var sum := 0.0
	for p in CombatResolver.fragment_distribution(10.0, 0.37):
		sum += p
	check(near(sum, 1.0, 1e-9), "the chances add up to one")
	# not exposed means not hurt by ANY class: at the burst, where every class hits, the wounded are exactly the exposed
	var wounded := 0
	for i in 20000:
		if CombatResolver.fragment_severity(1.0, 0.3) > 0:
			wounded += 1
	check(near(float(wounded) / 20000.0, 0.3, 0.015), "a man 30 percent exposed at the burst is hurt by something 30 percent of the time, not more (%.3f)" % (float(wounded) / 20000.0))

	# --- exposure: 1 standing in the open, less in cover, less lying down
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	var open_point: Vector2 = m(-5000, -5000)
	var building_point: Vector2 = GameConfig._building_rects[0].get_center()
	var up: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point)
	bm.player_units.append(up)
	check(CombatResolver.fragment_exposure(up, 10.0) == 1.0, "standing in the open: every potential applies")
	var down: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point + m(0, 500))
	bm.player_units.append(down)
	down.gone_to_ground = true
	check(near(CombatResolver.fragment_exposure(down, 10.0), GameConfig.PRONE_IN_OPEN_FACTOR, 1e-6), "lying in the open: a third of the potentials")
	# --- what stands between the burst and the person (user, 2026-10-22): 10 m of trees stop half, 20 m three quarters, a wall all, and in the building
	# the round burst in, 80 percent
	check(GameConfig.fragment_transmission(open_point, open_point + m(30, 0)) == 1.0, "open ground between: everything gets through")
	var rect: Rect2 = GameConfig._building_rects[0]
	var inside_a: Vector2 = rect.get_center()
	var inside_b: Vector2 = rect.get_center() + Vector2(minf(rect.size.x * 0.3, 40.0), 0.0)
	check(rect.has_point(inside_a) and rect.has_point(inside_b), "setup: two places in one building")
	check(near(GameConfig.fragment_transmission(inside_a, inside_b), 0.2, 1e-9), "a round that bursts in the building: 80 percent of the hits to a person in it are stopped")
	var outside_near: Vector2 = Vector2(rect.position.x - 15.0, rect.get_center().y)
	var outside_far: Vector2 = Vector2(rect.end.x + 15.0, rect.get_center().y)
	check(not rect.has_point(outside_near) and not rect.has_point(outside_far), "setup: places outside the building")
	check(GameConfig.fragment_transmission(outside_near, inside_a) == 0.0 and GameConfig.fragment_transmission(inside_a, outside_near) == 0.0, "a wall between (burst outside, person in, or the other way): no hit gets through")
	check(GameConfig.fragment_transmission(outside_near, outside_far) == 0.0, "a building between burst and person: no hit gets through")
	# a stretch of forest with open ground beyond it
	var edge := Vector2.INF
	for x in range(-3000, 6000, 10):
		for y in range(-500, 6000, 40):
			var p := m(x, y)
			var all_trees := true
			for k in range(0, 21):
				if GameConfig.get_terrain_type_at(p - m(k, 0)) != GameConfig.TerrainType.TREES:
					all_trees = false
					break
			if not all_trees:
				continue
			var all_open := true
			for k in range(1, 21):
				if GameConfig.get_terrain_type_at(p + m(k, 0)) != GameConfig.TerrainType.OPEN:
					all_open = false
					break
			if all_open:
				edge = p
				break
		if not is_inf(edge.x):
			break
	check(not is_inf(edge.x), "setup: the edge of a forest with 20 m of trees behind it and 20 m of open ground beyond")
	if not is_inf(edge.x):
		check(near(GameConfig.fragment_transmission(edge - m(10, 0), edge + m(0.5, 0)), 0.5, 0.04), "10 m of trees between: half the hits get through (%.3f)" % GameConfig.fragment_transmission(edge - m(10, 0), edge + m(0.5, 0)))
		check(near(GameConfig.fragment_transmission(edge - m(20, 0), edge + m(0.5, 0)), 0.25, 0.03), "20 m of trees: a quarter (%.3f)" % GameConfig.fragment_transmission(edge - m(20, 0), edge + m(0.5, 0)))
		check(near(GameConfig.fragment_transmission(edge - m(5, 0), edge + m(0.5, 0)), 0.707, 0.04), "5 m of trees: 0.5 to the power of a half (%.3f)" % GameConfig.fragment_transmission(edge - m(5, 0), edge + m(0.5, 0)))
		check(near(GameConfig.fragment_transmission(edge - m(10, 0), edge + m(10, 0)), 0.5, 0.04), "10 m of trees and then open ground: the open ground adds nothing (%.3f)" % GameConfig.fragment_transmission(edge - m(10, 0), edge + m(10, 0)))
		# the screen counts in the person's exposure, and only for the fragments that reach him
		var screened: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, edge + m(10, 0))
		bm.player_units.append(screened)
		check(near(CombatResolver.fragment_person_exposure(screened, edge - m(10, 0), edge + m(10, 0)), 0.5, 0.04), "a man 10 m behind the forest edge from a burst 10 m into it: half the potentials apply")
		var burst_count := 0
		for i in 600:
			screened.pips = screened.max_pips
			screened.state = Unit.State.ACTIVE
			bm._apply_shell_blast(edge - m(9, 0), null)
			if screened.pips < screened.max_pips:
				burst_count += 1
		# the man is 19 m from the burst: lethal, serious and light potentials each apply half the time (a roll for the whole line is not the thing)
		var expected_hit: float = CombatResolver.fragment_casualty_chance(19.0, CombatResolver.fragment_person_exposure(screened, edge - m(9, 0), edge + m(10, 0)))
		check(near(float(burst_count) / 600.0, expected_hit, 0.07), "...and in a battle he is hurt %.2f of the time, as the worked-out %.2f" % [float(burst_count) / 600.0, expected_hit])
		bm.player_units.erase(screened)
		screened.free()
	var inside: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, building_point)
	bm.player_units.append(inside)
	check(CombatResolver.fragment_person_exposure(inside, building_point + m(2, 0), building_point) < 0.21, "a squad's man in a building the round burst in: a fifth of the potentials")
	check(CombatResolver.fragment_person_exposure(inside, building_point + Vector2(rect.size.x, 0.0), building_point) == 0.0, "...none if it burst outside")

	# --- in a battle: a lone man in the open at a given distance, the fragments alone (past the 10 m of the blast), against the worked-out chances
	for d in [0.75 * r1, 1.5 * r1, 2.5 * r1, 3.25 * r1, 90.0, 105.0]:
		var counts := [0, 0, 0, 0] # none, walking, serious, dead
		for i in 600:
			var s: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, open_point + m(0, 1000))
			bm.player_units.append(s)
			bm._apply_shell_blast(s.global_position + m(d, 0), null)
			if s.pips == s.max_pips:
				counts[0] += 1
			elif s.killed_count > 0:
				counts[3] += 1
			elif s.heavily_wounded_count > 0:
				counts[2] += 1
			else:
				counts[1] += 1
			bm.player_units.erase(s)
			s.free()
		var worked3 := CombatResolver.fragment_distribution(d)
		var close := true
		for k in 4:
			if absf(float(counts[k]) / 600.0 - worked3[k]) > 0.07:
				close = false
		check(close, "%.1f m: %s of 600 against the worked-out %s" % [d, str(counts), str(worked3)])

	# a crew of five at 2.5 R1: each man hurt about half the time, so about two and a half of five are lost
	var lost := 0
	var crews := 300
	for i in crews:
		var crew: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, open_point + m(0, 2000))
		bm.enemy_units.append(crew)
		crew.mortar_rounds_remaining = 0
		bm._apply_shell_blast(crew.global_position + m(2.5 * r1, 0), null)
		lost += crew.crew_casualties
		bm.enemy_units.erase(crew)
		crew.free()
	var mean_lost: float = float(lost) / float(crews)
	check(mean_lost > 2.0 and mean_lost < 3.0, "a crew 2.5 R1 from a burst loses about two and a half of its five (%.2f)" % mean_lost)

	# a squad lying in the open takes much less than one standing, at the same distance
	var counts_standing := 0
	var counts_lying := 0
	for i in 300:
		var a: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point + m(0, 3000))
		var b: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point + m(0, 3500))
		b.gone_to_ground = true
		bm.player_units.append(a)
		bm.player_units.append(b)
		bm._apply_shell_blast(a.global_position + m(35, 0), null)
		bm._apply_shell_blast(b.global_position + m(35, 0), null)
		counts_standing += a.max_pips - a.pips
		counts_lying += b.max_pips - b.pips
		bm.player_units.erase(a)
		bm.player_units.erase(b)
		a.free()
		b.free()
	check(counts_lying > 0 and float(counts_lying) < 0.6 * float(counts_standing), "a squad 35 m from a burst: lying costs under 60 percent of standing (%d against %d)" % [counts_lying, counts_standing])

	# a squad's people are spread over 30 m, each rolled at his own distance: a round on its centre costs it most but not all of the nine (the unit's own
	# distance would give 9 with R1 20 m; with 13 m about 6.8 are lost and 2.2 spared)
	var spared := 0
	for i in 300:
		var sq: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point + m(0, 4000))
		bm.player_units.append(sq)
		bm._apply_shell_blast(sq.global_position, null)
		spared += sq.pips
		bm.player_units.erase(sq)
		sq.free()
	var expected_spared: float = 9.0 * (1.0 - disc_mean_chance(GameConfig.BLAST_SQUAD_SPREAD_M, 1.0))
	check(absf(float(spared) / 300.0 - expected_spared) < 0.6, "a round on the centre of a squad of nine leaves about %.1f of them untouched (%.2f; the blast takes a few of those)" % [expected_spared, float(spared) / 300.0])

	# --- the friendly-fire estimate follows the same radii: a round that can only land a long way from a unit endangers it not at all, one near does
	var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, open_point + m(0, 5000))
	bm.player_units.append(gun)
	var friendly: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point + m(0, 5200))
	bm.player_units.append(friendly)
	var foe: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, open_point + m(0, 5200) + m(300, 0))
	bm.enemy_units.append(foe)
	var far_check: Dictionary = bm._mortar_friendly_fire_check(gun, foe, friendly.global_position + m(250, 0))
	check(far_check.risk < 0.01 and not far_check.endangered, "an aim point 250 m from our squad: no risk (%s)" % str(far_check))
	var near_check: Dictionary = bm._mortar_friendly_fire_check(gun, foe, friendly.global_position + m(70, 0))
	check(near_check.risk > far_check.risk, "...and at 70 m (a man of its ring is within R3) there is some (%s against %s)" % [str(near_check.risk), str(far_check.risk)])

	print("Fragment radii tests: %d failures" % failures)
	quit(1 if failures else 0)
