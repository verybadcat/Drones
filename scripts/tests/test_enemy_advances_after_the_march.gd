extends SceneTree
## Direct user report: "the enemy is not advancing, for no good reason that I can see." The live
## snapshot showed 14 enemy squads parked at the last waypoint of the road, no move order, still
## reading "Following the assigned march route", 1400 m from the friendly squads (which had fallen
## back): the advance-by-bounds tier only ran for a squad that had broken from the march, and only
## contact breaks a squad from it. A squad whose march has run its course must press on by itself.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_advances_after_the_march.gd
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = TestCombatLogScript.new()
	return bm

func run() -> void:
	test_a_squad_that_finished_its_march_advances()
	test_a_squad_still_marching_is_left_alone()
	test_the_whole_force_parked_at_the_road_end_moves_on()
	test_squads_at_the_village_push_west()
	test_with_no_mortar_left_the_enemy_attacks_the_squads_it_knows()
	test_a_nearby_unengaged_squad_closes_on_a_known_spotter()
	test_a_distant_squad_does_not_bother_with_a_far_off_spotter()
	test_a_squad_already_engaging_a_real_squad_does_not_divert()
	test_only_one_of_several_nearby_squads_diverts()
	test_a_known_but_destroyed_spotter_is_not_pursued()
	test_spotter_hunt_applies_even_with_an_active_known_friendly_mortar()
	test_a_marching_squad_breaks_off_to_deal_with_a_known_spotter()
	print("Enemy advance after march tests: %d failures" % failures)
	quit(1 if failures else 0)


func meters(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

## A squad standing at the end of the road: route walked, nothing queued, never in contact.
func parked_squad(bm, position_m: Vector2) -> Unit:
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(position_m.x, position_m.y))
	squad.set_path([squad.global_position])
	squad.has_move_target = false # arrived at the last waypoint
	squad.move_queue.clear()
	bm.enemy_units.append(squad)
	return squad


func test_a_squad_that_finished_its_march_advances() -> void:
	var bm = make_battle()
	# The friendly force is far away and has fallen back: nothing in range, nobody to fire at.
	var mine: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, meters(100.0, 1200.0))
	bm.player_units.append(mine)
	var squad := parked_squad(bm, GameConfig.CURRENT_MAP.road_waypoints_m[-1])
	check(not squad.sought_cover and not squad.has_move_target, "Set-up: parked, never broke from the march")
	seed(2)
	bm._update_enemy_squad_advance()
	check(squad.has_move_target, "It is ordered forward (%s)" % squad.last_order_reason)
	check(squad.move_target.distance_to(GameConfig.CURRENT_MAP.village_center) < squad.global_position.distance_to(GameConfig.CURRENT_MAP.village_center), "...toward the objective, not away from it")
	check(squad.sought_cover, "...now an advancing squad, not one on the scripted march")
	check(squad.movement_predictable == false and squad.move_speed == GameConfig.ENEMY_ADVANCE_SPEED, "...as a rush, at the advance speed")
	bm.combat_log.free()
	bm.free()


func test_a_squad_still_marching_is_left_alone() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(4800.0, 1900.0))
	var path: Array[Vector2] = [meters(4000.0, 1900.0), meters(3000.0, 1500.0)]
	squad.set_path(path)
	bm.enemy_units.append(squad)
	bm._update_enemy_squad_advance()
	check(not squad.sought_cover and squad.move_target == path[0] and squad.move_queue.size() == 1, "Mid-march it keeps its route")
	# Between two waypoints of the march (current leg done, another queued): still marching.
	squad.has_move_target = false
	squad.move_queue = [path[1]]
	bm._update_enemy_squad_advance()
	check(not squad.sought_cover and not squad.has_move_target, "A squad with a leg still queued is not treated as arrived")
	bm.combat_log.free()
	bm.free()


func test_the_whole_force_parked_at_the_road_end_moves_on() -> void:
	var bm = make_battle()
	var mine: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, meters(100.0, 1200.0))
	bm.player_units.append(mine)
	var end: Vector2 = GameConfig.CURRENT_MAP.road_waypoints_m[-1]
	var squads: Array[Unit] = []
	for i in 6:
		squads.append(parked_squad(bm, end + Vector2(0.0, 40.0 * i - 100.0)))
	seed(4)
	bm._update_enemy_squad_advance()
	var moving := 0
	for s in squads:
		if s.has_move_target:
			moving += 1
	check(moving >= 5, "Nearly all of them move on (%d of 6)" % moving)
	bm.combat_log.free()
	bm.free()


## Direct user decision: "Yes, push West" — a squad that has closed on the village, with the friendly
## force fallen back and unseen, goes on west after it instead of stopping at the village.
func test_squads_at_the_village_push_west() -> void:
	var bm = make_battle()
	var mine: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, meters(-1000.0, 1500.0)) # fallen back, unseen
	bm.player_units.append(mine)
	var village: Vector2 = GameConfig.CURRENT_MAP.village_center
	# Standing on the standoff ring east of the village, as a squad that has closed on it does.
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, village + Vector2(GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS, 0.0))
	squad.sought_cover = true
	bm.enemy_units.append(squad)
	var objective: Vector2 = bm._enemy_advance_objective(squad)
	check(squad.village_reached, "Reaching the village is noted")
	check(objective.x < village.x - 1000.0 * GameConfig.PIXELS_PER_METER, "Its objective is now far to the west, not the village (%.0f m)" % (objective.x / GameConfig.PIXELS_PER_METER))
	seed(6)
	bm._update_enemy_squad_advance()
	check(squad.has_move_target and squad.move_target.x < squad.global_position.x, "It is ordered west")
	# The latch holds once it has moved off the ring (the village is now BEHIND it, farther than the ring).
	squad.global_position = village + Vector2(-600.0 * GameConfig.PIXELS_PER_METER, 0.0)
	check(bm._enemy_advance_objective(squad).x < village.x - 1000.0 * GameConfig.PIXELS_PER_METER, "...and it does not turn back to the village")
	# A squad that has not reached the village still heads for it.
	var far_squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, village + Vector2(2000.0 * GameConfig.PIXELS_PER_METER, 0.0))
	bm.enemy_units.append(far_squad)
	check(bm._enemy_advance_objective(far_squad) == village and not far_squad.village_reached, "A squad still short of the village heads for the village")
	# With nothing of the friendly side left in the field, there is nobody to push on after.
	mine.state = Unit.State.DESTROYED
	var last_squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, village + Vector2(GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS, 0.0))
	bm.enemy_units.append(last_squad)
	check(bm._enemy_advance_objective(last_squad) == village, "With no friendly force left in the field it stays at the village")
	bm.combat_log.free()
	bm.free()


## Direct user report: "At this point, the enemy has chased our mortar off of the map. They now know the
## approximate location of our squads. With no more mortar for our side, I would expect them to attack our
## squads." Three enemy squads stood at the west edge (where the mortar fled), pushing on that edge, with our
## squads 1300 m behind them and known.
func test_with_no_mortar_left_the_enemy_attacks_the_squads_it_knows() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, meters(-1400.0, 2100.0))
	mortar.state = Unit.State.WITHDRAWN # fled off the map
	bm.player_units.append(mortar)
	var ours_a: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, meters(210.0, 1940.0))
	var ours_b: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, meters(560.0, 2050.0))
	for s in [ours_a, ours_b]:
		bm.player_units.append(s)
		s.enemy_has_been_sighted = true # the enemy has seen them
		s.enemy_known_position = s.global_position
		s.enemy_known_state = Unit.State.ACTIVE
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-1100.0, 1190.0))
	enemy.sought_cover = true
	enemy.village_reached = true # it had pushed west past the village
	bm.enemy_units.append(enemy)
	# With the numbers to attack (2:1 or better: see test_enemy_consolidation.gd for what less does).
	for i in 3:
		var extra: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-1000.0, 1300.0 + 60.0 * i))
		bm.enemy_units.append(extra)
	bm._update_enemy_attack_stance()
	var objective: Vector2 = bm._enemy_advance_objective(enemy)
	check(objective.distance_to(ours_a.global_position) < 1.0, "Its objective is the nearest of our squads it knows of, not the map edge (%s)" % (objective / GameConfig.PIXELS_PER_METER))
	seed(3)
	bm._update_enemy_squad_advance()
	check(enemy.has_move_target and enemy.move_target.x > enemy.global_position.x, "It is ordered east, toward our squads")
	# Nothing known: the push west (or the village) as before.
	for s in [ours_a, ours_b]:
		s.enemy_has_been_sighted = false
	check(bm._enemy_advance_objective(enemy).x < meters(-1000.0, 0.0).x, "With no squad known, it still pushes west")
	# A destroyed squad is not an objective (the enemy's own information is that it is out of the fight).
	ours_a.enemy_has_been_sighted = true
	ours_a.enemy_known_state = Unit.State.DESTROYED
	check(bm._known_friendly_squad_objective(enemy) == Vector2.INF, "A squad the enemy knows is out of the fight is not an objective")
	ours_a.enemy_known_state = Unit.State.ACTIVE
	# While our mortar is in action it stays the objective.
	mortar.state = Unit.State.ACTIVE
	mortar.enemy_has_been_sighted = true
	mortar.enemy_known_position = meters(-800.0, 1500.0)
	mortar.enemy_known_position_time = bm.scenario_elapsed_time
	check(bm._friendly_mortar_is_active(), "Set-up: the mortar is back in action")
	check(bm._enemy_advance_objective(enemy) != ours_a.global_position, "While the mortar is in action the squads are not its objective")
	bm.combat_log.free()
	bm.free()


## Direct user ruling: "If they have seen the spotter, enemy squads should try to kill the spotter."
## Unlike attacking a known squad (test_with_no_mortar_left_the_enemy_attacks_the_squads_it_knows, above,
## which needs a real 2:1 numerical case), going after an unarmed, undefended spotter needs no such case —
## this deliberately keeps the enemy force small (a single squad, no numeric advantage at all) to prove
## that difference.
## Direct live report: an enemy mortar was shelling a known friendly spotter while a nearby enemy squad did
## nothing about it. Direct user ruling in response: "If the spotter's position is known, near enemy
## squads, and easy to reach, ONE nearby squad should act to deal with it. However, if the enemy sees the
## spotter from far off, or if they are engaging friendly squads, they might choose not to." Replaces an
## earlier, broader design (a known spotter as every squad's unconditional #1 objective, gated only on no
## friendly mortar being active) with this proximity- and availability-gated single-squad response instead.
func known_spotter(bm, position_m: Vector2) -> Unit:
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, meters(position_m.x, position_m.y))
	bm.player_units.append(spotter)
	spotter.enemy_has_been_sighted = true
	spotter.enemy_known_position = spotter.global_position
	spotter.enemy_known_state = Unit.State.ACTIVE
	return spotter


func test_a_nearby_unengaged_squad_closes_on_a_known_spotter() -> void:
	var bm = make_battle()
	var spotter := known_spotter(bm, Vector2(210.0, 1940.0))
	# 700m off: beyond SQUAD_ENGAGEMENT_RANGE (400m, so an actual approach move is needed) but well within
	# SQUAD_DANGER_RANGE (1200m) — no numerical advantage needed at all, unlike attacking a real known squad
	# (contrast the squad-hunting test above, which needs three extra squads for exactly that reason).
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-490.0, 1940.0))
	enemy.sought_cover = true
	enemy.village_reached = true
	bm.enemy_units.append(enemy)
	check(bm._spotter_hunt_candidate() == enemy, "Set-up: it is the (only) candidate")
	bm._update_enemy_squad_advance()
	check(enemy.has_move_target and enemy.move_target.distance_to(spotter.global_position) < 1.0, "It closes directly on the spotter's known position (%s)" % enemy.last_order_reason)
	check(enemy.move_speed == GameConfig.ENEMY_ADVANCE_SPEED, "...at the advance speed, hot-pursuit style")
	# It stops advancing once within real engagement range rather than walking onto the spotter's own spot.
	enemy.global_position = spotter.global_position + Vector2(GameConfig.SQUAD_ENGAGEMENT_RANGE * 0.5, 0)
	enemy.has_move_target = false
	bm._chase_spotter_directly(enemy)
	check(not enemy.has_move_target, "Close enough already: no further move ordered")
	bm.combat_log.free()
	bm.free()


func test_a_distant_squad_does_not_bother_with_a_far_off_spotter() -> void:
	var bm = make_battle()
	known_spotter(bm, Vector2(210.0, 1940.0))
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(210.0 + GameConfig.SQUAD_DANGER_RANGE / GameConfig.PIXELS_PER_METER + 50.0, 1940.0))
	enemy.sought_cover = true
	enemy.village_reached = true
	bm.enemy_units.append(enemy)
	check(bm._spotter_hunt_candidate() == null, "Too far off (beyond SQUAD_DANGER_RANGE) to be worth diverting for")
	bm.combat_log.free()
	bm.free()


func test_a_squad_already_engaging_a_real_squad_does_not_divert() -> void:
	var bm = make_battle()
	known_spotter(bm, Vector2(210.0, 1940.0))
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-100.0, 1940.0))
	enemy.sought_cover = true
	enemy.village_reached = true
	bm.enemy_units.append(enemy)
	# A live, engageable player squad right in front of it (100m off, well inside SQUAD_ENGAGEMENT_RANGE) —
	# "if they are engaging friendly squads, they might choose not to [deal with the spotter]."
	var opposing: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, enemy.global_position + Vector2(100.0, 0) * GameConfig.PIXELS_PER_METER)
	bm.player_units.append(opposing)
	opposing.is_visible = true
	check(bm._squad_already_engaging_a_real_squad(enemy), "Set-up: a real squad is right there, in range and LOS")
	check(bm._spotter_hunt_candidate() == null, "Already tied up in a real fight: not offered up as the spotter-hunter")
	seed(5)
	bm._update_enemy_squad_advance()
	check(enemy.last_order_reason.begins_with("Staying to fight"), "It stays and fights the real squad instead (%s)" % enemy.last_order_reason)
	bm.combat_log.free()
	bm.free()


func test_only_one_of_several_nearby_squads_diverts() -> void:
	var bm = make_battle()
	var spotter := known_spotter(bm, Vector2(210.0, 1940.0))
	var near: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-490.0, 1940.0)) # 700m off
	near.sought_cover = true
	near.village_reached = true
	bm.enemy_units.append(near)
	var farther: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-790.0, 1940.0)) # 1000m off
	farther.sought_cover = true
	farther.village_reached = true
	bm.enemy_units.append(farther)
	check(bm._spotter_hunt_candidate() == near, "The NEARER of the two is the one chosen — 'ONE nearby squad', not every eligible one")
	seed(6)
	bm._update_enemy_squad_advance()
	check(near.move_target.distance_to(spotter.global_position) < 1.0, "The near squad closes on the spotter")
	check(farther.last_order_reason.find("spotter") == -1, "The farther squad's own order is unrelated to the spotter — it was never offered the assignment (%s)" % farther.last_order_reason)
	bm.combat_log.free()
	bm.free()


## A spotter the enemy believes destroyed is not a candidate to hunt at all — matches
## _known_friendly_spotter_position's own existing DESTROYED exclusion.
func test_a_known_but_destroyed_spotter_is_not_pursued() -> void:
	var bm = make_battle()
	var spotter := known_spotter(bm, Vector2(210.0, 1940.0))
	spotter.enemy_known_state = Unit.State.DESTROYED
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-100.0, 1940.0))
	enemy.sought_cover = true
	enemy.village_reached = true
	bm.enemy_units.append(enemy)
	check(bm._known_friendly_spotter_position(enemy) == Vector2.INF, "A spotter the enemy knows is out of the fight is not tracked as known")
	check(bm._spotter_hunt_candidate() == null, "...so it is never offered up as a hunt candidate either")
	bm.combat_log.free()
	bm.free()


## Direct user ruling covers this explicitly ("near enemy squads, and easy to reach" — no mention of the
## friendly mortar's own status as an exception): unlike the earlier, superseded design, this proximity-
## gated response applies REGARDLESS of whether a friendly mortar is also active and known.
func test_spotter_hunt_applies_even_with_an_active_known_friendly_mortar() -> void:
	var bm = make_battle()
	var spotter := known_spotter(bm, Vector2(210.0, 1940.0))
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, meters(-800.0, 1500.0))
	bm.player_units.append(mortar)
	mortar.enemy_has_been_sighted = true
	mortar.enemy_known_position = mortar.global_position
	mortar.enemy_known_position_time = bm.scenario_elapsed_time
	# 700m from the spotter, and well within SQUAD_DANGER_RANGE of the mortar too (538m) — a real,
	# simultaneously-valid mortar-hunt-assignment competing for the exact same squad.
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-490.0, 1940.0))
	enemy.sought_cover = true
	enemy.village_reached = true
	bm.enemy_units.append(enemy)
	check(bm._friendly_mortar_is_active(), "Set-up: a friendly mortar is active and known")
	check(bm._spotter_hunt_candidate() == enemy, "The known, active friendly mortar does not disqualify the nearby spotter-hunt")
	seed(7)
	bm._update_enemy_squad_advance()
	check(enemy.move_target.distance_to(spotter.global_position) < 1.0, "The squad still closes on the spotter, not the mortar")
	bm.combat_log.free()
	bm.free()


## Direct user report, a second occurrence of the same underlying bug: "Enemy mortar shot at it when an
## enemy squad could have easily done the job. The squad just kept moving." Root cause: this function's own
## top-level "still on its scripted march" gate skipped a marching squad before it ever reached the
## spotter-hunt tier at all, and _spotter_hunt_candidate itself additionally excluded any such squad from
## candidacy outright — so a squad marching straight past a known, easily-reachable spotter never even
## considered it, matching "just kept moving" exactly. Deliberately marches the squad AWAY from the spotter
## (not toward it) so a pass just from continuing the existing route can't be mistaken for a real fix.
func test_a_marching_squad_breaks_off_to_deal_with_a_known_spotter() -> void:
	var bm = make_battle()
	var spotter := known_spotter(bm, Vector2(210.0, 1940.0))
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, meters(-490.0, 1940.0)) # 700m off
	var path: Array[Vector2] = [meters(-2000.0, 1940.0), meters(-3000.0, 1940.0)] # marching away from the spotter
	squad.set_path(path)
	bm.enemy_units.append(squad)
	check(not squad.sought_cover, "Set-up: still on its scripted march, never broken off for any reason yet")
	check(bm._spotter_hunt_candidate() == squad, "Set-up: it is a valid, available candidate despite still marching")
	bm._update_enemy_squad_advance()
	check(squad.sought_cover, "It breaks off the scripted march...")
	check(squad.move_target.distance_to(spotter.global_position) < 1.0, "...to close directly on the known spotter, not continuing its old route (%s)" % (squad.move_target / GameConfig.PIXELS_PER_METER))
	bm.combat_log.free()
	bm.free()
