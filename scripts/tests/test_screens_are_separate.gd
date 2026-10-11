extends SceneTree
## "There is no reason for anything from one screen to appear on the other one." main.gd shows
## one GameScreen at a time and frees the old one, with everything it created — including what
## it put in the map's SubViewport — so nothing survives into the next screen. Found by the
## refactor that made it so: the old main.gd freed the deployment widgets at "Start Battle" but
## not the deployment loupe, which stayed alive (and, once a token had been dragged, on screen)
## through the whole battle and its report.
##
## Run: godot --headless --path . --script scripts/tests/test_screens_are_separate.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

## Every node under `node` (not counting ones already queued for deletion) whose script is `script_file`.
func nodes_with_script(node: Node, script_file: String) -> Array:
	var found: Array = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_queued_for_deletion():
			continue
		for c in n.get_children():
			stack.append(c)
		if n.get_script() != null and str(n.get_script().resource_path).get_file() == script_file:
			found.append(n)
	return found

func screens_of(main: Node) -> Array:
	var found: Array = []
	for c in main.get_children():
		if c is GameScreen and not c.is_queued_for_deletion():
			found.append(c)
	return found

## What sits in the map's SubViewport (besides its camera), by class, not counting what is being freed.
func map_contents(main: Node) -> Array:
	var found: Array = []
	for c in main.map_viewport.get_children():
		if not (c is Camera2D) and not c.is_queued_for_deletion():
			found.append(c.get_script().resource_path.get_file() if c.get_script() != null else c.get_class())
	found.sort()
	return found

func run() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame

	check(screens_of(main).size() == 1 and main.current_screen is LevelSelectScreen, "The game opens on exactly one screen: level select")
	check(map_contents(main).is_empty(), "...with nothing in the map yet")

	main._show_deployment()
	await process_frame
	check(screens_of(main).size() == 1 and main.current_screen is DeploymentPhase, "Deployment replaces level select (one screen)")
	check(map_contents(main) == ["deployment_screen.gd"], "...its map-space part is the only thing in the map (got %s)" % [map_contents(main)])
	# Drag a token, so the loupe has something to remember (the state that used to outlive deployment).
	var deployment: DeploymentPhase = main.current_screen
	deployment._magnifier_last_token = deployment.deployment_screen.get_children().filter(func(c): return c is UnitToken)[0]
	await process_frame
	check(deployment.deployment_magnifier.visible, "Setup: the loupe is showing the last placement")

	deployment.request_start()
	await process_frame
	await process_frame
	check(screens_of(main).size() == 1 and main.current_screen is BattleScreen, "Start Battle replaces deployment (one screen)")
	check(not is_instance_valid(deployment), "The deployment screen is freed")
	var battle: BattleScreen = main.current_screen
	# The battle has its own blow-up window (the B key on a selected unit): the one loupe node there is, and it is not showing.
	var loupes: Array = nodes_with_script(main, "deployment_magnifier.gd")
	check(loupes.size() == 1 and loupes[0] == battle.blowup and not battle.blowup.visible, "No deployment loupe survives into the battle (only the battle's own blow-up, hidden: %d)" % loupes.size())
	check(nodes_with_script(main, "doctrine_panel.gd").is_empty() and nodes_with_script(main, "deployment_screen.gd").is_empty(), "...nor the doctrine panel or the deployment map layer")
	check(map_contents(main) == ["battle_manager.gd", "enemy_heatmap_overlay.gd"], "The battle's map-space parts are all that is in the map (got %s)" % [map_contents(main)])

	battle._on_battle_ended("Verdict: TEST")
	await process_frame
	check(screens_of(main).size() == 1 and battle.report != null, "The report is part of the battle screen, not a screen of its own")
	battle.report._on_review_history_pressed()
	await process_frame
	check(map_contents(main).has("battle_history_viewer.gd"), "Setup: history review puts its viewer in the map")

	main._show_level_select()
	await process_frame
	await process_frame
	check(screens_of(main).size() == 1 and main.current_screen is LevelSelectScreen, "Choosing a new setup replaces the battle with level select (one screen)")
	check(not is_instance_valid(battle), "The battle screen is freed, its report with it")
	check(map_contents(main).is_empty(), "Nothing of the battle or its history viewer is left in the map (got %s)" % [map_contents(main)])
	for script_file in ["battle_manager.gd", "casualty_dashboard.gd", "combat_log.gd", "unit_orders_panel.gd", "decision_inspector.gd", "battle_history_viewer.gd", "enemy_heatmap_overlay.gd", "drone_pilot_debug_panel.gd", "battle_report.gd"]:
		check(nodes_with_script(main, script_file).is_empty(), "No %s survives on the first screen" % script_file)

	print("Screens-are-separate tests: %d failures" % failures)
	quit(1 if failures else 0)
