extends SceneTree
## Direct user instruction: "A mortar that a drone has spotted should not conceal itself unless it can do so effectively. This seems unlikely.
## Rather, it should act in a way that makes it least likely to be hit. This might mean taking cover. It also might mean continually moving in
## unpredictable directions. It's a reasonable research question which is better. ... Yes do both." (both: the diagnostic and the edge look)
## Research, from the game's own numbers (flight 40 s, evasion radius 40 m, drone-corrected dispersion converging to 6 m in two rounds): after
## two minutes of fire a crew that stays put loses all five whether in the open (5.0) or in trees (4.2), straight-line movement loses all five
## (the round is led by heading), and movement that turns every 3, 5, 10 or 20 s loses 0.26, 0.45, 1.20 and 2.19. Hence: keep moving, turn
## every 4 s. Also fixed: a mortar that only a drone could see fled the map when the drone drifted past the hidden-detection range (250 m)
## while the crew's own visibility flag was still retained to 1.5 times it; the exemption now judges at the same retained range. And the
## last-resort flee's reason names who had it in sight.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_evades_drone_observation.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func make() -> Dictionary:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	bm.scenario_elapsed_time = 1000.0
	var um: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1700)); bm.player_units.append(um)
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, m(4620, 1700)); bm.player_units.append(drone)
	bm.active_drone = drone
	drone.is_visible = true # the enemy crew has seen the drone
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4600, 1700)); bm.enemy_units.append(em)
	bm._set_retreat_profile(em, Unit.Team.ENEMY)
	em.is_visible = true
	em.seconds_stationary = 1e9
	em.mortar_rounds_remaining = 15
	bm.unit_type_doctrines[Unit.Team.ENEMY] = preload("res://scripts/unit_doctrine.gd").sanitize({})
	bm.unit_type_doctrines[Unit.Team.PLAYER] = preload("res://scripts/unit_doctrine.gd").sanitize({})
	return {"bm": bm, "um": um, "drone": drone, "em": em}

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var c := make()
	var bm: BattleManager = c.bm
	var em: Unit = c.em
	var origin: Vector2 = em.global_position
	# 1. watched by a drone and aware of it: it keeps moving, changing direction at random intervals of 15-30 s (a shooter aiming at
	# where it stands would hit a crew that turns every few seconds, since it never gets 40 m away in the 40 s a round is in the air)
	var headings: Array[float] = []
	var turn_times: Array[float] = []
	var last_target := Vector2.ZERO
	var moving_ticks := 0
	var in_building := 0
	var max_stray := 0.0
	var ticks := 400
	for i in ticks:
		bm.scenario_elapsed_time += 1.0
		em.is_visible = true
		bm._decide_mortar_action(em)
		if em.has_move_target:
			moving_ticks += 1
			if not headings.is_empty() and not em.move_target.is_equal_approx(last_target):
				turn_times.append(float(i)) # a new leg was issued: a change of heading (some are by only a few degrees)
			last_target = em.move_target
			headings.append((em.move_target - em.global_position).angle())
			bm._step_toward_target(em, 1.0)
		if GameConfig.is_building_at(em.global_position):
			in_building += 1
		max_stray = maxf(max_stray, em.global_position.distance_to(origin))
	check(moving_ticks >= ticks - 5, "A mortar watched by a drone it has seen keeps moving (%d of %d ticks)" % [moving_ticks, ticks])
	check(bm._mortar_move_intent.get(em, "") == "evade_observed", "...as an evasive manoeuvre, not a concealment (%s)" % str(bm._mortar_move_intent.get(em, "")))
	var gaps: Array[float] = []
	for k in range(1, turn_times.size()):
		gaps.append(turn_times[k] - turn_times[k - 1])
	var shortest := 999.0
	var longest := 0.0
	var gap_sum := 0.0
	for g in gaps:
		shortest = minf(shortest, g)
		longest = maxf(longest, g)
		gap_sum += g
	check(turn_times.size() >= 9 and turn_times.size() <= 26, "...turning to a new direction now and then (%d turns in %d s)" % [turn_times.size(), ticks])
	check(gaps.size() >= 8 and shortest >= BattleManager.EVASION_TURN_MIN_S - 1.0 and longest <= BattleManager.EVASION_TURN_MAX_S + 1.0, "...never sooner than %d s or later than %d s after the last turn (shortest %.0f, longest %.0f)" % [int(BattleManager.EVASION_TURN_MIN_S), int(BattleManager.EVASION_TURN_MAX_S), shortest, longest])
	check(longest - shortest >= 5.0, "...at random intervals, not a fixed one (%.0f to %.0f s)" % [shortest, longest])
	check(not gaps.is_empty() and gap_sum / float(gaps.size()) > 19.0 and gap_sum / float(gaps.size()) < 26.0, "...about 22 s apart on average (%.1f)" % (gap_sum / float(maxi(gaps.size(), 1))))
	check(in_building == 0, "...never through a building")
	check(max_stray < m(450, 0).x, "...and staying near where it began (%.0f m at most)" % (max_stray / GameConfig.PIXELS_PER_METER))
	check(str(bm._mortar_reasoning.get(em, {}).get("detail", "")).contains("unpredictably"), "...and says why in its reasoning")
	# 2. when the watching stops, it stops (after the hold)
	em.is_visible = false
	bm.scenario_elapsed_time += BattleManager.EVASION_HOLD_S - 5.0
	bm._decide_mortar_action(em)
	check(bm._mortar_evasion.has(em), "It does not stop the instant the watching does (within the hold)")
	bm.scenario_elapsed_time += 10.0
	bm._decide_mortar_action(em)
	check(not bm._mortar_evasion.has(em) and not em.has_move_target, "...but stops once the hold has run out")
	bm.combat_log.free()
	bm.free()

	# 3. an armed threat close by takes over: the ordinary ladder, not the manoeuvre
	c = make()
	bm = c.bm
	em = c.em
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, em.global_position + m(-300, 0))
	bm.player_units.append(squad)
	squad.is_visible = true
	bm._update_player_intel()
	bm._update_enemy_intel() if bm.has_method("_update_enemy_intel") else null
	squad.enemy_has_been_sighted = true
	squad.enemy_known_position = squad.global_position
	bm._decide_mortar_action(em)
	check(bm._mortar_move_intent.get(em, "") != "evade_observed", "With an armed squad close by it is the ordinary ladder that decides, not the drone manoeuvre (%s)" % str(bm._mortar_move_intent.get(em, "")))
	bm.combat_log.free()
	bm.free()

	# 4. the boundary: a mortar in trees with the drone 265 m off (past the 250 m hidden range, inside the retained 375 m) is still "only a drone"
	c = make()
	bm = c.bm
	em = c.em
	var tree_spot := Vector2.INF
	for z in GameConfig._all_cover_zones():
		if z.type == GameConfig.TerrainType.TREES and z.center.x > m(3000, 0).x and z.center.x < m(4600, 0).x:
			tree_spot = z.center
			break
	check(not is_inf(tree_spot.x), "Setup: a wood on the east side")
	if not is_inf(tree_spot.x):
		em.global_position = tree_spot
		c.drone.global_position = tree_spot + m(265, 0)
		em.is_visible = true
		check(GameConfig.is_in_cover(GameConfig.get_terrain_type_at(em.global_position)), "Setup: the mortar is in cover (250 m hidden range)")
		check(bm._mortar_troubled_only_by_unarmed_observers(em), "A mortar in trees with a drone 265 m away (past 250 m, inside the retained 375 m) is judged to be troubled only by a drone")
	bm.combat_log.free()
	bm.free()

	# 5. the flee reason names who had it in sight
	c = make()
	bm = c.bm
	em = c.em
	em.global_position = m(4985, 1700)
	var watcher: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, em.global_position + m(-150, 0))
	bm.player_units.append(watcher)
	watcher.is_visible = true
	em.is_visible = true
	bm._mortar_flee_as_last_resort(em)
	check(em.last_order_reason.contains("in sight of") and em.last_order_reason.contains("(armed)"), "The last-resort flee records who had it in sight (%s)" % em.last_order_reason)
	bm.combat_log.free()
	bm.free()
	print("Mortar drone evasion tests: %d failures" % failures)
	quit(1 if failures else 0)
