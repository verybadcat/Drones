extends SceneTree
## Direct user report: a drone team's own status read "withdrawing," but the unit was nowhere to be found
## on screen — found via debug snapshot at a raw y of -485, well above the top of the map (y in
## [0, GameConfig.MAP_HEIGHT_PX]). A previous fix (see the design doc's own "retreating spotter's cover
## detour" entry) bounded only the ONE-TIME cover-seeking first leg a retreat can take. _step_retreat is a
## structurally separate code path — the ORDINARY, every-tick straight-line retreat that leg hands off to
## — and neither its zigzag jink nor its continuous _retreat_avoidance_offset steering had ever been bounded
## at all: a threat sitting persistently to one side, or an unlucky zigzag streak, can accumulate real drift
## over a long retreat with nothing pulling it back, eventually running the unit off the map outright.
##
## Run: godot --headless --path . --script scripts/tests/test_retreat_never_leaves_the_map.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
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
	bm.combat_log = Log.new()
	return bm

func run() -> void:
	test_sustained_zigzag_never_drifts_off_the_top()
	test_sustained_zigzag_never_drifts_off_the_bottom()
	test_sustained_threat_steering_never_drifts_off_the_map()
	print("Retreat never-leaves-the-map tests: %d failures" % failures)
	quit(1 if failures else 0)


## A long, unlucky zigzag streak (the SAME jink direction held for many ticks in a row, not the ordinary
## randomized back-and-forth) drifting steadily toward the top edge must never actually cross it.
func test_sustained_zigzag_never_drifts_off_the_top() -> void:
	var bm = make_battle()
	var unit: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(0.0, 5.0))
	bm.player_units.append(unit)
	unit.state = Unit.State.RETREATING
	unit.retreat_speed = GameConfig.REPOSITION_SPEED
	unit.retreat_target_x = -GameConfig.WEST_FLANK_WIDTH_PX # far enough that it never "arrives" mid-test
	unit.zigzagging = true
	unit._zigzag_timer = 1.0e9 # holds this exact velocity for the whole test, no re-roll
	unit._zigzag_lateral_velocity = -500.0 # a large, sustained push toward negative y (off the top)
	for i in 500:
		bm._step_retreat(unit, 0.5)
		check(unit.position.y >= 0.0, "Tick %d: never drifts above the top of the map (y=%.1f)" % [i, unit.position.y])
	check(unit.position.y == 0.0, "Set-up check: the sustained push was strong enough to actually reach the clamp, not just stay clear of it by coincidence (y=%.1f)" % unit.position.y)
	bm.combat_log.free()
	bm.free()


## The exact mirror for the bottom edge — a sustained push toward positive y must never cross
## GameConfig.MAP_HEIGHT_PX either.
func test_sustained_zigzag_never_drifts_off_the_bottom() -> void:
	var bm = make_battle()
	var unit: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(0.0, GameConfig.MAP_HEIGHT_PX - 5.0))
	bm.player_units.append(unit)
	unit.state = Unit.State.RETREATING
	unit.retreat_speed = GameConfig.REPOSITION_SPEED
	unit.retreat_target_x = -GameConfig.WEST_FLANK_WIDTH_PX
	unit.zigzagging = true
	unit._zigzag_timer = 1.0e9
	unit._zigzag_lateral_velocity = 500.0 # a large, sustained push toward positive y (off the bottom)
	for i in 500:
		bm._step_retreat(unit, 0.5)
		check(unit.position.y <= GameConfig.MAP_HEIGHT_PX, "Tick %d: never drifts below the bottom of the map (y=%.1f)" % [i, unit.position.y])
	check(unit.position.y == GameConfig.MAP_HEIGHT_PX, "Set-up check: the sustained push was strong enough to actually reach the clamp (y=%.1f)" % unit.position.y)
	bm.combat_log.free()
	bm.free()


## The other real source of sustained one-directional drift: a known threat sitting persistently to one
## side keeps _retreat_avoidance_offset steering the same way, tick after tick, for as long as the threat
## stays known and close — not just the zigzag jink above.
func test_sustained_threat_steering_never_drifts_off_the_map() -> void:
	var bm = make_battle()
	var unit: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(0.0, 5.0))
	bm.player_units.append(unit)
	unit.state = Unit.State.RETREATING
	unit.retreat_speed = GameConfig.REPOSITION_SPEED
	unit.retreat_target_x = -GameConfig.WEST_FLANK_WIDTH_PX
	# A known enemy well below this unit (higher y) makes _retreat_avoidance_offset steer steadily toward
	# lower y (away from it) every single tick, for as long as it stays the nearest known threat.
	var threat: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(0.0, GameConfig.MAP_HEIGHT_PX + 2000.0))
	bm.enemy_units.append(threat)
	threat.player_has_been_sighted = true
	threat.player_known_position = threat.global_position
	for i in 2000:
		bm._step_retreat(unit, 0.5)
		check(unit.position.y >= 0.0, "Tick %d: continuous threat-avoidance steering never drifts above the top (y=%.1f)" % [i, unit.position.y])
	bm.combat_log.free()
	bm.free()
