extends SceneTree
## Direct user report: "Better, but it still looks like some text is cut off." The weather block (wind, temperature, gusts) sits under the
## compass at the map's bottom edge, and its last line hung below the bottom of a map that fills the window (Voznesensk, 760 px).
## The compass is now placed so the block's last line, descenders included, is inside the map on every map, with 20 px to spare.
##
## Run: godot --headless --path . --script scripts/tests/test_hud_inside_map.gd
const Overlay = preload("res://scripts/map_hud_overlay.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original: String = GameConfig.current_map_id()
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		var c: Vector2 = Overlay.compass_center()
		var last_line_bottom: float = c.y + Overlay.WEATHER_LAST_LINE_BASELINE_OFFSET + Overlay.TEXT_DESCENT
		check(last_line_bottom <= GameConfig.MAP_HEIGHT_PX - 19.0, "%s: the weather block's last line ends at %.0f px, inside the map (%.0f px) with room to spare" % [map_id, last_line_bottom, GameConfig.MAP_HEIGHT_PX])
		check(c.y - 26.0 > 40.0, "%s: the compass is below the scale bar" % map_id)
		check(c.x + 26.0 <= GameConfig.CAMERA_VIEWPORT_WIDTH_PX, "%s: the compass is inside the map's right edge" % map_id)
	GameConfig.set_active_map(original)
	print("HUD inside map tests: %d failures" % failures)
	quit(1 if failures else 0)
