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
