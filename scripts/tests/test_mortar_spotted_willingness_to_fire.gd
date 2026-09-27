extends SceneTree
## Direct user report: "Even a mortar that has been spotted would have some willingness to fire if there
## is no indication of an opposing unit that can fire at it, such as an opposing mortar, or a nearby
## opposing squad. This should apply to both sides. The mortar's willingness to fire might be less than
## normal if it thinks there MIGHT be an opposing unit that can fire at it."
##
## Being merely SEEN used to be treated as danger on its own (BattleManager._decide_mortar_action's tier
## 1): a drone loitering overhead (unarmed, cannot itself fire back) produced the exact same unconditional
## flee-for-cover response as a squad closing in with a clear shot. `_mortar_spotted_danger` now splits
## that into three cases, tested here directly (it has no side effects, unlike _decide_mortar_action
## itself, so a large probabilistic sample can be drawn cheaply and repeatably):
##   1. No indication at all (no known opposing mortar in range, nothing nearby, and no opposing mortar
##      ever detected/known to exist) — always false, deterministically.
##   2. A concrete indication (a known-ACTIVE opposing mortar within its own range, OR a known/live
##      opposing unit within overrun-danger range) — always true, deterministically, on BOTH sides.
##   3. An uncertain indication (an opposing mortar known to exist somewhere, but not concretely in range
##      or nearby) — true SOME of the time, scaling with GameConfig.MORTAR_SPOTTED_UNKNOWN_THREAT_
##      RELOCATE_CHANCE and BattleManager._mortar_existence_confidence — never 0%, never 100%.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_spotted_willingness_to_fire.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()


## Case 1, both sides: nothing at all suggests an opposing unit could hit this position — not a nearby
## unit, not a known mortar in range, and no opposing mortar ever detected or sighted anywhere (so even
## the residual, decaying suspicion term is a hard 0). A spotted mortar must stay willing to fire.
func test_no_indication_means_no_spotted_danger() -> void:
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		var bm = make_battle()
		var mortar: Unit = bm._make_unit(team, Unit.Kind.MORTAR, Vector2(0, 0))
		(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(mortar)
		mortar.is_visible = true
		check(not bm._mortar_spotted_danger(mortar), "Team %s: a spotted mortar with no opposing units anywhere must not be treated as in danger" % Unit.Team.keys()[team])
		cleanup(bm)


## Not visible at all: no roll, no danger from this function regardless of what else exists (that's
## `threat_closing`'s own, separate job).
func test_not_visible_is_never_spotted_danger() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	mortar.is_visible = false
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(100), 0))
	bm.enemy_units.append(enemy_mortar)
	enemy_mortar.is_visible = true
	check(not bm._mortar_spotted_danger(mortar), "A mortar that isn't even spotted must read false here regardless of what's known nearby")
	cleanup(bm)


## Case 2a, both sides: a known-ACTIVE opposing mortar within ITS OWN max range (not necessarily close by
## in absolute terms) is a concrete threat — always relocates, no roll involved.
func test_known_opposing_mortar_in_range_is_always_spotted_danger() -> void:
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		var bm = make_battle()
		var mortar: Unit = bm._make_unit(team, Unit.Kind.MORTAR, Vector2(0, 0))
		(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(mortar)
		mortar.is_visible = true
		var opposing_team: Unit.Team = Unit.Team.ENEMY if team == Unit.Team.PLAYER else Unit.Team.PLAYER
		var far_but_in_range: Vector2 = Vector2(GameConfig.mortar_max_range(opposing_team) * 0.9, 0)
		var opp_mortar: Unit = bm._make_unit(opposing_team, Unit.Kind.MORTAR, far_but_in_range)
		(bm.enemy_units if team == Unit.Team.PLAYER else bm.player_units).append(opp_mortar)
		opp_mortar.is_visible = true
		check(far_but_in_range.length() > GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, "Setup: the opposing mortar must be well beyond overrun-danger range, so only the mortar-range check can be what's firing")
		for i in range(5): # deterministic, but exercise it a few times to be sure no roll sneaks in
			check(bm._mortar_spotted_danger(mortar), "Team %s: a known-ACTIVE opposing mortar within its own range must always read as spotted danger" % Unit.Team.keys()[team])
		cleanup(bm)


## Case 2b, both sides: a nearby opposing squad (live, within overrun-danger range) is also a concrete,
## unconditional threat — the live-visibility path, not dependent on player_known_position/
## _update_player_intel having already run this tick (a squad that becomes visible on the SAME tick the
## mortar is first spotted must count immediately).
func test_nearby_live_opposing_squad_is_always_spotted_danger() -> void:
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		var bm = make_battle()
		var mortar: Unit = bm._make_unit(team, Unit.Kind.MORTAR, Vector2(0, 0))
		(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(mortar)
		mortar.is_visible = true
		var opposing_team: Unit.Team = Unit.Team.ENEMY if team == Unit.Team.PLAYER else Unit.Team.PLAYER
		var squad: Unit = bm._make_unit(opposing_team, Unit.Kind.SQUAD, Vector2(GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE * 0.3, 0))
		(bm.enemy_units if team == Unit.Team.PLAYER else bm.player_units).append(squad)
		squad.is_visible = true # live this same tick — _update_player_intel/_update_enemy_intel never called
		for i in range(5):
			check(bm._mortar_spotted_danger(mortar), "Team %s: a nearby opposing squad, seen live this same tick, must always read as spotted danger" % Unit.Team.keys()[team])
		cleanup(bm)


## A drone overhead, and nothing else, is exactly the case that motivated this fix: unarmed, so it must
## not read as a concrete threat on its own, and with no opposing mortar known to exist anywhere, no
## uncertain-threat roll should be able to fire either (confidence is a hard 0).
func test_a_drone_alone_is_not_spotted_danger() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	mortar.is_visible = true
	var drone: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.DRONE, Vector2(m(50), 0)) # right on top of it
	bm.enemy_units.append(drone)
	drone.is_visible = true
	check(not bm._mortar_spotted_danger(mortar), "A drone overhead with nothing else around must not, by itself, make a spotted mortar treat itself as in danger")
	cleanup(bm)


## Case 3: an opposing mortar is known to exist (fired recently) but its actual position is nowhere near
## `mortar` (outside both the overrun-danger range and its own mortar range) — no CONCRETE indication, but
## a real, live "might still be one out there" suspicion. Must trigger sometimes, not never and not
## always — "willingness to fire might be less than normal", not zero and not unaffected.
func test_uncertain_indication_gives_a_reduced_not_zero_rate() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	mortar.is_visible = true
	# An enemy mortar the player knows is ACTIVE, but far outside anything _mortar_spotted_danger's
	# concrete checks would ever pick up from `mortar`'s own position.
	var far_pos: Vector2 = Vector2(GameConfig.mortar_max_range(Unit.Team.ENEMY) * 5.0, 0)
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, far_pos)
	bm.enemy_units.append(enemy_mortar)
	enemy_mortar.is_visible = true
	bm._update_player_intel() # records player_known_state == ACTIVE
	enemy_mortar.is_visible = false
	bm._last_detected_mortar_fire[enemy_mortar] = {"position": far_pos, "time": bm.scenario_elapsed_time} # fired just now: confidence == 1.0
	check(not bm._known_opposing_mortar_in_range(mortar), "Setup: the known enemy mortar must be out of its own range of `mortar`")
	check(not bm._nearby_opposing_unit_within(mortar, GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, true), "Setup: nothing must be within overrun-danger range either")
	check(is_equal_approx(bm._mortar_existence_confidence(Unit.Team.PLAYER), 1.0), "Setup: confidence must read as fresh/maximal (elapsed == 0)")

	seed(20260928)
	var trials := 400
	var danger_count := 0
	for i in range(trials):
		if bm._mortar_spotted_danger(mortar):
			danger_count += 1
	var rate: float = float(danger_count) / trials
	var expected: float = GameConfig.MORTAR_SPOTTED_UNKNOWN_THREAT_RELOCATE_CHANCE # confidence == 1.0
	check(danger_count > 0, "An uncertain indication must still sometimes read as danger, not never (got 0/%d)" % trials)
	check(danger_count < trials, "...but not always either — this is meant to be LESS than the concrete case's certainty (got %d/%d)" % [danger_count, trials])
	check(absf(rate - expected) < 0.08, "The observed rate (%.3f) should track GameConfig.MORTAR_SPOTTED_UNKNOWN_THREAT_RELOCATE_CHANCE (%.3f) at confidence 1.0" % [rate, expected])
	cleanup(bm)


## The uncertain-threat rate must actually decay as _mortar_existence_confidence decays (real tactical
## time passing with nothing further detected) — not a flat constant disguised as a "might."
func test_uncertain_indication_decays_with_existence_confidence() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	mortar.is_visible = true
	var far_pos: Vector2 = Vector2(GameConfig.mortar_max_range(Unit.Team.ENEMY) * 5.0, 0)
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, far_pos)
	bm.enemy_units.append(enemy_mortar)
	enemy_mortar.is_visible = true
	bm._update_player_intel()
	enemy_mortar.is_visible = false
	bm._last_detected_mortar_fire[enemy_mortar] = {"position": far_pos, "time": bm.scenario_elapsed_time}
	bm.scenario_elapsed_time += GameConfig.MORTAR_CONFIDENCE_DECAY_TAU * 4.0 # long decayed, near MORTAR_CONFIDENCE_FLOOR

	seed(20260928)
	var trials := 400
	var danger_count := 0
	for i in range(trials):
		if bm._mortar_spotted_danger(mortar):
			danger_count += 1
	var rate: float = float(danger_count) / trials
	var expected: float = GameConfig.MORTAR_SPOTTED_UNKNOWN_THREAT_RELOCATE_CHANCE * bm._mortar_existence_confidence(Unit.Team.PLAYER)
	check(expected < GameConfig.MORTAR_SPOTTED_UNKNOWN_THREAT_RELOCATE_CHANCE * 0.5, "Setup: confidence should have decayed well below its peak by now")
	check(absf(rate - expected) < 0.06, "The observed rate (%.3f) should track the decayed expectation (%.3f), not stay pinned at the peak" % [rate, expected])
	cleanup(bm)


## End-to-end through the real decision function: with no indication at all, a spotted mortar that has a
## valid, safe shot lined up must actually take/hold it (not relocate for cover) — the concrete behavioral
## payoff of this fix, not just the extracted predicate in isolation.
func test_decide_mortar_action_holds_a_shot_when_spotted_with_no_indication() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	mortar.is_visible = true
	# A distant squad target, well outside overrun-danger range, and no enemy mortar anywhere at all.
	var squad_pos: Vector2 = Vector2(GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE * 3.0, 0)
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, squad_pos)
	bm.enemy_units.append(squad)
	squad.is_visible = true
	var target: Unit = bm._mortar_shot_this_tick(mortar, bm.enemy_units)
	check(target == squad, "Setup check: the mortar must have a real, resolvable shot on the distant squad")
	bm._decide_mortar_action(mortar)
	check(not mortar.has_move_target, "Spotted with a safe shot and no indication anything can hit back: the crew should hold position and keep firing, not flee for cover")
	cleanup(bm)


func run() -> void:
	test_no_indication_means_no_spotted_danger()
	test_not_visible_is_never_spotted_danger()
	test_known_opposing_mortar_in_range_is_always_spotted_danger()
	test_nearby_live_opposing_squad_is_always_spotted_danger()
	test_a_drone_alone_is_not_spotted_danger()
	test_uncertain_indication_gives_a_reduced_not_zero_rate()
	test_uncertain_indication_decays_with_existence_confidence()
	test_decide_mortar_action_holds_a_shot_when_spotted_with_no_indication()
	print("Mortar spotted-willingness-to-fire tests: %d failures" % failures)
	quit(1 if failures else 0)
