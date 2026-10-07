extends SceneTree
## Direct user instruction: "Resupply run should be smart enough to avoid enemy squads. And they should shoot at it if they get the chance."
## A run steers around any enemy squad its side knows of that lies within reach of its straight line to the mortar (a point beside the
## squad, on the side with more room), and goes straight in when the way is clear or the mortar is itself inside the squad's reach. An
## enemy squad that has a visible run in range and sight does fire on it: the run is an ordinary visible unit to the target picker.
##
## Run: godot --headless --path . --script scripts/tests/test_resupply_run_avoids_squads.gd
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

func known_squad(bm, at: Vector2) -> Unit:
	var s: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, at)
	bm.enemy_units.append(s)
	s.is_visible = true
	bm._update_player_intel()
	s.is_visible = false # seen once, now out of sight: a remembered position
	return s

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(300, 1500))
	bm.player_units.append(mortar)
	var run_unit: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.RESUPPLY_RUN, m(2200, 1500))
	bm.player_units.append(run_unit)
	var goal: Vector2 = mortar.global_position
	var radius: float = BattleManager.RESUPPLY_AVOID_RADIUS

	check(bm._resupply_run_destination(run_unit, goal) == goal, "With no known enemy squad the run heads straight for the mortar")

	var squad := known_squad(bm, m(1250, 1530))
	var around: Vector2 = bm._resupply_run_destination(run_unit, goal)
	check(around != goal, "A known squad on the line sends the run round it")
	check(around.distance_to(squad.player_known_position) >= radius * 1.2, "...to a point clear of the squad's reach (%.0f m against %.0f)" % [around.distance_to(squad.player_known_position) / GameConfig.PIXELS_PER_METER, radius / GameConfig.PIXELS_PER_METER])

	# driven along its steering, the run keeps clear of the squad and still arrives
	var pos: Vector2 = run_unit.global_position
	var closest := INF
	var arrived := false
	for i in 3000:
		run_unit.global_position = pos
		var dest: Vector2 = bm._resupply_run_destination(run_unit, goal)
		pos += (dest - pos).normalized() * m(15, 0).x
		closest = minf(closest, pos.distance_to(squad.player_known_position))
		if pos.distance_to(goal) <= m(30, 0).x:
			arrived = true
			break
	check(arrived, "The run, steering round the squad, still reaches the mortar")
	check(closest >= radius * 0.9, "...never closer than %.0f m to the squad (%.0f m, reach %.0f)" % [radius * 0.9 / GameConfig.PIXELS_PER_METER, closest / GameConfig.PIXELS_PER_METER, radius / GameConfig.PIXELS_PER_METER])

	# a squad well off the line is no reason to detour
	squad.player_known_position = m(1250, 1530 + 1200)
	check(bm._resupply_run_destination(run_unit, goal) == goal, "A squad well away from the line is ignored")
	# a squad that already has the mortar in its reach cannot be avoided by a detour
	squad.player_known_position = goal + m(100, 100)
	check(bm._resupply_run_destination(run_unit, goal) == goal, "A squad with the mortar already in its reach: the run goes straight in")

	# and an enemy squad fires on a visible run in its range and sight
	bm.enemy_units.clear()
	var shooter: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(2200, 1500))
	bm.enemy_units.append(shooter)
	run_unit.global_position = m(2000, 1500)
	run_unit.is_visible = true
	var pick: Unit = bm._pick_target(shooter, bm.player_units)
	check(pick == run_unit, "An enemy squad with a visible run in range and in sight picks it as its target")
	run_unit.is_visible = false
	check(bm._pick_target(shooter, bm.player_units) == null, "...and cannot if it has not seen it")
	bm.combat_log.free()
	bm.free()
	print("Resupply run avoidance tests: %d failures" % failures)
	quit(1 if failures else 0)
