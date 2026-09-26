extends SceneTree
## Direct user request: "Inspect AI doesn't need a button, I think. But there should be a screen
## accessible from the setup page, and also from the battle, that shows the various keys. This would
## include the one that shows the assessment of where the enemy might be, for example. Try to make it as
## unobtrusive as possible. It's definitely not a battle order, which is what the top bar does."
##
## Run: godot --headless --path . --script scripts/tests/test_keys_help.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func key(keycode: int, unicode: int = 0, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.unicode = unicode
	e.shift_pressed = shift
	e.pressed = true
	return e

func all_text(node: Node) -> String:
	var text := ""
	for n in node.find_children("*", "Label", true, false):
		text += " " + n.text
	for n in node.find_children("*", "Button", true, false):
		text += " " + n.text
	return text

func run() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._show_deployment()
	await process_frame
	var phase: DeploymentPhase = main.current_screen
	var setup_help: KeysHelp = null
	for c in phase.get_children():
		if c is KeysHelp:
			setup_help = c
	check(setup_help != null, "The setup screen has the list of keys")
	check_help(setup_help, "setup screen")

	phase.request_start()
	for i in 3:
		await process_frame
	var battle: BattleScreen = main.current_screen
	check(battle.keys_help != null, "The battle has the list of keys")
	check_help(battle.keys_help, "battle")
	# No button for the AI inspector any more, but the key still works.
	check(not ("inspect_button" in FileAccess.get_file_as_string("res://scripts/battle_screen.gd")) and not ("Inspect AI" in all_text(battle)), "Inspect AI has no button")
	var was: bool = battle.decision_inspector.visible
	battle._unhandled_input(key(KEY_I))
	check(battle.decision_inspector.visible != was, "...but the i key still toggles it")
	# Not in the top bar (the battle orders): the hint is low on the screen.
	var hint: Button = battle.keys_help.find_children("*", "Button", true, false)[0]
	check(hint.global_position.y > 600.0, "The hint is low on the screen, away from the top bar (y=%.0f)" % hint.global_position.y)
	check(not battle.top_buttons.is_ancestor_of(hint) and not (hint in battle.top_buttons.get_children()), "...and is not among the battle-order buttons")
	# It stays above the report at the end of the battle.
	battle._on_battle_ended("Verdict: TEST")
	await process_frame
	check(battle.keys_help.get_index() == battle.get_child_count() - 1, "The list stays on top of the report")
	print("Keys help tests: %d failures" % failures)
	quit(1 if failures else 0)


func check_help(help: KeysHelp, where: String) -> void:
	check(not help.is_open(), "%s: the list starts closed" % where)
	var hint: Button = help.find_children("*", "Button", true, false)[0]
	check(hint.get_theme_font_size("font_size") <= 12 and hint.flat, "%s: the hint is small and flat (font %d)" % [where, hint.get_theme_font_size("font_size")])
	check(hint.get_theme_color("font_color").a < 0.6, "%s: ...and dim" % where)
	check(help.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s: it never blocks the map" % where)
	var text := all_text(help)
	for needle in ["Enemy", "enemy heat map", "where the enemy might be", "drone pilot", "AI inspector", "F1"]:
		check(needle.to_lower() in text.to_lower(), "%s: the list mentions '%s'" % [where, needle])
	for k in ["E", "D", "I"]:
		check(_has_key_row(help, k), "%s: the list has the %s key" % [where, k])
	# ? (as typed with shift on a US layout, and by its own keycode) and F1 open it; Esc, ?, F1 or a click close it.
	check(help.handles_key(key(KEY_F1)) and help.handles_key(key(KEY_QUESTION)) and help.handles_key(key(KEY_SLASH, 63, true)), "%s: ?, shift+/ and F1 are the keys for it" % where)
	check(not help.handles_key(key(KEY_ESCAPE)), "%s: Esc does nothing while it is closed" % where)
	check(not help.handles_key(key(KEY_E)), "%s: other keys are left alone" % where)
	help._unhandled_input(key(KEY_F1))
	check(help.is_open(), "%s: F1 opens it" % where)
	check(help.handles_key(key(KEY_ESCAPE)), "%s: Esc counts once it is open" % where)
	help._unhandled_input(key(KEY_ESCAPE))
	check(not help.is_open(), "%s: Esc closes it" % where)
	help._unhandled_input(key(KEY_QUESTION))
	check(help.is_open(), "%s: ? opens it" % where)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	help._input(click)
	check(not help.is_open(), "%s: a click closes it" % where)
	help.toggle()
	check(help.is_open(), "%s: the hint button (toggle) opens it" % where)
	help.toggle()


func _has_key_row(help: KeysHelp, k: String) -> bool:
	for l in help.find_children("*", "Label", true, false):
		if l.text == k:
			return true
	return false
