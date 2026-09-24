extends SceneTree
## The durable battle-score history (user: "track it in a durable way. The
## tracking should survive game restarts and also code updates. The player
## should be able to see average scores for different scenarios" — where a
## scenario is the LOCATION plus what kind of SCOUTING the player used).
##
## "Survives restarts" = a brand-new BattleScoreLog on the same file sees
## everything. "Survives code updates" = it lives outside the project, is
## append-only, tolerates unknown fields/versions, never deletes what it can't
## read, and stores the raw counts so a tuned rubric RE-SCORES history.
##
## Every test writes only to a disposable file under user://, never the real
## history.
##
## Run: godot --headless --path . --script scripts/tests/test_battle_score_log.gd
var failures := 0
var test_path: String = "user://test_battle_scores_%d.jsonl" % OS.get_process_id()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func fresh_log() -> BattleScoreLog:
	var log := BattleScoreLog.new()
	log.path = test_path
	return log

func wipe() -> void:
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))

func write_raw(text: String) -> void:
	var f := FileAccess.open(test_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func read_raw() -> String:
	return FileAccess.get_file_as_string(test_path)

## A finished battle's result, shaped like BattleManager.battle_result.
func result(position: String, enemy_killed: int, player_killed: int = 0, verdict: String = "SUCCESSFUL DEFENSE") -> Dictionary:
	var inputs := {"position": position, "enemy_killed": enemy_killed, "player_killed": player_killed}
	return {"rubric_version": BattleScore.RUBRIC_VERSION, "verdict": verdict, "score": BattleScore.score(inputs),
		"inputs": inputs}

func run() -> void:
	wipe()
	test_records_survive_a_restart()
	test_averages_are_per_scenario_location_and_scouting()
	test_a_tuned_rubric_rescores_the_whole_history()
	test_damaged_files_lose_at_most_the_damaged_line()
	test_unknown_fields_and_a_missing_file_are_fine()
	test_a_failed_write_never_throws()
	test_an_empty_path_means_no_history()
	wipe()
	print("Battle score log tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_records_survive_a_restart() -> void:
	wipe()
	var first := fresh_log()
	check(first.load_records().is_empty(), "No file yet: an empty history, not an error")
	check(first.record(result("held", 6), "pishchane", "DRONE_TEAM"), "Recording a finished battle must succeed")
	check(first.record(result("lost", 2, 3, "DEFEAT"), "pishchane", "DRONE_TEAM"), "...and another")
	# "Restart": nothing in memory survives, only the file.
	var second := fresh_log()
	var records: Array[Dictionary] = second.load_records()
	check(records.size() == 2, "A brand-new log object on the same file must see both battles, got %d" % records.size())
	if records.size() == 2:
		check(records[0].map_id == "pishchane" and records[0].recon_mode == "DRONE_TEAM", "Each record names its scenario (map id + recon mode)")
		check(records[0].verdict == "SUCCESSFUL DEFENSE" and records[1].verdict == "DEFEAT", "Oldest first, verdicts kept")
		check(is_equal_approx(records[0].score, 50.0) and is_equal_approx(records[1].score, -40.0), "The score is stored")
		check(records[0].inputs.enemy_killed == 6 and records[0].inputs.position == "held", "The raw counts behind the score are stored")
		check(records[0].rubric_version == BattleScore.RUBRIC_VERSION and records[0].has("time_utc") and records[0].v == BattleScoreLog.RECORD_VERSION, "Rubric version, schema version and a timestamp are stored")
	check(not second.record({}, "pishchane", "SPOTTER"), "There is nothing to record for an empty result")
	check(second.load_records().size() == 2, "...and it must not have written anything")
	check(BattleScoreLog.new().path.begins_with("user://"), "The real history lives in the per-user data folder, outside the project, so a code update can't touch it")


func test_averages_are_per_scenario_location_and_scouting() -> void:
	wipe()
	var log := fresh_log()
	log.record(result("held", 6), "pishchane", "DRONE_TEAM")      # +50
	log.record(result("held", 2), "pishchane", "DRONE_TEAM")      # +30
	log.record(result("lost", 0, 1), "pishchane", "DRONE_TEAM")   # -30
	log.record(result("held", 4), "pishchane", "SPOTTER")         # +40  (same place, different scouting)
	log.record(result("lost", 0), "pervomaiske", "DRONE_TEAM")    # -20  (different place, same scouting)
	var summaries: Array[Dictionary] = BattleScoreLog.summarize(log.load_records())
	check(summaries.size() == 3, "Location AND scouting both define a scenario: expected 3 scenarios, got %d" % summaries.size())
	var drone: Dictionary = BattleScoreLog.scenario_summary(log.load_records(), "pishchane", "DRONE_TEAM")
	check(drone.count == 3 and is_equal_approx(drone.average, 50.0 / 3.0), "Pishchane + drones: 3 battles averaging (50+30-30)/3, got %s" % [drone])
	check(is_equal_approx(drone.best, 50.0) and is_equal_approx(drone.worst, -30.0) and is_equal_approx(drone.latest, -30.0), "Best, worst and latest")
	var spotter: Dictionary = BattleScoreLog.scenario_summary(log.load_records(), "pishchane", "SPOTTER")
	check(spotter.count == 1 and is_equal_approx(spotter.average, 40.0), "The same place with a different kind of scouting is its own scenario")
	check(BattleScoreLog.scenario_summary(log.load_records(), "pervomaiske", "SPOTTER").is_empty(), "A scenario never played has no summary")
	check(summaries[0].map_id <= summaries[-1].map_id, "Summaries come back in a stable order")


func test_a_tuned_rubric_rescores_the_whole_history() -> void:
	wipe()
	# A line as written by an EARLIER build: its stored score is stale (999) but its counts are what matter.
	write_raw('{"v":1,"map_id":"pishchane","recon_mode":"SPOTTER","rubric_version":0,"score":999,"inputs":{"position":"held","enemy_killed":2}}\n'
		+ '{"v":1,"map_id":"pishchane","recon_mode":"SPOTTER","score":12.5}\n')
	var summary: Dictionary = BattleScoreLog.scenario_summary(fresh_log().load_records(), "pishchane", "SPOTTER")
	check(summary.count == 2, "Both the counted record and the number-only record are usable, got %s" % [summary])
	# 20 + 2*5 = 30 under the current rubric (NOT the stored 999); the number-only line keeps its stored 12.5.
	check(is_equal_approx(summary.average, (30.0 + 12.5) / 2.0), "History must be re-scored from stored counts under the CURRENT rubric (got average %s)" % summary.average)


func test_damaged_files_lose_at_most_the_damaged_line() -> void:
	wipe()
	var log := fresh_log()
	log.record(result("held", 6), "pishchane", "DRONE_TEAM")
	# Simulate a crash mid-write: garbage, a blank line, valid JSON of the wrong shape, and a final line cut off with no newline.
	var good: String = read_raw()
	write_raw(good + "this is not json\n\n[1,2,3]\n{\"map_id\": 5}\n" + '{"v":1,"map_id":"pishchane","recon_mode":"DRONE_TEAM","sco')
	var damaged := fresh_log()
	var records: Array[Dictionary] = damaged.load_records()
	check(records.size() == 1, "Only the intact record is usable, got %d" % records.size())
	check(damaged.skipped_lines == 4, "The four unreadable lines are counted, not silently dropped (got %d)" % damaged.skipped_lines)
	var before: String = read_raw()
	# The next battle must append cleanly even though the file ends mid-line.
	check(damaged.record(result("held", 4), "pishchane", "DRONE_TEAM"), "Appending after a cut-off line must still work")
	var after: Array[Dictionary] = fresh_log().load_records()
	check(after.size() == 2, "Both the old record and the new one must load (the new line must not be glued onto the cut-off one), got %d" % after.size())
	check(read_raw().begins_with(before), "Existing history is never rewritten or truncated — only appended to")


func test_unknown_fields_and_a_missing_file_are_fine() -> void:
	wipe()
	check(fresh_log().load_records().is_empty() and BattleScoreLog.summarize(fresh_log().load_records()).is_empty(), "A file that doesn't exist is simply no history")
	# A record from a FUTURE build: a higher version and fields this build has never heard of.
	write_raw('{"v":7,"map_id":"pishchane","recon_mode":"DRONE_TEAM","score":25.0,"weather":"snow","new_thing":{"a":1},"inputs":{"position":"held"}}\n')
	var records: Array[Dictionary] = fresh_log().load_records()
	check(records.size() == 1 and BattleScoreLog.rescored(records[0]) == 20.0, "A newer build's record must still be read (extra fields ignored)")
	# A map or mode this build doesn't know is kept, not hidden.
	write_raw('{"v":1,"map_id":"a_map_since_removed","recon_mode":"A_MODE_SINCE_RENAMED","score":5}\n')
	check(BattleScoreLog.summarize(fresh_log().load_records()).size() == 1, "History for a scenario this build no longer has is kept")


func test_a_failed_write_never_throws() -> void:
	var log := BattleScoreLog.new()
	log.path = "user://no_such_folder_for_tests/scores.jsonl"
	check(not log.record(result("held", 1), "pishchane", "SPOTTER"), "An unwritable location must report failure, not crash the end of a battle")
	check(log.load_records().is_empty(), "...and reading it is just an empty history")


## An empty path is "no history": how automated runs are kept off a real
## player's file (see main.gd). It must neither write nor read anything.
func test_an_empty_path_means_no_history() -> void:
	wipe()
	var log := BattleScoreLog.new()
	log.path = ""
	check(not log.record(result("held", 1), "pishchane", "SPOTTER"), "With no path there is nowhere to record")
	check(log.load_records().is_empty(), "...and nothing to read")
	check(not FileAccess.file_exists(test_path), "...and nothing may have been written anywhere")
