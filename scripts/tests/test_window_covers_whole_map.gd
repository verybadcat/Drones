extends SceneTree
## Two direct user reports. First: "The Voznesensk map has issues with dimensions. The weather gauge is partly off of the bottom, as is the
## compass." The window was resized to the map (800 px tall once Voznesensk grew to 4,000 m) but the stretch base size stayed at project.godot's
## 1660 x 760, the area actually drawn, so anything past 760 px was cut off. Then: "Now the opening screen zooms weirdly when I switch to
## that map": the first fix set the drawn area when a map was chosen on the scenario picker, which rescaled the picker itself. Now the drawn
## area is set when a screen with the map on it opens (deployment) to cover the whole map, and the picker is the same size for every map.
##
## Run: godot --headless --path . --script scripts/tests/test_window_covers_whole_map.gd
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
	var original: String = GameConfig.current_map_id()
	var picker_size := Vector2i.ZERO
	for map_id in GameConfig.MAPS.keys():
		# choosing the map on the scenario picker: the picker must not change size
		GameConfig.set_active_map(map_id)
		main._apply_map_dimensions()
		if picker_size == Vector2i.ZERO:
			picker_size = root.content_scale_size
		check(root.content_scale_size == picker_size, "%s: choosing it on the scenario picker leaves the drawn area at %s (got %s)" % [map_id, str(picker_size), str(root.content_scale_size)])
		# the screens with the map on them cover all of it
		main._show_deployment()
		await process_frame
		var drawn: Vector2i = root.content_scale_size
		check(drawn.y >= int(GameConfig.MAP_HEIGHT_PX), "%s: on the deployment screen the drawn area (%d px tall) covers the whole map (%d px)" % [map_id, drawn.y, int(GameConfig.MAP_HEIGHT_PX)])
		check(drawn.x >= int(GameConfig.CAMERA_VIEWPORT_WIDTH_PX), "%s: ...and its width (%d px) the map's (%d px)" % [map_id, drawn.x, int(GameConfig.CAMERA_VIEWPORT_WIDTH_PX)])
		main._show_level_select()
		await process_frame
		check(root.content_scale_size == picker_size, "%s: back on the scenario picker the drawn area is %s again (got %s)" % [map_id, str(picker_size), str(root.content_scale_size)])
	GameConfig.set_active_map(original)
	main._apply_map_dimensions()
	print("Window covers whole map tests: %d failures" % failures)
	quit(1 if failures else 0)
