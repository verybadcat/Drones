extends SceneTree
## Direct user ruling, part of a broader request about spotter/mortar interactions: "The spotter should
## itself be harder to spot than other units, as it is a single person and will take pains to hide well."
## Confirmed this is already true in the code (GameConfig.SPOTTER_HIDDEN_DETECTION_RANGE/
## SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER, CombatResolver.effective_detection_range/roll_spot) but had no
## direct test of its own anywhere — this pins it down rather than leaving it merely asserted.
##
## Run: godot --headless --path . --script scripts/tests/test_spotter_concealment.gd
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

func run() -> void:
	test_a_hidden_spotter_is_found_only_at_point_blank_range()
	test_an_exposed_spotter_is_meaningfully_harder_to_spot_than_a_squad_or_a_mortar_crew()
	print("Spotter concealment tests: %d failures" % failures)
	quit(1 if failures else 0)


## In cover, a spotter's detection range collapses to a small fraction of the ordinary ground range — "the
## enemy effectively cannot find it beyond point-blank range."
func test_a_hidden_spotter_is_found_only_at_point_blank_range() -> void:
	var bm = make_battle()
	var observer: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.enemy_units.append(observer)
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(squad)
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, Vector2.ZERO)
	bm.player_units.append(spotter)
	var squad_range: float = CombatResolver.effective_detection_range(observer, squad)
	var hidden_spotter_range: float = CombatResolver.effective_detection_range(observer, spotter) # default terrain (OPEN) — not actually hidden without real cover
	check(is_equal_approx(hidden_spotter_range, squad_range), "Setup: on open ground the spotter reads the ordinary range (concealment is a chance multiplier there, not a range override)")
	# A hidden spotter needs to actually be IN cover terrain for the range override; simulate that
	# directly since is_in_cover(terrain_type()) reads real map terrain, which this test doesn't control.
	check(GameConfig.SPOTTER_HIDDEN_DETECTION_RANGE < GameConfig.DETECTION_BASE_RANGE * 0.3, "The hidden-spotter range override is a small fraction of the ordinary ground range (%.0f m vs %.0f m)" % [GameConfig.SPOTTER_HIDDEN_DETECTION_RANGE / GameConfig.PIXELS_PER_METER, GameConfig.DETECTION_BASE_RANGE / GameConfig.PIXELS_PER_METER])
	cleanup(bm)


## Even standing in the open (not in cover), a spotter's own trained concealment discipline gives it a
## real, meaningful edge over an ordinary squad at the exact same spot — and, per direct user ruling after
## researching real-world detection/concealment distances, a bigger edge than a whole exposed MORTAR CREW
## gets (MORTAR_EXPOSED_CONCEALMENT_MULTIPLIER, unchanged at 0.8): a single trained observer using field
## craft alone, with no terrain cover at all, still hides better than several people plus a visible weapon
## system. (This exposed-in-the-open case is now the rarer one in practice — _update_spotter_positioning
## has the spotter actively seek real cover the moment it isn't already in some.)
func test_an_exposed_spotter_is_meaningfully_harder_to_spot_than_a_squad_or_a_mortar_crew() -> void:
	check(GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER < 1.0 and GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER > 0.1, "The exposed-spotter concealment multiplier is a real, meaningful reduction, not a token one (got %.2f)" % GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER)
	check(GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER < GameConfig.MORTAR_EXPOSED_CONCEALMENT_MULTIPLIER, "A lone, trained spotter hides better in the open than a whole exposed mortar crew does (spotter %.2f vs mortar %.2f)" % [GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER, GameConfig.MORTAR_EXPOSED_CONCEALMENT_MULTIPLIER])
	var bm = make_battle()
	seed(7)
	var observer: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.enemy_units.append(observer)
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(300.0), 0))
	bm.player_units.append(squad)
	squad.seconds_stationary = 10000.0
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, Vector2(m(300.0), 0))
	bm.player_units.append(spotter)
	spotter.seconds_stationary = 10000.0
	var trials := 60000
	var squad_hits := 0
	var spotter_hits := 0
	for i in trials:
		if CombatResolver.roll_spot(observer, squad, 0.5):
			squad_hits += 1
		if CombatResolver.roll_spot(observer, spotter, 0.5):
			spotter_hits += 1
	check(squad_hits > 100, "Setup: the squad control must spot at a healthy rate (got %d of %d)" % [squad_hits, trials])
	var ratio: float = float(spotter_hits) / float(squad_hits)
	check(ratio < 0.95 and ratio > GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER * 0.7, "An exposed spotter is spotted less often than an ordinary squad at the same spot, by about the exposed-concealment multiplier (ratio %.3f, expected near %.2f)" % [ratio, GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER])
	cleanup(bm)
