extends SceneTree
## Direct user request: "I want to move the seed to the first screen where the user picks a scenario.
## Also, after the scenario is over, it can be a tab on the score/damage by unit/aar display. Hopefully
## it is the case that picking the same seed reproduces the battle, at least in part? That should be
## explained, with a button to copy the seed."
##
## What the same seed does (measured here, and stated in the explanation the player reads): with the
## same location, setup, orders and frame timing the battle is identical; with a different frame timing
## (as in real play) it has the same weather and the same enemy force but the fight goes its own way.
##
## Run: godot --headless --path . --script scripts/tests/test_battle_seed.gd
const Profile = preload("res://scripts/commander_profile.gd")
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await test_the_seed_is_chosen_on_the_first_screen()
	await test_a_random_battle_still_gets_a_real_seed()
	await test_the_report_has_a_seed_tab_with_a_copy_button()
	await test_a_pasted_seed_is_read_correctly_even_without_losing_focus_first()
	test_what_the_same_seed_reproduces()
	print("Battle seed tests: %d failures" % failures)
	quit(1 if failures else 0)


func start_main():
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	return main


func test_the_seed_is_chosen_on_the_first_screen() -> void:
	var main = await start_main()
	var first: LevelSelectScreen = main.current_screen
	check(first.seed_box != null and int(first.seed_box.value) == -1, "The first screen has a seed box, defaulting to -1 (random)")
	check(first.chosen_seed() == -1, "...which reads as random")
	var text := ""
	for n in first.find_children("*", "Label", true, false) + first.find_children("*", "RichTextLabel", true, false):
		text += " " + n.text
	check("Battle seed" in text and "same weather" in text and "does not replay the battle" in text, "The screen explains what a seed does and does not do")
	# Set via the LineEdit's own text, not seed_box.value directly — matching how a real user's typing or
	# paste actually reaches the box (see chosen_seed's own doc comment: .value doesn't sync from a
	# programmatic .value= write back to the LineEdit's displayed text either, so a direct .value assignment
	# here would silently pass without ever exercising the real commit path chosen_seed()'s apply() call
	# depends on).
	first.seed_box.get_line_edit().text = "4242"
	first.mode_chosen.emit(GameConfig.ReconMode.DRONE_TEAM)
	await process_frame
	var phase: DeploymentPhase = main.current_screen
	check(phase is DeploymentPhase and phase.battle_seed == 4242, "The typed seed reaches the deployment screen (%s)" % str(phase.battle_seed))
	check(main.battle_seed == 4242, "...and is the battle's seed")
	check(Weather.current.hud_signature() == Weather.roll(4242 + 7919).hud_signature(), "The March weather shown at deployment is the one this seed gives")
	check(phase.build_doctrine().seed == 4242, "...and Start Battle carries it into the doctrine")
	main.queue_free()
	await process_frame


func test_a_random_battle_still_gets_a_real_seed() -> void:
	var main = await start_main()
	main.current_screen.mode_chosen.emit(GameConfig.ReconMode.SPOTTER)
	await process_frame
	var a: int = main.battle_seed
	check(a >= 0, "With -1 typed the battle still gets a real seed to show afterwards (%d)" % a)
	check(main.current_screen.build_doctrine().seed == a, "...and that is the seed the battle runs on")
	main._show_level_select()
	await process_frame
	main.current_screen.mode_chosen.emit(GameConfig.ReconMode.SPOTTER)
	await process_frame
	check(main.battle_seed != a, "...a different one each time (%d vs %d)" % [a, main.battle_seed])
	main.queue_free()
	await process_frame


func test_the_report_has_a_seed_tab_with_a_copy_button() -> void:
	var main = await start_main()
	main.current_screen.seed_box.get_line_edit().text = "777" # see the earlier test's own comment on why
	main.current_screen.mode_chosen.emit(GameConfig.ReconMode.SPOTTER)
	await process_frame
	main.current_screen.request_start()
	await process_frame
	await process_frame
	var battle: BattleScreen = main.current_screen
	check(battle.battle_manager.battle_seed == 777, "The battle ran on the seed typed on the first screen")
	battle._on_battle_ended("Verdict: TEST")
	await process_frame
	var report: BattleReport = battle.report
	var tab: Button = report.report_background.get_node("SeedTab")
	check(tab != null and tab.text == "Seed", "The report has a Seed tab")
	var names: Array = []
	for c in report.report_background.get_children():
		if c is Button:
			names.append(c.text)
	check(names.find("Score") < names.find("Damage by unit") and names.find("Damage by unit") < names.find("Seed") and names.find("Seed") < names.find("After Action Report"), "...among the score / damage by unit / after action report tabs (%s)" % str(names))
	var copy: Button = report.copy_seed_button
	check(copy != null and not copy.visible, "The copy button is not shown on the other tabs")
	tab.pressed.emit()
	check(copy.visible, "...and is on the Seed tab")
	var text: String = report.seed_tab_text()
	check("777" in text and "same weather" in text and "does not replay the battle" in text, "The tab shows the seed and explains what it does (%s)" % text)
	copy.pressed.emit()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		check(DisplayServer.clipboard_get() == "777", "Copy seed puts the number on the clipboard (got '%s')" % DisplayServer.clipboard_get())
	else:
		print("(clipboard is not available in this headless run; the copy call ran without error)")
	report.report_background.get_node("DamageByUnit").pressed.emit()
	check(not copy.visible, "The copy button goes away on the other tabs")
	main.queue_free()
	await process_frame


## Direct user report: pasted a seed copied from a prior battle's report, picked a recon mode right away,
## and got a different enemy force despite believing the same seed was used. Root cause: SpinBox.value
## (what chosen_seed() used to read directly) doesn't update from typed/pasted text until something commits
## it (Enter, an arrow click, or the LineEdit losing focus) — a paste followed immediately by clicking a
## recon-mode button, this screen's very next step, races that commit. Simulates a real paste exactly:
## setting the LineEdit's own text directly (what a Ctrl+V does) rather than seed_box.value (what the old,
## buggy code effectively required already having happened).
func test_a_pasted_seed_is_read_correctly_even_without_losing_focus_first() -> void:
	var main = await start_main()
	var first: LevelSelectScreen = main.current_screen
	first.seed_box.get_line_edit().text = "555555"
	check(int(first.seed_box.value) != 555555, "Setup: a pasted-but-uncommitted edit does NOT yet update .value — confirms this test is exercising the real race, not a no-op")
	check(first.chosen_seed() == 555555, "chosen_seed() reads the pasted value correctly anyway, with no focus change or Enter press in between")
	main.queue_free()
	await process_frame


## The claim the explanation makes, measured: same everything -> identical battle; same seed but different
## frame timing (as in real play) -> same force, start positions and weather, but a different fight; another
## seed -> a different force and weather.
func test_what_the_same_seed_reproduces() -> void:
	var a := run_battle(731, [0.5])
	var b := run_battle(731, [0.5])
	var c := run_battle(731, [0.4, 0.6])
	var d := run_battle(732, [0.5])
	check(a == b, "Same seed, same setup, same frame timing: the identical battle")
	check(a.squads == c.squads and a.mortars == c.mortars and a.start == c.start and a.weather == c.weather, "Same seed, different frame timing: the same weather and enemy force, in the same places")
	check(a.score != c.score or a.ticks != c.ticks, "...but the fight itself is not the same (score %s vs %s, %d vs %d ticks)" % [a.score, c.score, a.ticks, c.ticks])
	check(a.start != d.start or a.squads != d.squads or a.weather != d.weather, "Another seed gives another force or weather")


func run_battle(seed_value: int, dts: Array) -> Dictionary:
	Weather.current = Weather.roll(seed_value + 7919)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	var log = Log.new()
	var squads: Array[Dictionary] = []
	for pos in GameConfig.CURRENT_MAP.player.default_squad_positions:
		squads.append({"position": pos, "retreat_threshold": 0.5})
	bm.start_battle({"squads": squads,
		"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
		"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position}, "recon_mode": GameConfig.ReconMode.SPOTTER,
		"player_profile": Profile.preset("baseline"), "enemy_profile": Profile.preset("baseline"), "seed": seed_value}, log)
	var force := {"squads": 0, "mortars": 0}
	var start: Array = []
	for u in bm.enemy_units:
		if u.kind == Unit.Kind.SQUAD:
			force.squads += 1
		if u.kind == Unit.Kind.MORTAR:
			force.mortars += 1
		start.append(u.position)
	var weather: String = Weather.current.hud_signature()
	var ticks := 0
	while not bm.battle_over and ticks < 30000:
		bm._process(dts[ticks % dts.size()])
		ticks += 1
	var result := {"squads": force.squads, "mortars": force.mortars, "start": start, "weather": weather, "score": bm.battle_result.get("score", 0), "ticks": ticks}
	bm.free()
	log.free()
	return result
