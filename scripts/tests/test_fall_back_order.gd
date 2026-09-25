extends SceneTree
## Direct user request: "I want to be able to give any unit an order to 'fall back'.
## This does NOT have to mean to leave the map. It means the unit should evaluate
## where it might be safer than its current location, and move there. The orders can
## work similarly to the way they already work with the mortar." And: "The 'falling
## back' could even go forward if it thinks that is the safest direction."
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
	test_it_picks_a_position_judged_only_on_safety()
	test_it_can_go_forward_or_any_other_way()
	test_a_unit_with_nowhere_safer_refuses()
	test_a_sheltered_unit_with_no_threat_near_does_not_move()
	test_a_sheltered_unit_with_a_threat_near_assumes_its_position_is_about_to_be_lost()
	test_it_gets_away_from_an_advancing_enemy()
	test_it_does_not_run_from_one_enemy_into_the_arms_of_another()
	test_a_drone_is_not_a_threat_to_fall_back_from()
	test_the_worth_moving_for_threshold()
	test_the_order_lifecycle()
	test_other_systems_do_not_steer_the_unit_away()
	test_only_our_ground_units_in_action_can_be_ordered()
	test_a_retreat_ends_the_order()
	test_the_unit_actually_gets_there()
	test_it_works_through_the_real_battle_loop()
	test_the_mortar_falls_back_through_its_own_planner()
	test_clicking_selects_the_right_units()
	print("Fall-back order tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_it_picks_a_position_judged_only_on_safety() -> void:
	# The search samples its shelter candidates at random, so check several seeds.
	for sd in 8:
		seed(sd)
		var bm = make_battle()
		var u: Unit = exposed_squad(bm)
		var known: Array[Vector2] = bm._known_enemy_positions(Unit.Team.PLAYER)
		var here: float = bm._fall_back_score(u, u.global_position, known)
		var dest: Vector2 = bm._fall_back_destination(u)
		check(not is_inf(dest.x), "seed %d: an exposed squad with a known enemy in range finds somewhere safer" % sd)
		if not is_inf(dest.x):
			var there: float = bm._fall_back_score(u, dest, known)
			check(here - there >= BattleManager.FALL_BACK_MIN_IMPROVEMENT, "seed %d: it really is safer by the scoring (%.2f -> %.2f)" % [sd, here, there])
			check(GameConfig.is_in_cover(GameConfig.get_terrain_type_at(dest)), "seed %d: it is cover (%s)" % [sd, GameConfig.TerrainType.keys()[GameConfig.get_terrain_type_at(dest)]])
			check(dest.distance_to(u.global_position) <= m(700.0), "seed %d: nearby, not a run off the map (%.0f m)" % [sd, dest.distance_to(u.global_position) / GameConfig.PIXELS_PER_METER])
		cleanup(bm)


## Direct user follow-up: it "could even go forward if it thinks that is the safest
## direction". No direction is preferred: with the enemy at the squad's own rear
## (west) the safe ground is FORWARD (east); with the enemy ahead (east) it goes back
## (west); with the enemy to the north it goes south.
func test_it_can_go_forward_or_any_other_way() -> void:
	for sd in 6:
		seed(sd)
		var start := Vector2(-200, 1500)
		var cases := [["west (its rear)", Vector2(-700, 1500), "x", 1.0], ["east (ahead)", Vector2(300, 1500), "x", -1.0], ["north", Vector2(-200, 1000), "y", 1.0]]
		for c in cases:
			var bm = make_battle()
			var u: Unit = add_squad(bm, start)
			add_enemy(bm, c[1])
			var dest: Vector2 = bm._fall_back_destination(u)
			check(not is_inf(dest.x), "seed %d, enemy %s: it finds somewhere safer" % [sd, c[0]])
			if not is_inf(dest.x):
				var moved: float = (dest.x - u.global_position.x) if c[2] == "x" else (dest.y - u.global_position.y)
				check(moved * c[3] > 0.0, "seed %d, enemy %s: it goes away from the threat, along %s (moved %.0f px)" % [sd, c[0], c[2], moved])
			cleanup(bm)


func test_a_unit_with_nowhere_safer_refuses() -> void:
	seed(1)
	var bm = make_battle()
	var u: Unit = add_squad(bm, Vector2(300, 2000)) # already in trees, nothing known around
	check(is_inf(bm._fall_back_destination(u).x), "A unit already well sheltered has nowhere safer to go")
	check(not bm.set_fall_back_order(u, true), "So the order is refused")
	check(not bm.fall_back_ordered(u) and not u.has_move_target, "...no order stands and it does not move")
	check(log_has(bm, "can find nowhere safer"), "...and the log says why (got %s)" % str(bm.combat_log.captured))
	cleanup(bm)


## Already in good cover and the only threat a last-seen enemy far beyond the danger
## range (GameConfig.SQUAD_DANGER_RANGE, 1200 m): nothing is about to happen to it, and a
## hair's gain in safety is not worth moving for.
func test_a_sheltered_unit_with_no_threat_near_does_not_move() -> void:
	for sd in 6:
		seed(sd)
		var bm = make_battle()
		var u: Unit = add_squad(bm, Vector2(300, 2000)) # in trees
		var e: Unit = add_enemy(bm, Vector2(2500, 2000))
		e.is_visible = false # last seen there, not in view now
		check(is_inf(bm._fall_back_destination(u).x), "seed %d: a sheltered unit with the enemy far off is not sent anywhere" % sd)
		check(not bm.set_fall_back_order(u, true), "seed %d: so the order is refused" % sd)
		cleanup(bm)


## Direct user follow-up: the typical time to give this order is when the area is about to
## be overrun, so "maybe the unit should assume that its current location is about to
## become dangerous, even if it's in cover". The same sheltered unit, with the enemy last
## seen well inside the danger range, does go — and away from it.
func test_a_sheltered_unit_with_a_threat_near_assumes_its_position_is_about_to_be_lost() -> void:
	for sd in 6:
		seed(sd)
		var bm = make_battle()
		var u: Unit = add_squad(bm, Vector2(300, 2000)) # in trees
		var e: Unit = add_enemy(bm, Vector2(1000, 2000)) # 700 m east
		e.is_visible = false
		var dest: Vector2 = bm._fall_back_destination(u)
		check(not is_inf(dest.x), "seed %d: it goes although it is in cover" % sd)
		if not is_inf(dest.x):
			check(dest.distance_to(e.global_position) > u.global_position.distance_to(e.global_position), "seed %d: and farther from the enemy" % sd)
		cleanup(bm)


## Live report: told to "be safe" with an enemy advancing and becoming dangerous, squads
## did not move. Nothing but where the enemy is NOW was scored, and an enemy still
## beyond weapon range scored as harmless. An enemy squad marching in, from cover or
## from the open, at 500 to 1500 m: the squad moves, away from where it is headed.
func test_it_gets_away_from_an_advancing_enemy() -> void:
	for start in [Vector2(-200, 1500), Vector2(300, 2000)]: # open ground, trees
		for enemy_range in [500.0, 800.0, 1100.0, 1500.0]:
			for sd in 4:
				seed(sd)
				var bm = make_battle()
				var u: Unit = add_squad(bm, start)
				var e: Unit = add_enemy(bm, start + Vector2(enemy_range, 0))
				e.move_target = u.global_position
				e.has_move_target = true
				e.move_speed = GameConfig.REPOSITION_SPEED
				var dest: Vector2 = bm._fall_back_destination(u)
				var what := "from %s, enemy advancing from %d m (seed %d)" % [start, enemy_range, sd]
				check(not is_inf(dest.x), "It moves " + what)
				if not is_inf(dest.x):
					check(dest.distance_to(e.global_position) > u.global_position.distance_to(e.global_position), "...away from the enemy, " + what)
				cleanup(bm)


## "They don't want to become surrounded, for example": enemies on two sides (west and
## north) push a unit toward neither — it ends up no nearer to either than it started.
func test_it_does_not_run_from_one_enemy_into_the_arms_of_another() -> void:
	for sd in 8:
		seed(sd)
		var bm = make_battle()
		var u: Unit = add_squad(bm, Vector2(-200, 1500))
		var west: Unit = add_enemy(bm, Vector2(-700, 1500))
		var north: Unit = add_enemy(bm, Vector2(-200, 1000))
		var dest: Vector2 = bm._fall_back_destination(u)
		check(not is_inf(dest.x), "seed %d: flanked, it moves" % sd)
		if not is_inf(dest.x):
			check(dest.distance_to(west.global_position) >= u.global_position.distance_to(west.global_position) - m(25.0), "seed %d: no nearer the western enemy" % sd)
			check(dest.distance_to(north.global_position) >= u.global_position.distance_to(north.global_position) - m(25.0), "seed %d: no nearer the northern one" % sd)
		cleanup(bm)


## A drone has no weapon; a sighted one next to a sheltered squad is nothing to run from.
func test_a_drone_is_not_a_threat_to_fall_back_from() -> void:
	var bm = make_battle()
	var u: Unit = add_squad(bm, Vector2(300, 2000)) # in trees
	var d: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.DRONE, Vector2(m(400), m(2000)))
	bm.enemy_units.append(d)
	d.is_visible = true
	bm._update_player_intel() # the player side now knows where the drone is
	check(d.player_has_been_sighted and bm._known_enemy_positions(Unit.Team.PLAYER).size() == 1, "Setup: the drone is a known contact")
	d.move_target = u.global_position
	d.has_move_target = true
	d.move_speed = GameConfig.REPOSITION_SPEED
	check(is_inf(bm._fall_back_destination(u).x), "An enemy drone alone, even approaching, gives a sheltered squad nothing to fall back from")
	cleanup(bm)


## The threshold itself, with the scoring set by hand: a candidate must beat the current
## position by at least FALL_BACK_MIN_IMPROVEMENT to be worth the move.
func test_the_worth_moving_for_threshold() -> void:
	var minimum: float = BattleManager.FALL_BACK_MIN_IMPROVEMENT
	for c in [[0.95, false], [1.0 - minimum + 0.01, false], [1.0 - minimum - 0.01, true], [0.2, true]]:
		var bm = load("res://scripts/tests/fall_back_scoring_stub.gd").new()
		root.add_child(bm)
		bm.set_process(false)
		bm.combat_log = Log.new()
		var u: Unit = add_squad(bm, Vector2(-200, 1500))
		bm.here_score = 1.0
		bm.candidate_score = c[0]
		var dest: Vector2 = bm._fall_back_destination(u)
		check(is_inf(dest.x) != c[1], "A candidate scoring %.2f against 1.00 here (need %.2f better): worth moving is %s" % [c[0], minimum, c[1]])
		cleanup(bm)


func test_the_order_lifecycle() -> void:
	var bm = make_battle()
	var u: Unit = exposed_squad(bm)
	check(bm.set_fall_back_order(u, true), "The order is accepted")
	check(bm.fall_back_ordered(u) and u.has_move_target, "The unit is ordered and on the move")
	var dest: Vector2 = bm._fall_back_orders[u].destination
	check(u.move_target.distance_to(dest) < 1.0, "...to the chosen position")
	check(u.last_order_reason == "Ordered to fall back to a safer position.", "...and its debug reason says so (got '%s')" % u.last_order_reason)
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


func test_the_mortar_falls_back_through_its_own_planner() -> void:
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
