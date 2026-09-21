extends SceneTree
## Guards the burst-fire feature: a mortar engagement no longer always
## fires exactly one round before its reload/displace cycle — it commits
## to a burst of GameConfig.MORTAR_BURST_MAX_SHOTS (up to 4) rounds at the
## SAME target, fired in quick succession, before packing up. Direct user
## requirement, four real factors combining into BattleManager.
## _mortar_burst_shot_count's continuous score:
## - Range: closer favors a bigger burst.
## - Ammo on hand: more ammo favors a bigger burst.
## - Resupply expected soon: reads like having more ammo (reuses the exact
##   same scarcity/urgency composite _pick_target's own hold-fire chance
##   already computes).
## - A scheduled retreat coming up soon: worth burning ammo now rather than
##   carrying it off unused (reuses _scheduled_retreat_ammo_discount).
## Direct user requirement, verbatim: "cap it at 3 shots if under 1000
## meters" — a hard ceiling below GameConfig.MORTAR_BURST_CLOSE_RANGE,
## below the normal GameConfig.MORTAR_BURST_MAX_SHOTS (4) ceiling.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_burst_fire.gd
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

func meters(x: float) -> float:
	return x * GameConfig.PIXELS_PER_METER

## Attaches an in-transit resupply run for `mortar` — _mortar_resupply_
## urgency reads this as maximally imminent (1.0), the same as
## mortar_resupply_status's own "in_transit" case.
func _attach_in_transit_run(bm, mortar: Unit) -> void:
	var run: Unit = bm._make_unit(mortar.team, Unit.Kind.RESUPPLY_RUN, mortar.global_position)
	run.resupply_target_mortar = mortar
	run.resupply_delivered = false
	if mortar.team == Unit.Team.PLAYER:
		bm.player_units.append(run)
	else:
		bm.enemy_units.append(run)

func _average_burst(bm, mortar: Unit, target: Unit, trials: int) -> Dictionary:
	var total := 0
	var max_seen := 0
	var min_seen := 999
	seed(1)
	for i in trials:
		var shots: int = bm._mortar_burst_shot_count(mortar, target)
		total += shots
		max_seen = maxi(max_seen, shots)
		min_seen = mini(min_seen, shots)
	return {"avg": float(total) / float(trials), "max": max_seen, "min": min_seen}


func test_closer_range_favors_a_bigger_burst() -> void:
	var bm = make_battle()
	var far_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	far_mortar.mortar_rounds_remaining = 1 # low ammo, no resupply/retreat — isolates range alone
	var far_target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(4400.0), 0))
	var far := _average_burst(bm, far_mortar, far_target, 300)

	var close_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	close_mortar.mortar_rounds_remaining = 1
	var close_target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(500.0), 0))
	var close := _average_burst(bm, close_mortar, close_target, 300)

	check(close.avg > far.avg + 0.4,
		"A closer target should favor a bigger average burst (close avg %.2f, far avg %.2f)" % [close.avg, far.avg])
	bm.combat_log.free()
	bm.free()


func test_close_range_is_hard_capped_at_three() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar.mortar_rounds_remaining = GameConfig.MORTAR_STARTING_AMMO # full ammo
	bm.player_units.append(mortar)
	_attach_in_transit_run(bm, mortar) # + resupply imminent
	bm.scheduled_retreat_time = bm.scenario_elapsed_time # + retreat imminent — maximize every OTHER factor
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(500.0), 0)) # under the 1000m cap
	var result := _average_burst(bm, mortar, target, 300)

	check(result.max <= 3,
		"Under GameConfig.MORTAR_BURST_CLOSE_RANGE, burst size must never exceed 3 even with every other factor maxed out (saw %d)" % result.max)
	check(result.avg > 2.5,
		"With every non-range factor maxed out, the close-range-capped average should sit near the 3-shot ceiling (got %.2f)" % result.avg)
	bm.combat_log.free()
	bm.free()


func test_resupply_expected_soon_reads_like_more_ammo() -> void:
	var bm = make_battle()
	var mortar_no_resupply: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar_no_resupply.mortar_rounds_remaining = 1
	bm.player_units.append(mortar_no_resupply)
	var target_a: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(4400.0), 0))
	var without_resupply := _average_burst(bm, mortar_no_resupply, target_a, 300)

	var mortar_resupply: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar_resupply.mortar_rounds_remaining = 1 # same low ammo
	bm.player_units.append(mortar_resupply)
	_attach_in_transit_run(bm, mortar_resupply)
	var target_b: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(4400.0), 0)) # same far range
	var with_resupply := _average_burst(bm, mortar_resupply, target_b, 300)

	check(with_resupply.avg > without_resupply.avg + 1.0,
		"An imminent resupply run should raise the average burst size roughly like having full ammo, even with the same low rounds on hand (without: %.2f, with: %.2f)" % [without_resupply.avg, with_resupply.avg])
	bm.combat_log.free()
	bm.free()


func test_imminent_scheduled_retreat_raises_burst_size() -> void:
	var bm = make_battle()
	var mortar_no_retreat: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar_no_retreat.mortar_rounds_remaining = 1
	var target_a: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(4400.0), 0))
	var without_retreat := _average_burst(bm, mortar_no_retreat, target_a, 300)

	bm.scheduled_retreat_time = bm.scenario_elapsed_time # due right now — maximally imminent
	var mortar_retreat: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar_retreat.mortar_rounds_remaining = 1 # same low ammo, still no resupply
	var target_b: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(4400.0), 0))
	var with_retreat := _average_burst(bm, mortar_retreat, target_b, 300)

	check(with_retreat.avg > without_retreat.avg + 1.0,
		"An imminent scheduled retreat should raise the average burst size, willing to expend ammo rather than carry it off unused (without: %.2f, with: %.2f)" % [without_retreat.avg, with_retreat.avg])
	bm.combat_log.free()
	bm.free()


func test_burst_size_never_exceeds_the_global_maximum() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar.mortar_rounds_remaining = GameConfig.MORTAR_STARTING_AMMO
	bm.player_units.append(mortar)
	_attach_in_transit_run(bm, mortar)
	bm.scheduled_retreat_time = bm.scenario_elapsed_time
	# Just outside the close-range cap, so the real GameConfig.MORTAR_BURST_
	# MAX_SHOTS ceiling (4) is the one actually being tested here, not the
	# separate close-range-cap-of-3 from test_close_range_is_hard_capped_
	# at_three.
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(1100.0), 0))
	var result := _average_burst(bm, mortar, target, 300)

	check(result.max == GameConfig.MORTAR_BURST_MAX_SHOTS,
		"With every willingness factor maxed out just outside the close-range cap, the global ceiling (%d) should actually be reached at least once in 300 trials (saw max %d)" % [GameConfig.MORTAR_BURST_MAX_SHOTS, result.max])
	check(result.avg > 3.3,
		"Near-maximal willingness just outside the close-range cap should average close to the global ceiling (got %.2f)" % result.avg)
	bm.combat_log.free()
	bm.free()


## Direct integration check through the real firing path (_tick_fire), not
## just the scoring function in isolation — a burst that wants more rounds
## than the mortar actually has on hand must fire what's available and
## stop cleanly, never going negative or erroring.
func test_tick_fire_stops_early_when_ammo_runs_out_mid_burst() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar.mortar_rounds_remaining = 2 # deliberately less than a maxed-out burst would want
	mortar.fire_timer = 0.0
	bm.player_units.append(mortar)
	_attach_in_transit_run(bm, mortar) # resupply urgency 1.0 makes ammo_willingness 1.0 regardless of the 2 rounds on hand
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(500.0), 0)) # under the close-range cap (3), but demand here floors to 2 deterministically — see the design doc entry for the math
	bm.enemy_units.append(target)
	# Bypass _pick_target's own hold-fire coin flip so this test is about
	# the burst LOOP, not target-selection randomness — same technique
	# test_unit_doctrine.gd's own risk test already uses.
	bm._mortar_tick_shot[mortar] = {"resolved": true, "target": target}

	var pending_before: int = bm._pending_mortar_shots.size()
	bm._tick_fire(mortar, 1.0, 60.0, bm.enemy_units)

	check(mortar.mortar_rounds_remaining == 0,
		"A burst that wants more rounds than are on hand must fire every remaining round, not fewer (left with %d)" % mortar.mortar_rounds_remaining)
	check(bm._pending_mortar_shots.size() - pending_before == 2,
		"Exactly 2 rounds (all that were on hand) must have actually been launched, got %d" % (bm._pending_mortar_shots.size() - pending_before))
	check(mortar.fire_timer == mortar.reload_time,
		"The burst loop completing (even cut short by ammo) must still hand off to the ordinary reload cycle")
	bm.combat_log.free()
	bm.free()


## Confirms the ordinary case actually fires MORE than the old fixed
## one-shot-per-engagement behavior when conditions favor a bigger burst —
## not just that the scoring function returns a bigger number in isolation.
func test_tick_fire_fires_more_than_one_shot_for_a_generous_burst() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar.mortar_rounds_remaining = GameConfig.MORTAR_STARTING_AMMO
	mortar.fire_timer = 0.0
	bm.player_units.append(mortar)
	_attach_in_transit_run(bm, mortar)
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(meters(500.0), 0))
	bm.enemy_units.append(target)
	bm._mortar_tick_shot[mortar] = {"resolved": true, "target": target}

	var pending_before: int = bm._pending_mortar_shots.size()
	var rounds_before: int = mortar.mortar_rounds_remaining
	bm._tick_fire(mortar, 1.0, 60.0, bm.enemy_units)

	var shots_fired: int = bm._pending_mortar_shots.size() - pending_before
	check(shots_fired >= 2,
		"Full ammo, resupply imminent, and close range should deterministically commit to at least 2 shots this burst (got %d)" % shots_fired)
	check(rounds_before - mortar.mortar_rounds_remaining == shots_fired,
		"Ammo consumed must exactly match the number of rounds actually launched")
	bm.combat_log.free()
	bm.free()


## Direct user question: "Enemy mortars should fire salvoes, just as
## friendly mortars do. Do they?" They do — the burst logic sits in the
## shared _tick_fire path — and this locks it in for the ENEMY side through
## the real firing path, not just the scoring function.
func test_enemy_mortars_fire_bursts_too() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	mortar.mortar_rounds_remaining = GameConfig.MORTAR_STARTING_AMMO
	mortar.fire_timer = 0.0
	bm.enemy_units.append(mortar)
	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(meters(500.0), 0))
	bm.player_units.append(target)
	bm._mortar_tick_shot[mortar] = {"resolved": true, "target": target}
	var pending_before: int = bm._pending_mortar_shots.size()
	var rounds_before: int = mortar.mortar_rounds_remaining
	bm._tick_fire(mortar, 1.0, 60.0, bm.player_units)
	var shots_fired: int = bm._pending_mortar_shots.size() - pending_before
	check(shots_fired >= 2, "An enemy mortar with full ammo at close range must fire a multi-round burst, not a single shot (got %d)" % shots_fired)
	check(rounds_before - mortar.mortar_rounds_remaining == shots_fired, "Ammo consumed must match the rounds launched")
	bm.combat_log.free()
	bm.free()


## The player's scheduled retreat is the PLAYER's plan — an enemy mortar
## must neither know about it nor change its behavior because of it. It
## used to: _scheduled_retreat_ammo_discount never checked whose mortar was
## asking, so an imminent player retreat made enemy mortars stop
## conserving ammo (and, once bursts existed, fire bigger ones).
func test_enemy_mortars_ignore_the_players_scheduled_retreat() -> void:
	var bm = make_battle()
	var player_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	player_mortar.mortar_rounds_remaining = 10
	enemy_mortar.mortar_rounds_remaining = 10
	bm.player_units.append(player_mortar)
	bm.enemy_units.append(enemy_mortar)
	bm.scheduled_retreat_time = bm.scenario_elapsed_time # the player's retreat is due right now
	check(bm._scheduled_retreat_ammo_discount(player_mortar) < 0.01,
		"Setup check: the player's own mortar must see its own imminent retreat (discount near 0)")
	check(bm._scheduled_retreat_ammo_discount(enemy_mortar) == 1.0,
		"An enemy mortar must read NO retreat discount — the scheduled retreat isn't its side's plan (got %.3f)" % bm._scheduled_retreat_ammo_discount(enemy_mortar))

	# And through the burst count: same far range, low ammo, retreat imminent.
	var enemy_target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(meters(5800.0), 0)) # far for the enemy's 6000m reach
	enemy_mortar.mortar_rounds_remaining = 1
	var with_schedule := _average_burst(bm, enemy_mortar, enemy_target, 300)
	bm.scheduled_retreat_time = INF
	var without_schedule := _average_burst(bm, enemy_mortar, enemy_target, 300)
	check(is_equal_approx(with_schedule.avg, without_schedule.avg),
		"The player's scheduled retreat must not change an enemy mortar's burst size (with %.2f, without %.2f)" % [with_schedule.avg, without_schedule.avg])
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_closer_range_favors_a_bigger_burst()
	test_close_range_is_hard_capped_at_three()
	test_resupply_expected_soon_reads_like_more_ammo()
	test_imminent_scheduled_retreat_raises_burst_size()
	test_burst_size_never_exceeds_the_global_maximum()
	test_tick_fire_stops_early_when_ammo_runs_out_mid_burst()
	test_tick_fire_fires_more_than_one_shot_for_a_generous_burst()
	test_enemy_mortars_fire_bursts_too()
	test_enemy_mortars_ignore_the_players_scheduled_retreat()
	if failures == 0:
		print("Mortar burst fire tests: 0 failures")
	else:
		print("Mortar burst fire tests: %d failures" % failures)
	quit(1 if failures else 0)
