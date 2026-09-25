extends SceneTree
## The scale bar, compass and weather block (MapHudOverlay) and the tactical clock belong
## to the map and the battle, not to the screen where a scenario is chosen: the first
## screen shows none of them ("I don't want the 1000 m scale above it until we get to the
## next screen. Also the 6:00 part is not needed on this screen. We also don't need the
## 'North' compass"), deployment onward shows them, and coming back to the first screen
## hides them again. The location readout stays on every screen.
##
## Run: godot --headless --path . --script scripts/tests/test_map_marks_by_screen.gd
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
	check(main.current_screen is LevelSelectScreen, "Setup: the game opens on the level-select screen")
	check(not main._map_hud_overlay.map_marks_visible, "The first screen draws no scale bar, compass or weather")
	check(not main._clock_label.visible, "...and no clock")
	check(main._location_label.visible, "...but the location readout stays")
	check(not main._map_hud_overlay.weather_visible, "...and no weather block")
	main._show_deployment()
	await process_frame
	check(main._map_hud_overlay.map_marks_visible and main._clock_label.visible and main._map_hud_overlay.weather_visible, "Deployment shows the scale bar, compass, clock and weather again")
	main._show_level_select()
	await process_frame
	check(not main._map_hud_overlay.map_marks_visible and not main._clock_label.visible and not main._map_hud_overlay.weather_visible, "Back on the first screen they are hidden again")
	check(main._location_label.visible, "...with the location readout still there")
	main._show_deployment()
	main.current_screen.request_start()
	await process_frame
	check(main._map_hud_overlay.map_marks_visible and main._clock_label.visible, "The battle shows them")
	print("Map marks by screen tests: %d failures" % failures)
	quit(1 if failures else 0)
