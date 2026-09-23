extends SceneTree
## Guards a direct user correction: "The latest battle just ended as a
## successful defense. The stalemate code must have triggered... I'm
## thinking that when that happens, the verdict should be 'STALEMATE'. It
## can then talk about losses, which in this case would have been
## favorable. Don't say that the position was held, or that it was lost.
## Neither is true." A stalemate (BattleManager._ended_by_stalemate, set
## when _check_battle_end's stagnation-timeout branch is what actually ended
## the fight — see test_stalemate_armed_mortar.gd for that mechanism itself)
## used to fall straight into the ordinary held/exchange_ratio verdict
## branching, so it could read as "SUCCESSFUL DEFENSE" or "DEFEAT" even
## though nothing was actually decided.
##
## Run: godot --headless --path . --script scripts/tests/test_stalemate_verdict.gd
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

func capture_report(bm) -> String:
	var captured := [""]
	bm.battle_ended.connect(func(text: String): captured[0] = text)
	bm._end_battle()
	return captured[0]


## A static standoff, both mortars dry, one squad already down on each
## side (a real, favorable-for-the-player exchange) -- the exact reported
## shape: a stalemate with losses on the board, some of them favorable.
func test_stalemate_reports_a_distinct_verdict_and_no_held_or_lost_claim() -> void:
	var bm = make_battle()
	var p_squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(p_squad)
	p_squad.pips = p_squad.max_pips - 1 # one favorable-exchange casualty each side
	var e_squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(10000, 0))
	bm.enemy_units.append(e_squad)
	e_squad.pips = e_squad.max_pips - 3
	bm._ended_by_stalemate = true

	var text: String = capture_report(bm)
	check(bm.battle_over, "Setup check: _end_battle must actually end the battle")
	check("Verdict: STALEMATE" in text, "A stalemate-ended battle must report the STALEMATE verdict (got: %s)" % text.split("\n")[1])
	check("SUCCESSFUL DEFENSE" not in text and "PYRRHIC DEFENSE" not in text and "DEFEAT" not in text and "TACTICAL WITHDRAWAL" not in text,
		"A stalemate must never also read as one of the decided verdicts")
	check("held: YES" not in text and "held: NO" not in text,
		"Neither 'held' nor 'lost' is true of a stalemate -- the report must not claim either (got: %s)" % text.split("\n")[2])
	check("stalemate" in text.to_lower(), "The map-result line must itself say this was a stalemate, not stay silent about it")
	check("Player casualties:" in text and "Enemy casualties:" in text,
		"Losses must still be reported in full -- a stalemate isn't an excuse to omit the casualty picture")


## An ordinary decisive battle (the enemy wiped out, not a stalemate) must
## be completely unaffected -- same verdicts, same held line, as before.
func test_an_ordinary_decisive_battle_is_unaffected() -> void:
	var bm = make_battle()
	var p_squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(p_squad)
	var e_squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	bm.enemy_units.append(e_squad)
	e_squad.pips = 0 # a real DESTROYED unit has already lost every pip on the way there
	e_squad.state = Unit.State.DESTROYED
	check(not bm._ended_by_stalemate, "Setup check: this battle must not be flagged as a stalemate")

	var text: String = capture_report(bm)
	check("Verdict: STALEMATE" not in text, "A genuinely decided battle must never read as a stalemate")
	check("SUCCESSFUL DEFENSE" in text, "This exact setup (player intact, enemy destroyed) must still read as a successful defense (got: %s)" % text.split("\n")[1])
	check("held: YES" in text, "The ordinary held line must still appear for a decided battle (got: %s)" % text.split("\n")[2])


func run() -> void:
	test_stalemate_reports_a_distinct_verdict_and_no_held_or_lost_claim()
	test_an_ordinary_decisive_battle_is_unaffected()
	print("Stalemate verdict tests: %d failures" % failures)
	quit(1 if failures else 0)
