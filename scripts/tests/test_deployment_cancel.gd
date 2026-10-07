extends SceneTree
## Direct user request: "I want a 'cancel' button next to 'start battle' on that screen. 'Cancel' would take us back to the previous screen."
## The deployment (setup) screen has a Cancel button beside Start Battle; pressing it frees the screen and shows the scenario picker again,
## with nothing started, and a new setup can be begun from there.
##
## Run: godot --headless --path . --script scripts/tests/test_deployment_cancel.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func screens_of(main: Node) -> Array:
	return main.get_children().filter(func(c): return c is GameScreen and not c.is_queued_for_deletion())

func run() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._show_deployment()
	await process_frame
	var phase: DeploymentPhase = main.current_screen
	check(phase.cancel_button != null and phase.cancel_button.text == "Cancel", "The setup screen has a Cancel button")
	if phase.cancel_button == null:
		quit(1)
		return
	var start: Button = phase.start_button
	var cancel: Button = phase.cancel_button
	check(is_equal_approx(cancel.position.y, start.position.y) and cancel.position.x >= start.position.x + start.get_combined_minimum_size().x, "...on the same row as Start Battle, to its right, not overlapping it")
	check(cancel.position.x + cancel.get_combined_minimum_size().x <= GameConfig.CAMERA_VIEWPORT_WIDTH_PX + 320.0, "...and inside the window")
	var started: Array = []
	phase.start_requested.connect(func(d): started.append(d))
	cancel.pressed.emit()
	await process_frame
	await process_frame
	check(started.is_empty(), "Cancel starts no battle")
	check(main.current_screen is LevelSelectScreen and screens_of(main).size() == 1, "Cancel takes us back to the scenario picker, as the only screen")
	check(not is_instance_valid(phase), "...and the setup screen is freed")
	check(main.map_viewport.get_children().filter(func(c): return not (c is Camera2D) and not c.is_queued_for_deletion()).is_empty(), "...with nothing of the setup left in the map")
	# a new setup can be begun from there
	main._show_deployment()
	await process_frame
	check(main.current_screen is DeploymentPhase and main.current_screen.cancel_button != null, "A new setup can be started afterwards, with its own Cancel")
	print("Deployment cancel tests: %d failures" % failures)
	quit(1 if failures else 0)
