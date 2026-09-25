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
	# Weather is global (Weather.current outlives every screen); the scenario picker simply shows
	# none of it: not on the map, and not as wind or rain sound. Windy and raining, so that any
	# leak would be audible.
	var lingering := Weather.roll(3) # a finished battle's weather, still lying around
	lingering.wind_speed_10m = 12.0
	lingering._wet = true
	lingering.precip_mm_h = 4.0
	lingering.temperature_c = 10.0
	Weather.current = lingering
	main._show_level_select()
	await process_frame
	await process_frame
	check(Weather.current == lingering, "Weather is global: picking a scenario does not clear it")
	check(not main._map_hud_overlay.weather_visible, "The scenario picker draws no weather on the map")
	check(main.wind_ambience._target == WindAmbience.plan(-1.0) and main.rain_ambience._target == RainAmbience.plan(Weather.Intensity.NONE, Weather.Precip.NONE), "...and plays no wind or rain sound, though there is weather about")
	main._show_deployment()
	await process_frame
	await process_frame
	check(Weather.current != null and Weather.current != lingering and not Weather.current.battle_started, "Deployment rolls a fresh weather for the coming battle")
	var deployed: Weather = Weather.current
	check(main._map_hud_overlay.weather_visible, "Deployment shows the weather on the map")
	check(main.wind_ambience._target == WindAmbience.plan(deployed.wind_speed_10m) and main.rain_ambience._target == RainAmbience.plan(deployed.intensity_class(), deployed.precip_type()), "...and plays it")
	main._show_level_select()
	await process_frame
	await process_frame
	check(Weather.current == deployed, "Going back to the scenario picker leaves the weather alone")
	check(not main._map_hud_overlay.weather_visible and main.wind_ambience._target == WindAmbience.plan(-1.0), "...but shows and plays none of it")
	main._show_deployment()
	check(Weather.current != null and Weather.current != deployed, "Each deployment gets its own weather")
	print("Weather indicator phase tests: %d failures" % failures)
	quit(1 if failures else 0)
