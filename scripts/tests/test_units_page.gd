extends SceneTree
## Direct user request: "'Designer notes' can be changed to 'About this game'. Between that button and the 'credits' one, I want a button
## entitled 'Units'. This should bring up a screen which documents the characteristics of squads, mortars, spotters, drone teams, and drones."
##
## The opening screen has three buttons in a row, About this game, Units, Credits, each opening a page with a Close button, one page at a
## time. The Units page covers the five kinds of unit and its figures are the game's own: read from the constants and from the units as the
## game sets them up, so this test compares what the page says with what the game does.
##
## Run: godot --headless --path . --script scripts/tests/test_units_page.gd
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

func has_figure(text: String, figure: String, message: String) -> void:
	check(figure in text, "%s (the page should say \"%s\")" % [message, figure])

func run() -> void:
	var text: String = LevelSelectScreen.units_text()
	var ppm: float = GameConfig.PIXELS_PER_METER
	# the five kinds of unit
	for heading in ["SQUADS", "MORTARS", "SPOTTERS", "DRONE TEAMS", "DRONES"]:
		check(("\n" + heading + "\n") in text, "The page has a section: %s" % heading)
	check(not ("%d" in text) and not ("%s" in text) and not ("%%" in text), "No unfilled format code is left in the text")

	# the figures are the game's: units as the game sets them up
	var squad_u := Unit.new(); squad_u.setup(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	var squad_r := Unit.new(); squad_r.setup(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	var mortar_u := Unit.new(); mortar_u.setup(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	var mortar_r := Unit.new(); mortar_r.setup(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	var team := Unit.new(); team.setup(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	has_figure(text, "%d people, on both sides" % squad_u.max_pips, "A squad's size")
	has_figure(text, "a Ukrainian squad hits with %d%%" % int(round(squad_u.base_hit_chance * 100.0)), "The Ukrainian squad's accuracy")
	has_figure(text, "a Russian one with %d%%" % int(round(squad_r.base_hit_chance * 100.0)), "The Russian squad's accuracy")
	check(squad_u.base_hit_chance > squad_r.base_hit_chance, "Setup: the defenders do shoot straighter (%.2f against %.2f)" % [squad_u.base_hit_chance, squad_r.base_hit_chance])
	has_figure(text, "within %d m and has a clear line of sight" % int(round(GameConfig.SQUAD_ENGAGEMENT_RANGE / ppm)), "A squad's range")
	has_figure(text, "adds %d%% to its suppression" % int(round(GameConfig.SUPPRESSION_PER_VOLLEY * 100.0)), "A volley's suppression")
	has_figure(text, "From %d%% a squad is pinned" % int(round(GameConfig.SUPPRESSION_PIN_LEVEL * 100.0)), "The pin level")
	has_figure(text, "lost %d%% of its people" % int(round(squad_u.retreat_threshold * 100.0)), "A squad's breaking point")
	has_figure(text, "Crew: %d for the Ukrainians, %d for the Russians" % [mortar_u.crew_size, mortar_r.crew_size], "The mortar crews")
	has_figure(text, "it starts with %d rounds and can hold %d" % [mortar_u.mortar_rounds_remaining, GameConfig.MORTAR_MAX_AMMO_ON_HAND], "The mortar's ammunition")
	has_figure(text, "A round takes %d seconds to land" % int(GameConfig.MORTAR_FLIGHT_TIME), "A mortar round's flight")
	has_figure(text, "a reload of %d seconds" % int(mortar_u.reload_time), "The mortar's reload")
	has_figure(text, "4,500 m (Ukrainian) or 6,000 m (Russian)", "The mortars' ranges")
	check(int(GameConfig.MORTAR_MAX_RANGE_PLAYER / ppm) == 4500 and int(GameConfig.MORTAR_MAX_RANGE_ENEMY / ppm) == 6000, "Setup: those ranges are the game's")
	has_figure(text, "%d people, unarmed, with %d Mavic 3 drones and %d spare batteries" % [team.crew_size, GameConfig.DRONE_FLEET_SIZE, GameConfig.DRONE_SPARE_BATTERIES], "The drone team")
	has_figure(text, "it flies at %d m" % int(GameConfig.DRONE_ALTITUDE_M), "A drone's altitude")
	has_figure(text, "it sees out to 1,600 m" if int(GameConfig.DRONE_DETECTION_RANGE / ppm) == 1600 else "NOT 1,600", "A drone's range")
	has_figure(text, "notices enemies out to 1,400 m" if int((GameConfig.DETECTION_BASE_RANGE + GameConfig.SPOTTER_DETECTION_RANGE_BONUS) / ppm) == 1400 else "NOT 1,400", "A spotter's range")
	for u in [squad_u, squad_r, mortar_u, mortar_r, team]:
		u.free()

	# the buttons and the pages
	var screen := LevelSelectScreen.new()
	root.add_child(screen)
	await process_frame
	var about_button: Button = screen.designer_notes_button
	var units_button: Button = screen.units_button
	var credits_button: Button = screen.credits_button
	check(about_button != null and about_button.text == "About this game", "The first button reads About this game")
	check(units_button != null and units_button.text == "Units", "...the second reads Units")
	check(credits_button != null and credits_button.text == "Credits", "...and the third Credits")
	check(about_button.get_parent() == units_button.get_parent() and units_button.get_parent() == credits_button.get_parent(), "All three are in one row")
	check(about_button.get_index() < units_button.get_index() and units_button.get_index() < credits_button.get_index(), "...in the order About this game, Units, Credits")
	await process_frame
	check(units_button.global_position.x >= about_button.global_position.x + about_button.size.x and credits_button.global_position.x >= units_button.global_position.x + units_button.size.x, "...left to right, not overlapping")
	check(is_equal_approx(units_button.global_position.y, about_button.global_position.y) and is_equal_approx(credits_button.global_position.y, about_button.global_position.y), "...on the same line")
	check(screen.units_panel == null or not screen.units_panel.visible, "The Units page is not showing until asked for")
	units_button.pressed.emit()
	await process_frame
	check(screen.units_panel != null and screen.units_panel.visible, "Pressing Units opens the page")
	var shown: String = all_text(screen.units_panel)
	check("SQUADS" in shown and "DRONES" in shown and "Mavic 3" in shown, "...showing the units")
	var close: Button = close_button(screen.units_panel)
	check(close != null, "...with a Close button")
	# one page at a time, all three ways
	about_button.pressed.emit()
	await process_frame
	check(screen.designer_notes_panel.visible and not screen.units_panel.visible, "Opening About this game puts Units away")
	units_button.pressed.emit()
	await process_frame
	check(screen.units_panel.visible and not screen.designer_notes_panel.visible, "...and opening Units puts About this game away")
	credits_button.pressed.emit()
	await process_frame
	check(screen.credits_panel.visible and not screen.units_panel.visible and not screen.designer_notes_panel.visible, "...and opening Credits puts both away")
	units_button.pressed.emit()
	await process_frame
	check(screen.units_panel.visible and not screen.credits_panel.visible, "...and Units puts Credits away")
	if close != null:
		close.pressed.emit()
		await process_frame
		check(not screen.units_panel.visible, "Close puts the Units page away")
		units_button.pressed.emit()
		await process_frame
		check(screen.units_panel.visible, "...and Units brings it back")
	print("Units page tests: %d failures" % failures)
	quit(1 if failures else 0)
