extends SceneTree
## Direct user report: "I think enemy mortars are firing while moving. Can you tell from the history if
## this is in fact the case? They should have the same restrictions as friendly mortars in this regard."
##
## The live history (mortar_audio_snapshot.json / mortar_decision_snapshot.json) couldn't settle it either
## way: the recorded per-mortar position history is only the last ~40 ticks (about 23 real seconds), and
## none of the actual shot timestamps in the audio log fell inside that window by the time it was
## checked — so the past shots themselves aren't reconstructable from what the game keeps. Reading the
## code instead: an ORDINARY shot already can't happen while moving, for either side, via the shared
## _mortar_shot_this_tick (gated on seconds_stationary >= MORTAR_SETUP_TEARDOWN_TIME, which
## _tick_movement resets to 0 every tick a unit is actually stepping toward a target) — that part was
## already equal. The one real gap was COUNTER-BATTERY: _resolve_mortar_counter_battery schedules a
## responder's return shot for a fixed future fire_time, using the responder's readiness at THAT INSTANT
## only (setup_remaining, folded into the delay) — never re-checked. A crew ordered to relocate again for
## some other reason before fire_time arrived used to fire right on schedule regardless, moving or not.
## Since counter-battery always answers whichever side just fired, this is exactly the shape of "the enemy
## mortar fired while moving": the enemy is the responder whenever the FRIENDLY mortar fires and draws a
## reply. Fixed to wait for the same readiness ordinary fire requires.
##
## Run: godot --headless --path . --script scripts/tests/test_counter_battery_stops_to_fire.gd
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

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_a_moving_responder_waits_to_fire()
	test_a_spotted_or_endangered_responder_waits_too()
	test_a_drone_alone_counts_only_if_the_crew_has_seen_it()
	test_ordinary_fire_is_already_gated_the_same_for_both_sides()
	test_counter_battery_fire_spends_ammo()
	test_a_responder_that_runs_dry_before_firing_aborts_the_mission()
	test_a_dry_responder_never_takes_on_a_counter_battery_mission()
	test_a_responder_already_committed_does_not_take_on_a_second_mission()
	print("Counter-battery movement tests: %d failures" % failures)
	quit(1 if failures else 0)


## A strike whose fire_time has arrived, but the responder (an enemy mortar — the case the user reported)
## is actively mid-relocation: it must not fire yet.
func test_a_moving_responder_waits_to_fire() -> void:
	var bm = make_battle()
	var responder: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1200))
	bm.enemy_units.append(responder)
	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1200))
	bm.player_units.append(target)
	responder.has_move_target = true
	responder.activity = Unit.Activity.MOVING
	responder.seconds_stationary = 0.0
	bm._pending_counter_battery.append({
		"attacker": responder, "target": target, "impact_position": target.global_position,
		"fire_time": bm.scenario_elapsed_time, "impact_time": bm.scenario_elapsed_time + GameConfig.MORTAR_FLIGHT_TIME, "fired": false,
	})
	bm._resolve_pending_counter_battery()
	check(bm._pending_counter_battery.size() == 1 and not bm._pending_counter_battery[0].fired, "A responder still moving at fire_time does not fire yet")
	check(not bm._last_detected_mortar_fire.has(responder), "...and gives no muzzle-flash detection away")

	# It keeps waiting, tick after tick, while it stays in motion.
	for i in 5:
		responder.seconds_stationary = 0.0 # still moving
		bm._resolve_pending_counter_battery()
	check(not bm._pending_counter_battery[0].fired, "Still waiting after several more ticks of continued movement")

	# Once it actually stops long enough (the same setup time ordinary fire requires), it fires.
	responder.has_move_target = false
	responder.activity = Unit.Activity.STATIONARY
	responder.seconds_stationary = GameConfig.MORTAR_SETUP_TEARDOWN_TIME
	bm._resolve_pending_counter_battery()
	check(bm._pending_counter_battery[0].fired, "Once stationary long enough, it fires")
	check(bm._last_detected_mortar_fire.has(responder), "...and the muzzle flash is recorded")
	cleanup(bm)


## Stationary long enough, but spotted (or facing an unwatched threat closing in) right now: the same
## team-agnostic tier-1 danger signal that would send it fleeing instead of firing an ordinary shot. Checked
## for both sides — "the same restrictions as friendly mortars" cuts both ways.
func test_a_spotted_or_endangered_responder_waits_too() -> void:
	for team in [Unit.Team.ENEMY, Unit.Team.PLAYER]:
		var bm = make_battle()
		var responder: Unit = bm._make_unit(team, Unit.Kind.MORTAR, m(4700, 1200))
		var target: Unit = bm._make_unit(Unit.Team.PLAYER if team == Unit.Team.ENEMY else Unit.Team.ENEMY, Unit.Kind.MORTAR, m(500, 1200))
		if team == Unit.Team.ENEMY:
			bm.enemy_units.append(responder)
			bm.player_units.append(target)
		else:
			bm.player_units.append(responder)
			bm.enemy_units.append(target)
		responder.is_visible = true # spotted right now
		responder.seconds_stationary = GameConfig.MORTAR_SETUP_TEARDOWN_TIME
		bm._pending_counter_battery.append({
			"attacker": responder, "target": target, "impact_position": target.global_position,
			"fire_time": bm.scenario_elapsed_time, "impact_time": bm.scenario_elapsed_time + GameConfig.MORTAR_FLIGHT_TIME, "fired": false,
		})
		bm._resolve_pending_counter_battery()
		check(not bm._pending_counter_battery[0].fired, "%s: a spotted responder does not fire either, same as it would hold an ordinary shot" % Unit.Team.keys()[team])
		responder.is_visible = false
		bm._resolve_pending_counter_battery()
		check(bm._pending_counter_battery[0].fired, "%s: no longer spotted, it fires" % Unit.Team.keys()[team])
		cleanup(bm)


## Direct user correction: "'not spotted' should be 'not aware that it has been spotted'. If a drone sees
## it, it may not be aware of that." — then refined again: "It might be aware of drone-only sighting. It
## depends if it has seen the drone or not." Same drone-alone set-up test_mortar_ignores_drone.gd already
## uses (4 m away, nothing else watching), tried both ways: the drone unseen by the crew's own side, and
## the drone spotted right back.
func test_a_drone_alone_counts_only_if_the_crew_has_seen_it() -> void:
	var bm = make_battle()
	var responder: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 637))
	bm.enemy_units.append(responder)
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, responder.global_position + Vector2(-4.0, 0.0) * GameConfig.PIXELS_PER_METER)
	bm.player_units.append(drone)
	responder.is_visible = true
	check(bm._mortar_troubled_only_by_unarmed_observers(responder), "Set-up: only the drone overhead has the mortar in sight")
	responder.seconds_stationary = GameConfig.MORTAR_SETUP_TEARDOWN_TIME
	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1200))
	bm.player_units.append(target)
	var strike := {
		"attacker": responder, "target": target, "impact_position": target.global_position,
		"fire_time": bm.scenario_elapsed_time, "impact_time": bm.scenario_elapsed_time + GameConfig.MORTAR_FLIGHT_TIME, "fired": false,
	}

	drone.is_visible = false # the crew's own side has not spotted this drone
	check(not bm._mortar_has_seen_an_unarmed_observer(responder) and not bm._mortar_aware_of_being_spotted(responder), "Not having seen the drone, the crew is not aware of the sighting")
	bm._pending_counter_battery.clear()
	bm._pending_counter_battery.append(strike.duplicate())
	bm._resolve_pending_counter_battery()
	check(bm._pending_counter_battery[0].fired, "...so it still fires")

	drone.is_visible = true # the crew's own side HAS spotted this drone
	check(bm._mortar_has_seen_an_unarmed_observer(responder) and bm._mortar_aware_of_being_spotted(responder), "Having seen the drone, the crew is aware it may have been seen too")
	bm._pending_counter_battery.clear()
	bm._pending_counter_battery.append(strike.duplicate())
	bm._resolve_pending_counter_battery()
	check(not bm._pending_counter_battery[0].fired, "...so now it waits, the same as if a squad had it in sight")
	cleanup(bm)


## What was already true, confirmed directly rather than assumed: an ORDINARY shot (not a counter-battery
## reply) cannot happen while a mortar of either side is actually moving, because seconds_stationary is
## reset to 0 every tick _tick_movement finds it stepping toward a target.
func test_ordinary_fire_is_already_gated_the_same_for_both_sides() -> void:
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		var bm = make_battle()
		var mortar: Unit = bm._make_unit(team, Unit.Kind.MORTAR, m(0, 0))
		mortar.mortar_rounds_remaining = 20
		mortar.move_target = m(500, 0)
		mortar.has_move_target = true
		mortar.move_speed = GameConfig.MORTAR_RELOCATE_SPEED
		var opposing: Array[Unit] = [bm._make_unit(Unit.Team.PLAYER if team == Unit.Team.ENEMY else Unit.Team.ENEMY, Unit.Kind.SQUAD, m(50, 0))]
		if team == Unit.Team.PLAYER:
			bm.player_units.append(mortar)
			bm.enemy_units.append(opposing[0])
		else:
			bm.enemy_units.append(mortar)
			bm.player_units.append(opposing[0])
		opposing[0].is_visible = true
		var rounds_before: int = mortar.mortar_rounds_remaining
		for i in 40: # walking the whole way there, real frame-scale ticks
			bm._tick_movement(0.5)
			bm._tick_fire(mortar, 0.1, 0.5, opposing)
			check(mortar.mortar_rounds_remaining == rounds_before, "%s mortar must not fire while still walking (tick %d)" % [Unit.Team.keys()[team], i])
			if not mortar.has_move_target:
				break
		cleanup(bm)


## Direct user report: "In the history, it is not showing expenditure of ammunition for friendly counter
## battery fire." Root cause: a counter-battery reply never went through _launch_mortar_shot (the only
## other place mortar_rounds_remaining was ever decremented) — it fired through its own separate scheduling
## path that never touched ammo at all.
func test_counter_battery_fire_spends_ammo() -> void:
	var bm = make_battle()
	var responder: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1200))
	bm.enemy_units.append(responder)
	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1200))
	bm.player_units.append(target)
	var starting_ammo: int = responder.mortar_rounds_remaining
	check(starting_ammo > 0, "Setup: the responder starts with real ammunition on hand")
	responder.seconds_stationary = GameConfig.MORTAR_SETUP_TEARDOWN_TIME
	bm._pending_counter_battery.append({
		"attacker": responder, "target": target, "impact_position": target.global_position,
		"fire_time": bm.scenario_elapsed_time, "impact_time": bm.scenario_elapsed_time + GameConfig.MORTAR_FLIGHT_TIME, "fired": false,
	})
	bm._resolve_pending_counter_battery()
	check(bm._pending_counter_battery[0].fired, "Setup: it actually fires this tick")
	check(responder.mortar_rounds_remaining == starting_ammo - 1, "Firing the counter-battery reply spends exactly one round (%d -> %d)" % [starting_ammo, responder.mortar_rounds_remaining])
	cleanup(bm)


## A crew that ran dry (most plausibly by firing an ordinary shot) in the gap between the mission being
## called in and its own fire_time arriving cannot conjure a round from nowhere — the mission is dropped,
## nothing lands, exactly like a crew knocked out before it could fire.
func test_a_responder_that_runs_dry_before_firing_aborts_the_mission() -> void:
	var bm = make_battle()
	var responder: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1200))
	bm.enemy_units.append(responder)
	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1200))
	bm.player_units.append(target)
	responder.seconds_stationary = GameConfig.MORTAR_SETUP_TEARDOWN_TIME
	responder.mortar_rounds_remaining = 0
	bm._pending_counter_battery.append({
		"attacker": responder, "target": target, "impact_position": target.global_position,
		"fire_time": bm.scenario_elapsed_time, "impact_time": bm.scenario_elapsed_time + GameConfig.MORTAR_FLIGHT_TIME, "fired": false,
	})
	bm._resolve_pending_counter_battery()
	check(bm._pending_counter_battery.is_empty(), "No rounds left to fire the reply with: the mission is dropped, nothing lands")
	cleanup(bm)


## Direct user report: "It also shows counter battery fire at two mortars at the same time." Root cause:
## nothing stopped a dry-of-ammo (or already-committed) responder from being newly tasked. Both new checks
## in _resolve_mortar_counter_battery run BEFORE its own randf() roll, so these are deterministic regardless
## of GameConfig.MORTAR_COUNTER_BATTERY_CHANCE.
func test_a_dry_responder_never_takes_on_a_counter_battery_mission() -> void:
	var bm = make_battle()
	var responder: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1200))
	bm.enemy_units.append(responder)
	responder.mortar_rounds_remaining = 0
	var firing: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1200))
	bm.player_units.append(firing)
	bm._resolve_mortar_counter_battery(firing)
	check(bm._pending_counter_battery.is_empty(), "A dry responder cannot credibly commit to counter-battery fire")
	cleanup(bm)


## A single tube can only ever be mid-mission for one call for fire at a time — the same "one incoming
## strike per shot" idea this function's own existing comment already states, from the other direction:
## a responder already committed to an earlier call cannot ALSO pick up a second, independent one before
## the first is resolved.
func test_a_responder_already_committed_does_not_take_on_a_second_mission() -> void:
	var bm = make_battle()
	var responder: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1200))
	bm.enemy_units.append(responder)
	var target_a: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1200))
	bm.player_units.append(target_a)
	var target_b: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(600, 1200))
	bm.player_units.append(target_b)
	bm._pending_counter_battery.append({
		"attacker": responder, "target": target_a, "impact_position": target_a.global_position,
		"fire_time": bm.scenario_elapsed_time + 100.0, "impact_time": bm.scenario_elapsed_time + 200.0, "fired": false,
	})
	check(bm._pending_counter_battery.size() == 1, "Setup: one mission already pending")
	seed(13) # makes the responder's own chance roll succeed on the very first draw — without the
	# already-committed guard this is checking for, that would otherwise schedule a second strike;
	# unseeded, an unlucky roll could pass this check for the wrong reason (never rolling at all)
	bm._resolve_mortar_counter_battery(target_b) # a second, independent originating shot
	check(bm._pending_counter_battery.size() == 1, "Already committed to one mission: does not take on a second")
	cleanup(bm)
