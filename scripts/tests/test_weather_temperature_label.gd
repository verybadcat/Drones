extends SceneTree
## Direct user request: "the weather info should show temperature." The map's
## weather block now shows it beside the wind speed, in both units.
##
## Run: godot --headless --path . --script scripts/tests/test_weather_temperature_label.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var w := Weather.new()
	for case in [[8.7, "9°C (48°F)"], [0.0, "0°C (32°F)"], [-3.0, "-3°C (27°F)"], [30.0, "30°C (86°F)"], [-40.0, "-40°C (-40°F)"]]:
		w.temperature_c = case[0]
		check(w.temperature_label() == case[1], "%.1f C should read %s, got %s" % [case[0], case[1], w.temperature_label()])
	# The HUD block redraws when the temperature changes.
	w.temperature_c = 8.7
	var before: String = w.hud_signature()
	w.temperature_c = 12.0
	check(w.hud_signature() != before, "A temperature change must trigger a HUD redraw")
	# The HUD source actually draws it.
	var src := FileAccess.get_file_as_string("res://scripts/map_hud_overlay.gd")
	check("temperature_label()" in src, "The weather block must draw the temperature")
	print("Weather temperature label tests: %d failures" % failures)
	quit(1 if failures else 0)
