extends SceneTree
## Where the player actually sees the battle score: at the end of every
## battle (main.gd records it to the durable history and adds this scenario's
## running average to the report), and on the level-select screen (average
## per scenario — location + scouting). The record is written ONLY here, in
## the real UI flow — BattleManager never writes history.
##
## Run: godot --headless --path . --script scripts/tests/test_battle_score_display.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0
var test_path: String = "user://test_battle_score_display_%d.jsonl" % OS.get_process_id()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func wipe() -> void:
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))

## Size of a file in bytes, or -1 if it doesn't exist.
func file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	return FileAccess.open(path, FileAccess.READ).get_length()

## Every text (Label/RichTextLabel/etc.) anywhere under `node`.
func all_text(node: Node) -> String:
	var out: PackedStringArray = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if "text" in n and n.text is String and not (n.text as String).is_empty():
			out.append(n.text)
		for c in n.get_children():
			stack.append(c)
	return "\n".join(out)

## A battle we win, ended for real (report text + result), NOT yet handed to main.
func finished_battle(enemy_dead: int) -> Array:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var ours: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(ours)
	var theirs: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	bm.enemy_units.append(theirs)
	theirs.pips = 0
	theirs.state = Unit.State.DESTROYED
	theirs.killed_count = enemy_dead
	theirs.heavily_wounded_count = 0
	theirs.walking_wounded_count = 9 - enemy_dead
	var text := [""]
	bm.battle_ended.connect(func(t: String): text[0] = t)
	bm._end_battle()
	return [bm, text[0]]

func run() -> void:
	wipe()
	await test_battle_end_records_and_shows_the_scenario_average()
	await test_level_select_shows_average_scores_per_scenario()
	wipe()
	print("Battle score display tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_battle_end_records_and_shows_the_scenario_average() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame

	# An automated (headless) run must never touch a player's real history (a
	# precaution: several tests drive main.gd's real battle-end flow). Here a
	# finished battle goes through main with NO path override at all, and the
	# real history file must not change.
	check(main.score_log.path.is_empty(), "A headless run must default to NO history path, not the player's real file")
	var real_size_before: int = file_size(BattleScoreLog.DEFAULT_PATH)
	var unguarded: Array = finished_battle(4)
	main.battle_manager = unguarded[0]
	main._on_battle_ended(unguarded[1])
	check(file_size(BattleScoreLog.DEFAULT_PATH) == real_size_before, "A battle ended in an automated run must not write to the real history (%d -> %d bytes)" % [real_size_before, file_size(BattleScoreLog.DEFAULT_PATH)])
	check(not ("Scenario average" in all_text(main.report_background)), "...and with no history there's no scenario average to show")
	main._show_level_select()
	await process_frame
	check(main.level_select_screen.score_log == main.score_log, "The level-select screen shares main's one history (and its guard)")

	main.score_log.path = test_path
	main.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var map_id: String = GameConfig.current_map_id()

	# No battle at all (e.g. the existing report-button tests): nothing to record, nothing breaks.
	main._on_battle_ended("Verdict: TEST")
	check(main.score_log.load_records().is_empty(), "A report with no finished battle behind it must record nothing")
	main._show_level_select()
	await process_frame

	# Battle 1: 9 enemy dead-or-wounded, position held. We use the game's own number.
	var first: Array = finished_battle(4)
	main.battle_manager = first[0]
	main._on_battle_ended(first[1])
	var score_one: float = first[0].battle_result.score
	var records: Array[Dictionary] = main.score_log.load_records()
	check(records.size() == 1, "The finished battle must be written to the durable history, got %d records" % records.size())
	if records.size() == 1:
		check(records[0].map_id == map_id and records[0].recon_mode == "DRONE_TEAM", "...filed under its scenario (this map + this scouting), got %s / %s" % [records[0].map_id, records[0].recon_mode])
		check(is_equal_approx(records[0].score, score_one), "...with the score that was shown")
	var shown: String = all_text(main.report_background)
	check(("Battle score: %s" % BattleScore.format(score_one)) in shown, "The report on screen must show the battle score")
	check("Scenario average: %s over 1 battle (" % BattleScore.format(score_one) in shown, "...and this scenario's average, singular for the first battle (got: %s)" % shown.substr(0, 400))
	check(GameConfig.CURRENT_MAP.name in shown and GameConfig.RECON_MODE_LABELS[GameConfig.ReconMode.DRONE_TEAM] in shown, "...naming the scenario: location and scouting")
	var lines: PackedStringArray = shown.split("\n")
	var score_index := -1
	for i in lines.size():
		if lines[i].begins_with("Battle score:"):
			score_index = i
	check(score_index >= 0 and score_index + 1 < lines.size() and lines[score_index + 1].begins_with("Scenario average:"), "The average sits directly under the score")

	# Battle 2 in the same scenario: the average now covers both.
	main._show_level_select()
	await process_frame
	var second: Array = finished_battle(9)
	main.battle_manager = second[0]
	main._on_battle_ended(second[1])
	var score_two: float = second[0].battle_result.score
	check(not is_equal_approx(score_one, score_two), "Setup check: the two battles should score differently")
	var expected_average: float = (score_one + score_two) / 2.0
	check(("Scenario average: %s over 2 battles" % BattleScore.format(expected_average)) in all_text(main.report_background), "The second battle's report must show the average of both, %s" % BattleScore.format(expected_average))

	# Same location, DIFFERENT scouting: its own scenario, starting fresh.
	main._show_level_select()
	await process_frame
	main.recon_mode = GameConfig.ReconMode.SPOTTER
	var third: Array = finished_battle(4)
	main.battle_manager = third[0]
	main._on_battle_ended(third[1])
	check("over 1 battle (" in all_text(main.report_background), "A different kind of scouting at the same location must have its own average, not share the drone one")
	check(main.score_log.load_records().size() == 3, "All three battles are in the history")


func test_level_select_shows_average_scores_per_scenario() -> void:
	wipe()
	var empty := LevelSelectScreen.new()
	empty.score_log.path = test_path
	root.add_child(empty)
	await process_frame
	check("No battles scored yet." in all_text(empty), "With no history the screen says so")
	empty.queue_free()

	var log := BattleScoreLog.new()
	log.path = test_path
	var maps: Array = GameConfig.MAPS.keys()
	var won := {"position": "held", "enemy_killed": 6}   # +50
	var lost := {"position": "lost", "enemy_killed": 1}  # -15
	for inputs in [won, won, lost]:
		log.record({"score": BattleScore.score(inputs), "inputs": inputs, "verdict": "X"}, maps[0], "DRONE_TEAM")
	log.record({"score": 50.0, "inputs": won, "verdict": "X"}, maps[0], "SPOTTER")
	log.record({"score": 50.0, "inputs": won, "verdict": "X"}, "a_map_since_removed", "DRONE_TEAM")

	var screen := LevelSelectScreen.new()
	screen.score_log.path = test_path
	root.add_child(screen)
	await process_frame
	var text: String = all_text(screen)
	check(not ("No battles scored yet." in text), "With history the screen shows it instead")
	check(LevelSelectScreen.scenario_label(maps[0], "DRONE_TEAM") in text, "Each scenario is labelled by location and scouting: %s" % LevelSelectScreen.scenario_label(maps[0], "DRONE_TEAM"))
	check(LevelSelectScreen.scenario_label(maps[0], "SPOTTER") in text, "...and the same place with the other scouting is its own row")
	check(BattleScore.format((50.0 + 50.0 - 15.0) / 3.0) in text, "The average for the drone scenario ((50+50-15)/3) must be shown")
	check("a_map_since_removed" in text, "History for a map this build no longer has is still shown, by its stored id")
	check(LevelSelectScreen.scenario_label("x", "Y") == "x — Y", "An unknown map/mode falls back to the stored ids")
	screen.queue_free()
