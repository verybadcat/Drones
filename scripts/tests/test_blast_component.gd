extends SceneTree
## Blast as its own injury component, beside the fragments. User, 2026-10-22: "we are going to split out wounds into blast and fragments. For the blast
## component: 0-1 meters: dead; 2-4 meters: serious; 5-10 meters: walking. In between those ranges, have it probabilistic and linear, so 60/40 dead or
## serious at 1.4 meters for example. If you are in vegetation, then 33% of the time, you completely escape blast effects, regardless of the above. If
## you are in a building, it is 67% of the time." A person hurt by blast and by fragments counts once, as the more severe.
##
## Run: godot --headless --path . --script scripts/tests/test_blast_component.gd
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

## How many of 1000 evenly spaced rolls (at the middle of each thousandth, clear of the edges) give each severity at this distance: [none, walking, serious, dead].
func split_at(distance_m: float) -> Array:
	var counts := [0, 0, 0, 0]
	for k in 1000:
		counts[CombatResolver.blast_severity(distance_m, (float(k) + 0.5) / 1000.0)] += 1
	return counts

func run() -> void:
	# --- the bands
	for d in [0.0, 0.5, 1.0]:
		check(split_at(d) == [0, 0, 0, 1000], "%.1f m: dead (%s)" % [d, str(split_at(d))])
	check(split_at(1.4) == [0, 0, 400, 600], "1.4 m: 60 percent dead, 40 serious (%s)" % str(split_at(1.4)))
	check(split_at(1.5) == [0, 0, 500, 500], "1.5 m: half and half (%s)" % str(split_at(1.5)))
	check(split_at(1.9) == [0, 0, 900, 100], "1.9 m: 10 percent dead (%s)" % str(split_at(1.9)))
	for d in [2.0, 3.0, 4.0]:
		check(split_at(d) == [0, 0, 1000, 0], "%.1f m: serious (%s)" % [d, str(split_at(d))])
	check(split_at(4.5) == [0, 500, 500, 0], "4.5 m: half serious, half walking (%s)" % str(split_at(4.5)))
	check(split_at(4.2) == [0, 200, 800, 0], "4.2 m: 80 percent serious (%s)" % str(split_at(4.2)))
	for d in [5.0, 7.5, 10.0]:
		check(split_at(d) == [0, 1000, 0, 0], "%.1f m: walking (%s)" % [d, str(split_at(d))])
	for d in [10.01, 30.0, 200.0]:
		check(split_at(d) == [1000, 0, 0, 0], "%.2f m: nothing (%s)" % [d, str(split_at(d))])

	# --- the escape
	check(CombatResolver.blast_escape_chance(GameConfig.TerrainType.OPEN) == 0.0, "in the open nobody escapes the blast")
	check(is_equal_approx(CombatResolver.blast_escape_chance(GameConfig.TerrainType.TREES), 0.33), "in vegetation 33 percent escape")
	check(is_equal_approx(CombatResolver.blast_escape_chance(GameConfig.TerrainType.BUILDING), 0.67), "in a building 67 percent escape")
	check(absf(CombatResolver.blast_escape_chance(GameConfig.TerrainType.TREES, 0.5) - 0.1815) < 0.001, "a unit moving through vegetation keeps part of it (0.18)")
	check(absf(CombatResolver.blast_escape_chance(GameConfig.TerrainType.BUILDING, 0.9) - 0.6317) < 0.001, "a unit moving through a building keeps almost all of it (0.63)")

	# --- a person's own distance
	seed(7)
	var total := 0.0
	var inside := true
	for i in 4000:
		var d: float = CombatResolver.person_distance_m(0.0, 30.0)
		total += d
		if d > 30.0 + 0.001:
			inside = false
	check(inside and absf(total / 4000.0 - 20.0) < 1.0, "spread over 30 m round the burst: within 30 m, mean about 20 m (%.1f)" % (total / 4000.0))
	var far_ok := true
	for i in 500:
		var d2: float = CombatResolver.person_distance_m(100.0, 30.0)
		if d2 < 69.9 or d2 > 130.1:
			far_ok = false
	check(far_ok, "a burst 100 m from the centre of a 30 m spread is 70-130 m from its people")
	check(CombatResolver.person_distance_m(12.0, 0.0) == 12.0, "a lone person is where the unit is")

	# --- in a battle
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	var open_point: Vector2 = m(-5000, -5000)

	# a lone person (a spotter) in the open at different distances from a burst, 400 times each
	var expectations := {}
	for case in [{"d": 0.5, "n": 400}, {"d": 3.0, "n": 400}, {"d": 7.0, "n": 400}, {"d": 12.0, "n": 400}]:
		var killed := 0
		var heavily := 0
		var walking := 0
		var none := 0
		for i in case.n:
			var s: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, open_point)
			bm.player_units.append(s)
			bm._apply_shell_blast(open_point + m(case.d, 0), null)
			killed += s.killed_count
			heavily += s.heavily_wounded_count
			walking += s.walking_wounded_count
			if s.pips == s.max_pips:
				none += 1
			check(s.killed_count + s.heavily_wounded_count + s.walking_wounded_count == s.max_pips - s.pips, "everyone lost is in exactly one count")
			bm.player_units.erase(s)
			s.free()
		expectations[case.d] = [killed, heavily, walking, none]
	var at05: Array = expectations[0.5]
	check(at05[0] == 400, "0.5 m: dead, every time (%s)" % str(at05))
	var at3: Array = expectations[3.0]
	check(at3[3] == 0 and at3[2] == 0 and at3[1] > 230 and at3[0] < 170, "3 m: always a casualty, serious or dead, never walking; fragments make some of the serious dead (%s)" % str(at3))
	var at7: Array = expectations[7.0]
	# 7 m is inside R1 and inside the blast's walking band: the blast leaves him walking at least, the fragments dead 40 percent of the time, serious 42, else walking
	check(at7[3] == 0 and at7[0] > 130 and at7[0] < 190 and at7[1] > 140 and at7[1] < 200 and at7[2] > 40 and at7[2] < 100, "7 m: about 40 percent dead, 42 serious, 18 walking, nobody untouched (%s)" % str(at7))
	var at12: Array = expectations[12.0]
	check(at12[3] < 40 and at12[0] > 100 and at12[0] < 175, "12 m, past the blast: only the fragments, who within R1 kill about a third of the time and leave one in forty untouched (%s)" % str(at12))

	# in vegetation and in a building at 7 m
	var tree_point := Vector2.INF
	for x in range(-2000, 6000, 40):
		for y in range(-500, 6000, 40):
			var p := m(x, y)
			if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.TREES and GameConfig.get_terrain_type_at(p + m(7, 0)) != GameConfig.TerrainType.BUILDING:
				tree_point = p
				break
		if not is_inf(tree_point.x):
			break
	check(not is_inf(tree_point.x), "setup: a place in vegetation was found")
	var building_point: Vector2 = GameConfig._building_rects[0].get_center()
	for case in [{"name": "vegetation", "at": tree_point, "low": 0.62, "high": 0.90}, {"name": "a building", "at": building_point, "low": 0.30, "high": 0.60}]:
		if is_inf(case.at.x):
			continue
		var hurt := 0
		var trials := 600
		for i in trials:
			var s2: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, case.at)
			bm.player_units.append(s2)
			bm._apply_shell_blast(case.at + m(2.0, 0), null) # 2 m: dead on the blast alone, so a casualty unless it is escaped
			if s2.pips < s2.max_pips:
				hurt += 1
			bm.player_units.erase(s2)
			s2.free()
		var rate: float = float(hurt) / float(trials)
		# hurt unless the blast is escaped AND the fragments (reduced by the cover) also miss
		var probe: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, case.at)
		var escape: float = CombatResolver.blast_escape_chance(probe.exposure_terrain(), probe.cover_kept())
		var expected: float = 1.0 - escape * (1.0 - CombatResolver.fragment_casualty_chance(2.0, CombatResolver.fragment_person_exposure(probe, case.at + m(2.0, 0), case.at)))
		probe.free()
		check(absf(rate - expected) < 0.07 and escape > 0.3, "2 m from a burst in %s: %.2f hurt (expected %.2f)" % [case.name, rate, expected])

	# a squad is spread over 30 m: a burst on its centre catches about one of nine by blast, not all of them
	var blast_total := 0
	var casualties_total := 0
	for i in 400:
		var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point)
		bm.player_units.append(squad)
		var landed: Array[Dictionary] = bm._apply_shell_blast(open_point, null)
		for rec in landed:
			if rec.unit == squad:
				blast_total += int(rec.by_blast)
				casualties_total += int(rec.casualties)
		bm.player_units.erase(squad)
		squad.free()
	var mean_blast: float = float(blast_total) / 400.0
	check(mean_blast > 0.1 and mean_blast < 0.45, "a burst on the centre of a squad of nine: about one of them is within the blast, and by blast alone or as much as the fragments hurts a fifth to a third of those (%.2f)" % mean_blast)
	check(float(casualties_total) / 400.0 > 7.5 and float(casualties_total) / 400.0 < 8.7, "...the fragments do the rest: with R1 20 m, a squad spread over 30 m loses about 8 of 9 (%.2f casualties a round)" % (float(casualties_total) / 400.0))
	var far_blast := 0
	for i in 200:
		var squad2: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point)
		bm.player_units.append(squad2)
		var landed2: Array[Dictionary] = bm._apply_shell_blast(open_point + m(55, 0), null)
		for rec in landed2:
			if rec.unit == squad2:
				far_blast += int(rec.by_blast)
		bm.player_units.erase(squad2)
		squad2.free()
	check(far_blast == 0, "a burst 55 m from a squad's centre is beyond the blast of all its people (%d)" % far_blast)

	# a mortar crew within a few metres of the burst is wrecked
	var wrecked := 0
	for i in 200:
		var crew: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, open_point)
		bm.player_units.append(crew)
		crew.mortar_rounds_remaining = 0
		bm._apply_shell_blast(open_point + m(2.0, 0), null)
		if crew.crew_casualties >= crew.crew_size - 1:
			wrecked += 1
		check(crew.killed_count + crew.heavily_wounded_count + crew.walking_wounded_count == crew.crew_casualties, "the crew's casualties are all in one count")
		bm.player_units.erase(crew)
		crew.free()
	check(wrecked > 150, "a burst 2 m from the tube leaves a crew of four with one or none standing (%d of 200)" % wrecked)

	print("Blast component tests: %d failures" % failures)
	quit(1 if failures else 0)
