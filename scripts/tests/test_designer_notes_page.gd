extends SceneTree
## Direct user request: "Let's add a 'designer notes' page. The button for it can go where 'credits' is now, with 'credits' to the right of
## it. This should explain where the idea for the game came from, the different recon roles, and also the role of the player as commander,
## and why it is not a twitch game."
##
## The opening screen (LevelSelectScreen) has a "Designer notes" button where Credits was, Credits to its right; each opens a page with a
## Close button, and only one page shows at a time. The notes cover the four subjects, and what they say about the game is tied to the
## game's own rules (the defaults, the keys, the pace), so it cannot quietly go out of date.
##
## (The user later rewrote the first section, so the notes no longer have to quote the first design session or name mission
## command or the 2022 setting; the test checks the headings and the facts the page states about the game.)
## Run: godot --headless --path . --script scripts/tests/test_designer_notes_page.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func all_text(node: Node) -> String:
	var out := ""
	if node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	elif node is Label:
		out += (node as Label).text + "\n"
	for child in node.get_children():
		out += all_text(child)
	return out

func close_button(panel: Control) -> Button:
	for b in panel.find_children("*", "Button", true, false):
		if (b as Button).text == "Close":
			return b
	return null

func run() -> void:
	var text: String = LevelSelectScreen.designer_notes_text()
	# the four subjects
	for heading in ["THE GOAL OF THE GAME", "THE RECON ROLES", "YOU ARE THE COMMANDER", "WHY IT IS NOT A TWITCH GAME"]:
		check(heading in text, "The notes have a section: %s" % heading)
	for needle in ["drones", "Artillery Spotter", "Drone Recon", "Mavic 3", "micromanage", "pause"]:
		check(needle in text, "The notes mention %s" % needle)
	# no format codes left in the text, and the percentages are single
	check(not ("%d" in text) and not ("%%" in text) and not ("%s" in text), "No unfilled format code is left in the text")
	check("50% casualties" in text, "...and the percentage reads as one")

	# the figures come from the game's own constants
	var minutes: int = int(GameConfig.TIME_SCALE_NORMAL / 60.0)
	check(("one second of your time is %d tactical minute" % minutes) in text, "The pace stated is the game's (1 real second = %d tactical minute)" % minutes)
	check(("%d tactical seconds to land" % int(GameConfig.MORTAR_FLIGHT_TIME)) in text, "...a mortar round's flight time is the game's (%d s)" % int(GameConfig.MORTAR_FLIGHT_TIME))
	check(("runs %d times faster" % int(GameConfig.TIME_SCALE_FAST_FORWARD / GameConfig.TIME_SCALE_NORMAL)) in text, "...and so is the fast-forward ratio")
	var squad_m: int = int(round(GameConfig.ENEMY_ADVANCE_SPEED / GameConfig.PIXELS_PER_METER * GameConfig.TIME_SCALE_NORMAL / 10.0)) * 10
	check(("about %d m in that second" % squad_m) in text and squad_m >= 60 and squad_m <= 120, "...and a squad's pace (about %d m a second of the player's time)" % squad_m)

	# what it says about the commander's standing orders and keys is what the game does
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._show_deployment()
	await process_frame
	var doctrine: Dictionary = main.current_screen.build_doctrine()
	check(is_equal_approx(doctrine.squads[0].retreat_threshold, 0.5), "Squads do break off at 50% casualties by default, as the notes say")
	check(doctrine.mortar.shoot_and_scoot == true, "...and the mortar does shoot and move by default")
	var keys_text := ""
	for pair in KeysHelp.KEYS:
		keys_text += str(pair[0]) + " " + str(pair[1]) + "\n"
	check("(I)" in text and "(E)" in text and "(D)" in text and keys_text.contains("I") and keys_text.contains("E") and keys_text.contains("D"), "The keys the notes name (I, E, D) are in the keys list")
	main.queue_free()
	await process_frame

	# the buttons and the pages
	var screen := LevelSelectScreen.new()
	root.add_child(screen)
	await process_frame
	var notes_button: Button = screen.designer_notes_button
	var credits_button: Button = screen.credits_button
	check(notes_button != null and notes_button.text == "Designer notes", "The opening screen has a Designer notes button")
	check(credits_button != null and credits_button.text == "Credits", "...and a Credits button")
	check(notes_button.get_parent() == credits_button.get_parent(), "...in the same row")
	check(notes_button.get_index() < credits_button.get_index(), "...with Credits to the right of Designer notes (index %d, %d)" % [notes_button.get_index(), credits_button.get_index()])
	await process_frame
	check(credits_button.global_position.x >= notes_button.global_position.x + notes_button.size.x and is_equal_approx(credits_button.global_position.y, notes_button.global_position.y), "...on the same line, not overlapping")
	check(screen.designer_notes_panel == null or not screen.designer_notes_panel.visible, "The notes are not showing until asked for")
	notes_button.pressed.emit()
	await process_frame
	check(screen.designer_notes_panel != null and screen.designer_notes_panel.visible, "Pressing Designer notes opens the page")
	var shown: String = all_text(screen.designer_notes_panel)
	check("WHY IT IS NOT A TWITCH GAME" in shown and "Drone Recon" in shown, "...showing the notes")
	var close: Button = close_button(screen.designer_notes_panel)
	check(close != null, "...with a Close button")
	# only one page at a time
	credits_button.pressed.emit()
	await process_frame
	check(screen.credits_panel.visible and not screen.designer_notes_panel.visible, "Opening Credits puts the notes away")
	notes_button.pressed.emit()
	await process_frame
	check(screen.designer_notes_panel.visible and not screen.credits_panel.visible, "...and opening the notes puts Credits away")
	if close != null:
		close.pressed.emit()
		await process_frame
		check(not screen.designer_notes_panel.visible, "Close puts the notes away")
		notes_button.pressed.emit()
		await process_frame
		check(screen.designer_notes_panel.visible, "...and Designer notes brings them back")
	print("Designer notes page tests: %d failures" % failures)
	quit(1 if failures else 0)
