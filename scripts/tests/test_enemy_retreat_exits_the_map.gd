extends SceneTree
## Direct user report: "Enemy is retreating but failed to exit the map." Confirmed directly via the live
## debug snapshot: every enemy unit on the field was stuck in RETREATING at exactly x=MAP_WIDTH_PX,
## has_move_target=false, never reaching WITHDRAWN.
##
## Root cause: a same-session earlier fix ("A long retreat's own continuous drift could run a unit off the
## map") had _step_retreat clamp next_pos through GameConfig.clamp_to_operating_area every tick, to stop
## unbounded y-drift from zigzag/threat-steering. That helper's x range is [-WEST_FLANK_WIDTH_PX,
## MAP_WIDTH_PX] — a deliberate west-side buffer wide enough to contain PLAYER_SAFE_X, but with no matching
## east-side buffer, since none of its other callers ever need to reach past the map's east edge.
## GameConfig.ENEMY_SAFE_X (the enemy's own retreat_target_x) is deliberately set PAST that edge
## (spawn_x + 150m) — clamping x walled the enemy side off from ever reaching its own exit line at all.
##
## Fix: _step_retreat now clamps y only, not x — x was never the source of the original drift bug.
##
## Run: godot --headless --path . --script res://scripts/tests/test_enemy_retreat_exits_the_map.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_a_retreating_enemy_reaches_its_safe_line_and_withdraws()
	test_a_retreating_player_still_withdraws_too()
	print("Enemy-retreat-exits-the-map tests: %d failures" % failures)
	quit(1 if failures else 0)


## The exact reported mechanism: an enemy squad well inside the map, RETREATING toward ENEMY_SAFE_X (which
## sits past GameConfig.MAP_WIDTH_PX by construction), must actually reach it and become WITHDRAWN rather
## than sticking at MAP_WIDTH_PX forever.
func test_a_retreating_enemy_reaches_its_safe_line_and_withdraws() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.combat_log = Log.new()
	var unit: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(GameConfig.MAP_WIDTH_PX - 200.0, GameConfig.MAP_HEIGHT_PX / 2.0))
	unit.state = Unit.State.RETREATING
	unit.retreat_speed = GameConfig.ENEMY_RETREAT_SPEED
	unit.retreat_target_x = GameConfig.ENEMY_SAFE_X
	check(GameConfig.ENEMY_SAFE_X > GameConfig.MAP_WIDTH_PX, "Set-up: ENEMY_SAFE_X really is past the map's east edge, or this test proves nothing")
	var withdrawn := false
	for i in 2000:
		bm._step_retreat(unit, 1.0)
		if unit.state == Unit.State.WITHDRAWN:
			withdrawn = true
			break
	check(withdrawn, "The retreating enemy unit actually reaches its safe line and withdraws, instead of sticking at MAP_WIDTH_PX forever")
	check(unit.position.x == GameConfig.ENEMY_SAFE_X, "Its final x is exactly its own safe line, not clamped short of it")
	bm.combat_log.free()
	bm.free()


## Regression guard: a retreating PLAYER unit (whose own safe line already sits inside the clamp's old x
## range) must still withdraw correctly with the clamp narrowed to y-only.
func test_a_retreating_player_still_withdraws_too() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.combat_log = Log.new()
	var unit: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(-GameConfig.WEST_FLANK_WIDTH_PX + 200.0, GameConfig.MAP_HEIGHT_PX / 2.0))
	unit.state = Unit.State.RETREATING
	unit.retreat_speed = GameConfig.PLAYER_RETREAT_SPEED
	unit.retreat_target_x = GameConfig.PLAYER_SAFE_X
	var withdrawn := false
	for i in 2000:
		bm._step_retreat(unit, 1.0)
		if unit.state == Unit.State.WITHDRAWN:
			withdrawn = true
			break
	check(withdrawn, "A retreating player unit still reaches its own safe line and withdraws")
	bm.combat_log.free()
	bm.free()
