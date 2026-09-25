extends SceneTree
## Direct user request (with a screenshot of the end-of-battle report covering the
## elevation/location labels, "Inspect AI" and the retreat slider along the top):
## "Let's move the end-of-battle panel a bit further down in the UI so it doesn't
## overlap elements at the top. The buttons below it then also have to move down."
##
## Run: godot --headless --path . --script scripts/tests/test_report_layout.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func bottom_of(c: Control) -> float:
	return c.position.y + maxf(c.size.y, c.get_combined_minimum_size().y)

func run() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._on_battle_ended("Verdict: TEST")
	var panel: ColorRect = main.report_background
	# The strip along the top: everything main.gd keeps there.
	var strip: Array[Control] = [main._elevation_label, main._location_label, main._clock_label]
	var strip_bottom := 0.0
	for c in strip:
		strip_bottom = maxf(strip_bottom, bottom_of(c))
	# Controls made when a battle starts sit in the same strip: their fixed y and
	# height as main.gd lays them out (Inspect AI button at y=8, the retreat slider
	# and label at y=12, each about 31 px tall at most).
	strip_bottom = maxf(strip_bottom, 8.0 + 31.0)
	strip_bottom = maxf(strip_bottom, 12.0 + 31.0)
	check(panel.position.y >= strip_bottom, "The report panel (top %.0f) must clear the strip along the top of the screen (bottom %.0f)" % [panel.position.y, strip_bottom])
	check(panel.position.y > 20.0, "...it has moved down from where it used to sit (y=20)")
	# The three buttons stack below it, in order, without overlapping it or each other.
	var buttons: Array[Control] = [main.restart_button, main.review_history_button, main.hide_report_button]
	var previous_bottom: float = panel.position.y + panel.size.y
	for b in buttons:
		check(b.position.y >= previous_bottom, "%s (top %.0f) must sit below what is above it (bottom %.0f)" % [b.text, b.position.y, previous_bottom])
		previous_bottom = bottom_of(b)
	var window_height: float = maxf(GameConfig.MAP_HEIGHT_PX, GameConfig.MIN_WINDOW_HEIGHT_PX)
	check(previous_bottom <= window_height, "The last button (bottom %.0f) must still be inside the window (%.0f)" % [previous_bottom, window_height])
	# The tabs and the text still sit inside the panel.
	var scroll: ScrollContainer = null
	for c in panel.get_children():
		if c is ScrollContainer:
			scroll = c
	check(scroll != null and scroll.position.y + scroll.size.y <= panel.size.y, "The report text stays inside the panel")
	print("Report layout tests: %d failures (panel y=%.0f..%.0f, buttons to %.0f, window %.0f)" % [failures, panel.position.y, panel.position.y + panel.size.y, previous_bottom, window_height])
	main.free()
	quit(1 if failures else 0)
