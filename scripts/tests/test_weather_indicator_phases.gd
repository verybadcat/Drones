extends SceneTree
## The wind/precipitation indicator belongs to the deployment and battle phases
## only. User: "The wind indicator should be removed when the player is picking
## a scenario." Main clears the current weather when the level-select screen
## comes up (so a finished battle's weather never lingers there) and rolls a
## fresh one only when deployment starts.
##
## Run: godot --headless --path . --script scripts/tests/test_weather_indicator_phases.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	Weather.current = Weather.roll(3) # a finished battle's weather, still lying around
	main._show_level_select()
	check(Weather.current == null, "Picking a scenario must not show any weather (the overlay draws nothing when there is none)")
	main._show_deployment()
	check(Weather.current != null and not Weather.current.battle_started, "Deployment rolls a fresh weather for the coming battle")
	var deployed: Weather = Weather.current
	main._show_level_select()
	check(Weather.current == null, "Going back to the scenario picker clears it again")
	main._show_deployment()
	check(Weather.current != null and Weather.current != deployed, "Each deployment gets its own weather")
	print("Weather indicator phase tests: %d failures" % failures)
	quit(1 if failures else 0)
