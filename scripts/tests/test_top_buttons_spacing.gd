extends SceneTree
## Direct user request: "Let's make the spacing among the top buttons uniform." The four order buttons
## (Clear Orders, Fall Back, Retreat Now, Pause) had different gaps between them (they were placed at
## fixed x positions, and the labels differ in width).
##
## Run: godot --headless --path . --script scripts/tests/test_top_buttons_spacing.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func gaps(buttons: Array) -> Array:
	var out: Array = []
	for i in range(1, buttons.size()):
		out.append(buttons[i].position.x - (buttons[i - 1].position.x + buttons[i - 1].size.x))
	return out

func run() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._show_deployment()
	await process_frame
	main.current_screen.request_start()
	for i in 3:
		await process_frame
	var battle: BattleScreen = main.current_screen
	var buttons: Array = [battle.clear_orders_button, battle.fall_back_button, battle.retreat_button, battle.pause_button]
	var g: Array = gaps(buttons)
	check(g.size() == 3 and absf(g[0] - g[1]) < 0.5 and absf(g[1] - g[2]) < 0.5, "The gaps between the four buttons are equal (%s)" % str(g))
	check(g[0] > 4.0 and g[0] < 30.0, "...and a modest size (%.1f px)" % g[0])
	var y: float = buttons[0].global_position.y
	for b in buttons:
		check(is_equal_approx(b.global_position.y, y), "They share one row")
	# Pause becomes Resume (a different width): the gaps stay equal.
	battle._on_pause_pressed()
	await process_frame
	await process_frame
	g = gaps(buttons)
	check(absf(g[0] - g[1]) < 0.5 and absf(g[1] - g[2]) < 0.5, "...also once Pause reads Resume (%s)" % str(g))
	print("Top button spacing tests: %d failures" % failures)
	quit(1 if failures else 0)
