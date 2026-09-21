extends SceneTree
## Guards a live-reported drone problem: "the drones are doing too much
## mortar searching far away from our mortar. We know there are dangerous
## enemy squads nearby. Sure a mortar could come, but we've done a lot of
## searching without finding one." Then: "in real life one wouldn't know
## for certain a mortar reinforcement is not coming. So it could be. But
## that has to be weighed against the known dangerous enemy squads," and
## about a briefly seen squad in the rear: "that should be a major concern
## for the drone team as it threatens both the mortar and the drone team."
##
## Root cause: the drone's mortar-sweep score was 100 x a confidence that
## decays only with TIME since the last detected mortar fire (15-minute
## constant), so for ~35 tactical minutes it outranked tracking even the
## most dangerous squad (whose score tops out at 10), regardless of how
## many empty cells had been checked or what dangerous squads were known.
## BattleManager._drone_mortar_search_weight now weighs it: never a certain
## zero, worn down by empty sweeps, discounted by known squad danger
## (including last-seen squads, and extra for ones near the mortar or drone
## team) — and identical to the old behavior early in a battle.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_mortar_search_weighing.gd
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

func friendly(bm, kind: Unit.Kind, pos: Vector2) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.PLAYER, kind, pos)
	bm.player_units.append(u)
	return u

func enemy(bm, kind: Unit.Kind, pos: Vector2, visible := true) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.ENEMY, kind, pos)
	bm.enemy_units.append(u)
	u.is_visible = visible
	bm._update_player_intel() # records the sighting (and its time) for anything visible
	return u


func test_unchanged_early_in_a_battle() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2.ZERO)
	enemy(bm, Unit.Kind.MORTAR, Vector2(3000, 0), false) # an active mortar, never seen
	check(is_equal_approx(bm._drone_mortar_search_weight(), bm._mortar_existence_confidence()),
		"With no known squad danger and no empty sweeps, the weight must equal the existing confidence exactly (got %.3f vs %.3f)" % [bm._drone_mortar_search_weight(), bm._mortar_existence_confidence()])
	check(bm._drone_mortar_search_weight() > 0.9, "Setup check: confidence should be near its peak this early")


func test_never_a_certain_zero() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2.ZERO)
	var mortar: Unit = enemy(bm, Unit.Kind.MORTAR, Vector2(3000, 0), false)
	mortar.state = Unit.State.WITHDRAWN
	check(bm._mortar_existence_confidence() == 0.0, "Setup check: every enemy mortar out of action reads a hard 0.0 in the existing function")
	check(is_equal_approx(bm._drone_mortar_search_weight(), GameConfig.DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE),
		"A real recon element can't be certain no mortar (or reinforcement) remains — the weight must sit at the small residual, not zero (got %.3f)" % bm._drone_mortar_search_weight())
	check(GameConfig.TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP * GameConfig.DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE < GameConfig.TARGET_PRIORITY_SQUAD_MAX * 0.25,
		"The residual must stay below a squad even modestly close to a friendly (it must never outrank real tracking)")


func test_known_squad_danger_discounts_the_search() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2.ZERO)
	enemy(bm, Unit.Kind.MORTAR, Vector2(3000, 0), false)
	var calm: float = bm._drone_mortar_search_weight()
	enemy(bm, Unit.Kind.SQUAD, Vector2(10, 0)) # visible and right on top of a friendly
	var pressure: float = bm._known_squad_danger_pressure()
	check(pressure > 0.9, "A visible squad right beside a friendly unit must read as near-full danger pressure (got %.2f)" % pressure)
	var expected: float = calm * (1.0 - GameConfig.DRONE_MORTAR_SEARCH_DANGER_DISCOUNT * pressure)
	check(is_equal_approx(bm._drone_mortar_search_weight(), expected),
		"The weight must be discounted by exactly DRONE_MORTAR_SEARCH_DANGER_DISCOUNT x pressure (got %.3f, expected %.3f)" % [bm._drone_mortar_search_weight(), expected])
	check(bm._drone_mortar_search_weight() < calm * 0.3, "At full pressure the search must drop to roughly a fifth")


func test_last_seen_squad_still_counts_and_fades_with_age() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2.ZERO)
	var squad: Unit = enemy(bm, Unit.Kind.SQUAD, Vector2(10, 0))
	squad.is_visible = false # seen a moment ago, not now
	var fresh: float = bm._known_squad_danger_pressure()
	check(fresh > 0.9, "A squad seen a moment ago but not visible now still counts at its last-known position (got %.2f)" % fresh)
	bm.scenario_elapsed_time = GameConfig.DRONE_CONTACT_BONUS_EXPIRY * 0.5
	var half: float = bm._known_squad_danger_pressure()
	check(absf(half - fresh * 0.5) < 0.02, "Halfway through the contact window the pressure must have faded to about half (got %.2f vs fresh %.2f)" % [half, fresh])
	bm.scenario_elapsed_time = GameConfig.DRONE_CONTACT_BONUS_EXPIRY + 1.0
	check(bm._known_squad_danger_pressure() == 0.0, "A sighting older than the contact window must no longer count")
	# A squad never sighted at all is not "known" — no free omniscience.
	var bm2 = make_battle()
	friendly(bm2, Unit.Kind.SQUAD, Vector2.ZERO)
	var hidden: Unit = bm2._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(10, 0))
	bm2.enemy_units.append(hidden)
	check(bm2._known_squad_danger_pressure() == 0.0, "A squad the player has never sighted must not count, however close it really is")


func test_squad_near_mortar_or_drone_team_counts_extra() -> void:
	# 200px from an ordinary friendly SQUAD: modest danger.
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2.ZERO)
	enemy(bm, Unit.Kind.SQUAD, Vector2(200, 0))
	var near_squad: float = bm._known_squad_danger_pressure()
	# The same 200px from the friendly MORTAR: an exposed rear asset.
	var bm2 = make_battle()
	friendly(bm2, Unit.Kind.MORTAR, Vector2.ZERO)
	enemy(bm2, Unit.Kind.SQUAD, Vector2(200, 0))
	var near_mortar: float = bm2._known_squad_danger_pressure()
	# And from the DRONE TEAM.
	var bm3 = make_battle()
	friendly(bm3, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	enemy(bm3, Unit.Kind.SQUAD, Vector2(200, 0))
	var near_drone_team: float = bm3._known_squad_danger_pressure()
	check(near_mortar > near_squad + 0.2, "A squad near the friendly mortar must read as a bigger concern than the same distance from an ordinary squad (%.2f vs %.2f)" % [near_mortar, near_squad])
	check(near_drone_team > near_squad + 0.2, "A squad near the drone team must read as a bigger concern too (%.2f vs %.2f)" % [near_drone_team, near_squad])
	# A squad well inside the flanking radius of the mortar is full pressure.
	var bm4 = make_battle()
	friendly(bm4, Unit.Kind.MORTAR, Vector2.ZERO)
	enemy(bm4, Unit.Kind.SQUAD, Vector2(GameConfig.MORTAR_FLANK_THREAT_RADIUS * 0.3, 0))
	check(is_equal_approx(bm4._known_squad_danger_pressure(), 1.0), "A known squad within ~a third of the flanking radius of the mortar must be full pressure")


func test_empty_sweeps_wear_confidence_down_and_fresh_evidence_resets_it() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2(9000, 9000)) # far from everything: no danger pressure
	enemy(bm, Unit.Kind.MORTAR, Vector2(3000, 0), false)
	var base: float = bm._drone_mortar_search_weight()
	bm._empty_sweep_arrivals = 6
	bm._empty_sweep_evidence_stamp = bm._latest_mortar_evidence_time()
	var worn: float = bm._drone_mortar_search_weight()
	check(is_equal_approx(worn, base * pow(GameConfig.DRONE_EMPTY_SWEEP_CONFIDENCE_FACTOR, 6)),
		"Six empty sweeps must multiply the confidence by the factor six times (got %.3f, expected %.3f)" % [worn, base * pow(GameConfig.DRONE_EMPTY_SWEEP_CONFIDENCE_FACTOR, 6)])
	# A fresh mortar fire detection is real evidence: the wear resets at once.
	bm.scenario_elapsed_time = 500.0
	bm._last_detected_mortar_fire[bm.enemy_units[0]] = {"position": Vector2(3000, 0), "time": 490.0}
	check(bm._effective_empty_sweeps() == 0, "New mortar evidence must reset the empty-sweep count immediately")
	# Many empties never push the weight below the residual.
	bm._empty_sweep_arrivals = 500
	bm._empty_sweep_evidence_stamp = bm._latest_mortar_evidence_time()
	check(bm._drone_mortar_search_weight() >= GameConfig.DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE - 0.0001, "The weight must never fall below the residual")


func test_reaching_a_sweep_cell_counts_as_an_empty_search_but_a_flank_check_does_not() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2(9000, 9000))
	enemy(bm, Unit.Kind.MORTAR, Vector2(3000, 0), false)
	bm.active_drone = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
	var cell: Dictionary = bm._sweep_candidates()[0]
	bm.active_drone.global_position = cell.point
	bm._drone_current_destination_key = cell.key
	bm._drone_routine_recon_target([])
	check(bm._empty_sweep_arrivals == 1, "Arriving at a sweep cell with no new mortar evidence must count as one empty search (got %d)" % bm._empty_sweep_arrivals)

	var bm2 = make_battle()
	friendly(bm2, Unit.Kind.SQUAD, Vector2(9000, 9000))
	enemy(bm2, Unit.Kind.MORTAR, Vector2(3000, 0), false)
	bm2.active_drone = bm2._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
	var flank: Array = [{"key": "flank:0", "point": Vector2.ZERO, "value": 0.5}]
	bm2._drone_current_destination_key = "flank:0"
	bm2._drone_routine_recon_target(flank)
	check(bm2._empty_sweep_arrivals == 0, "Checking a flank gap is not a mortar search — it must not wear the mortar confidence down")


## The reported behavior end to end. Mid-battle (elapsed 1200s, confidence
## ~0.3 — under the old formula still 30 points of sweep against a squad's
## maximum of 10) with a dangerous squad right on top of a friendly unit:
## the drone must now track the squad. With NO known danger, the mortar
## search must still win as before.
func test_drone_tracks_a_dangerous_squad_over_a_speculative_mortar_sweep() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2.ZERO)
	enemy(bm, Unit.Kind.MORTAR, Vector2(3000, 0), false)
	bm.active_drone = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
	bm.scenario_elapsed_time = 1200.0
	enemy(bm, Unit.Kind.SQUAD, Vector2(10, 0))
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.tier == "Tracking dangerous squad",
		"With a dangerous squad in real contact, the drone must track it rather than fly a speculative mortar sweep (tier was: %s)" % bm._drone_pilot_reasoning.tier)

	var bm2 = make_battle()
	friendly(bm2, Unit.Kind.SQUAD, Vector2.ZERO)
	enemy(bm2, Unit.Kind.MORTAR, Vector2(3000, 0), false)
	bm2.active_drone = bm2._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
	bm2.scenario_elapsed_time = 1200.0
	enemy(bm2, Unit.Kind.SQUAD, Vector2(GameConfig.SQUAD_DANGER_RANGE * 5.0, 0)) # visible but nowhere near anyone
	bm2._drone_search_target()
	check(bm2._drone_pilot_reasoning.tier == "Routine background recon",
		"With no dangerous squad known, the speculative mortar search must still win as before (tier was: %s)" % bm2._drone_pilot_reasoning.tier)


func run() -> void:
	test_unchanged_early_in_a_battle()
	test_never_a_certain_zero()
	test_known_squad_danger_discounts_the_search()
	test_last_seen_squad_still_counts_and_fades_with_age()
	test_squad_near_mortar_or_drone_team_counts_extra()
	test_empty_sweeps_wear_confidence_down_and_fresh_evidence_resets_it()
	test_reaching_a_sweep_cell_counts_as_an_empty_search_but_a_flank_check_does_not()
	test_drone_tracks_a_dangerous_squad_over_a_speculative_mortar_sweep()
	print("Drone mortar-search weighing tests: %d failures" % failures)
	quit(1 if failures else 0)
