extends SceneTree
## Fragments as three radii. User, 2026-10-22: "for people standing and without cover, let's use three radii. R1 for potential lethal wounds, R2 for
## potential serious wounds, and R3 for potential light wounds. However, an actual hit should sometimes be less serious than the potential. Give it a 40%
## chance to be at its potential level, 30% to be one level lower, and 30% to be two levels lower ... For each person inside of any radius, roll everything
## that might apply, then take only the worst outcome that actually applies. For example, if a person is hit by a 'potentially lethal' fragment that gets
## reduced two levels, and a 'potentially serious' fragment that is not reduced, they would end up with a serious wound only. For now, try R1=20 meters,
## R2=2R1, and R3=3R1."
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

## The levels of the potentials at this distance as text, "1, 2, 3".
func levels(distance_m: float) -> String:
	var parts: Array[String] = []
	for level in CombatResolver.fragment_potentials(distance_m):
		parts.append(str(level))
	return ", ".join(parts)

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

func run() -> void:
	# --- the radii: R1 20 m, R2 40 m, R3 60 m
	check(levels(0.0) == "1, 2, 3", "inside R1: light, serious and lethal potentials")
	check(levels(20.0) == "1, 2, 3", "exactly R1 is inside it")
	check(levels(20.5) == "1, 2", "between R1 and R2: light and serious")
	check(levels(40.0) == "1, 2", "exactly R2 is inside it")
	check(levels(40.5) == "1", "between R2 and R3: light only")
	check(levels(60.0) == "1", "exactly R3 is inside it")
	check(levels(60.5) == "", "past R3: nothing")

	# --- one potential, reduced: 40 percent as it is, 30 one lower, 30 two lower
	for level in [1, 2, 3]:
		check(CombatResolver.fragment_reduced(level, 0.0) == level and CombatResolver.fragment_reduced(level, 0.399) == level, "level %d: as it is below 0.4" % level)
		check(CombatResolver.fragment_reduced(level, 0.4) == level - 1 and CombatResolver.fragment_reduced(level, 0.699) == level - 1, "level %d: one lower from 0.4 to 0.7" % level)
		check(CombatResolver.fragment_reduced(level, 0.7) == maxi(level - 2, 0) and CombatResolver.fragment_reduced(level, 0.999) == maxi(level - 2, 0), "level %d: two lower from 0.7 (never below none)" % level)

	# --- the worst outcome of everything that applies, worked out
	var inside_r1 := CombatResolver.fragment_distribution(10.0)
	check(near(inside_r1[0], 0.0, 1e-9) and near(inside_r1[3], 0.40, 1e-9) and near(inside_r1[2], 0.42, 1e-9) and near(inside_r1[1], 0.18, 1e-9), "within R1: nobody untouched; dead 40, serious 42, walking 18 percent (%s)" % str(inside_r1))
	var inside_r2 := CombatResolver.fragment_distribution(30.0)
	check(near(inside_r2[3], 0.0, 1e-9) and near(inside_r2[2], 0.40, 1e-9) and near(inside_r2[1], 0.42, 1e-9) and near(inside_r2[0], 0.18, 1e-9), "between R1 and R2: serious 40, walking 42, untouched 18 percent (%s)" % str(inside_r2))
	var inside_r3 := CombatResolver.fragment_distribution(50.0)
	check(near(inside_r3[1], 0.40, 1e-9) and near(inside_r3[0], 0.60, 1e-9) and near(inside_r3[2] + inside_r3[3], 0.0, 1e-9), "between R2 and R3: walking 40, untouched 60 percent (%s)" % str(inside_r3))
	check(CombatResolver.fragment_casualty_chance(61.0) == 0.0, "past R3 nobody is hurt")
	check(near(CombatResolver.fragment_casualty_chance(30.0), 0.82, 1e-9) and near(CombatResolver.fragment_casualty_chance(50.0), 0.40, 1e-9) and near(CombatResolver.fragment_casualty_chance(5.0), 1.0, 1e-9), "chance of any wound: 1 within R1, 0.82 within R2, 0.40 within R3")

	# --- the rolled outcome agrees with the worked-out one, at each radius and with a share of the potentials applying
	seed(31)
	for case in [{"d": 10.0, "x": 1.0}, {"d": 30.0, "x": 1.0}, {"d": 50.0, "x": 1.0}, {"d": 10.0, "x": 0.3}, {"d": 30.0, "x": 0.5}]:
		var rolled := sampled(case.d, case.x, 20000)
		var worked := CombatResolver.fragment_distribution(case.d, case.x)
		var agree := true
		for k in 4:
			if absf(rolled[k] - worked[k]) > 0.015:
				agree = false
		check(agree, "%.0f m, exposure %.1f: rolled %s against worked out %s" % [case.d, case.x, str(rolled), str(worked)])
	var sum := 0.0
	for p in CombatResolver.fragment_distribution(10.0, 0.37):
		sum += p
	check(near(sum, 1.0, 1e-9), "the chances add up to one")

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
	check(CombatResolver.fragment_exposure(up, 10.0, GameConfig.TerrainType.OPEN) == 1.0, "standing in the open: every potential applies")
	var down: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point + m(0, 500))
	bm.player_units.append(down)
	down.gone_to_ground = true
	check(near(CombatResolver.fragment_exposure(down, 10.0, GameConfig.TerrainType.OPEN), GameConfig.PRONE_IN_OPEN_FACTOR, 1e-6), "lying in the open: a third of the potentials")
	var inside: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, building_point)
	bm.player_units.append(inside)
	var in_building: float = CombatResolver.fragment_exposure(inside, 10.0, GameConfig.TerrainType.BUILDING)
	check(in_building < 0.3 and in_building > 0.1, "standing in a building: well under a third (%.3f)" % in_building)
	check(CombatResolver.fragment_exposure(inside, 50.0, GameConfig.TerrainType.BUILDING) < in_building, "...and less the further the burst, which only the weak far fragments reach")

	# --- in a battle: a lone man in the open at a given distance, the fragments alone (past the 10 m of the blast)
	var results := {}
	for d in [15.0, 30.0, 50.0, 65.0]:
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
		results[d] = counts
	var at15: Array = results[15.0]
	check(at15[0] == 0 and at15[3] > 200 and at15[3] < 280, "15 m: nobody untouched, about 40 percent dead (%s)" % str(at15))
	var at30: Array = results[30.0]
	check(at30[3] == 0 and at30[2] > 190 and at30[2] < 290 and at30[0] > 60 and at30[0] < 160, "30 m: nobody dead, about 40 percent serious, 18 untouched (%s)" % str(at30))
	var at50: Array = results[50.0]
	check(at50[3] + at50[2] == 0 and at50[1] > 190 and at50[1] < 290, "50 m: at most a light wound, 40 percent of the time (%s)" % str(at50))
	var at65: Array = results[65.0]
	check(at65[0] == 600, "65 m: past R3, nobody is hurt (%s)" % str(at65))

	# a crew of five at 50 m: each man a light wound 40 percent of the time, so about two of five are lost
	var lost := 0
	var crews := 300
	for i in crews:
		var crew: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, open_point + m(0, 2000))
		bm.enemy_units.append(crew)
		crew.mortar_rounds_remaining = 0
		bm._apply_shell_blast(crew.global_position + m(50, 0), null)
		lost += crew.crew_casualties
		bm.enemy_units.erase(crew)
		crew.free()
	var mean_lost: float = float(lost) / float(crews)
	check(mean_lost > 1.5 and mean_lost < 2.6, "a crew 50 m from a burst loses about two of its five (%.2f)" % mean_lost)

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

	# a squad's people are spread over 30 m, each rolled at his own distance: a round on its centre leaves about one in ten untouched (a third of the people
	# are past R1 where the serious and light potentials may miss), not none, which is what the unit's own distance would give
	var spared := 0
	for i in 300:
		var sq: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point + m(0, 4000))
		bm.player_units.append(sq)
		bm._apply_shell_blast(sq.global_position, null)
		spared += sq.pips
		bm.player_units.erase(sq)
		sq.free()
	check(float(spared) / 300.0 > 0.5 and float(spared) / 300.0 < 1.6, "a round on the centre of a squad of nine leaves about one of them untouched (%.2f)" % (float(spared) / 300.0))

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
