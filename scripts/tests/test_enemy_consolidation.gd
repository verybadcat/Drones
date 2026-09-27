extends SceneTree
## Direct user ruling: "Earlier I told you that if the friendly mortar was gone, enemy squads should attack the
## friendly squads. I am realizing that's not true if the enemy squads don't think they have a significant
## numerical advantage. If numbers are less than 2:1 in their favor, it would be reasonable for them to
## consolidate somewhere on the map, avoiding the friendly squads, and allowing a stalemate to happen. In this
## case, far-advanced enemies would try to navigate back to wherever the enemy is trying to consolidate,
## avoiding the friendly squads."
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_consolidation.gd
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

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

## Our mortar gone (withdrawn); `friendly` squads of ours the enemy knows of at their own positions;
## `enemy` enemy squads in a loose group at `at_m`.
func setup_battle(friendly: int, enemy: int, at_m: Vector2 = Vector2(3500, 1500)):
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(-1400, 2000))
	mortar.state = Unit.State.WITHDRAWN
	bm.player_units.append(mortar)
	for i in friendly:
		var f: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1400, 1300 + 250 * i))
		bm.player_units.append(f)
		f.enemy_has_been_sighted = true
		f.enemy_known_position = f.global_position
		f.enemy_known_state = Unit.State.ACTIVE
		f.enemy_known_pips = f.pips
	for i in enemy:
		var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(at_m.x, at_m.y + 80 * i))
		e.sought_cover = true
		bm.enemy_units.append(e)
	return bm

func enemy_squads(bm) -> Array:
	return bm.enemy_units.filter(func(u): return u.kind == Unit.Kind.SQUAD)

func run() -> void:
	test_two_to_one_attacks()
	test_less_than_that_gathers_clear_of_our_squads()
	test_the_choice_has_hysteresis()
	test_far_advanced_squads_go_back_avoiding_our_squads()
	test_the_way_round_and_the_nearness_penalty()
	test_the_mortar_still_comes_first_and_nothing_known_changes_nothing()
	print("Enemy consolidation tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_two_to_one_attacks() -> void:
	var bm = setup_battle(3, 6) # 6 v 3: exactly 2:1
	bm._update_enemy_attack_stance()
	check(bm._enemy_attack_stance(), "At 2:1 the enemy attacks")
	var u: Unit = enemy_squads(bm)[0]
	var objective: Vector2 = bm._enemy_advance_objective(u)
	var nearest: float = INF
	for f in bm.player_units:
		if f.kind == Unit.Kind.SQUAD:
			nearest = minf(nearest, objective.distance_to(f.global_position))
	check(nearest < 1.0, "...its objective is one of our squads (%s)" % (objective / GameConfig.PIXELS_PER_METER))
	seed(1)
	bm._update_enemy_squad_advance()
	var moving := 0
	for e in enemy_squads(bm):
		if e.has_move_target and e.move_target.x < e.global_position.x:
			moving += 1
	check(moving >= 5, "...and they go west toward us (%d of 6)" % moving)
	cleanup(bm)


func test_less_than_that_gathers_clear_of_our_squads() -> void:
	var bm = setup_battle(3, 5) # 5 v 3: under 2:1
	bm._update_enemy_attack_stance()
	check(not bm._enemy_attack_stance(), "Under 2:1 the enemy will not attack")
	var u: Unit = enemy_squads(bm)[0]
	var point: Vector2 = bm._enemy_advance_objective(u)
	for f in bm.player_units:
		if f.kind == Unit.Kind.SQUAD:
			check(point.distance_to(f.global_position) >= BattleManager.ENEMY_CONSOLIDATION_STANDOFF - 1.0, "The gathering point is beyond the standoff from each of our squads (%.0f m)" % (point.distance_to(f.global_position) / GameConfig.PIXELS_PER_METER))
	check(bm._enemy_advance_objective(enemy_squads(bm)[3]) == point, "...one point for all of them")
	seed(2)
	bm._update_enemy_squad_advance()
	for e in enemy_squads(bm):
		if e.has_move_target:
			var nearest_before: float = INF
			var nearest_after: float = INF
			for f in bm.player_units:
				if f.kind == Unit.Kind.SQUAD:
					nearest_before = minf(nearest_before, e.global_position.distance_to(f.global_position))
					nearest_after = minf(nearest_after, e.move_target.distance_to(f.global_position))
			check(nearest_after >= nearest_before - 1.0, "No squad's bound takes it toward ours (%.0f m to %.0f m)" % [nearest_before / GameConfig.PIXELS_PER_METER, nearest_after / GameConfig.PIXELS_PER_METER])
	# Once gathered they wait: nothing to do, which is what lets a stalemate happen.
	for e in enemy_squads(bm):
		e.global_position = point + m(0, 40 * e.get_index() % 200)
		e.has_move_target = false
		e.move_queue.clear()
	bm._update_enemy_squad_advance()
	var still := 0
	for e in enemy_squads(bm):
		if not e.has_move_target:
			still += 1
	check(still == enemy_squads(bm).size(), "Gathered, they stand still (%d of %d)" % [still, enemy_squads(bm).size()])
	cleanup(bm)


func test_the_choice_has_hysteresis() -> void:
	var bm = setup_battle(5, 10) # 2.0
	bm._update_enemy_attack_stance()
	check(bm._enemy_attack_stance(), "10 v 5: attack")
	enemy_squads(bm)[0].pips = 0
	enemy_squads(bm)[0].state = Unit.State.DESTROYED # 9 v 5 = 1.8: below 2 but above the keep ratio
	bm._update_enemy_attack_stance()
	check(bm._enemy_attack_stance(), "A ratio of 1.8 does not stop an attack that has begun")
	enemy_squads(bm)[1].state = Unit.State.DESTROYED
	enemy_squads(bm)[2].state = Unit.State.DESTROYED # 7 v 5 = 1.4
	bm._update_enemy_attack_stance()
	check(not bm._enemy_attack_stance(), "...but 1.4 does")
	enemy_squads(bm)[3].state = Unit.State.ACTIVE
	# 7 v 5 again: 1.4 does not restart it; it takes the full 2:1
	bm._update_enemy_attack_stance()
	check(not bm._enemy_attack_stance(), "Once gathering, 1.4 does not restart the attack")
	cleanup(bm)


## "Far-advanced enemies would try to navigate back to wherever the enemy is trying to consolidate, avoiding
## the friendly squads."
func test_far_advanced_squads_go_back_avoiding_our_squads() -> void:
	var bm = setup_battle(3, 5)
	# The gathering point is to the east; one squad is far advanced, just beyond one of our squads, on the
	# far side of it from home.
	var far: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(600, 1400))
	far.sought_cover = true
	bm.enemy_units.append(far)
	bm._update_enemy_attack_stance()
	var point: Vector2 = bm._enemy_consolidation_point()
	check(point.x > m(2500, 0).x, "Set-up: the gathering point is on the enemy's side (%s)" % (point / GameConfig.PIXELS_PER_METER))
	var step: Vector2 = bm._consolidation_step(far)
	check(step != far.global_position, "The far-advanced squad is ordered back")
	# The straight line back to the point runs through our squads at x = 1400; the bound avoids them.
	var straight: Vector2 = far.global_position + (point - far.global_position).normalized() * GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE
	var known: Array[Vector2] = bm._known_friendly_squad_positions()
	var nearest_step: float = INF
	var nearest_straight: float = INF
	for k in known:
		nearest_step = minf(nearest_step, step.distance_to(k))
		nearest_straight = minf(nearest_straight, straight.distance_to(k))
	check(nearest_step > nearest_straight, "Its bound stays farther from our squads than the straight line back would (%.0f m against %.0f m)" % [nearest_step / GameConfig.PIXELS_PER_METER, nearest_straight / GameConfig.PIXELS_PER_METER])
	# Followed bound after bound, it gets back and never walks up to one of our squads.
	var pos: Vector2 = far.global_position
	var closest: float = INF
	for i in 30:
		far.global_position = pos
		var next: Vector2 = bm._consolidation_step(far)
		if next == pos:
			break
		pos = next
		for k in known:
			closest = minf(closest, pos.distance_to(k))
	check(pos.distance_to(point) <= BattleManager.ENEMY_CONSOLIDATION_ARRIVE_RADIUS + GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE, "...it gets back to the gathering point (%.0f m short; at %s, point %s)" % [pos.distance_to(point) / GameConfig.PIXELS_PER_METER, pos / GameConfig.PIXELS_PER_METER, point / GameConfig.PIXELS_PER_METER])
	check(closest > GameConfig.SQUAD_ENGAGEMENT_RANGE, "...without coming within our squads' engagement range on the way (closest %.0f m)" % (closest / GameConfig.PIXELS_PER_METER))
	cleanup(bm)


func test_the_mortar_still_comes_first_and_nothing_known_changes_nothing() -> void:
	# Our mortar in action: as before, its objective, whatever the numbers.
	var bm = setup_battle(3, 4)
	bm.player_units[0].state = Unit.State.ACTIVE
	bm.player_units[0].enemy_has_been_sighted = true
	bm.player_units[0].enemy_known_position = m(-1400, 2000)
	bm.player_units[0].enemy_known_position_time = bm.scenario_elapsed_time
	bm.player_units[0].is_visible = true
	bm._update_enemy_attack_stance()
	check(bm._friendly_mortar_is_active() and bm._enemy_advance_objective(enemy_squads(bm)[0]).distance_to(m(-1400, 2000)) < 1.0, "With our mortar in action the objective is the mortar, whatever the numbers")
	cleanup(bm)
	# Nothing known of our squads: nothing to be outnumbered by; the earlier behaviour (village, push west).
	var bm2 = setup_battle(0, 4)
	bm2._update_enemy_attack_stance()
	check(bm2._enemy_attack_stance(), "With no squad of ours known the stance is the old one (attack, i.e. carry on)")
	cleanup(bm2)


## The two pieces of the avoidance, each on its own: the way point round a group of our squads that the straight
## line back runs through, and the cost of nearness to one.
func test_the_way_round_and_the_nearness_penalty() -> void:
	var bm = setup_battle(3, 5)
	var known: Array[Vector2] = bm._known_friendly_squad_positions()
	var target: Vector2 = m(3000, 1500)
	var goal: Vector2 = bm._consolidation_goal(m(500, 1550), target, known) # through the middle of our three squads
	check(goal != target, "A line back that runs through our squads is aimed round them (way point %s)" % (goal / GameConfig.PIXELS_PER_METER))
	for k in known:
		var closest: float = Geometry2D.get_closest_point_to_segment(k, m(500, 1550), goal).distance_to(k)
		check(closest > GameConfig.SQUAD_ENGAGEMENT_RANGE, "...and the leg to it stays out of engagement range of each of ours (%.0f m)" % (closest / GameConfig.PIXELS_PER_METER))
	check(bm._consolidation_goal(m(500, 3400), m(3000, 3400), known) == m(3000, 3400), "A line that runs well clear is not bent")
	var near: float = bm._consolidation_score(m(1500, 1500), target, known)
	var clear: float = bm._consolidation_score(m(1500, 1500) + Vector2(0, 0), target, [])
	check(near > clear + GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE, "Standing close to our squads is costed against a bound (%.0f m worse)" % ((near - clear) / GameConfig.PIXELS_PER_METER))
	cleanup(bm)
