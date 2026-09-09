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
	var panel = main.doctrine_panel
	panel._player_profile.select(3)
	panel._on_profile_selected(3)
	panel._enemy_profile.select(2)
	panel._seed.value = 731
	panel.get_child(0).scroll_vertical = 340
	await process_frame
	main._on_start_pressed()
	main.battle_manager.set_process(false)
	for i in 100:
		main.battle_manager._process(0.5)
	main.battle_manager.is_paused = true
	main.decision_inspector.show()
	main.decision_inspector._refresh()
	await process_frame
	assert(main.battle_manager.profile_for(Unit.Team.PLAYER).id == "deliberate")
	assert(main.battle_manager.profile_for(Unit.Team.ENEMY).id == "aggressive")
	for entry in main.decision_inspector._unit_ids:
		for record in main.battle_manager.decisions.records_for(entry):
			assert(record.team == Unit.Team.PLAYER)
	var export_path := "user://decision_trace_test_%d.json" % OS.get_process_id()
	main.decision_inspector._live.button_pressed = false
	var before = main.decision_inspector._review_entries.duplicate(true)
	main.battle_manager.is_paused = false
	for i in 10:
		main.battle_manager._process(0.5)
	main.decision_inspector._refresh()
	assert(before == main.decision_inspector._review_entries)
	main.decision_inspector._export(export_path)
	var exported = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	assert(exported.schema_version == 1)
	for record in exported.events:
		assert(record.team == Unit.Team.PLAYER)
	main.decision_inspector._developer.button_pressed = true
	main.decision_inspector._export(export_path)
	exported = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	assert(exported.developer_view)
	assert(exported.events.any(func(e): return e.team == Unit.Team.ENEMY))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	main._on_battle_ended("UI transition test")
	main._show_level_select()
	await process_frame
	assert(main.decision_inspector == null)
	assert(main.inspect_button == null)
	assert(main.level_select_screen != null)
	print("UI: profile wiring, frozen history, export filtering and restart passed")
	quit()
