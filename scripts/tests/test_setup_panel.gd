extends SceneTree
## Direct user request: "During the setup, I want to get rid of most of the part at the right of the
## screen (the preferences). I do want to keep the part below, and also keep the battle seed." What is
## left of the sidebar is the instruction line, the battle seed and the Start Battle button; every
## removed preference is at its old default, so a battle started from setup is what it was with the
## controls untouched.
##
## Run: godot --headless --path . --script scripts/tests/test_setup_panel.gd
const UnitDoctrine = preload("res://scripts/unit_doctrine.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func descendants(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append(c)
		out.append_array(descendants(c))
	return out

func run() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._show_deployment()
	await process_frame
	var phase: DeploymentPhase = main.current_screen
	var panel: DoctrinePanel = phase.doctrine_panel

	var kinds := {}
	for n in descendants(panel):
		kinds[n.get_class()] = kinds.get(n.get_class(), 0) + 1
	check(not kinds.has("OptionButton") and not kinds.has("HSlider") and not kinds.has("CheckBox"), "No preference controls are left (found %s)" % str(kinds))
	check(not kinds.has("SpinBox"), "...and no seed box either: the seed is chosen on the first screen now (found %s)" % str(kinds))
	var text := ""
	for n in descendants(panel):
		if n is Label or n is RichTextLabel:
			text += " " + n.text
	check("Holding %s. Drag your units into position on the map, set doctrine below, then start the battle." % GameConfig.CURRENT_MAP.name in text, "The instruction line is kept word for word, as the user asked (%s)" % text)
	check(not ("Battle seed" in text), "...and no battle seed label")
	check(phase.start_button != null and phase.start_button.position.y >= panel.position.y + panel.size.y, "The Start Battle button sits just under the panel")
	check(phase.start_button.position.y < 300.0, "...near the top rather than where the long panel used to end (y=%.0f)" % phase.start_button.position.y)

	var captured: Array = []
	phase.start_requested.connect(func(d): captured.append(d))
	phase.battle_seed = 1234
	phase.request_start()
	var d: Dictionary = captured[0]
	check(d.seed == 1234, "The seed the screen was given goes into the battle")
	check(d.player_profile.id == "baseline" and d.enemy_profile.id == "baseline", "Both commanders are the baseline profile, as the controls' defaults were")
	check(is_equal_approx(d.squads[0].retreat_threshold, 0.5), "Squads retreat at 50% casualties, as the slider's default did")
	check(d.mortar.shoot_and_scoot == true, "The mortar shoots and scoots, as the checkbox's default did")
	check(d.player_unit_types == UnitDoctrine.sanitize({}) and d.enemy_unit_types == UnitDoctrine.sanitize({}), "No per-unit-type orders")
	check(is_equal_approx(d.player_profile.protection, 1.0) and d.player_profile.deterministic == false, "The baseline weights and randomness are untouched")
	print("Setup panel tests: %d failures" % failures)
	quit(1 if failures else 0)
