extends SceneTree
## Guards the real-world-grounded blast-casualty probability model
## (CombatResolver.blast_casualty_chance) added after a direct question:
## "A 'safe distance' is different from a distance at which getting hurt
## is possible but unlikely... cover would also matter." Replaces what
## used to be a flat LINEAR falloff to a hard, certain zero at each call
## site's own radius with exponential decay calibrated so the real,
## cited "casualty radius" (GameConfig.MORTAR_BLAST_CASUALTY_RADIUS) is
## exactly the 50%-of-max point, continuing smoothly (never truly zero)
## beyond it, and applies real terrain cover (CombatResolver.MORTAR_
## COVER_MULTIPLIER) on top.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_blast_chance.gd
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


func test_chance_is_calibrated_to_casualty_radius_as_the_fifty_percent_point() -> void:
	var at_radius := CombatResolver.blast_casualty_chance(GameConfig.MORTAR_BLAST_CASUALTY_RADIUS, 1.0, GameConfig.TerrainType.OPEN)
	check(absf(at_radius - 0.5) < 0.001,
		"blast_casualty_chance at exactly MORTAR_BLAST_CASUALTY_RADIUS must be half of max_chance (real 'casualty radius' is conventionally the 50%% point), got %.4f" % at_radius)

	var at_zero := CombatResolver.blast_casualty_chance(0.0, 1.0, GameConfig.TerrainType.OPEN)
	check(absf(at_zero - 1.0) < 0.001,
		"blast_casualty_chance right at the impact point (distance 0) must equal max_chance exactly, got %.4f" % at_zero)


func test_chance_decays_monotonically_and_never_hits_a_hard_zero() -> void:
	var prev := 1.0
	for d_m in [0.0, 10.0, 26.0, 40.0, 60.0, 100.0, 200.0]:
		var chance := CombatResolver.blast_casualty_chance(d_m * GameConfig.PIXELS_PER_METER, 1.0, GameConfig.TerrainType.OPEN)
		check(chance <= prev, "blast_casualty_chance must never increase with distance (violated at %.0fm)" % d_m)
		check(chance > 0.0, "blast_casualty_chance must never hit a hard zero even far out (%.0fm gave exactly 0) — real fragmentation decays smoothly, it doesn't have a wall" % d_m)
		prev = chance


func test_cover_reduces_chance_in_the_expected_order() -> void:
	var d: float = GameConfig.MORTAR_BLAST_CASUALTY_RADIUS
	var open_chance := CombatResolver.blast_casualty_chance(d, 1.0, GameConfig.TerrainType.OPEN)
	var trees_chance := CombatResolver.blast_casualty_chance(d, 1.0, GameConfig.TerrainType.TREES)
	var building_chance := CombatResolver.blast_casualty_chance(d, 1.0, GameConfig.TerrainType.BUILDING)
	check(open_chance > trees_chance and trees_chance > building_chance,
		"Cover must reduce blast-casualty chance in the order OPEN > TREES > BUILDING (got %.3f / %.3f / %.3f)" % [open_chance, trees_chance, building_chance])
	check(absf(open_chance - 0.5) < 0.001,
		"A victim in the OPEN at the casualty radius must get exactly the bare (uncovered) curve, got %.4f" % open_chance)


## Integration check on the real call site: a counter-battery strike whose
## target is still exactly AT COUNTER_BATTERY_BLAST_RADIUS from the old
## position (the boundary this project's own scoot logic treats as "just
## barely cleared") must carry a real, statistically-measurable, low
## chance of a hit — not the flat, certain-zero cliff edge the old linear
## model gave at this exact distance. This is the direct, literal answer
## to "a safe distance is different from a distance at which getting hurt
## is possible but unlikely."
func test_counter_battery_hit_chance_at_the_blast_radius_boundary_is_low_but_nonzero() -> void:
	var expected: float = CombatResolver.blast_casualty_chance(GameConfig.COUNTER_BATTERY_BLAST_RADIUS, 1.0, GameConfig.TerrainType.OPEN)
	check(expected > 0.0 and expected < 0.25,
		"Right at the counter-battery blast radius boundary, the real chance should be low but clearly nonzero (a handful to ~20%%), got %.3f" % expected)

	var bm = make_battle()
	var home: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, home)
	bm.player_units.append(mortar)
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, home + Vector2(2000, 0))
	bm.enemy_units.append(enemy_mortar)

	var hits := 0
	const TRIALS := 800
	seed(24681)
	for i in TRIALS:
		mortar.state = Unit.State.ACTIVE
		mortar.pips = 4
		var strikes: Array[Dictionary] = [{
			"target": mortar, "attacker": enemy_mortar, "fired": true,
			"impact_position": home + Vector2(GameConfig.COUNTER_BATTERY_BLAST_RADIUS, 0),
			"impact_time": bm.scenario_elapsed_time - 1.0,
		}]
		bm._pending_counter_battery = strikes
		bm._resolve_pending_counter_battery()
		# take_hit removes a pip on an actual hit — a clean miss leaves the
		# freshly-reset pip count untouched.
		if mortar.pips < 4:
			hits += 1
	var rate: float = float(hits) / float(TRIALS)
	check(hits > 0, "Across %d trials right at the blast-radius boundary, at least some real hits should occur (got 0 — looks like the old certain-miss cliff is still in effect)" % TRIALS)
	check(rate < 0.30, "Across %d trials right at the blast-radius boundary, the hit rate should stay low (~%.1f%% expected), got %.1f%%" % [TRIALS, expected * 100.0, rate * 100.0])
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_chance_is_calibrated_to_casualty_radius_as_the_fifty_percent_point()
	test_chance_decays_monotonically_and_never_hits_a_hard_zero()
	test_cover_reduces_chance_in_the_expected_order()
	test_counter_battery_hit_chance_at_the_blast_radius_boundary_is_low_but_nonzero()
	print("Mortar blast-chance tests: %d failures" % failures)
	quit()
