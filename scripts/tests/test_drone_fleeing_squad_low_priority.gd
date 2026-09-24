extends SceneTree
## Direct user request: "As with a fleeing mortar, a fleeing enemy squad should be a
## low priority target for the drone. The only exception would be if a lot of enemy
## squads start fleeing at the same time, indicating that the whole force is
## retreating." And, of the live case: "In this case, nothing else is visible. Maybe
## that's why." The drone's "Finishing a retreating contact" tier was scored 2.0 for a
## lone fleeing contact, which beat routine search's floor (0.4), so with nothing else
## visible the drone sat on one fleeing squad — with 22% battery — while two ACTIVE
## squads it could not see were still out there. Now a lone fleeing contact scores
## below routine search (and must be affordable); a routed force (its general retreat,
## or at least 3 fleeing squads and half of those known to be on the field) is still
## finished at the high priority.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_fleeing_squad_low_priority.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
const CHASE_TIER := "Finishing a retreating contact"
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

## A friendly squad (not a mortar: a friendly mortar would add the flank-watch duty,
## which competes with the tiers under test), the drone team and an airborne drone.
func make_battle(charge: float = 0.9):
	var w := Weather.new()
	w.wind_speed_10m = 0.0
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 1
	Weather.current = w
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.weather = w
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var friendly: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(1400), m(1800)))
	bm.player_units.append(friendly)
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800), m(1500)))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(2000), m(900)))
	bm.player_units.append(d)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_battery_charge = charge
	bm.active_drone = d
	return bm

## An enemy squad the player has seen, last seen in `state`; visible now or not.
func add_squad(bm, pos: Vector2, state: Unit.State, visible: bool) -> Unit:
	var s: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, pos)
	bm.enemy_units.append(s)
	s.state = state
	s.is_visible = visible
	s.player_has_been_sighted = true
	s.player_known_state = state
	s.player_known_position = pos
	return s

func tier(bm) -> String:
	bm._drone_search_target()
	return str(bm._drone_pilot_reasoning.get("tier", ""))

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_the_live_case()
	test_a_routed_force_is_still_finished()
	test_what_counts_as_a_lot_of_squads()
	test_a_low_priority_contact_must_be_affordable()
	test_the_low_priority_stays_below_routine_search()
	print("Drone fleeing-squad priority tests: %d failures" % failures)
	quit(1 if failures else 0)


## One fleeing squad visible, nothing else in view, two ACTIVE squads seen earlier
## and now out of sight (the live battle).
func test_the_live_case() -> void:
	var bm = make_battle()
	var fleeing: Unit = add_squad(bm, Vector2(m(2100), m(886)), Unit.State.RETREATING, true)
	add_squad(bm, Vector2(m(-860), m(845)), Unit.State.ACTIVE, false)
	add_squad(bm, Vector2(m(2355), m(3081)), Unit.State.ACTIVE, false)
	check(not bm._enemy_force_is_fleeing(), "Setup: one of three known squads fleeing is not a routed force")
	var t: String = tier(bm)
	check(t != CHASE_TIER, "A lone fleeing squad must not draw the drone when nothing else is visible (tier was %s)" % t)
	var target: Vector2 = bm._drone_pilot_reasoning.get("target", Vector2.INF)
	check(target.distance_to(fleeing.global_position) > m(300.0), "...and the drone is not sent to it (target %s)" % str(target))
	cleanup(bm)
	# Same with nothing else known at all: still routine search, not the straggler.
	bm = make_battle()
	add_squad(bm, Vector2(m(2100), m(886)), Unit.State.RETREATING, true)
	t = tier(bm)
	check(t != CHASE_TIER, "Even with no other squad known, a lone fleeing squad is not chased (tier was %s)" % t)
	cleanup(bm)


## The exception: a lot of squads fleeing at once — the whole force is running.
func test_a_routed_force_is_still_finished() -> void:
	var bm = make_battle()
	for i in 4:
		add_squad(bm, Vector2(m(2100 + 150 * i), m(886)), Unit.State.RETREATING, true)
	add_squad(bm, Vector2(m(-860), m(845)), Unit.State.ACTIVE, false)
	check(bm._enemy_force_is_fleeing(), "Setup: 4 of 5 known squads fleeing is a routed force")
	var t: String = tier(bm)
	check(t == CHASE_TIER, "When the force is routed the drone finishes the fleeing squads (tier was %s)" % t)
	cleanup(bm)
	# The enemy commander's own general retreat is the same exception, as before.
	bm = make_battle()
	add_squad(bm, Vector2(m(2100), m(886)), Unit.State.RETREATING, true)
	bm.enemy_general_retreat_ordered = true
	check(bm._enemy_force_is_fleeing() and tier(bm) == CHASE_TIER, "A general retreat is a routed force")
	cleanup(bm)


## [fleeing, active] known squads -> routed? At least 3 fleeing AND at least half of
## those on the field.
func test_what_counts_as_a_lot_of_squads() -> void:
	for c in [[1, 0, false], [2, 0, false], [3, 0, true], [2, 1, false], [3, 1, true], [3, 3, true], [3, 4, false], [4, 4, true], [4, 5, false], [5, 5, true], [1, 5, false]]:
		var bm = make_battle()
		for i in c[0]:
			add_squad(bm, Vector2(m(2000 + 100 * i), m(900)), Unit.State.RETREATING, true)
		for i in c[1]:
			add_squad(bm, Vector2(m(1000 + 100 * i), m(2500)), Unit.State.ACTIVE, false)
		check(bm._enemy_force_is_fleeing() == c[2], "%d fleeing, %d active known: routed should be %s" % [c[0], c[1], c[2]])
		cleanup(bm)
	# Squads already withdrawn or destroyed are not "on the field"; ones never seen do not count.
	var bm = make_battle()
	for i in 3:
		add_squad(bm, Vector2(m(2000 + 100 * i), m(900)), Unit.State.RETREATING, true)
	for i in 10:
		add_squad(bm, Vector2(m(3000), m(500 + 100 * i)), Unit.State.WITHDRAWN, false)
	var unseen: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(500), m(500)))
	bm.enemy_units.append(unseen)
	check(bm._enemy_force_is_fleeing(), "Squads that have left the field, or that were never seen, do not dilute a rout the drone team can see")
	cleanup(bm)
	# The drone team can only judge a rout from what it has SEEN: squads that are
	# fleeing in truth but were last seen advancing do not make a rout it knows of.
	bm = make_battle()
	for i in 4:
		var hidden: Unit = add_squad(bm, Vector2(m(2000 + 100 * i), m(900)), Unit.State.ACTIVE, false)
		hidden.state = Unit.State.RETREATING # truth; the player's last sighting says ACTIVE
	check(not bm._enemy_force_is_fleeing(), "Squads fleeing out of sight are not a rout the drone team knows about")
	cleanup(bm)


## A low-priority distraction is not worth a flight the battery can't afford.
func test_a_low_priority_contact_must_be_affordable() -> void:
	var bm = make_battle(0.02)
	add_squad(bm, Vector2(m(4400), m(900)), Unit.State.RETREATING, true)
	var t: String = tier(bm)
	check(t != CHASE_TIER, "A drone that can barely get home does not chase a lone fleeing squad (tier was %s)" % t)
	cleanup(bm)


## The value that makes "low priority" true: below the lowest routine search can be.
func test_the_low_priority_stays_below_routine_search() -> void:
	var routine_floor: float = GameConfig.TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP * GameConfig.DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE * (1.0 - GameConfig.DRONE_MORTAR_SEARCH_DANGER_DISCOUNT)
	check(GameConfig.TARGET_PRIORITY_RETREATING_ENEMY_LOW < routine_floor, "The lone-fleeing-contact priority (%.2f) must stay below routine search's floor (%.2f)" % [GameConfig.TARGET_PRIORITY_RETREATING_ENEMY_LOW, routine_floor])
	check(GameConfig.TARGET_PRIORITY_RETREATING_ENEMY > GameConfig.TARGET_PRIORITY_SQUAD_MAX, "...while a routed force is still worth more than any single squad")
