extends SceneTree
## Run: godot --headless --path . --script scripts/tests/test_decision_ui.gd
func _initialize():
	call_deferred("run")
func run():
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_recon_mode_chosen(GameConfig.ReconMode.DRONE_TEAM)
	await process_frame
	await process_frame
	# The setup screen no longer has controls for profiles or per-type orders (only the seed), so
	# the doctrine is built from what it does produce and the rest is filled in here, then handed to
	# the battle exactly as Start Battle would.
	var phase: DeploymentPhase = main.current_screen
	phase.doctrine_panel._seed.value = 731
	var doctrine: Dictionary = phase.build_doctrine()
	assert(doctrine.seed == 731)
	doctrine.player_profile = load("res://scripts/commander_profile.gd").preset("deliberate")
	doctrine.enemy_profile = load("res://scripts/commander_profile.gd").preset("aggressive")
	var unit_doctrine = load("res://scripts/unit_doctrine.gd")
	doctrine.player_unit_types["mortar"] = {"targeting": unit_doctrine.TARGET_IDS[4], "risk": unit_doctrine.RISK_IDS[2]}
	doctrine.enemy_unit_types["squad"] = {"targeting": unit_doctrine.TARGET_IDS[1], "risk": doctrine.enemy_unit_types["squad"].risk}
	await process_frame
	phase.start_requested.emit(doctrine)
	var battle: BattleScreen = main.current_screen
	battle.battle_manager.set_process(false)
	for i in 100:
		battle.battle_manager._process(0.5)
	battle.battle_manager.is_paused = true
	battle.decision_inspector.show()
	battle.decision_inspector._refresh()
	await process_frame
	assert(battle.battle_manager.profile_for(Unit.Team.PLAYER).id == "deliberate")
	assert(battle.battle_manager.profile_for(Unit.Team.ENEMY).id == "aggressive")
	assert(battle.battle_manager.unit_type_doctrines[Unit.Team.PLAYER].mortar.risk == "balanced")
	assert(battle.battle_manager.unit_type_doctrines[Unit.Team.ENEMY].squad.targeting == "nearest")
	for entry in battle.decision_inspector._unit_ids:
		for record in battle.battle_manager.decisions.records_for(entry):
			assert(record.team == Unit.Team.PLAYER)
	var export_path := "user://decision_trace_test_%d.json" % OS.get_process_id()
	battle.decision_inspector._live.button_pressed = false
	var before = battle.decision_inspector._review_entries.duplicate(true)
	battle.battle_manager.is_paused = false
	for i in 10:
		battle.battle_manager._process(0.5)
	battle.decision_inspector._refresh()
	assert(before == battle.decision_inspector._review_entries)
	battle.decision_inspector._export(export_path)
	var exported = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	assert(exported.schema_version == 1)
	for record in exported.events:
		assert(record.team == Unit.Team.PLAYER)
	battle.decision_inspector._developer.button_pressed = true
	battle.decision_inspector._export(export_path)
	exported = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	assert(exported.developer_view)
	assert(exported.events.any(func(e): return e.team == Unit.Team.ENEMY))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	battle._on_battle_ended("UI transition test")
	battle.report.report_background.get_node("DamageByUnit").pressed.emit()
	main._show_level_select()
	await process_frame
	assert(not is_instance_valid(battle))
	assert(main.current_screen is LevelSelectScreen)
	print("UI: profile wiring, frozen history, export filtering and restart passed")
	quit()
