extends SceneTree
## Guards the resupply reorder-point behavior: a physical resupply run
## should only actually dispatch once a mortar's on-hand ammo has drawn
## down to GameConfig.MORTAR_RESUPPLY_REORDER_POINT, not merely "isn't
## completely full" — see that constant's own doc comment for the real
## logistics reasoning (FM 7-90's resupply methods stage ammunition
## against anticipated need, not top off a position every chance a
## scheduled run happens to come up).
##
## Also guards a direct, live-reported bug fix: "the resupply run was set
## to arrive, but the mortar still had over 10 rounds. It delayed the run
## by an hour. That's the wrong reaction. What should happen is that the
## run should go into a state of 'waiting offmap'. It should remain in
## that state until the mortar gets down to ten rounds. When that
## happens, the resupply run should immediately enter the map, and the
## next run should be requested." The OLD code marked a held run resolved
## (silently discarded) the instant its transit timer expired, regardless
## of ammo — a run "held" this way is now genuinely staged and re-checked
## every tick instead, and the moment any run actually commits (dispatch
## or failure), the next one is requested immediately — a continuous
## one-run-at-a-time pipeline, not a batch that waits to be fully used up.
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


## A pending run whose transit has finished (arrival_time already past)
## but whose ammo is still well above the reorder point.
func _make_pending_run(bm, mortar: Unit) -> void:
	bm._mortar_resupply[mortar] = {
		"arrival_time": -1.0, "warning_time": -1.0, "warned": false, "staged": false,
	}


func test_run_held_well_above_reorder_point() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 20 # well above MORTAR_RESUPPLY_REORDER_POINT (10)
	_make_pending_run(bm, mortar)
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
	_make_pending_run(bm, mortar)
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
	_make_pending_run(bm, mortar)
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
	_make_pending_run(bm, mortar)
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


## The exact live-reported bug: a run whose transit has finished while
## ammo is still high must NOT be discarded — it must stay genuinely
## pending (still tracked, ready to be re-checked), and the moment ammo
## actually draws down to the reorder point on a LATER tick, it must
## dispatch immediately, without ever having to be re-requested from
## scratch.
func test_held_run_stays_pending_and_dispatches_once_ammo_drops() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 20 # well above the reorder point
	_make_pending_run(bm, mortar)

	bm._update_mortar_resupply()
	check(_spawn_count(bm, Unit.Team.PLAYER) == 0,
		"Setup check: nothing should dispatch yet, ammo is still high")
	check(bm._mortar_resupply.has(mortar),
		"A held run must remain genuinely pending — the old bug discarded it outright the instant its transit timer expired, regardless of ammo")
	check(bm._mortar_resupply[mortar].staged,
		"A held run must be marked staged, so it's narrated once and its status reads correctly rather than looking like it's still in ordinary transit")

	# Real combat draws the crew's ammo down below the reorder point on a
	# later tick — the SAME pending record (never re-requested) must now
	# dispatch immediately.
	mortar.mortar_rounds_remaining = 8
	seed(2) # deterministic — MORTAR_RESUPPLY_FAILURE_CHANCE is a real 10% roll, unrelated to what this test checks
	bm._update_mortar_resupply()
	check(_spawn_count(bm, Unit.Team.PLAYER) == 1,
		"The same held run must dispatch immediately once ammo actually draws down to the reorder point")
	bm.combat_log.free()
	bm.free()


## Direct correction: the moment a run commits — dispatched OR failed —
## the next one must be requested immediately, not left for a separate
## "ask again" step. A continuous one-run-at-a-time pipeline.
func test_dispatch_immediately_requests_the_next_run() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	bm._player_sighted_enemy = true # required for request_mortar_resupply's own eligibility check
	mortar.mortar_rounds_remaining = 2
	_make_pending_run(bm, mortar)
	seed(2) # a real, deterministic non-failure roll
	bm._update_mortar_resupply()
	check(_spawn_count(bm, Unit.Team.PLAYER) == 1, "Setup check: this run must have actually dispatched")
	check(bm._mortar_resupply.has(mortar),
		"The instant a run dispatches, the next one must already be requested — not left waiting for a separate step")
	check(bm._mortar_resupply[mortar].arrival_time > bm.scenario_elapsed_time,
		"The freshly-requested next run must be a real, fresh future transit, not a leftover from the one that just dispatched")
	bm.combat_log.free()
	bm.free()


## Same guarantee on the failure path — a real run that fails to get
## through must not leave the mortar stranded waiting for a manual
## re-request either.
func test_failure_immediately_requests_the_next_run() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	bm._player_sighted_enemy = true
	mortar.mortar_rounds_remaining = 2
	_make_pending_run(bm, mortar)
	# Find a seed that actually fails the 10% roll, so this test exercises
	# the failure path specifically rather than the dispatch one.
	var failure_seed := -1
	for s in range(200):
		seed(s)
		if randf() < GameConfig.MORTAR_RESUPPLY_FAILURE_CHANCE:
			failure_seed = s
			break
	check(failure_seed != -1, "Setup check: must find a seed that actually rolls a failure")
	seed(failure_seed)
	bm._update_mortar_resupply()
	check(_spawn_count(bm, Unit.Team.PLAYER) == 0, "Setup check: this specific roll must have failed, not dispatched")
	check(bm._mortar_resupply.has(mortar),
		"Even a failed run must immediately request the next one, not strand the mortar waiting for a manual re-request")
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_run_held_well_above_reorder_point()
	test_run_dispatched_at_reorder_point()
	test_run_dispatched_well_below_reorder_point()
	test_dispatched_run_delivers_meaningful_amount()
	test_held_run_stays_pending_and_dispatches_once_ammo_drops()
	test_dispatch_immediately_requests_the_next_run()
	test_failure_immediately_requests_the_next_run()
	if failures == 0:
		print("Mortar resupply tests: 0 failures")
	else:
		print("Mortar resupply tests: %d failures" % failures)
	quit(1 if failures else 0)
