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

## The largest real BUILDING zone on the actual loaded map, so cover-preference tests mean something
## against real map data rather than a hand-picked coordinate that could silently stop meaning anything if
## the map ever changes. {center, half_size}.
func _largest_building() -> Dictionary:
	var best_area := -1.0
	var best := {"center": Vector2.INF, "half_size": Vector2.ZERO}
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type != GameConfig.TerrainType.BUILDING:
			continue
		var area: float = zone.rect.size.x * zone.rect.size.y
		if area > best_area:
			best_area = area
			best = {"center": zone.rect.get_center(), "half_size": zone.rect.size * 0.5}
	return best


func run() -> void:
	test_two_to_one_attacks()
	test_less_than_that_gathers_clear_of_our_squads()
	test_the_choice_has_hysteresis()
	test_far_advanced_squads_go_back_avoiding_our_squads()
	test_the_way_round_and_the_nearness_penalty()
	test_the_mortar_still_comes_first_and_nothing_known_changes_nothing()
	test_squads_separate_from_each_other_when_gathered()
	test_consolidation_score_costs_standing_on_a_sibling()
	test_consolidation_point_seeking_cover_finds_real_nearby_cover()
	test_consolidation_point_seeking_cover_leaves_a_covered_point_alone()
	test_enemy_consolidation_point_itself_lands_in_cover_when_available()
	print("Enemy consolidation tests: %d failures" % failures)
	quit(1 if failures else 0)


## Direct user report: "When the enemy squads consolidate around a position, they should have a bit more
## separation from each other than what they are currently doing." Several squads start bunched together
## (setup_battle's own `80 * i` spacing — 80m apart, essentially on top of one another) well under the 2:1
## attack threshold; walked bound-by-bound (same idiom as test_far_advanced_squads_go_back_avoiding_our_
## squads' own settling loop) until every squad stops moving, they must end up markedly more spread out
## than the 80m they started at.
func test_squads_separate_from_each_other_when_gathered() -> void:
	var bm = setup_battle(3, 5, Vector2(3500, 1500)) # bunched only 80m apart at spawn
	var squads: Array = enemy_squads(bm)
	var starting_min_pairwise := INF
	for i in squads.size():
		for j in range(i + 1, squads.size()):
			starting_min_pairwise = minf(starting_min_pairwise, squads[i].global_position.distance_to(squads[j].global_position))
	check(starting_min_pairwise < m(100, 0).x, "Setup: the squads really do start bunched close together (%.0f m)" % (starting_min_pairwise / GameConfig.PIXELS_PER_METER))
	for round in 60:
		var moved := false
		for e in squads:
			var next: Vector2 = bm._consolidation_step(e)
			if next != e.global_position:
				moved = true
			e.global_position = next
		if not moved:
			break
	var settled_min_pairwise := INF
	for i in squads.size():
		for j in range(i + 1, squads.size()):
			settled_min_pairwise = minf(settled_min_pairwise, squads[i].global_position.distance_to(squads[j].global_position))
	check(settled_min_pairwise > BattleManager.ENEMY_CONSOLIDATION_SQUAD_SPACING * 0.5, "Settled squads keep meaningfully more than their 80m starting separation (got %.0f m)" % (settled_min_pairwise / GameConfig.PIXELS_PER_METER))
	check(settled_min_pairwise > starting_min_pairwise * 2.0, "...a real improvement over the bunched starting point, not just noise (%.0f m -> %.0f m)" % [starting_min_pairwise / GameConfig.PIXELS_PER_METER, settled_min_pairwise / GameConfig.PIXELS_PER_METER])
	cleanup(bm)


## The separation term in isolation: standing exactly on a sibling costs more than standing clear of one,
## same shape as the existing friendly-squad nearness check just below this in the file.
func test_consolidation_score_costs_standing_on_a_sibling() -> void:
	var bm = make_battle()
	var target: Vector2 = m(3000, 1500)
	var sibling: Vector2 = m(1500, 1500)
	var on_sibling: float = bm._consolidation_score(sibling, target, [], [sibling])
	var clear: float = bm._consolidation_score(sibling, target, [], [])
	check(on_sibling > clear + BattleManager.ENEMY_CONSOLIDATION_SPACING_WEIGHT * 0.9, "Standing right on a sibling is costed against a bound (%.0f m worse)" % ((on_sibling - clear) / GameConfig.PIXELS_PER_METER))
	var far_from_sibling: Vector2 = sibling + Vector2(BattleManager.ENEMY_CONSOLIDATION_SQUAD_SPACING * 2.0, 0)
	var far_score: float = bm._consolidation_score(far_from_sibling, target, [], [sibling])
	check(is_equal_approx(far_score, bm._consolidation_score(far_from_sibling, target, [], [])), "Well beyond the spacing distance, a sibling costs nothing")
	cleanup(bm)


## Direct user follow-up: "Also, they should prefer to consolidate where there is cover." Starting from a
## real OPEN point a short, controlled distance from the largest actual BUILDING zone on the loaded map, the
## search must find real cover instead of settling for open ground.
func test_consolidation_point_seeking_cover_finds_real_nearby_cover() -> void:
	var building: Dictionary = _largest_building()
	check(not is_inf(building.center.x), "Setup: the map has at least one real BUILDING zone")
	# Half the building's own half-width inside its near edge, along the search's own angle-0 axis (a
	# radius-only, 30-degree-step ring search — see _consolidation_point_seeking_cover — always tries 180
	# degrees, i.e. straight back the way it came), so at least one search radius lands solidly inside it
	# regardless of the zone's exact real-world size.
	var offset: float = building.half_size.x + 300.0 * GameConfig.PIXELS_PER_METER
	var open_point: Vector2 = building.center + Vector2(offset, 0)
	check(not GameConfig.is_in_cover(GameConfig.get_terrain_type_at(open_point)), "Setup: the starting point is open ground, not itself inside another zone")
	var bm = make_battle()
	var result: Vector2 = bm._consolidation_point_seeking_cover(open_point, [])
	check(GameConfig.is_in_cover(GameConfig.get_terrain_type_at(result)), "The search finds real nearby cover instead of settling for open ground (result %s)" % (result / GameConfig.PIXELS_PER_METER))
	cleanup(bm)


## A point already in cover is left exactly alone — no reason to search at all.
func test_consolidation_point_seeking_cover_leaves_a_covered_point_alone() -> void:
	var building: Dictionary = _largest_building()
	var bm = make_battle()
	var result: Vector2 = bm._consolidation_point_seeking_cover(building.center, [])
	check(result == building.center, "A point already in cover is returned unchanged")
	cleanup(bm)


## End-to-end through _enemy_consolidation_point() itself: enemy squads centred right next to real cover
## (and no known friendly squads to push the point away at all) must have their shared gathering point
## actually land in that cover, not just next to it.
func test_enemy_consolidation_point_itself_lands_in_cover_when_available() -> void:
	var building: Dictionary = _largest_building()
	var offset: float = building.half_size.x + 300.0 * GameConfig.PIXELS_PER_METER
	var open_point: Vector2 = building.center + Vector2(offset, 0)
	var bm = make_battle()
	for i in 3:
		var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, open_point + m(0, 20.0 * i))
		bm.enemy_units.append(e)
	var point: Vector2 = bm._enemy_consolidation_point()
	check(GameConfig.is_in_cover(GameConfig.get_terrain_type_at(point)), "The shared gathering point itself lands in real cover when there is some nearby (result %s)" % (point / GameConfig.PIXELS_PER_METER))
	cleanup(bm)


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
			# The real safety requirement ("avoiding the friendly squads") is staying clear of the standoff,
			# not literally maximizing distance on every single bound: since squads now also step aside from
			# a crowded sibling (direct user report: "they should have a bit more separation from each
			# other"), and that side-step is unrelated to the friendly-avoidance direction, a bound can, in
			# principle, trade a few meters of friendly clearance for real separation while both squads start
			# and stay WAY beyond the standoff (nearest_before here is over 2000m against a 1500m standoff) —
			# harmless, and no longer literally monotonic once two independent concerns are both in play.
			check(nearest_after >= BattleManager.ENEMY_CONSOLIDATION_STANDOFF - 1.0, "No squad's bound brings it within the standoff of ours (%.0f m to %.0f m)" % [nearest_before / GameConfig.PIXELS_PER_METER, nearest_after / GameConfig.PIXELS_PER_METER])
	# Once gathered AND properly separated from each other they wait: nothing to do, which is what lets a
	# stalemate happen. (Bunched together, even right at the point, is no longer "gathered" on its own — see
	# the dedicated separation tests below; this checks the true settled end state.) Placed evenly around a
	# circle comfortably inside ARRIVE_RADIUS (so every one of them still reads as "arrived" at the shared
	# point) with an adjacent-pair chord distance comfortably beyond SQUAD_SPACING.
	var squads_here: Array = enemy_squads(bm)
	for e in squads_here:
		var angle: float = TAU * float(e.get_index()) / float(squads_here.size())
		e.global_position = point + Vector2(250.0 * GameConfig.PIXELS_PER_METER, 0).rotated(angle)
		e.has_move_target = false
		e.move_queue.clear()
	bm._update_enemy_squad_advance()
	var still := 0
	for e in enemy_squads(bm):
		if not e.has_move_target:
			still += 1
	check(still == enemy_squads(bm).size(), "Gathered and properly spread out, they stand still (%d of %d)" % [still, enemy_squads(bm).size()])
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
