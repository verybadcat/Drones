extends SceneTree
## The battle-outcome score, now part of the game (user: "put it into the
## game... Display it at battle end"). The rubric is the user's own, fixed
## 2026-09-08 (see BattleScore and the design doc's "A fixed battle-outcome
## scoring rubric"); this guards every value in it, the stalemate rule (a
## stalemate is neither held nor lost, so it scores 0 for the position), and
## that a finished battle really carries -- and displays -- its score.
##
## One score, from the TRUE results (user: "the score can go based off of the
## true results"), and casualties count by WHOSE SIDE they fall on regardless
## of what caused them ("friendly casualties count against the player,
## regardless of the source (i.e. friendly fire)... enemy casualties count in
## favor, regardless of the source").
##
## Run: godot --headless --path . --script scripts/tests/test_battle_score.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_every_rubric_value()
	test_position_terms_and_the_stalemate_rule()
	test_missing_inputs_count_as_zero()
	test_a_finished_battle_carries_and_displays_its_score()
	test_mortar_terms_in_a_finished_battle()
	test_a_stalemate_scores_zero_for_the_position()
	test_the_score_uses_true_results_even_where_the_report_only_estimates()
	test_casualties_count_by_side_whatever_the_source()
	test_captured_personnel_count_on_both_sides()
	test_line_items_always_sum_to_the_score()
	test_breakdown_text_lists_what_happened()
	print("Battle score tests: %d failures" % failures)
	quit(1 if failures else 0)


## One term at a time against a battle that is otherwise a stalemate (0).
func term(key: String, count: int) -> float:
	return BattleScore.score({"position": "stalemate", key: count})

func test_every_rubric_value() -> void:
	var expected := {
		"player_killed": -10.0, "enemy_killed": 5.0,
		"player_captured": -8.0, "enemy_captured": 8.0,
		"player_heavily_wounded": -4.0, "enemy_heavily_wounded": 2.0,
		"player_walking_wounded": -1.0, "enemy_walking_wounded": 0.5,
		"player_mortar_lost": -5.0, "enemy_mortar_out": 2.5,
	}
	for key in expected:
		check(is_equal_approx(term(key, 1), expected[key]), "%s: one should score %s, got %s" % [key, expected[key], term(key, 1)])
		check(is_equal_approx(term(key, 3), expected[key] * 3.0), "%s: scores must scale with the count" % key)
	check(term("player_killed", 1) < -term("enemy_killed", 1), "A friendly death must cost more than an enemy death is worth (the user's deliberate asymmetry)")
	check(is_equal_approx(term("player_captured", 1), -term("enemy_captured", 1)), "Captures are symmetric")


func test_position_terms_and_the_stalemate_rule() -> void:
	check(is_equal_approx(BattleScore.score({"position": "held"}), 20.0), "Position held is +20")
	check(is_equal_approx(BattleScore.score({"position": "lost"}), -20.0), "Position lost is -20")
	check(is_equal_approx(BattleScore.score({"position": "stalemate"}), 0.0), "A stalemate is neither held nor lost: 0")
	check(BattleScore.position_key(true, false) == "held" and BattleScore.position_key(false, false) == "lost", "held/lost map to their keys")
	check(BattleScore.position_key(true, true) == "stalemate" and BattleScore.position_key(false, true) == "stalemate", "A stalemate is a stalemate whichever side 'holds' the ground")
	# A worked battle: held, 2 of ours killed, 1 heavily + 2 walking wounded; 6 of theirs killed, 1 captured, 3 walking wounded, their mortar out.
	var worked := {"position": "held", "player_killed": 2, "player_heavily_wounded": 1, "player_walking_wounded": 2,
		"enemy_killed": 6, "enemy_captured": 1, "enemy_walking_wounded": 3, "enemy_mortar_out": 1}
	check(is_equal_approx(BattleScore.score(worked), 20.0 - 20.0 - 4.0 - 2.0 + 30.0 + 8.0 + 1.5 + 2.5), "A worked example must add up term by term, got %s" % BattleScore.score(worked))
	check(BattleScore.format(42.5) == "+42.5" and BattleScore.format(-17.0) == "-17.0" and BattleScore.format(0.0) == "+0.0", "Scores display signed, one decimal")


func test_missing_inputs_count_as_zero() -> void:
	check(is_equal_approx(BattleScore.score({}), 0.0), "An empty record scores 0, it must not crash")
	check(is_equal_approx(BattleScore.score({"position": "held", "enemy_killed": 2}), 30.0), "Absent counts are zero (an older stored record may lack fields)")
	check(is_equal_approx(BattleScore.score({"position": "nonsense"}), 0.0), "An unknown position scores like a stalemate")


# ------------------------------------------------------------ a finished battle

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func add(bm, team: Unit.Team, kind: Unit.Kind, pos: Vector2) -> Unit:
	var u: Unit = bm._make_unit(team, kind, pos)
	(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(u)
	return u

## Our squad survives holding the ground; theirs is wiped out where it stood,
## fully assessable: 5 killed, 2 heavily wounded, 2 walking wounded (all 9).
func decisive_win(bm) -> Dictionary:
	var ours: Unit = add(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	ours.pips = ours.max_pips - 1
	ours.killed_count = 1
	var theirs: Unit = add(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	theirs.pips = 0
	theirs.state = Unit.State.DESTROYED
	theirs.killed_count = 5
	theirs.heavily_wounded_count = 2
	theirs.walking_wounded_count = 2
	return {"ours": ours, "theirs": theirs}

func capture_report(bm) -> String:
	var captured := [""]
	bm.battle_ended.connect(func(text: String): captured[0] = text)
	bm._end_battle()
	return captured[0]

func test_a_finished_battle_carries_and_displays_its_score() -> void:
	var bm = make_battle()
	check(bm.battle_result.is_empty(), "No result exists before the battle ends")
	decisive_win(bm)
	var text: String = capture_report(bm)
	var result: Dictionary = bm.battle_result
	check(not result.is_empty(), "_end_battle must produce a battle_result")
	check(result.inputs.position == "held" and result.held, "This battle was held")
	check(result.inputs.enemy_killed == 5 and result.inputs.enemy_heavily_wounded == 2 and result.inputs.enemy_walking_wounded == 2,
		"The enemy counts must come straight from the assessed casualties, got %s" % [result.inputs])
	check(result.inputs.player_killed == 1, "Our own casualty counts")
	check(is_equal_approx(result.score, BattleScore.score(result.inputs)), "The score is the rubric applied to the stored counts")
	check(is_equal_approx(result.score, 20.0 - 10.0 + 25.0 + 4.0 + 1.0), "This battle: held +20, 1 of ours killed -10, 5 killed +25, 2 heavily wounded +4, 2 walking wounded +1 = %s" % result.score)
	check(result.rubric_version == BattleScore.RUBRIC_VERSION, "Every result is stamped with the rubric version")
	check(("Battle score: %s" % BattleScore.format(result.score)) in text, "The report must display the score (got: %s)" % text.split("\n").slice(0, 5))
	check(text.split("\n").find("Verdict: %s" % result.verdict) >= 0, "...alongside the verdict, which the score must not replace")
	# starting a new battle clears the old result
	var squads: Array[Dictionary] = []
	for pos in GameConfig.CURRENT_MAP.player.default_squad_positions:
		squads.append({"position": pos, "retreat_threshold": 0.3})
	bm.start_battle({"squads": squads, "mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": false}, "spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position}, "recon_mode": GameConfig.ReconMode.SPOTTER}, Log.new())
	check(bm.battle_result.is_empty(), "A new battle must not inherit the last one's result")


func test_mortar_terms_in_a_finished_battle() -> void:
	var bm = make_battle()
	decisive_win(bm)
	var our_mortar: Unit = add(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(-50, 0))
	our_mortar.state = Unit.State.DESTROYED
	var their_mortar: Unit = add(bm, Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(150, 0))
	their_mortar.state = Unit.State.DESTROYED
	capture_report(bm)
	check(bm.battle_result.inputs.player_mortar_lost == 1, "A destroyed friendly mortar is a lost gun")
	check(bm.battle_result.inputs.enemy_mortar_out == 1, "A destroyed enemy mortar is out")

	# An enemy mortar that merely withdrew is out only if we hold the ground it left.
	var bm2 = make_battle()
	decisive_win(bm2)
	var fled: Unit = add(bm2, Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(150, 0))
	fled.state = Unit.State.WITHDRAWN
	capture_report(bm2)
	check(bm2.battle_result.inputs.enemy_mortar_out == 1, "A withdrawn enemy mortar counts as out when we hold the ground")
	check(BattleScore.enemy_mortar_out(fled, true) and not BattleScore.enemy_mortar_out(fled, false), "...but not if the position was lost")


func test_a_stalemate_scores_zero_for_the_position() -> void:
	var bm = make_battle()
	decisive_win(bm)
	bm._ended_by_stalemate = true
	capture_report(bm)
	check(bm.battle_result.inputs.position == "stalemate", "A stalemate must be recorded as one")
	check(bm.battle_result.stalemate and bm.battle_result.verdict == "STALEMATE", "...consistent with the verdict")
	var as_held: Dictionary = bm.battle_result.inputs.duplicate()
	as_held.position = "held"
	check(is_equal_approx(BattleScore.score(as_held) - bm.battle_result.score, 20.0), "The stalemate must be exactly the +20 short of the same battle called held")


## We are wiped out (the position is lost); the enemy took 3 killed + 2
## heavily wounded but is still in the field and was never sighted, so the
## report can only ESTIMATE its losses. The score counts what really
## happened: -20 - 90 + 15 + 4 = -91 (a best-guess score would have read -110).
func test_the_score_uses_true_results_even_where_the_report_only_estimates() -> void:
	var bm = make_battle()
	var ours: Unit = add(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	ours.pips = 0
	ours.state = Unit.State.DESTROYED
	ours.killed_count = 9
	var theirs: Unit = add(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	theirs.pips = 4
	theirs.killed_count = 3
	theirs.heavily_wounded_count = 2
	var text: String = capture_report(bm)
	check(bm.battle_result.inputs.enemy_killed == 3 and bm.battle_result.inputs.enemy_heavily_wounded == 2, "The unseen enemy casualties are counted, got %s" % [bm.battle_result.inputs])
	check(is_equal_approx(bm.battle_result.score, -91.0), "The score is built from the true results, got %s" % bm.battle_result.score)
	check("Battle score: -91.0" in text and not ("Battle score: -110.0" in text), "The report shows that true score")


## "Friendly casualties count against the player, regardless of the source
## (i.e. friendly fire). Similarly, enemy casualties count in favor,
## regardless of the source." Casualties are read off the VICTIMS, so nothing
## about who caused them matters: these are caused with no attacker at all
## (nothing in any damage-by-unit table), and still count.
func test_casualties_count_by_side_whatever_the_source() -> void:
	var baseline_bm = make_battle()
	add(baseline_bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	add(baseline_bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	capture_report(baseline_bm)
	var baseline: float = baseline_bm.battle_result.score

	var bm = make_battle()
	var ours: Unit = add(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	var theirs: Unit = add(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	# Friendly fire: a mortar-type hit on our own squad, no attacker recorded anywhere.
	for i in 3:
		ours.take_hit(true)
	# The enemy hurting itself (its own stray round): still in the player's favor.
	for i in 3:
		theirs.take_hit(true)
	capture_report(bm)
	var inputs: Dictionary = bm.battle_result.inputs
	var ours_lost: int = inputs.player_killed + inputs.player_heavily_wounded + inputs.player_walking_wounded + inputs.player_captured
	var theirs_lost: int = inputs.enemy_killed + inputs.enemy_heavily_wounded + inputs.enemy_walking_wounded + inputs.enemy_captured
	check(ours_lost == ours.max_pips - ours.pips and ours_lost > 0, "Every casualty our side took must be counted against us (%d counted, %d lost)" % [ours_lost, ours.max_pips - ours.pips])
	check(theirs_lost == theirs.max_pips - theirs.pips and theirs_lost > 0, "Every casualty the enemy took must be counted in our favor, whatever hurt them (%d counted, %d lost)" % [theirs_lost, theirs.max_pips - theirs.pips])
	var expected: float = baseline \
		+ BattleScore.FRIENDLY_DEATH * inputs.player_killed + BattleScore.FRIENDLY_HEAVILY_WOUNDED * inputs.player_heavily_wounded + BattleScore.FRIENDLY_WALKING_WOUNDED * inputs.player_walking_wounded \
		+ BattleScore.ENEMY_DEATH * inputs.enemy_killed + BattleScore.ENEMY_HEAVILY_WOUNDED * inputs.enemy_heavily_wounded + BattleScore.ENEMY_WALKING_WOUNDED * inputs.enemy_walking_wounded
	check(is_equal_approx(bm.battle_result.score, expected), "The score moves by exactly those casualties' rubric values (%s vs expected %s)" % [bm.battle_result.score, expected])


## Captured personnel are casualties too, for either side, whoever's fault it
## was: a surrendered unit's remaining strength is what was captured.
func test_captured_personnel_count_on_both_sides() -> void:
	var bm = make_battle()
	var ours: Unit = add(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	ours.pips = 5
	ours.state = Unit.State.SURRENDERED
	var theirs: Unit = add(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	theirs.pips = 7
	theirs.state = Unit.State.SURRENDERED
	capture_report(bm)
	check(bm.battle_result.inputs.player_captured == 5, "Our surrendered personnel are captured, got %s" % [bm.battle_result.inputs])
	check(bm.battle_result.inputs.enemy_captured == 7, "So are theirs, got %s" % [bm.battle_result.inputs])
	check(is_equal_approx(bm.battle_result.score, BattleScore.score({"position": bm.battle_result.inputs.position, "player_captured": 5, "enemy_captured": 7})), "...and each is scored at its own rate (-8 vs +8)")


## The Score tab's line items (user: "The score can show the line items that
## went into computing the score"). They come from the SAME term table score()
## uses, so they can never disagree with the number -- checked here across a
## spread of battles, not just one.
func test_line_items_always_sum_to_the_score() -> void:
	var samples: Array[Dictionary] = [
		{}, {"position": "held"}, {"position": "lost", "player_killed": 9},
		{"position": "held", "player_killed": 2, "player_captured": 1, "player_heavily_wounded": 3, "player_walking_wounded": 4, "player_mortar_lost": 1,
			"enemy_killed": 7, "enemy_captured": 2, "enemy_heavily_wounded": 5, "enemy_walking_wounded": 6, "enemy_mortar_out": 2},
		{"position": "stalemate", "enemy_killed": 1, "enemy_walking_wounded": 1},
	]
	for inputs in samples:
		var total := 0.0
		for item in BattleScore.line_items(inputs):
			total += item.points
			check(is_equal_approx(item.points, item.count * item.value), "Each line item is count x value (%s)" % item.key)
		check(is_equal_approx(total, BattleScore.score(inputs)), "The line items must sum to the score for %s (got %s vs %s)" % [inputs, total, BattleScore.score(inputs)])
	var items: Array[Dictionary] = BattleScore.line_items({"position": "held"})
	check(items[0].key == "position" and items.size() == 1 + BattleScore.TERMS.size(), "The position is first, then every scored term")


func test_breakdown_text_lists_what_happened() -> void:
	var inputs := {"position": "held", "player_killed": 2, "enemy_killed": 6, "enemy_walking_wounded": 3, "enemy_mortar_out": 1}
	var text: String = BattleScore.breakdown_text(inputs, "Scenario average: +1.0 over 3 battles (X, Y)")
	var lines: PackedStringArray = text.split("\n")
	check(lines[0] == "Battle score: %s" % BattleScore.format(BattleScore.score(inputs)), "It leads with the total, got %s" % lines[0])
	check(lines[1].begins_with("Scenario average:"), "...then the scenario average when there is one")
	check("  Position held: +20.0" in lines, "The position is a line item")
	check("  Our personnel killed: 2 \u00d7 -10 = -20.0" in lines, "A friendly loss shows count x points-each = points, got %s" % [lines])
	check("  Enemy killed: 6 \u00d7 +5 = +30.0" in lines, "An enemy loss the same way")
	check("  Enemy walking wounded: 3 \u00d7 +0.5 = +1.5" in lines, "Fractional values keep their sign and precision")
	check("  Enemy mortar destroyed or abandoned: 1 \u00d7 +2.5 = +2.5" in lines, "The mortar term too")
	check(not ("Our personnel captured" in text) and not ("Our mortar lost" in text), "Terms that didn't happen are not listed")
	check(lines[-1] == "Total: %s" % BattleScore.format(BattleScore.score(inputs)), "It ends with the total, got %s" % lines[-1])
	check(not ("Scenario average" in BattleScore.breakdown_text(inputs)), "No scenario line when none is given")
	check("Stalemate" in BattleScore.breakdown_text({"position": "stalemate"}), "A stalemate says so rather than claiming held or lost")
	check(not ("held" in BattleScore.breakdown_text({"position": "stalemate"}).replace("held or lost", "")), "...and never calls it held")
