extends SceneTree
## Guards a direct user report of confusion: "How can we have taken 16
## casualties when the damage by unit shows [7 killed+wounded], and some of
## them were definitely on the enemy mortar team?" Root cause: nothing wrong
## with the arithmetic — BattleManager._compute_side_stats correctly folds a
## SURRENDERED unit's whole remaining strength into pips_lost (a surrender
## never reduces `pips`, so it has to be added in explicitly or it reads as
## "suffered nothing" — see that function's own doc comment), but the
## sidebar's "N/M personnel lost" line never said so, so the gap between it
## and the AAR's own killed+wounded total looked like a bug. Direct user
## follow-up: "casualties sidebar should explicitly mention surrenders if
## there are any. If there are no surrenders, it should not say '0
## surrendered' or anything of the sort."
##
## Run: godot --headless --path . --script scripts/tests/test_casualty_dashboard_captured.gd
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

## A real dashboard, wired to `bm`, with its actual UI built (_ready needs
## to have run — see CasualtyDashboard's own doc comment on why the labels
## don't exist until then).
func make_dashboard(bm):
	var dash := CasualtyDashboard.new()
	root.add_child(dash)
	dash.setup(bm)
	return dash


func test_no_mention_when_nobody_surrendered() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(squad)
	squad.pips = squad.max_pips - 2 # ordinary combat casualties, no surrender
	var dash = make_dashboard(bm)
	dash._refresh()
	var text: String = dash._player_label.text
	check("captured" not in text, "With nobody captured, the line must not mention captures at all (got '%s')" % text)
	check(("%d/%d" % [2, squad.max_pips]) in text, "Setup check: the ordinary casualty count must still show (got '%s')" % text)
	dash.queue_free()
	bm.combat_log.free()
	bm.free()


func test_mentions_the_exact_captured_count_when_a_unit_surrendered() -> void:
	var bm = make_battle()
	var wounded_squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(wounded_squad)
	wounded_squad.pips = wounded_squad.max_pips - 2 # 2 real casualties, still fighting
	var surrendered_squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(100, 0))
	bm.player_units.append(surrendered_squad)
	surrendered_squad.state = Unit.State.SURRENDERED # pips untouched -- the whole squad is the capture
	var dash = make_dashboard(bm)
	dash._refresh()
	var text: String = dash._player_label.text
	var total_lost: int = 2 + surrendered_squad.max_pips
	check(("%d captured" % surrendered_squad.max_pips) in text,
		"With a unit surrendered, the line must name the exact captured count (expected '%d captured', got '%s')" % [surrendered_squad.max_pips, text])
	check(("%d/" % total_lost) in text,
		"The headline lost count must still be the combined total, captures included (expected %d, got '%s')" % [total_lost, text])
	dash.queue_free()
	bm.combat_log.free()
	bm.free()


## The estimated (enemy-side, fog-of-war) line runs through the exact same
## captured_suffix code, so it WOULD show a count the instant _compute_side_
## stats ever populates one there — but that function deliberately only
## folds a surrender into `captured` on the non-estimated branch (a
## separate, pre-existing estimated-vs-confirmed design boundary, unrelated
## to this fix: the live sidebar's enemy read is always the fog-of-war
## estimate, and "captured" here specifically means confirmed, not
## guessed). So today this line correctly stays silent even with an enemy
## unit surrendered — captured_suffix has nothing to report, not because
## the mention logic was skipped.
func test_estimated_enemy_line_has_nothing_to_report_yet() -> void:
	var bm = make_battle()
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.enemy_units.append(enemy)
	enemy.state = Unit.State.SURRENDERED
	enemy.player_has_been_sighted = true
	enemy.player_known_state = Unit.State.SURRENDERED
	enemy.player_known_pips = enemy.pips
	var dash = make_dashboard(bm)
	dash._refresh()
	var text: String = dash._enemy_label.text
	check(text.begins_with("Enemy: ~"), "Setup check: the enemy line must be the estimated/'~' variant")
	check("captured" not in text, "The estimated view doesn't track captures at all yet (a separate, pre-existing boundary) — must not claim it does (got '%s')" % text)
	dash.queue_free()
	bm.combat_log.free()
	bm.free()


## The replay/history-scrub path (BattleHistoryViewer.casualty_pips_at_
## current_index) is a separate producer of the same stats shape -- must
## carry the same captured count, not silently drop it during a scrub.
func test_history_replay_also_reports_captured() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(squad)
	squad.state = Unit.State.SURRENDERED
	var viewer := BattleHistoryViewer.new()
	viewer.history = [{"units": [{"team": Unit.Team.PLAYER, "kind": Unit.Kind.SQUAD, "state": Unit.State.SURRENDERED, "max_pips": squad.max_pips, "pips": squad.pips}]}]
	viewer.current_index = 0
	var stats: Dictionary = viewer.casualty_pips_at_current_index(Unit.Team.PLAYER)
	check(stats.captured == squad.max_pips, "The replay path must report the same captured count as the live one (got %d, expected %d)" % [stats.captured, squad.max_pips])
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_no_mention_when_nobody_surrendered()
	test_mentions_the_exact_captured_count_when_a_unit_surrendered()
	test_estimated_enemy_line_has_nothing_to_report_yet()
	test_history_replay_also_reports_captured()
	print("Casualty dashboard captured-count tests: %d failures" % failures)
	quit(1 if failures else 0)
