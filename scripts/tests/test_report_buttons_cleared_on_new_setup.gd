extends SceneTree
## Direct user bug report: "When the player goes to 'choose new setup', the
## show/hide report button should disappear." The end-of-battle report
## creates three buttons (Choose new setup, Review Battle History, Hide/Show
## Report) but Main._clear_all() only ever tore down three of them --
## hide_report_button was in neither its free list nor its null reset, so it
## outlived the report it belonged to and sat on the scenario picker.
##
## Run: godot --headless --path . --script scripts/tests/test_report_buttons_cleared_on_new_setup.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

## Every Button under `main` whose text is one of the report's own controls.
func _report_buttons(main: Node) -> Array:
	var found: Array = []
	for child in main.get_children():
		if child is Button and not child.is_queued_for_deletion() \
				and child.text in ["Hide Report", "Show Report", "Review Battle History", "Choose new setup and try again"]:
			found.append(child.text)
	return found

func run() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame

	main._on_battle_ended("Verdict: TEST")
	check(_report_buttons(main).size() == 3, "Setup check: the report should show all three buttons, got %s" % [_report_buttons(main)])

	main._show_level_select()
	await process_frame
	check(main.hide_report_button == null, "hide_report_button must be released when going back to the scenario picker")
	check(_report_buttons(main).is_empty(), "No report button may survive 'choose new setup', still showing: %s" % [_report_buttons(main)])

	# Same after hiding the report first (the button then reads "Show Report"),
	# and across a second battle: a stale button must not pile up.
	main._show_deployment()
	main._on_battle_ended("Verdict: TEST 2")
	main._on_hide_report_pressed()
	check(main.hide_report_button.text == "Show Report", "Setup check: hiding the report flips the button to Show Report")
	main._show_level_select()
	await process_frame
	check(_report_buttons(main).is_empty(), "A 'Show Report' button must not survive 'choose new setup' either, still showing: %s" % [_report_buttons(main)])

	print("Report buttons cleared on new setup tests: %d failures" % failures)
	quit(1 if failures else 0)
