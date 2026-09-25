extends SceneTree
## Direct user request: "I want to be able to give any unit an order to 'fall back'.
## This does NOT have to mean to leave the map. It means the unit should evaluate
## where it might be safer than its current location, and move there." Reworked after
## use ("it's not working very well. Let's change the paradigm"): "Fall back" now
## "requires the unit to move towards the edge of the map, unless it is already very
## close. It does not require the unit to fall back off of the map. In general it should
## move 500-1000 meters, but it could go over that, or maybe slightly less if there is an
## excellent position say 400 meters back, but that should be rare. It does not have to
## be straight back. Just generally towards the edge."
##
## Run: godot --headless --path . --script scripts/tests/test_fall_back_order.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0
var _selected: Array = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

## A known (visible) enemy squad at `pos_m`.
func add_enemy(bm, pos_m: Vector2) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(pos_m.x), m(pos_m.y)))
	bm.enemy_units.append(e)
	e.is_visible = true
	e.player_has_been_sighted = true
	e.player_known_position = e.global_position
	e.player_known_state = Unit.State.ACTIVE
	return e

func add_squad(bm, pos_m: Vector2) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(pos_m.x), m(pos_m.y)))
	bm.player_units.append(u)
	return u

## The standard exposed squad: on open ground at (-200, 1500) m with a known enemy
## squad 500 m to its WEST (its own rear side).
func exposed_squad(bm) -> Unit:
	var u: Unit = add_squad(bm, Vector2(-200, 1500))
	add_enemy(bm, Vector2(-700, 1500))
	return u

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func log_has(bm, fragment: String) -> bool:
	for line in bm.combat_log.captured:
		if fragment in line:
			return true
	return false

func run() -> void:
	seed(7)
	test_it_falls_back_toward_its_edge_500_to_1000_m()
	test_it_need_not_go_straight_back()
	test_the_distance_penalty_has_the_asked_for_shape()
	test_a_shorter_position_wins_only_if_it_is_excellent()
	test_a_unit_already_very_close_to_its_edge_does_not_move()
	test_a_unit_near_its_edge_goes_as_far_as_the_edge_allows()
	test_a_place_past_the_edge_is_never_chosen_however_good_it_scores()
	test_it_gets_away_from_an_advancing_enemy()
	test_it_does_not_fall_back_into_the_path_of_an_advancing_enemy()
	test_the_scoring_counts_advancing_enemies_and_adds_up_all_the_enemies()
	test_it_does_not_run_from_one_enemy_into_the_arms_of_another()
	test_a_drone_is_not_a_threat_to_fall_back_from()
	test_the_order_lifecycle()
	test_other_systems_do_not_steer_the_unit_away()
	test_only_our_ground_units_in_action_can_be_ordered()
	test_a_retreat_ends_the_order()
	test_the_unit_actually_gets_there()
	test_it_works_through_the_real_battle_loop()
	test_the_mortar_falls_back_the_same_way()
	test_clicking_selects_the_right_units()
	print("Fall-back order tests: %d failures" % failures)
	quit(1 if failures else 0)


## Where the player's units' edge is (the line a retreat runs to), in metres.
func edge_m() -> float:
	return GameConfig.PLAYER_SAFE_X / GameConfig.PIXELS_PER_METER

## An enemy squad marching at `toward`, visible and known.
func add_advancing_enemy(bm, pos_m: Vector2, toward: Unit) -> Unit:
	var e: Unit = add_enemy(bm, pos_m)
	e.move_target = toward.global_position
	e.has_move_target = true
	e.move_speed = GameConfig.REPOSITION_SPEED
	return e

## Angle (degrees) between the way from `from` to `to` and due west, the direction of the
## player's edge.
func bearing_off_west(from: Vector2, to: Vector2) -> float:
	return absf(rad_to_deg((to - from).angle_to(Vector2(-1, 0))))


## The scenarios: open ground and trees, at a few places, with no enemy, an enemy ahead,
## one advancing, one to the side and one behind. Several seeds (the hidden-spot samples
## are random).
func scenarios() -> Array:
	var out: Array = []
	for start in [Vector2(1500, 1500), Vector2(1500, 2000), Vector2(-200, 1500), Vector2(300, 500)]:
		for enemy in [null, Vector2(600, 0), Vector2(900, 0), Vector2(0, -500), Vector2(-500, 0)]:
			for sd in 3:
				out.append({"start": start, "enemy": enemy, "advancing": enemy != null and enemy == Vector2(900, 0), "seed": sd})
	return out


func test_it_falls_back_toward_its_edge_500_to_1000_m() -> void:
	var in_range := 0
	var total := 0
	for sc in scenarios():
		seed(sc.seed)
		var bm = make_battle()
		var u: Unit = add_squad(bm, sc.start)
		if sc.enemy != null:
			var e: Unit = add_advancing_enemy(bm, sc.start + sc.enemy, u) if sc.advancing else add_enemy(bm, sc.start + sc.enemy)
		var dest: Vector2 = bm._fall_back_destination(u)
		var what := "from %s, enemy %s (seed %d)" % [sc.start, str(sc.enemy), sc.seed]
		check(not is_inf(dest.x), "It finds a place to fall back to, " + what)
		if not is_inf(dest.x):
			var d_m: float = dest.distance_to(u.global_position) / GameConfig.PIXELS_PER_METER
			check(dest.x < u.global_position.x, "...toward its edge (west), " + what)
			check(bearing_off_west(u.global_position, dest) <= BattleManager.FALL_BACK_MAX_BEARING_DEG + 0.5, "...within %d degrees of it, %s" % [BattleManager.FALL_BACK_MAX_BEARING_DEG, what])
			check(d_m >= 400.0 - 1.0 and d_m <= 1500.0 + 1.0, "...not absurdly near or far (%.0f m), %s" % [d_m, what])
			check(dest.x >= GameConfig.PLAYER_SAFE_X - 0.01, "...and never past the edge itself, " + what)
			total += 1
			if d_m >= 500.0 - 1.0 and d_m <= 1000.0 + 1.0:
				in_range += 1
		cleanup(bm)
	check(total > 0 and float(in_range) / total >= 0.85, "In general 500-1000 m (%d of %d)" % [in_range, total])


## "It does not have to be straight back. Just generally towards the edge."
func test_it_need_not_go_straight_back() -> void:
	var bearings: Array[float] = []
	for sc in scenarios():
		seed(sc.seed)
		var bm = make_battle()
		var u: Unit = add_squad(bm, sc.start)
		if sc.enemy != null:
			add_enemy(bm, sc.start + sc.enemy)
		var dest: Vector2 = bm._fall_back_destination(u)
		if not is_inf(dest.x):
			bearings.append(bearing_off_west(u.global_position, dest))
		cleanup(bm)
	check(bearings.max() > 20.0 and bearings.min() < 10.0, "Destinations vary in bearing (%.0f to %.0f degrees off due west)" % [bearings.min(), bearings.max()])


func test_the_distance_penalty_has_the_asked_for_shape() -> void:
	var bm = make_battle()
	for c in [[500.0, 0.0], [750.0, 0.0], [1000.0, 0.0], [400.0, 0.5], [300.0, 1.0], [1500.0, 0.75]]:
		check(is_equal_approx(bm._fall_back_distance_penalty(c[0], 5000.0), c[1]), "%.0f m costs %.2f (got %.2f)" % [c[0], c[1], bm._fall_back_distance_penalty(c[0], 5000.0)])
	# A unit with the edge nearer than the preferred minimum is not penalised for stopping there.
	check(is_equal_approx(bm._fall_back_distance_penalty(300.0, 300.0), 0.0), "Reaching the edge 300 m away costs nothing")
	check(is_equal_approx(bm._fall_back_distance_penalty(150.0, 300.0), 0.75), "...but stopping 150 m short of it does")
	cleanup(bm)


## "Maybe slightly less if there is an excellent position say 400 meters back, but that
## should be rare": with the scoring set by hand, a 400 m spot that is a lot better beats
## the 500-1000 m range and one that is only a little better does not.
func test_a_shorter_position_wins_only_if_it_is_excellent() -> void:
	for c in [[-0.8, true], [-0.3, false], [0.0, false]]:
		var bm = load("res://scripts/tests/fall_back_scoring_stub.gd").new()
		root.add_child(bm)
		bm.set_process(false)
		bm.combat_log = Log.new()
		var u: Unit = add_squad(bm, Vector2(1500, 1500))
		bm.bonus_point = u.global_position + Vector2(-m(400.0), 0.0)
		bm.bonus = c[0]
		var dest: Vector2 = bm._fall_back_destination(u)
		var d_m: float = dest.distance_to(u.global_position) / GameConfig.PIXELS_PER_METER
		check((absf(d_m - 400.0) < 1.0) == c[1], "A 400 m spot scoring %.1f better than the rest: taken is %s (went %.0f m)" % [c[0], c[1], d_m])
		cleanup(bm)


## "Unless it is already very close": no order, and the log says why.
func test_a_unit_already_very_close_to_its_edge_does_not_move() -> void:
	var bm = make_battle()
	var u: Unit = add_squad(bm, Vector2(edge_m() + 150.0, 1500))
	check(is_inf(bm._fall_back_destination(u).x), "A unit 150 m from its edge has nowhere to fall back to")
	check(not bm.set_fall_back_order(u, true), "So the order is refused")
	check(not bm.fall_back_ordered(u) and not u.has_move_target, "...no order stands and it does not move")
	check(log_has(bm, "already at the edge of the map"), "...and the log says why (got %s)" % str(bm.combat_log.captured))
	cleanup(bm)


## Nearer its edge than 500 m but not very close: it goes as far as the edge allows and
## never past it (and never leaves the map: this is not a retreat).
func test_a_unit_near_its_edge_goes_as_far_as_the_edge_allows() -> void:
	for remaining in [300.0, 450.0, 700.0]:
		for sd in 3:
			seed(sd)
			var bm = make_battle()
			var u: Unit = add_squad(bm, Vector2(edge_m() + remaining, 1500))
			var dest: Vector2 = bm._fall_back_destination(u)
			check(not is_inf(dest.x), "%.0f m from its edge it still falls back" % remaining)
			if not is_inf(dest.x):
				check(dest.x >= GameConfig.PLAYER_SAFE_X - 0.01, "...but not past the edge (%.0f m from it)" % ((dest.x - GameConfig.PLAYER_SAFE_X) / GameConfig.PIXELS_PER_METER))
				check(dest.x < u.global_position.x, "...and toward it")
				var left_m: float = (dest.x - GameConfig.PLAYER_SAFE_X) / GameConfig.PIXELS_PER_METER
				check(left_m <= remaining * 0.5 + 1.0, "...using most of the room it has (%.0f m of %.0f m left)" % [left_m, remaining])
			cleanup(bm)


## The best-scoring place (by hand) lies just past the edge: it is clamped back, not used.
func test_a_place_past_the_edge_is_never_chosen_however_good_it_scores() -> void:
	var bm = load("res://scripts/tests/fall_back_scoring_stub.gd").new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var u: Unit = add_squad(bm, Vector2(edge_m() + 300.0, 1500))
	bm.bonus_point = u.global_position + Vector2(-m(400.0), 0.0) # 100 m beyond the edge
	bm.bonus = -5.0
	var dest: Vector2 = bm._fall_back_destination(u)
	check(not is_inf(dest.x) and dest.x >= GameConfig.PLAYER_SAFE_X - 0.01, "A place beyond the edge is not used (x %.0f m, edge %.0f m)" % [dest.x / GameConfig.PIXELS_PER_METER, edge_m()])
	cleanup(bm)


## Live report (when it was still called "be safe"): with an enemy advancing and becoming dangerous, squads
## did not move. Where the enemy WILL be counts: an enemy marching in from the north
## (across the direction of the fall back) leaves the unit farther from where it is
## headed, not nearer.
func test_it_gets_away_from_an_advancing_enemy() -> void:
	for sd in 6:
		seed(sd)
		var bm = make_battle()
		var u: Unit = add_squad(bm, Vector2(1500, 1500))
		var e: Unit = add_advancing_enemy(bm, Vector2(1500, 1000), u)
		var projected: Vector2 = bm._advancing_enemy_projections(Unit.Team.PLAYER)[0]
		var dest: Vector2 = bm._fall_back_destination(u)
		check(not is_inf(dest.x), "seed %d: it moves" % sd)
		if not is_inf(dest.x):
			check(dest.distance_to(projected) > u.global_position.distance_to(projected), "seed %d: and ends farther from where the enemy is headed" % sd)
		cleanup(bm)


## The enemy is still 1500 m off (beyond the danger range, so nothing that is known about
## where it IS matters) but marching straight at the squad, from the direction it would
## fall back in: where it will be in four minutes is right on the straight-back route, and
## the destination steers clear of that.
func test_it_does_not_fall_back_into_the_path_of_an_advancing_enemy() -> void:
	for sd in 6:
		seed(sd)
		var bm = make_battle()
		var u: Unit = add_squad(bm, Vector2(1500, 1500))
		add_advancing_enemy(bm, Vector2(0, 1500), u)
		var projected: Vector2 = bm._advancing_enemy_projections(Unit.Team.PLAYER)[0]
		var dest: Vector2 = bm._fall_back_destination(u)
		check(not is_inf(dest.x), "seed %d: it still falls back" % sd)
		if not is_inf(dest.x):
			check(dest.distance_to(projected) >= m(400.0), "seed %d: but not to within 400 m of where the enemy will be (%.0f m)" % [sd, dest.distance_to(projected) / GameConfig.PIXELS_PER_METER])
		cleanup(bm)


## The scoring terms themselves, on one and the same point (so the terrain cancels): a place
## near where an enemy squad will be scores worse, and each further enemy nearby adds to it
## rather than only the nearest counting. And the destination search hands the projections on.
func test_the_scoring_counts_advancing_enemies_and_adds_up_all_the_enemies() -> void:
	var bm = make_battle()
	var u: Unit = add_squad(bm, Vector2(1500, 1500))
	var point: Vector2 = u.global_position + Vector2(-m(700.0), 0.0)
	var a := Vector2(point.x, point.y + m(900.0)) # 900 m from the point: no risk forecast, just distance
	var b := Vector2(point.x, point.y - m(900.0))
	var none: Array[Vector2] = []
	var one: Array[Vector2] = [a]
	var two: Array[Vector2] = [a, b]
	var near_projected: Array[Vector2] = [point + Vector2(m(100.0), 0.0)]
	var far_projected: Array[Vector2] = [point + Vector2(m(900.0), 0.0)]
	var base: float = bm._fall_back_score(u, point, none, none)
	check(bm._fall_back_score(u, point, none, near_projected) - base >= 1.0, "A place 100 m from where an enemy will be is penalised heavily (by at least 1.0 of score)")
	check(bm._fall_back_score(u, point, none, near_projected) > bm._fall_back_score(u, point, none, far_projected), "...more than one 900 m from it")
	var one_enemy: float = bm._fall_back_score(u, point, one, none)
	var two_enemies: float = bm._fall_back_score(u, point, two, none)
	check(one_enemy > base and two_enemies > one_enemy + 0.05, "Each enemy nearby adds to the exposure (%.2f, %.2f, %.2f)" % [base, one_enemy, two_enemies])
	cleanup(bm)
	# The search passes the projected positions on to the scoring.
	bm = load("res://scripts/tests/fall_back_scoring_stub.gd").new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var v: Unit = add_squad(bm, Vector2(1500, 1500))
	add_advancing_enemy(bm, Vector2(1500, 1000), v)
	bm._fall_back_destination(v)
	check(bm.last_advancing_count == 1, "_fall_back_destination scores with the advancing enemy's projected position (got %d)" % bm.last_advancing_count)
	cleanup(bm)


## "They don't want to become surrounded": enemies to the north and east push a unit toward
## neither — it ends up no nearer to either than it started.
func test_it_does_not_run_from_one_enemy_into_the_arms_of_another() -> void:
	for sd in 8:
		seed(sd)
		var bm = make_battle()
		var u: Unit = add_squad(bm, Vector2(1500, 1500))
		var east: Unit = add_enemy(bm, Vector2(2000, 1500))
		var north: Unit = add_enemy(bm, Vector2(1500, 1000))
		var dest: Vector2 = bm._fall_back_destination(u)
		check(not is_inf(dest.x), "seed %d: flanked, it moves" % sd)
		if not is_inf(dest.x):
			check(dest.distance_to(east.global_position) >= u.global_position.distance_to(east.global_position) - m(25.0), "seed %d: no nearer the eastern enemy" % sd)
			check(dest.distance_to(north.global_position) >= u.global_position.distance_to(north.global_position) - m(25.0), "seed %d: no nearer the northern one" % sd)
		cleanup(bm)


## A drone has no weapon; a sighted one, even approaching, changes nothing.
func test_a_drone_is_not_a_threat_to_fall_back_from() -> void:
	var results: Array[Vector2] = []
	for with_drone in [false, true]:
		var bm = make_battle()
		var u: Unit = add_squad(bm, Vector2(1500, 1500))
		if with_drone:
			var d: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.DRONE, Vector2(m(1700), m(1500)))
			bm.enemy_units.append(d)
			d.is_visible = true
			bm._update_player_intel() # the player side now knows where the drone is
			check(d.player_has_been_sighted and bm._known_enemy_positions(Unit.Team.PLAYER).size() == 1, "Setup: the drone is a known contact")
			d.move_target = u.global_position
			d.has_move_target = true
			d.move_speed = GameConfig.REPOSITION_SPEED
		seed(5)
		results.append(bm._fall_back_destination(u))
		cleanup(bm)
	check(results[0].is_equal_approx(results[1]), "An enemy drone makes no difference to where a squad falls back to")


func test_the_order_lifecycle() -> void:
	var bm = make_battle()
	var u: Unit = exposed_squad(bm)
	check(bm.set_fall_back_order(u, true), "The order is accepted")
	check(bm.fall_back_ordered(u) and u.has_move_target, "The unit is ordered and on the move")
	var dest: Vector2 = bm._fall_back_orders[u].destination
	check(u.move_target.distance_to(dest) < 1.0, "...to the chosen position")
	check(u.last_order_reason == "Ordered to fall back toward the map edge.", "...and its debug reason says so (got '%s')" % u.last_order_reason)
	check(log_has(bm, "ordered to fall back ---"), "The log records the order")
	check(bm.set_fall_back_order(u, true), "Ordering it again is harmless")
	check(bm._fall_back_orders.size() == 1, "...and does not stack")
	# Countermanded.
	check(bm.set_fall_back_order(u, false), "It can be countermanded")
	check(not bm.fall_back_ordered(u) and not u.has_move_target, "...the order is gone and the unit stops")
	check(log_has(bm, "order to fall back cancelled"), "...and the log says so")
	check(not bm.set_fall_back_order(u, false), "Countermanding when nothing is ordered does nothing")
	# Arrival ends it.
	check(bm.set_fall_back_order(u, true), "Ordered again")
	dest = bm._fall_back_orders[u].destination
	u.global_position = dest
	bm._update_fall_back_orders()
	check(not bm.fall_back_ordered(u) and not u.has_move_target, "On arrival the order ends and the unit stands")
	check(log_has(bm, "has fallen back"), "...and the log says it has fallen back")
	cleanup(bm)


## The systems that would otherwise steer the unit (its own cover-seeking, risk policy,
## a fresh move from anywhere) must not undo the order.
func test_other_systems_do_not_steer_the_unit_away() -> void:
	var bm = make_battle()
	var u: Unit = exposed_squad(bm)
	bm.set_fall_back_order(u, true)
	var dest: Vector2 = bm._fall_back_orders[u].destination
	# Something else re-aims the unit.
	u.move_target = Vector2(m(-900), m(1200))
	u.move_queue.clear()
	bm._update_friendly_squad_positioning()
	bm._update_ground_risk_orders()
	bm._update_fall_back_orders()
	check(u.has_move_target and u.move_target.distance_to(dest) < 1.0, "After other systems ran, the unit is back on its way to the ordered position")
	# Stopped by something else entirely.
	u.has_move_target = false
	bm._update_fall_back_orders()
	check(u.has_move_target and u.move_target.distance_to(dest) < 1.0, "A unit that was stopped is put back on its way")
	cleanup(bm)


## Each of these WOULD find somewhere safer if it were allowed to (checked), so the
## refusal is about who it is, not about the ground.
func test_only_our_ground_units_in_action_can_be_ordered() -> void:
	seed(4)
	var bm = make_battle()
	# An enemy squad exposed to a player squad it can see.
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(-200), m(1500)))
	bm.enemy_units.append(enemy)
	var ours: Unit = add_squad(bm, Vector2(-700, 1500))
	ours.is_visible = true
	enemy.enemy_has_been_sighted = true
	ours.enemy_has_been_sighted = true
	ours.enemy_known_position = ours.global_position
	ours.enemy_known_state = Unit.State.ACTIVE
	check(not is_inf(bm._fall_back_destination(enemy).x), "Setup: the exposed enemy squad would find somewhere safer")
	check(not bm.set_fall_back_order(enemy, true), "An enemy unit cannot be given the player's order")
	cleanup(bm)
	for kind in [Unit.Kind.DRONE, Unit.Kind.RESUPPLY_RUN]:
		bm = make_battle()
		var u: Unit = bm._make_unit(Unit.Team.PLAYER, kind, Vector2(m(-200), m(1500)))
		bm.player_units.append(u)
		add_enemy(bm, Vector2(-700, 1500))
		check(not is_inf(bm._fall_back_destination(u).x), "Setup: an exposed %s would find somewhere safer" % Unit.Kind.keys()[kind])
		check(not bm.set_fall_back_order(u, true), "%s cannot be ordered (a drone flies its own mission, a resupply run is not ours to steer)" % Unit.Kind.keys()[kind])
		cleanup(bm)
	bm = make_battle()
	var hurt: Unit = exposed_squad(bm)
	hurt.state = Unit.State.RETREATING
	check(not is_inf(bm._fall_back_destination(hurt).x), "Setup: an exposed retreating squad would find somewhere safer")
	check(not bm.set_fall_back_order(hurt, true), "A unit already retreating cannot be ordered")
	cleanup(bm)
	# The other orderable kinds get the same treatment as a squad.
	for kind in [Unit.Kind.SPOTTER, Unit.Kind.DRONE_TEAM]:
		bm = make_battle()
		var u: Unit = bm._make_unit(Unit.Team.PLAYER, kind, Vector2(m(-200), m(1500)))
		bm.player_units.append(u)
		add_enemy(bm, Vector2(-700, 1500))
		check(bm.set_fall_back_order(u, true) and bm.fall_back_ordered(u), "%s can be ordered to fall back" % Unit.Kind.keys()[kind])
		cleanup(bm)


func test_a_retreat_ends_the_order() -> void:
	var bm = make_battle()
	var u: Unit = exposed_squad(bm)
	bm.set_fall_back_order(u, true)
	bm.order_general_retreat()
	bm._update_fall_back_orders()
	check(not bm.fall_back_ordered(u), "A general retreat overrides a fall-back order")
	cleanup(bm)


## Through the real movement: it walks there and the order ends.
func test_the_unit_actually_gets_there() -> void:
	var bm = make_battle()
	var u: Unit = exposed_squad(bm)
	check(bm.set_fall_back_order(u, true), "Setup: ordered")
	var dest: Vector2 = bm._fall_back_orders[u].destination
	var ticks := 0
	while bm.fall_back_ordered(u) and ticks < 4000:
		bm._tick_movement(6.0)
		bm._update_fall_back_orders()
		ticks += 1
	check(not bm.fall_back_ordered(u), "The order ends (after %d ticks)" % ticks)
	check(u.global_position.distance_to(dest) <= Unit.MOVE_ARRIVE_RADIUS * 2.0, "...with the unit at the destination (%.0f m off)" % (u.global_position.distance_to(dest) / GameConfig.PIXELS_PER_METER))
	check(not u.has_move_target, "...and standing")
	cleanup(bm)


## Through the battle's own per-tick loop (_process), not the pieces called by hand:
## the order is looked after every tick and ends on arrival.
func test_it_works_through_the_real_battle_loop() -> void:
	seed(9)
	var bm = make_battle()
	var u: Unit = exposed_squad(bm)
	check(bm.set_fall_back_order(u, true), "Setup: ordered")
	var dest: Vector2 = bm._fall_back_orders[u].destination
	var steps := 0
	while bm.fall_back_ordered(u) and steps < 6000 and not bm.battle_over:
		bm._process(0.05)
		steps += 1
	check(not bm.fall_back_ordered(u), "The battle loop ends the order on arrival (%d steps)" % steps)
	check(u.global_position.distance_to(dest) <= Unit.MOVE_ARRIVE_RADIUS * 3.0, "...with the unit at the ordered position (%.0f m off)" % (u.global_position.distance_to(dest) / GameConfig.PIXELS_PER_METER))
	cleanup(bm)


func test_the_mortar_falls_back_the_same_way() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-200), m(1500)))
	bm.player_units.append(mortar)
	bm._friendly_mortar_home_position = mortar.global_position
	add_enemy(bm, Vector2(-700, 1500))
	check(bm.set_fall_back_order(mortar, true), "A mortar in the open with an enemy near accepts the order")
	check(bm._mortar_move_intent.get(mortar, "") == "fall_back" and mortar.has_move_target, "It is under way with the fall_back intent")
	bm._update_mortar_decisions()
	check(bm._mortar_reasoning.get(mortar, {}).get("tier", "") == "Commander's order", "The decision ladder defers to the commander's order (got %s)" % str(bm._mortar_reasoning.get(mortar, {})))
	check(mortar.has_move_target, "...and does not stop the walk")
	# A queued shoot-and-scoot must not take over.
	bm._pending_mortar_displacement[mortar] = {"destination": Vector2(m(500), m(500)), "speed": 1.0, "intent": "scoot", "urgent": false, "ready_time": 0.0}
	bm._resolve_pending_mortar_displacement()
	check(bm._mortar_move_intent.get(mortar, "") == "fall_back", "A pending scoot does not replace the order")
	var dest: Vector2 = bm._fall_back_orders[mortar].destination
	mortar.global_position = dest
	bm._update_fall_back_orders()
	check(not bm.fall_back_ordered(mortar) and not mortar.has_move_target and bm._mortar_move_intent.get(mortar, "") == "", "On arrival the order ends and the mortar's own decisions resume")
	# The mortar's own snapshot shows the order.
	check(bm.mortar_decision_debug_snapshot()[mortar.display_name()].orders.has("fall_back"), "The mortar debug snapshot carries the order state")
	cleanup(bm)


func test_clicking_selects_the_right_units() -> void:
	var bm = make_battle()
	var squad: Unit = add_squad(bm, Vector2(100, 1500))
	var far_squad: Unit = add_squad(bm, Vector2(2000, 1500))
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, Vector2(m(400), m(1500)))
	bm.player_units.append(spotter)
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(600), m(1500)))
	bm.player_units.append(team)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(800), m(1500)))
	bm.player_units.append(mortar)
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(1000), m(1500)))
	bm.player_units.append(drone)
	var enemy: Unit = add_enemy(bm, Vector2(1200, 1500))
	_selected.clear()
	bm.unit_selected.connect(func(u): _selected.append(u))
	for u in [squad, far_squad, spotter, team, mortar]:
		check(bm.handle_click(u.global_position + Vector2(4, 4)) == u, "Clicking %s selects it" % u.display_name())
	check(_selected.size() == 5, "unit_selected was emitted for each")
	check(bm.handle_click(drone.global_position) == null, "A drone cannot be selected")
	check(bm.handle_click(enemy.global_position) == null, "An enemy unit cannot be selected")
	check(bm.handle_click(Vector2(m(1500), m(200))) == null, "Empty ground selects nothing")
	squad.state = Unit.State.RETREATING
	check(bm.handle_click(squad.global_position) == null, "A unit no longer in action cannot be selected")
	# Overlapping units: the nearest wins.
	var a: Unit = add_squad(bm, Vector2(3000, 1500))
	var b: Unit = add_squad(bm, Vector2(3000, 1500) + Vector2(2, 0))
	check(bm.handle_click(b.global_position) == b and bm.handle_click(a.global_position) == a, "With units close together the nearest to the click wins")
	cleanup(bm)
