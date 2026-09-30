extends SceneTree
## Direct user report: watching the post-battle replay, a resupply run appeared to drive right past a
## mortar that was actively relocating (shoot-and-scoot/evade/hunt — NOT retreating, which already aborts
## the run outright, see BattleManager._resolve_resupply_run_arrivals) without ever delivering. The user
## had an extreme play-speed override active (Godot's own debug time-scale set to 8x) stacked on top of
## this game's own TIME_SCALE_FAST_FORWARD tier (300x) — together capable of a single _process tick's
## scenario_delta far larger than this project's movement code had ever been exercised against.
##
## Root cause: BattleManager._update_resupply_run_targets (called once, BEFORE _tick_movement each tick)
## sets the run's move_target from the mortar's position as of the START of the tick. Under an ordinary
## scenario_delta that staleness is trivial next to MORTAR_RESUPPLY_ARRIVAL_RADIUS, and the run's real
## speed advantage (MORTAR_RESUPPLY_RUN_SPEED, 7 m/s, vs. a relocating mortar's MORTAR_RELOCATE_SPEED, 2.2
## m/s) converges it in. But at a large enough single-tick scenario_delta, the mortar's OWN per-tick
## displacement can exceed the arrival radius outright, and since the run is always chasing LAST tick's
## already-stale position, it can perpetually trail just outside arrival range tick after tick, forever,
## even though it is genuinely faster than what it's chasing.
##
## Fixed in _tick_movement itself: a RESUPPLY_RUN in transit to an ACTIVE mortar now has its move_target
## refreshed to that mortar's CURRENT position immediately before taking its own step — not just once,
## before either of them has moved this tick. This works without restructuring anything because a
## RESUPPLY_RUN's target mortar is always earlier in the same player_units/enemy_units array (see
## _spawn_resupply_run), so by the time this loop reaches the run's own turn, the mortar has already taken
## its own step for this tick.
##
## Run: godot --headless --path . --script res://scripts/tests/test_resupply_run_catches_relocating_mortar.gd
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
	test_run_catches_a_relocating_mortar_under_an_extreme_tick_size()
	test_run_still_catches_a_relocating_mortar_at_an_ordinary_tick_size()
	print("Resupply-run-catches-relocating-mortar tests: %d failures" % failures)
	quit(1 if failures else 0)


## A deterministic pursuit: the mortar moves in a straight line, away from the run's own approach
## direction, at MORTAR_RELOCATE_SPEED, toward a destination far enough away that it never actually
## arrives during the test — exactly like a real, sustained shoot-and-scoot/evade/hunt leg, just without
## needing a random destination each time (which would make this test flaky). The run starts well beyond
## MORTAR_RESUPPLY_ARRIVAL_RADIUS and must close a shrinking-but-nonzero net gap (run 7 m/s minus mortar
## 2.2 m/s = 4.8 m/s closing speed) under a single-tick scenario_delta of 40 tactical seconds — large
## enough that a single tick's mortar displacement alone (2.2 * 40 = 88m in GameConfig's own units) already
## exceeds MORTAR_RESUPPLY_ARRIVAL_RADIUS (30m), which is exactly the regime the reverted code fails in.
func test_run_catches_a_relocating_mortar_under_an_extreme_tick_size() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 2
	mortar.move_target = Vector2(-100000.0, 0.0) # far enough west it never arrives during this test
	mortar.has_move_target = true
	mortar.move_speed = GameConfig.MORTAR_RELOCATE_SPEED

	var run: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.RESUPPLY_RUN, Vector2(2000.0, 0.0))
	run.resupply_target_mortar = mortar
	run.move_target = mortar.global_position
	run.has_move_target = true
	run.move_speed = GameConfig.MORTAR_RESUPPLY_RUN_SPEED
	run.movement_predictable = false
	run.state_changed.connect(bm._on_resupply_run_state_changed)
	bm.player_units.append(run)

	var scenario_delta: float = 40.0
	var delivered := false
	for i in 200:
		bm._update_resupply_run_targets()
		bm._tick_movement(scenario_delta)
		bm._resolve_resupply_run_arrivals()
		if mortar.mortar_rounds_remaining > 2:
			delivered = true
			break
	check(delivered, "The run eventually catches and delivers to a mortar that's continuously relocating, even under an extreme single-tick scenario_delta")
	bm.combat_log.free()
	bm.free()


## Sanity/regression guard: an ordinary, small scenario_delta (well under the regime this bug needed)
## must still deliver correctly against a relocating mortar — the fix must not have changed normal-speed
## behavior at all.
func test_run_still_catches_a_relocating_mortar_at_an_ordinary_tick_size() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 2
	mortar.move_target = Vector2(-100000.0, 0.0)
	mortar.has_move_target = true
	mortar.move_speed = GameConfig.MORTAR_RELOCATE_SPEED

	var run: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.RESUPPLY_RUN, Vector2(2000.0, 0.0))
	run.resupply_target_mortar = mortar
	run.move_target = mortar.global_position
	run.has_move_target = true
	run.move_speed = GameConfig.MORTAR_RESUPPLY_RUN_SPEED
	run.movement_predictable = false
	run.state_changed.connect(bm._on_resupply_run_state_changed)
	bm.player_units.append(run)

	var scenario_delta: float = 1.0
	var delivered := false
	for i in 3000:
		bm._update_resupply_run_targets()
		bm._tick_movement(scenario_delta)
		bm._resolve_resupply_run_arrivals()
		if mortar.mortar_rounds_remaining > 2:
			delivered = true
			break
	check(delivered, "Still delivers correctly at an ordinary tick size (regression guard)")
	bm.combat_log.free()
	bm.free()
