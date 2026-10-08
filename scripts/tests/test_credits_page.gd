extends SceneTree
## Direct user request: "Add a credits page to the opening screen." The opening screen (LevelSelectScreen) has a
## "Credits" button that opens a page crediting the map data (Overture Maps, Microsoft ML Building Footprints,
## OpenStreetMap, ESA WorldCover, SRTM, the satellite pictures used to check the maps), the sounds and the
## engine, and a Close button.
##
## The page must not claim more than is known: every sound is credited to Pixabay with its title, contributor and
## Pixabay ID and page address (the mortar shots to "Mortar Shell 2" by TommyLynn, ID 371034), and the licence is named as
## Pixabay's as it publishes it, not quoted.
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
	check(not ("not recorded" in text), "...with nothing left as unknown (every sound has its page address)")
	for address in ["film-special-effects-mortar-shell-2-371034", "nature-snow-rain-35637", "nature-soft-wind-318856", "nature-wind-blowing-457954", "nature-gentle-rain-for-relaxation-and-sleep-337279", "nature-drizzle-4perspectives-23254", "nature-rain-sound-188158", "nature-cozy-midnight-rain-04-448568", "film-special-effects-battle-war-zone-gun-fight-32155"]:
		check("pixabay.com/sound-effects/" + address in text, "The credits give the page for %s" % address)
	# every sound, with its title, contributor and Pixabay ID
	for needle in ["Mortar Shell 2", "TommyLynn", "371034", "soft wind", "storegraphic", "318856", "wind blowing", "soundreality", "457954",
			"gentle rain for relaxation and sleep", "eryliaa", "337279", "drizzle 4perspectives", "23254", "rain sound", "boons_freak", "188158",
			"cozy midnight rain 04", "dragon-studio", "448568", "snow rain", "35637", "battle war zone gun fight", "freesound_community", "32155",
			"pixabay.com/service/license-summary", "pixabay.com/sound-effects/film-special-effects-mortar-shell-2-371034", "pixabay.com/sound-effects/nature-snow-rain-35637"]:
		check(needle in text, "The sounds credit lists %s" % needle)
	check(not ("source was not recorded" in text) and not ("licence terms were not recorded" in text), "...and no sound is left as having no known source")
	# the mortar shots' own note records the source, the contributor, the ID, what was done to it and the six clips
	var note := FileAccess.get_file_as_string("res://assets/audio/mortar_fire/SOURCES.md")
	for needle in ["Mortar Shell 2", "TommyLynn", "371034", "tommylynn-mortar-shell-2-371034.mp3", "12 dB", "split", "mortar_shot_1.wav", "mortar_shot_6.wav", "license-summary", "film-special-effects-mortar-shell-2-371034"]:
		check(needle in note, "assets/audio/mortar_fire/SOURCES.md records %s" % needle)
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
