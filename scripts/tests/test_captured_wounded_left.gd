extends SceneTree
## Wounded left behind in a retreat are captured (user, 2026-10-21: "If they retreat and leave the person behind, they will be captured."). The rule
## that governs the counting is the general one: "if someone counts in multiple ways, only the highest one counts" -- a man left behind is captured and
## wounded, and counts as the higher of the two, once. And the reports say that they were wounded left behind on the battlefield ("Somewhere it should
## say that").
##
## Run: godot --headless --path . --script scripts/tests/test_captured_wounded_left.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func run() -> void:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()

	# a squad that left 4 heavily wounded behind and has 1 walking wounded: 9 - 4 - 1 = 4 people left
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(-5000, -5000))
	bm.enemy_units.append(squad)
	squad.state = Unit.State.WITHDRAWN
	squad.pips = 4
	squad.wounded_left_behind_count = 4
	squad.walking_wounded_count = 1
	var ours: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(-5000, -3000))
	bm.player_units.append(ours)

	var stats: Dictionary = bm._compute_side_stats(bm.enemy_units)
	check(stats.captured == 4 and stats.captured_wounded_left == 4, "the 4 left behind are 4 captured, all of them wounded left behind (%d, %d)" % [stats.captured, stats.captured_wounded_left])
	check(stats.heavily_wounded == 0, "...and are not also heavily wounded (%d)" % stats.heavily_wounded)
	check(stats.killed + stats.heavily_wounded + stats.walking_wounded + stats.captured == stats.pips_lost, "...so everyone lost is in exactly one count (%d)" % stats.pips_lost)

	# a squad that surrendered whole, with none left behind: captured, but none of them wounded left behind
	var surrendered: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(-5000, -4000))
	bm.enemy_units.append(surrendered)
	surrendered.state = Unit.State.SURRENDERED
	var with_surrender: Dictionary = bm._compute_side_stats(bm.enemy_units)
	check(with_surrender.captured == 4 + surrendered.max_pips and with_surrender.captured_wounded_left == 4, "a surrendered squad is captured but is not 'wounded left behind' (%d, %d)" % [with_surrender.captured, with_surrender.captured_wounded_left])

	# the score: the highest of the ways they count, once each, and no more
	var result: Dictionary = bm._build_battle_result("TEST", false, bm._compute_side_stats(bm.player_units), stats)
	check(result.inputs.enemy_captured == 4 and result.inputs.enemy_heavily_wounded == 0 and result.inputs.enemy_captured_wounded_left == 4, "the score inputs: 4 captured, no heavily wounded, 4 of the captured left behind")
	var items: Array[Dictionary] = BattleScore.line_items(result.inputs)
	var from_them := 0.0
	for item in items:
		if item.key == "enemy_captured" or item.key == "enemy_heavily_wounded":
			from_them += item.points
	var highest: float = maxf(BattleScore.ENEMY_CAPTURED, BattleScore.ENEMY_HEAVILY_WOUNDED)
	check(is_equal_approx(from_them, 4.0 * highest), "...worth the highest of the ways each counts, once: 4 x %s, not more (%.1f)" % [str(highest), from_them])
	check(BattleScore.score(result.inputs) == BattleScore.score({"position": result.inputs.position, "enemy_captured": 4, "enemy_walking_wounded": result.inputs.enemy_walking_wounded}), "...and the extra count does not change the score")

	# the score breakdown says so
	var text: String = BattleScore.breakdown_text(result.inputs)
	check("4 of them wounded left behind on the battlefield" in text, "the score breakdown says that they were wounded left behind on the battlefield:\n%s" % text)
	var plain: String = BattleScore.breakdown_text({"position": "held", "enemy_captured": 3})
	check(not ("left behind" in plain), "a capture by surrender does not say it")

	# the after action report says so (the position held, so the enemy is assessed on the battlefield)
	var held_bm := BattleManager.new()
	root.add_child(held_bm)
	held_bm.set_process(false)
	held_bm.combat_log = Log.new()
	var left_squad: Unit = held_bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(-5000, -5000))
	held_bm.enemy_units.append(left_squad)
	left_squad.pips = 5
	left_squad.wounded_left_behind_count = 4
	var our_squad: Unit = held_bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(-5000, -3000))
	held_bm.player_units.append(our_squad)
	var report := {"text": ""}
	held_bm.battle_ended.connect(func(t): report.text = t)
	held_bm._end_battle()
	check(held_bm.battle_over, "the battle ended")
	check("Of the Russians captured, 4 were wounded left behind on the battlefield" in report.text, "the report says that they were wounded left behind on the battlefield:
%s" % report.text)
	check("4 captured" in report.text, "...and counts them as captured (4 captured)")

	print("Captured wounded left behind tests: %d failures" % failures)
	quit(1 if failures else 0)
