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
	var panel = main.current_screen.doctrine_panel
	panel._player_profile.select(3)
	panel._on_profile_selected(3)
	panel._enemy_profile.select(2)
	panel._unit_type.select(1)
	panel._load_unit_orders()
	panel._type_target.select(4)
	panel._type_risk.select(2)
	panel._save_unit_orders()
	panel._unit_type.select(0)
	panel._load_unit_orders()
	assert(panel._type_target.selected == 0)
	panel._type_side.select(1)
	panel._load_unit_orders()
	panel._type_target.select(1)
	panel._save_unit_orders()
	panel._seed.value = 731
	panel.get_child(0).scroll_vertical = 340
	await process_frame
	main.current_screen.request_start()
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
