extends SceneTree
## Guards the ballistic-dispersion + fire-adjustment feature added alongside
## the collateral-damage work: a mortar's real impact point differs from its
## calculated aim point (BattleManager._mortar_dispersion_offset), and
## "walking fire" onto a persistent target converges that dispersion toward
## a floor over successive shots — but only for as long as somebody can
## actually see where the rounds are landing (BattleManager._mortar_fire_
## observation_quality). See GameConfig.MORTAR_DISPERSION_* for the cited
## real-world grounding.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_dispersion.gd
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


## No observer at all (an isolated mortar/target pair, nothing else on
## either side) must report "none" and never converge — real unobserved/
## predicted fire has no way to learn from a round nobody watched land.
func test_no_observer_never_converges() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(300, 0))
	bm.enemy_units.append(target)

	check(bm._mortar_fire_observation_quality(mortar, target) == "none",
		"With no observer at all on either side, observation quality must read 'none'")

	var aim_point: Vector2 = target.global_position
	var early := 0.0
	var late := 0.0
	const TRIALS := 400
	seed(778899)
	# Each trial resets _mortar_fire_adjustment first — NOT the same as calling _mortar_dispersion_offset
	# TRIALS times in a row without resetting. A real, previously-caught gap in this exact test: with no
	# reset, "early" and "late" are just two adjacent 400-call windows on the SAME accumulating shot
	# counter — if unobserved fire ever wrongly gained fast convergence (a spotter-speed decay, say), both
	# windows would already be sitting at the converged floor well before either measurement started (fast
	# decay reaches its floor within ~10-15 calls, a rounding error against 400), so the two averages would
	# still read as "flat" relative to EACH OTHER even though real, wrong convergence happened. Resetting
	# per trial instead measures the actual quantity that matters: does shot N ever look any different from
	# shot 1 for a target nobody is watching.
	for i in TRIALS:
		bm._mortar_fire_adjustment.erase(mortar)
		early += fire_round(bm, mortar, target, aim_point).length()
	for i in TRIALS:
		bm._mortar_fire_adjustment.erase(mortar)
		for j in 10: # burn 10 "prior" shots at this same target before the one actually measured
			fire_round(bm, mortar, target, aim_point)
		late += fire_round(bm, mortar, target, aim_point).length()
	var early_avg := early / TRIALS
	var late_avg := late / TRIALS
	check(absf(early_avg - late_avg) < early_avg * 0.35,
		"Unobserved fire's average miss distance must stay roughly flat shot over shot (early avg %.1f vs late avg %.1f px) — no observer means no correction, ever" % [early_avg, late_avg])
	bm.combat_log.free()
	bm.free()


## A dedicated spotter with live LOS on the target must both be detected as
## the "spotter" quality tier AND make successive shots converge — later
## shots at the same target should land meaningfully closer, on average,
## than the very first one.
func test_spotter_observation_converges() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(300, 0))
	bm.enemy_units.append(target)
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, target.global_position + Vector2(0, 60))
	bm.player_units.append(spotter)

	check(bm._mortar_fire_observation_quality(mortar, target) == "spotter",
		"A dedicated spotter with live LOS on the target must read as 'spotter' quality")

	var aim_point: Vector2 = target.global_position
	seed(112233)
	# Average many independent "first shot" samples (resetting the
	# adjustment state each time) rather than trusting a single noisy draw
	# — a lone unadjusted sample could land unusually close to the aim
	# point by pure chance and make a real convergence look fake or absent.
	var early_total := 0.0
	const EARLY_TRIALS := 200
	for i in EARLY_TRIALS:
		bm._mortar_fire_adjustment.erase(mortar)
		early_total += fire_round(bm, mortar, target, aim_point).length()
	var early_avg := early_total / EARLY_TRIALS

	for i in 10: # prime enough corrected shots to approach the convergence floor
		fire_round(bm, mortar, target, aim_point)
	var late_total := 0.0
	const LATE_TRIALS := 200
	for i in LATE_TRIALS:
		late_total += fire_round(bm, mortar, target, aim_point).length()
	var late_avg := late_total / LATE_TRIALS

	# The spotter's own convergence floor is well under half this
	# scenario's unadjusted CEP (base_cep here is ~9px at 1500m range vs
	# an 18m/3.6px floor), so a real, substantial reduction should show
	# up, not noise-level drift.
	check(late_avg < early_avg * 0.7,
		"Converged spotter-observed fire should show a substantial reduction from the unadjusted average, not a marginal one (early avg=%.1f px, converged avg=%.1f px)" % [early_avg, late_avg])
	bm.combat_log.free()
	bm.free()


## Drone observation is the highest-quality channel modeled — it must
## converge to a tighter final dispersion than a dedicated spotter given
## the same number of corrected shots (real-world grounding: reported
## Ukraine-war drone-directed fire missions needing an order of magnitude
## fewer rounds than unobserved fire — see GameConfig.MORTAR_DISPERSION_
## DRONE_* 's own doc comment).
func test_drone_converges_tighter_than_spotter() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var spotter_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	var drone_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start + Vector2(500, 0))
	bm.player_units.append(spotter_mortar)
	bm.player_units.append(drone_mortar)
	var target_a: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(300, 0))
	var target_b: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(800, 0))
	bm.enemy_units.append(target_a)
	bm.enemy_units.append(target_b)
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, target_a.global_position + Vector2(0, 60))
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, target_b.global_position + Vector2(0, 60))
	bm.player_units.append(spotter)
	bm.player_units.append(drone)

	check(bm._mortar_fire_observation_quality(drone_mortar, target_b) == "drone",
		"A drone with live LOS on the target must read as the top 'drone' quality tier, ahead of a spotter")

	seed(445566)
	const ROUNDS := 15
	const TRIALS := 1000
	for i in ROUNDS - 1:
		fire_round(bm, spotter_mortar, target_a, target_a.global_position)
		fire_round(bm, drone_mortar, target_b, target_b.global_position)
	var spotter_total := 0.0
	var drone_total := 0.0
	for i in TRIALS:
		spotter_total += fire_round(bm, spotter_mortar, target_a, target_a.global_position).length()
		drone_total += fire_round(bm, drone_mortar, target_b, target_b.global_position).length()
	var spotter_avg := spotter_total / TRIALS
	var drone_avg := drone_total / TRIALS
	# A hard analytic bound, not just a relative comparison between two
	# noisy samples of what could theoretically be the same distribution:
	# the drone's OWN convergence floor (6m) is well under half the
	# spotter's (18m), so fully-converged drone fire's average sampled
	# miss distance must land under the spotter's floor outright.
	check(drone_avg < GameConfig.MORTAR_DISPERSION_SPOTTER_FLOOR,
		"Fully-converged drone-observed fire's average miss distance (%.1f px) should land under the spotter's OWN convergence floor (%.1f px) — drone observation is modeled as strictly better" % [drone_avg, GameConfig.MORTAR_DISPERSION_SPOTTER_FLOOR])
	check(drone_avg < spotter_avg,
		"After the same number of corrected rounds, drone-observed fire should converge tighter than spotter-observed fire (drone avg=%.1f px, spotter avg=%.1f px)" % [drone_avg, spotter_avg])
	bm.combat_log.free()
	bm.free()


## Direct user request, after asking whether an enemy mortar being wiped out quickly was "just luck": a
## single, direct, apples-to-apples comparison of all three tiers side by side — same mortar/target range
## (so the same starting base_cep), same fixed number of corrected shots, three completely independent
## mortar/target pairs (so none of the three can contaminate another's _mortar_fire_adjustment state).
## The three separate tests above already establish each piece rigorously on its own; this ties them
## together into the one ordered claim actually asked for.
func test_walk_in_orders_drone_fastest_spotter_middling_none_absent() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var none_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	var spotter_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start + Vector2(700, 0))
	var drone_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start + Vector2(1400, 0))
	bm.player_units.append(none_mortar)
	bm.player_units.append(spotter_mortar)
	bm.player_units.append(drone_mortar)
	# Each target sits the identical 300px offset from its own mortar, so all three start from exactly the
	# same base_cep (a function of range alone) — the only thing that can differ between them is quality.
	# The 700px spacing between pairs (not the original 500 the drone-vs-spotter test above uses — that
	# test never needs a genuine "nothing at all" pair) clears even the worst-case squad-tier detection
	# range (DETECTION_BASE_RANGE + DETECTION_ELEVATION_BONUS, 280px) with real margin, confirmed directly:
	# at 500px spacing, the "none" mortar's own siblings registered as accidental squad-tier observers of
	# its target purely by being in range, defeating the whole point of that pair.
	var none_target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, none_mortar.global_position + Vector2(300, 0))
	var spotter_target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, spotter_mortar.global_position + Vector2(300, 0))
	var drone_target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, drone_mortar.global_position + Vector2(300, 0))
	bm.enemy_units.append(none_target)
	bm.enemy_units.append(spotter_target)
	bm.enemy_units.append(drone_target)
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, spotter_target.global_position + Vector2(0, 60))
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, drone_target.global_position + Vector2(0, 60))
	bm.player_units.append(spotter)
	bm.player_units.append(drone)

	check(bm._mortar_fire_observation_quality(none_mortar, none_target) == "none", "Set-up: nothing at all is watching the first target")
	check(bm._mortar_fire_observation_quality(spotter_mortar, spotter_target) == "spotter", "Set-up: only the spotter watches the second")
	check(bm._mortar_fire_observation_quality(drone_mortar, drone_target) == "drone", "Set-up: only the drone watches the third")

	seed(1357911)
	const ROUNDS := 5
	const TRIALS := 1000
	# Each trial is reset to exactly ROUNDS-1 PRIOR corrected shots before the one actually measured — NOT
	# just called TRIALS times in a row starting from there. Calling it TRIALS times in a row would let the
	# measurement loop itself keep silently correcting further (each of the 1000 calls counts as one more
	# real shot), so for a slow-but-nonzero decay, 1000 EXTRA corrected shots converges it almost all the
	# way regardless of how slow that decay actually is — the exact same class of blind spot found and
	# fixed in test_no_observer_never_converges above, here confirmed directly: an artificially slowed
	# MORTAR_DISPERSION_DRONE_DECAY (0.15 -> 0.99, drone converging barely faster than not at all) still
	# passed this check with the naive "just average the next 1000 calls" loop, because those 1000 calls
	# were themselves enough correction to converge it to the drone's own (much tighter) floor regardless.
	# Pinning the shot count isolates the one real quantity being claimed: dispersion after exactly ROUNDS
	# corrected shots, not "eventually, given enough total shots."
	var none_total := 0.0
	var spotter_total := 0.0
	var drone_total := 0.0
	for i in TRIALS:
		bm._mortar_fire_adjustment[none_mortar] = {"target": none_target, "shots": ROUNDS - 1}
		bm._mortar_fire_adjustment[spotter_mortar] = {"target": spotter_target, "shots": ROUNDS - 1}
		bm._mortar_fire_adjustment[drone_mortar] = {"target": drone_target, "shots": ROUNDS - 1}
		none_total += fire_round(bm, none_mortar, none_target, none_target.global_position).length()
		spotter_total += fire_round(bm, spotter_mortar, spotter_target, spotter_target.global_position).length()
		drone_total += fire_round(bm, drone_mortar, drone_target, drone_target.global_position).length()
	var none_avg := none_total / TRIALS
	var spotter_avg := spotter_total / TRIALS
	var drone_avg := drone_total / TRIALS

	check(drone_avg < spotter_avg and spotter_avg < none_avg,
		"After the same %d corrected rounds, the walk-in orders strictly drone < spotter < none (drone=%.1f px, spotter=%.1f px, none=%.1f px)" % [ROUNDS, drone_avg, spotter_avg, none_avg])
	# "Nonexistent" isn't just "worse than the other two" — unobserved fire must not have moved from its
	# OWN unadjusted starting point at all, matching test_no_observer_never_converges's own direct check.
	var none_first_shot_total := 0.0
	for i in 200:
		bm._mortar_fire_adjustment.erase(none_mortar)
		none_first_shot_total += fire_round(bm, none_mortar, none_target, none_target.global_position).length()
	var none_first_shot_avg := none_first_shot_total / 200
	check(absf(none_avg - none_first_shot_avg) < none_first_shot_avg * 0.35,
		"Unobserved fire after %d rounds is statistically indistinguishable from its own very first, unadjusted shot — no walk-in at all (round-%d avg=%.1f px vs first-shot avg=%.1f px)" % [ROUNDS, ROUNDS, none_avg, none_first_shot_avg])
	bm.combat_log.free()
	bm.free()


## Switching targets must throw away any accumulated correction — a
## correction learned against one aim point says nothing about a different
## one, exactly like real adjust-fire doctrine (a new fire mission against
## a new target starts from scratch, not mid-bracket).
func test_target_switch_resets_adjustment() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	var target_a: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(300, 0))
	var target_b: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(300, 200))
	bm.enemy_units.append(target_a)
	bm.enemy_units.append(target_b)
	var spotter_a: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, target_a.global_position + Vector2(0, 60))
	var spotter_b: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, target_b.global_position + Vector2(0, 60))
	bm.player_units.append(spotter_a)
	bm.player_units.append(spotter_b)

	seed(998877)
	for i in 8:
		fire_round(bm, mortar, target_a, target_a.global_position)
	check(bm._mortar_fire_adjustment.get(mortar, {}).get("shots", 0) >= 8,
		"After several corrected shots at target A, the adjustment counter must have advanced")

	fire_round(bm, mortar, target_b, target_b.global_position)
	var after_switch: Dictionary = bm._mortar_fire_adjustment.get(mortar, {})
	check(after_switch.get("target") == target_b and after_switch.get("shots", -1) == 1,
		"Switching to a new target must reset the adjustment counter — a correction learned against target A's aim point doesn't apply to target B's (got target=%s shots=%s)" % [after_switch.get("target"), after_switch.get("shots")])
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_no_observer_never_converges()
	test_spotter_observation_converges()
	test_drone_converges_tighter_than_spotter()
	test_walk_in_orders_drone_fastest_spotter_middling_none_absent()
	test_target_switch_resets_adjustment()
	if failures == 0:
		print("Mortar dispersion tests: 0 failures")
	else:
		print("Mortar dispersion tests: %d failures" % failures)
	quit()


## One round fired, landed and seen: the offset it had, with the correction from it noted for the next round (a round fired before the
## ones in the air have landed gets none: see BattleManager._note_round_landed).
func fire_round(bm, mortar: Unit, target: Unit, aim: Vector2) -> Vector2:
	var offset: Vector2 = bm._mortar_dispersion_offset(mortar, target, aim)
	bm.scenario_elapsed_time += 20.0
	bm._note_round_landed(mortar, target)
	return offset
