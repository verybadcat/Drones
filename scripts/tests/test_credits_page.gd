extends SceneTree
## Direct user request: "Add a credits page to the opening screen." The opening screen (LevelSelectScreen) has a
## "Credits" button that opens a page crediting the map data (Overture Maps, Microsoft ML Building Footprints,
## OpenStreetMap, ESA WorldCover, SRTM, the satellite pictures used to check the maps), the sounds and the
## engine, and a Close button.
##
## The page must not claim more than is known: the sounds' licence terms were never looked up and the mortar
## shots have no recorded source, and the page says that.
##
## Run: godot --headless --path . --script scripts/tests/test_credits_page.gd
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
	elif node is Button:
		out += (node as Button).text + "\n"
	for child in node.get_children():
		out += all_text(child)
	return out

func run() -> void:
	# The text itself.
	var text: String = LevelSelectScreen.credits_text()
	for needle in ["Overture Maps", "Microsoft", "OpenStreetMap", "ODbL", "ESA WorldCover", "CC BY 4.0", "SRTM", "OpenTopoData", "Esri", "Pixabay", "Godot"]:
		check(needle in text, "The credits name %s" % needle)
	check("not recorded" in text, "...and say plainly where a source or licence was not recorded")
	# The page on the real screen.
	var screen := LevelSelectScreen.new()
	root.add_child(screen)
	await process_frame
	check(screen.credits_button != null and screen.credits_button.text == "Credits", "The opening screen has a Credits button")
	check(screen.credits_panel == null or not screen.credits_panel.visible, "...and the page is not showing until it is asked for")
	screen.credits_button.pressed.emit()
	await process_frame
	check(screen.credits_panel != null and screen.credits_panel.visible, "Pressing Credits opens the page")
	var shown: String = all_text(screen.credits_panel)
	check("Overture Maps" in shown and "OpenStreetMap" in shown and "Pixabay" in shown, "...showing the credits")
	var close: Button = null
	for b in screen.credits_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "Close":
			close = b
	check(close != null, "...with a Close button")
	if close != null:
		close.pressed.emit()
		await process_frame
		check(not screen.credits_panel.visible, "Close puts the page away")
		screen.credits_button.pressed.emit()
		await process_frame
		check(screen.credits_panel.visible, "...and Credits brings it back")
	print("Credits page tests: %d failures" % failures)
	quit(1 if failures else 0)
