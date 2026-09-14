extends SceneTree
## Guards the resupply reorder-point behavior: a physical resupply run
## should only actually dispatch once a mortar's on-hand ammo has drawn
## down to GameConfig.MORTAR_RESUPPLY_REORDER_POINT, not merely "isn't
## completely full" — see that constant's own doc comment for the real
## logistics reasoning (FM 7-90's resupply methods stage ammunition
## against anticipated need, not top off a position every chance a
## scheduled wave happens to come up).
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_resupply.gd
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

const TestCombatLogScript = preload("res://scripts/tests/test_combat_log.gd")

func _spawn_count(bm, team: Unit.Team) -> int:
	var units: Array[Unit] = bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units
	var count := 0
	for u in units:
		if u.kind == Unit.Kind.RESUPPLY_RUN:
			count += 1
	return count


func test_run_held_well_above_reorder_point() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 20 # well above MORTAR_RESUPPLY_REORDER_POINT (10)
	# Constructed directly rather than via request_mortar_resupply (which
	# requires confirmed contact) — this test is only about the dispatch
	# check itself, not the separate request-eligibility gate.
	var wave_arrival_times: Array[float] = [-1.0]
	bm._mortar_resupply[mortar] = {
		"wave_arrival_times": wave_arrival_times, "warning_times": wave_arrival_times.duplicate(),
		"wave_warned": [false], "wave_resolved": [false],
	}
	bm._update_mortar_resupply()
	check(_spawn_count(bm, Unit.Team.PLAYER) == 0,
		"A mortar well above the reorder point must NOT get a physical resupply run dispatched")
	bm.combat_log.free()
	bm.free()


func test_run_dispatched_at_reorder_point() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = GameConfig.MORTAR_RESUPPLY_REORDER_POINT # exactly at the point — must dispatch, not hold
	var wave_arrival_times: Array[float] = [-1.0]
	bm._mortar_resupply[mortar] = {
		"wave_arrival_times": wave_arrival_times, "warning_times": wave_arrival_times.duplicate(),
		"wave_warned": [false], "wave_resolved": [false],
	}
	seed(2) # deterministic — MORTAR_RESUPPLY_FAILURE_CHANCE is a real 10% roll, unrelated to what this test checks
	bm._update_mortar_resupply()
	check(_spawn_count(bm, Unit.Team.PLAYER) == 1,
		"A mortar exactly AT the reorder point must get a resupply run dispatched, not held")
	bm.combat_log.free()
	bm.free()


func test_run_dispatched_well_below_reorder_point() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 2
	var wave_arrival_times: Array[float] = [-1.0]
	bm._mortar_resupply[mortar] = {
		"wave_arrival_times": wave_arrival_times, "warning_times": wave_arrival_times.duplicate(),
		"wave_warned": [false], "wave_resolved": [false],
	}
	seed(2) # deterministic — MORTAR_RESUPPLY_FAILURE_CHANCE is a real 10% roll, unrelated to what this test checks
	bm._update_mortar_resupply()
	check(_spawn_count(bm, Unit.Team.PLAYER) == 1,
		"A mortar well below the reorder point must get a resupply run dispatched")
	bm.combat_log.free()
	bm.free()


## A run genuinely dispatched must still deliver a real, meaningful
## amount of ammunition, not a token top-up — the whole point of raising
## the dispatch threshold is that a committed trip is worth the exposure.
func test_dispatched_run_delivers_meaningful_amount() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = GameConfig.MORTAR_RESUPPLY_REORDER_POINT
	var wave_arrival_times: Array[float] = [-1.0]
	bm._mortar_resupply[mortar] = {
		"wave_arrival_times": wave_arrival_times, "warning_times": wave_arrival_times.duplicate(),
		"wave_warned": [false], "wave_resolved": [false],
	}
	seed(2) # deterministic — MORTAR_RESUPPLY_FAILURE_CHANCE is a real 10% roll, unrelated to what this test checks
	bm._update_mortar_resupply()
	var run: Unit = null
	for u in bm.player_units:
		if u.kind == Unit.Kind.RESUPPLY_RUN:
			run = u
	check(run != null, "A run must have been dispatched")
	if run != null:
		var deliverable: int = mini(GameConfig.MORTAR_RESUPPLY_ROUNDS, GameConfig.MORTAR_MAX_AMMO_ON_HAND - mortar.mortar_rounds_remaining)
		check(deliverable >= GameConfig.MORTAR_RESUPPLY_REORDER_POINT,
			"A dispatched run's deliverable amount should be a real, substantial delivery, not a token few rounds (got %d)" % deliverable)
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_run_held_well_above_reorder_point()
	test_run_dispatched_at_reorder_point()
	test_run_dispatched_well_below_reorder_point()
	test_dispatched_run_delivers_meaningful_amount()
	if failures == 0:
		print("Mortar resupply tests: 0 failures")
	else:
		print("Mortar resupply tests: %d failures" % failures)
	quit(1 if failures else 0)
