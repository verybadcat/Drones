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
	for i in TRIALS:
		early += bm._mortar_dispersion_offset(mortar, target, aim_point).length()
	for i in TRIALS:
		late += bm._mortar_dispersion_offset(mortar, target, aim_point).length()
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
		early_total += bm._mortar_dispersion_offset(mortar, target, aim_point).length()
	var early_avg := early_total / EARLY_TRIALS

	for i in 10: # prime enough corrected shots to approach the convergence floor
		bm._mortar_dispersion_offset(mortar, target, aim_point)
	var late_total := 0.0
	const LATE_TRIALS := 200
	for i in LATE_TRIALS:
		late_total += bm._mortar_dispersion_offset(mortar, target, aim_point).length()
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
		bm._mortar_dispersion_offset(spotter_mortar, target_a, target_a.global_position)
		bm._mortar_dispersion_offset(drone_mortar, target_b, target_b.global_position)
	var spotter_total := 0.0
	var drone_total := 0.0
	for i in TRIALS:
		spotter_total += bm._mortar_dispersion_offset(spotter_mortar, target_a, target_a.global_position).length()
		drone_total += bm._mortar_dispersion_offset(drone_mortar, target_b, target_b.global_position).length()
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
		bm._mortar_dispersion_offset(mortar, target_a, target_a.global_position)
	check(bm._mortar_fire_adjustment.get(mortar, {}).get("shots", 0) >= 8,
		"After several corrected shots at target A, the adjustment counter must have advanced")

	bm._mortar_dispersion_offset(mortar, target_b, target_b.global_position)
	var after_switch: Dictionary = bm._mortar_fire_adjustment.get(mortar, {})
	check(after_switch.get("target") == target_b and after_switch.get("shots", -1) == 1,
		"Switching to a new target must reset the adjustment counter — a correction learned against target A's aim point doesn't apply to target B's (got target=%s shots=%s)" % [after_switch.get("target"), after_switch.get("shots")])
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_no_observer_never_converges()
	test_spotter_observation_converges()
	test_drone_converges_tighter_than_spotter()
	test_target_switch_resets_adjustment()
	if failures == 0:
		print("Mortar dispersion tests: 0 failures")
	else:
		print("Mortar dispersion tests: %d failures" % failures)
	quit()
