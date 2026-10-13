class_name LevelSelectScreen
extends GameScreen
## The very first screen the player sees: choose which real place to fight
## over (see GameConfig.MAPS) and which reconnaissance/target-acquisition
## setup to fight with (see GameConfig.ReconMode). main.gd shows this before
## deployment and reads the choices off map_chosen/mode_chosen. Built the
## same programmatic way as every other screen in this game — no separate
## .tscn.

const BattleScore = preload("res://scripts/battle_score.gd")
const BattleScoreLog = preload("res://scripts/battle_score_log.gd")

signal mode_chosen(mode: GameConfig.ReconMode)
## Emitted the moment the map dropdown's selection changes — live, not
## gated behind a separate "Choose" button, since there's nothing to
## commit to first the way there is for recon mode (which shapes the rest
## of deployment). main.gd reacts immediately so this screen's own
## location readout, and everything else GameConfig.CURRENT_MAP-derived,
## is already showing the newly-picked place before the player moves on.
signal map_chosen(map_id: String)

## Index -> map id, in the same order the dropdown lists them — an
## OptionButton only ever hands back an index, never the id string itself.
var _map_ids: Array[String] = []

## The durable score history shown to the right of the setup (see BattleScoreLog).
## Public so a test can point it at a disposable file BEFORE this screen enters the
## tree; nothing else should reassign it.
var score_log := BattleScoreLog.new()

## The score table's cells (see _build_score_history): "map|mode" -> Button, the one
## currently opened (null if none), the records it was built from, and the panel that
## shows the opened cell's details.
var _cells: Dictionary = {}
var _opened_cell: Button = null
var _records: Array[Dictionary] = []
var _detail_panel: PanelContainer = null
var _detail_box: VBoxContainer = null

## The "Credits" button and the page it opens (see _toggle_credits); the panel is built the first time it is wanted.
var credits_button: Button = null
var credits_panel: PanelContainer = null
var designer_notes_button: Button = null
var designer_notes_panel: PanelContainer = null
var units_button: Button = null
var units_panel: PanelContainer = null

const SETUP_WIDTH: float = 820.0
const CELL_SIZE := Vector2(200, 58)
const ROW_HEADING_WIDTH: float = 190.0
const RECENT_BATTLES_SHOWN: int = 4


func _ready() -> void:
	super()

	# Two columns: the setup on the left, the score history on the right of it.
	var columns := HBoxContainer.new()
	columns.position = Vector2(60, 50)
	columns.add_theme_constant_override("separation", 40)
	add_child(columns)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	columns.add_child(root)

	root.add_child(_build_map_picker())
	root.add_child(_build_seed_box())

	var title := GameConfig.make_selectable_label("Choose your reconnaissance setup")
	title.add_theme_font_size_override("normal_font_size", 22)
	root.add_child(title)

	root.add_child(_build_option(
		GameConfig.RECON_MODE_LABELS[GameConfig.ReconMode.SPOTTER],
		"The original setup: a small ground team calls in fire on whatever it can see from wherever you post it.",
		GameConfig.ReconMode.SPOTTER
	))
	root.add_child(_build_option(
		GameConfig.RECON_MODE_LABELS[GameConfig.ReconMode.DRONE_TEAM],
		"Replaces the spotter with a 3-person team equipped with four Mavic-3 scout drones, plus spare batteries",
		GameConfig.ReconMode.DRONE_TEAM
	))

	root.add_child(_build_page_buttons())

	columns.add_child(_build_score_history())


## No map is shown yet, so no scale bar, compass or clock (see GameScreen).
func shows_map_marks() -> bool:
	return false


## Picking a scenario shows no weather: this battle's is only rolled when deployment starts.
func shows_weather() -> bool:
	return false


## The player's scores as a table: a row per location, a column per reconnaissance
## setup, and in each cell only the average score and the number of battles fought
## (from the durable history in BattleScoreLog, which survives restarts and code
## updates; scores are re-scored under the current rubric). Clicking a cell opens more
## about that scenario underneath (best, worst, latest, the recent battles); clicking it
## again, or another cell, closes or moves it. Every location and setup the game has
## is there, with a dash where nothing has been fought; history for a location or
## setup this build no longer has gets a row or column of its own, by its stored id.
func _build_score_history() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	# As wide as the table will be — also with no history to fill it: the labels here have no
	# minimum width of their own, and in a column with nothing else to give it one they would
	# shrink to nothing and the "No battles scored yet." line would never be seen.
	box.custom_minimum_size = Vector2(ROW_HEADING_WIDTH + GameConfig.ReconMode.size() * (CELL_SIZE.x + 8.0), 0.0)

	var title := GameConfig.make_selectable_label("Your average scores")
	title.add_theme_font_size_override("normal_font_size", 17)
	box.add_child(title)

	_records = score_log.load_records()
	var summaries: Array[Dictionary] = BattleScoreLog.summarize(_records)
	if summaries.is_empty():
		box.add_child(GameConfig.make_selectable_label("No battles scored yet."))
		return box

	var by_scenario: Dictionary = {}
	for entry in summaries:
		by_scenario["%s|%s" % [entry.map_id, entry.recon_mode]] = entry
	var map_ids: Array[String] = _table_map_ids(summaries)
	var modes: Array[String] = _table_recon_modes(summaries)

	var grid := GridContainer.new()
	grid.columns = modes.size() + 1
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	grid.add_child(_heading_label("", ROW_HEADING_WIDTH))
	for mode in modes:
		grid.add_child(_heading_label(mode_label(mode), CELL_SIZE.x))
	for map_id in map_ids:
		grid.add_child(_heading_label(map_name(map_id), ROW_HEADING_WIDTH))
		for mode in modes:
			grid.add_child(_score_cell(map_id, mode, by_scenario.get("%s|%s" % [map_id, mode], {})))

	_detail_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.92)
	style.set_content_margin_all(12.0)
	style.set_corner_radius_all(6.0)
	_detail_panel.add_theme_stylebox_override("panel", style)
	_detail_panel.visible = false
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 4)
	_detail_panel.add_child(_detail_box)
	box.add_child(_detail_panel)
	return box


## Every location: the game's own, in its catalog order, then any that only the
## history knows (by id).
func _table_map_ids(summaries: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for map_id in GameConfig.MAPS:
		ids.append(map_id)
	var extra: Array[String] = []
	for entry in summaries:
		if not ids.has(entry.map_id) and not extra.has(entry.map_id):
			extra.append(entry.map_id)
	extra.sort()
	return ids + extra


## Every reconnaissance setup: the game's own, in its order, then any only the
## history knows.
func _table_recon_modes(summaries: Array[Dictionary]) -> Array[String]:
	var modes: Array[String] = []
	for key in GameConfig.ReconMode.keys():
		modes.append(key)
	var extra: Array[String] = []
	for entry in summaries:
		if not modes.has(entry.recon_mode) and not extra.has(entry.recon_mode):
			extra.append(entry.recon_mode)
	extra.sort()
	return modes + extra


func _heading_label(text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return label


## One cell: the average and the number of battles, or a dash (and nothing to click)
## where that scenario has not been fought.
func _score_cell(map_id: String, mode: String, entry: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.focus_mode = Control.FOCUS_NONE
	if entry.is_empty():
		button.text = "—"
		button.disabled = true
	else:
		button.text = "%s\n%s" % [BattleScore.format(entry.average), battles_text(entry.count)]
		button.toggle_mode = true
		button.tooltip_text = "Click for more about %s" % scenario_label(map_id, mode)
		button.toggled.connect(_on_cell_toggled.bind(map_id, mode, button))
	_cells["%s|%s" % [map_id, mode]] = button
	return button


func _on_cell_toggled(pressed: bool, map_id: String, mode: String, button: Button) -> void:
	if pressed:
		if _opened_cell != null and _opened_cell != button and is_instance_valid(_opened_cell):
			_opened_cell.set_pressed_no_signal(false)
		_opened_cell = button
		_show_details(map_id, mode)
	elif _opened_cell == button:
		_opened_cell = null
		_detail_panel.visible = false


## More about one scenario: its counts, best, worst and latest score, and its most
## recent battles, newest first.
func _show_details(map_id: String, mode: String) -> void:
	for child in _detail_box.get_children():
		_detail_box.remove_child(child)
		child.queue_free()
	var entry: Dictionary = BattleScoreLog.scenario_summary(_records, map_id, mode)
	var heading := GameConfig.make_selectable_label(scenario_label(map_id, mode))
	heading.add_theme_font_size_override("normal_font_size", 16)
	_detail_box.add_child(heading)
	_detail_box.add_child(GameConfig.make_selectable_label("%s   Average %s   Best %s   Worst %s   Latest %s" % [
		battles_text(entry.count), BattleScore.format(entry.average), BattleScore.format(entry.best), BattleScore.format(entry.worst), BattleScore.format(entry.latest)]))
	var battles: Array[Dictionary] = BattleScoreLog.scenario_battles(_records, map_id, mode, RECENT_BATTLES_SHOWN)
	_detail_box.add_child(GameConfig.make_selectable_label("Most recent battles, newest first:" if battles.size() > 1 else "The battle:"))
	for battle in battles:
		var parts: PackedStringArray = []
		if not battle.time_utc.is_empty():
			parts.append(battle.time_utc.replace("T", " ") + " UTC")
		if not battle.verdict.is_empty():
			parts.append(battle.verdict)
		parts.append(BattleScore.format(battle.score))
		_detail_box.add_child(GameConfig.make_selectable_label("   ".join(parts)))
	if entry.count > battles.size():
		_detail_box.add_child(GameConfig.make_selectable_label("(and %d earlier)" % (entry.count - battles.size())))
	_detail_panel.visible = true


static func battles_text(count: int) -> String:
	return "1 battle" if count == 1 else "%d battles" % count


## A location's own name; one this build no longer has shows its stored id — old
## history is never hidden just because the catalog changed.
static func map_name(map_id: String) -> String:
	return GameConfig.MAPS[map_id].name if GameConfig.MAPS.has(map_id) else map_id


## A recon setup's own label; one this build no longer has shows its stored id.
static func mode_label(recon_mode: String) -> String:
	return GameConfig.RECON_MODE_LABELS[GameConfig.ReconMode[recon_mode]] if GameConfig.ReconMode.has(recon_mode) else recon_mode


## "Pishchane — Level 1 — Drone Recon".
static func scenario_label(map_id: String, recon_mode: String) -> String:
	return "%s — %s" % [map_name(map_id), mode_label(recon_mode)]


## Every real place in the catalog, by its own place name — GameConfig.
## MAPS' own keys (e.g. "pervomaiske") are internal ids, never shown.
## Defaults to whichever map is already active (the one main.gd's window
## was just sized for), not always the first entry, so opening this screen
## never silently re-picks a different map than what's actually loaded.
func _build_map_picker() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var label := GameConfig.make_selectable_label("Location")
	box.add_child(label)

	var picker := OptionButton.new()
	var selected_index := 0
	for map_id in GameConfig.MAPS:
		if GameConfig.CURRENT_MAP == GameConfig.MAPS[map_id]:
			selected_index = _map_ids.size()
		_map_ids.append(map_id)
		picker.add_item(GameConfig.MAPS[map_id].name)
	picker.select(selected_index)
	picker.item_selected.connect(func(index: int): map_chosen.emit(_map_ids[index]))
	box.add_child(picker)

	return box


## The battle seed, chosen here with the scenario ("I want to move the seed to the first screen where
## the user picks a scenario"). -1 (the default) means a random one, which the battle report shows
## afterwards so it can be copied and used again. See main.gd, which draws it for the battle.
var seed_box: SpinBox
## The seed the previous battle ran on (-1 if none has been set up yet this session). Set by main.gd
## before this screen is added to the tree, since _ready builds the button from it.
var last_battle_seed: int = -1
var use_last_seed_button: Button


## Fills the seed box with the last battle's seed. Sets the LineEdit's own text, then commits it with
## apply(), rather than assigning .value alone: a later chosen_seed() calls apply() too, which re-parses
## whatever text the box is showing — a bare .value assignment would be reverted by that if the displayed
## text hadn't followed (see chosen_seed's own doc comment on the SpinBox commit race).
func use_last_battle_seed() -> void:
	if last_battle_seed < 0 or seed_box == null:
		return
	seed_box.get_line_edit().text = str(last_battle_seed)
	seed_box.apply()


## Direct user request: the seed's explanatory paragraph (SEED_NOTE) used to sit here always visible, a
## full wrapped paragraph under the spin box. "I want the text below to be available, but not immediately
## displayed. Perhaps hidden behind a mouseover of a help icon or a question mark?" Replaced with a small,
## quiet HelpIcon ("(?)") to the right of the input row — see that class's own doc comment for why a plain
## `tooltip_text` on a bare Control wasn't enough (a direct, immediate follow-up report: the default
## one-line tooltip ran the whole paragraph off the edge of the screen). The Seed tab on the battle report
## (BattleReport.seed_tab_text) still shows SEED_NOTE in full, unchanged — that is a place the player
## deliberately navigated to for exactly this information, not a screen it should sit on by default.
##
## Also per direct user request: no up/down stepper — a seed is typed or pasted, never nudged by one, and
## the arrows just ate width for nothing (`buttons_width` is the theme constant that reserves their column;
## 0 collapses it entirely, arrows and all — confirmed directly by listing SpinBox's own theme_override_
## constants, there's no separate "hide the arrows" flag). Narrower now that the reserved arrow column is
## gone.
func _build_seed_box() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(GameConfig.make_selectable_label("Battle seed (-1 = random)"))
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)
	seed_box = SpinBox.new()
	seed_box.min_value = -1
	seed_box.max_value = MAX_SEED
	seed_box.value = -1
	seed_box.custom_minimum_size = Vector2(140, 0)
	seed_box.add_theme_constant_override("buttons_width", 0)
	input_row.add_child(seed_box)
	# Direct user request: a "use seed from last battle" button when choosing a new setup, "grayed out if
	# there was no last battle". main.gd hands the last battle's seed in (last_battle_seed, -1 until one
	# has been set up this session) before this screen is built.
	use_last_seed_button = Button.new()
	use_last_seed_button.text = "Use seed from last battle"
	use_last_seed_button.disabled = last_battle_seed < 0
	use_last_seed_button.tooltip_text = "No battle yet this session." if last_battle_seed < 0 else "Seed %d" % last_battle_seed
	use_last_seed_button.pressed.connect(use_last_battle_seed)
	input_row.add_child(use_last_seed_button)
	var help := HelpIcon.new()
	help.tooltip_text = SEED_NOTE
	input_row.add_child(help)
	box.add_child(input_row)
	return box


## The seed as typed: -1 for random, else 0 and up.
##
## Direct user report: pasted a seed from a prior battle's report, picked a recon mode right after, and
## got a different enemy force anyway. Root cause: SpinBox.value doesn't update from a pasted/typed edit
## until something commits it (Enter, an arrow click, or the LineEdit losing focus) — confirmed directly by
## setting a SpinBox's LineEdit text and reading .value before and after calling apply(): it read the OLD
## value first. Clicking straight from the seed field to a recon-mode button (this screen's very next
## step, per _on_recon_mode_chosen) races that commit against main.gd's own read of chosen_seed() — a
## pasted number could still lose to whatever the box last held. apply() forces the pending text to commit
## before anything reads .value, closing the race regardless of which way it happened to resolve before.
func chosen_seed() -> int:
	if seed_box == null:
		return -1
	seed_box.apply()
	return int(seed_box.value)


const MAX_SEED: int = 2147483647
## What a seed does and does not do (measured: see the design doc's 2026-09-26 entry for the
## same-setup claims, and its 2026-10-03 entry for the "whichever location and reconnaissance setup"
## ones — the enemy force has its own dice stream now, and the starting weather never looked at the map).
## Shared with the report's Seed tab (BattleReport), which repeats it beside the seed the battle used.
##
## The enemy force is described as "how many squads and mortars, and how each is set up" on purpose, not
## by listing the details: some of those (the commander's breaking point) are secret from the player. And
## where the enemy STARTS is stated separately because it is the one part that does follow the map.
const SEED_NOTE: String = "Using the same seed again gives you the same weather and the same enemy force (how many squads and mortars, and how each is set up) whichever location and reconnaissance setup you choose. Where the enemy starts follows the map, so a different location puts that same force in that location's places. On the same location and setup, the game's other dice also start from the same place. It does not replay the battle: what happens after that depends on what you do and on the exact timing of the game's frames, so the fight will still go its own way."


## The credits page, opened from the "Credits" button under the setup options (direct user request: "Add a
## credits page to the opening screen"). Plain facts about where the map data, the sounds and the engine came
## from, with the licences the sources publish them under. Kept as one function so a test can read it.
##
## What it must NOT do is claim more than is known: the sounds are all from Pixabay (the developer's statement), each with the title,
## contributor and ID from its file name and the page address the developer opened and confirmed (2026-10-07), and the licence is only
## named as Pixabay's, as it publishes it, not quoted (see assets/audio/*/SOURCES.md).
static func credits_text() -> String:
	return "\n".join([
		"CREDITS",
		"",
		"MAP DATA",
		"Building footprints: Overture Maps Foundation (overturemaps.org), which combines Microsoft's Global ML Building Footprints with OpenStreetMap. Open Database Licence (ODbL) 1.0.",
		"",
		"Roads, rivers, place names and the map locations: © OpenStreetMap contributors (openstreetmap.org/copyright), ODbL 1.0; a few road segments from TomTom, supplied through Overture Maps.",
		"",
		"Tree cover: ESA WorldCover © European Space Agency, CC BY 4.0, supplied through Overture Maps.",
		"",
		"Ground elevation: NASA Shuttle Radar Topography Mission (SRTM) 30 m data, supplied through OpenTopoData (opentopodata.org).",
		"",
		"Satellite pictures used only to check the maps against reality (they are not part of the game): Esri World Imagery (Esri, Maxar, Earthstar Geographics, and the GIS User Community).",
		"",
		"The account of the fighting at Voznesensk follows English Wikipedia (\"Battle of Voznesensk\") and a Krym.Realii interview with Ukrainian defenders (2023).",
		"",
		"SOUNDS",
		"All of the game's sounds are from Pixabay (pixabay.com/sound-effects), used under Pixabay's licence terms as Pixabay publishes them (pixabay.com/service/license-summary). Each is listed as its title, its Pixabay contributor (user name), its Pixabay ID and its page.",
		"",
		"Mortar shots: \"Mortar Shell 2\" by TommyLynn (Pixabay ID 371034, pixabay.com/sound-effects/film-special-effects-mortar-shell-2-371034), cut into six separate shots and made quieter.",
		"",
		"Wind: \"soft wind\" by storegraphic (318856, pixabay.com/sound-effects/nature-soft-wind-318856); \"wind blowing\" by soundreality (457954, pixabay.com/sound-effects/nature-wind-blowing-457954), edited into a seamless loop.",
		"",
		"Rain and sleet: \"gentle rain for relaxation and sleep\" by eryliaa (337279, pixabay.com/sound-effects/nature-gentle-rain-for-relaxation-and-sleep-337279), \"drizzle 4perspectives\" by freesound_community (23254, pixabay.com/sound-effects/nature-drizzle-4perspectives-23254) and \"rain sound\" by boons_freak (188158, pixabay.com/sound-effects/nature-rain-sound-188158), each shortened to its first 30 seconds; \"cozy midnight rain 04\" by dragon-studio (448568, pixabay.com/sound-effects/nature-cozy-midnight-rain-04-448568); \"snow rain\" by freesound_community (35637, pixabay.com/sound-effects/nature-snow-rain-35637).",
		"",
		"Gunfire: \"battle war zone gun fight\" by freesound_community (32155, pixabay.com/sound-effects/film-special-effects-battle-war-zone-gun-fight-32155).",
		"",
		"ENGINE",
		"Made with the Godot Engine (godotengine.org), MIT licence.",
		"",
	])


## "About this game", "Units" and "Credits", left to right: the three pages that open over the setup.
func _build_page_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	designer_notes_button = Button.new()
	designer_notes_button.text = "About this game"
	designer_notes_button.custom_minimum_size = Vector2(150, 0)
	designer_notes_button.pressed.connect(_toggle_designer_notes)
	row.add_child(designer_notes_button)
	units_button = Button.new()
	units_button.text = "Units"
	units_button.custom_minimum_size = Vector2(120, 0)
	units_button.pressed.connect(_toggle_units)
	row.add_child(units_button)
	credits_button = Button.new()
	credits_button.text = "Credits"
	credits_button.custom_minimum_size = Vector2(120, 0)
	credits_button.pressed.connect(_toggle_credits)
	row.add_child(credits_button)
	return row


## Opens the credits page over the setup (or closes it again). Built on first use. Only one of the pages shows at a time.
func _toggle_credits() -> void:
	if credits_panel == null:
		credits_panel = _build_page_panel(credits_text(), _toggle_credits)
	_toggle_page(credits_panel)


## Opens the "About this game" page (the designer notes) over the setup, or closes it again, the same way.
func _toggle_designer_notes() -> void:
	if designer_notes_panel == null:
		designer_notes_panel = _build_page_panel(designer_notes_text(), _toggle_designer_notes)
	_toggle_page(designer_notes_panel)


## Opens the Units page over the setup, or closes it again, the same way.
func _toggle_units() -> void:
	if units_panel == null:
		units_panel = _build_page_panel(units_text(), _toggle_units)
	_toggle_page(units_panel)


## Shows `panel` if it is hidden (hiding the other pages), or hides it if it is showing.
func _toggle_page(panel: PanelContainer) -> void:
	for other in [credits_panel, designer_notes_panel, units_panel]:
		if other != null and other != panel:
			other.visible = false
	panel.visible = not panel.visible


## A page over the setup: the text in a scrolling box and a Close button that calls `on_close`. Starts hidden.
func _build_page_panel(text: String, on_close: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = Vector2(60, 50)
	panel.custom_minimum_size = Vector2(900, 640)
	panel.z_index = 100
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.98)
	style.set_content_margin_all(18.0)
	style.set_corner_radius_all(6.0)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var body := GameConfig.make_selectable_label(text)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(840, 0)
	scroll.add_child(body)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120, 0)
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(on_close)
	box.add_child(close)
	add_child(panel)
	panel.visible = false
	return panel


## The designer notes page (direct user request: "a 'designer notes' page ... where the idea for the game came from, the different recon
## roles, and also the role of the player as commander, and why it is not a twitch game"). Written from the design record (the first
## design document and its revision log, docs/designs/tactical-commander-doctrine.md) and from the game's own rules; the figures
## are taken from the constants so the page cannot drift from the game.
static func designer_notes_text() -> String:
	var tactical_minute_per_second: int = int(GameConfig.TIME_SCALE_NORMAL / 60.0)
	var shell_flight_s: int = int(GameConfig.MORTAR_FLIGHT_TIME)
	var fast_forward_ratio: int = int(GameConfig.TIME_SCALE_FAST_FORWARD / GameConfig.TIME_SCALE_NORMAL)
	var squad_metres_per_second: int = int(round(GameConfig.ENEMY_ADVANCE_SPEED / GameConfig.PIXELS_PER_METER * GameConfig.TIME_SCALE_NORMAL / 10.0)) * 10
	return "\n".join([
		"ABOUT THIS GAME",
		"",
		"THE GOAL OF THE GAME",
		"The goal of this game is to illustrate why drones are so important in modern warfare. At Level 1, we show only the barest beginnings of the drone revolution, namely the use of drones for reconnaissance. Even with this limited use, they make a big difference, as the game illustrates. You should find that you can get significantly better average scores with drone recon than you can with artillery spotters.",
		"",
		"The role of the commander is limited, as it is in a real war. In both NATO and Ukrainian doctrine, a commander of a small engagement should generally not give detailed orders to units. Rather, the commander should give units general instructions, which they are supposed to know how to implement. The available in-game orders reflect this.",
		"",
		"The first version had two infantry squads and a mortar a side, and no drones at all. Drones were to come later, \"to use recon and artillery spotting\", once the basic game worked without them. The maps are made from real map data of Ukrainian villages, and the Voznesensk map follows the account of the real battle there.",
		"",
		"THE RECON ROLES",
		"What your side knows decides everything, because every unit, yours and the enemy's, acts only on what its own side knows. Enemy units stay invisible until somebody sees them, and a mortar can fire at a target its side knows about, but its rounds only walk onto the target if someone is watching where they land. Fire that nobody observes never gets more accurate. So the question each setup asks is who does the watching.",
		"",
		"Level 0, Artillery Spotter: a small ground team that calls in fire on whatever it can see from wherever you post it. It is unarmed and sees only what is in its own line of sight, so it has to be near enough to see the enemy, which puts it at risk of being seen.",
		"",
		"Level 1, Drone Recon: a 3-person team with four Mavic 3 scout drones and spare batteries replaces the spotter. A drone sees much more ground, and one directly over a target lets the mortar's fire close in on it within a few rounds. The team's pilot decides where the drones look and flies them, so you do not. They are out of reach of ground fire in the game; what limits them is battery, wind and rain, and the team on the ground, which can still be found and lost.",
		"",
		"Your squads watch too, and their eyes count for something, but they are the weakest observers of the fall of shot. Each setup is scored separately, so the two levels can be compared.",
		"",
		"YOU ARE THE COMMANDER",
		"You are not a unit and you do not steer one. Before the battle you decide where the squads, the mortar and the recon team start. The standing orders are the ones a force would carry in: squads break off at 50%% casualties, and the mortar fires and moves rather than stay where it is found. After that the units decide: squads advance, take cover and fight, the mortar chooses its targets, when to move and when to hold fire, and the pilot flies.",
		"",
		"During the battle you have a few blunt orders: click a unit for its orders card (fall back; for the mortar, whether it may spend ammunition on enemy squads), or order every unit to fall back, or withdraw the whole force, or clear what you have ordered. You can pause and think at any time. To see why units did what they did, the AI inspector (I), the enemy heat map (E) and the drone pilot's reasoning (D) are on keys. You are judged on the result: how well the setup and the few orders fit the situation.",
		"",
		"WHY IT IS NOT A TWITCH GAME",
		"The pace rules it out. While the two sides are in contact, one second of your time is %d tactical minute. A mortar round takes %d tactical seconds to land, less than one second of yours, and a squad on foot covers about %d m in that second. No one could micromanage that, and no one could on a real battlefield: by the time a commander hears of something and answers, the situation has already changed. When nobody sees an enemy the clock runs %d times faster.",
		"",
		"What is scarce is information and foresight, not reflexes. The skill is in choosing where to stand, what to watch with, and when to give up ground, before the fighting starts, and in reading afterwards what happened and why. The aim is that after watching a squad hold or break, you want to change what you set up and try again, which is why the same seed gives the same weather and the same enemy force.",
		"",
	]) % [tactical_minute_per_second, shell_flight_s, squad_metres_per_second, fast_forward_ratio]


## The Units page (direct user request: a "Units" button between "About this game" and "Credits" that "should bring up a screen which
## documents the characteristics of squads, mortars, spotters, drone teams, and drones"). Every figure is read from the game's own
## constants and from the units as the game sets them up, so the page cannot drift from the game.
static func units_text() -> String:
	var ppm: float = GameConfig.PIXELS_PER_METER
	var squad_u: Unit = _sample_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD)
	var squad_r: Unit = _sample_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD)
	var mortar_u: Unit = _sample_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR)
	var mortar_r: Unit = _sample_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR)
	var drone_team: Unit = _sample_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM)
	var cover: Dictionary = CombatResolver.SQUAD_COVER_MULTIPLIER
	var mortar_cover: Dictionary = CombatResolver.MORTAR_COVER_MULTIPLIER
	var lines: PackedStringArray = []
	lines.append("UNITS")
	lines.append("")
	lines.append("SQUADS")
	lines.append("%d people, on both sides, armed with small arms: the only unit that fights at close quarters." % squad_u.max_pips)
	lines.append("")
	lines.append("Fire: at any enemy it can see within %s and has a clear line of sight to (buildings and hills block it). It cannot fire while it is moving with intent, on the march or dashing for cover." % _metres(GameConfig.SQUAD_ENGAGEMENT_RANGE / ppm))
	lines.append("")
	lines.append("Accuracy: before terrain and range, a Ukrainian squad hits with %s of its shots and a Russian one with %s (the Ukrainians are defending prepared positions). Cover multiplies that by %s in the open, %s in trees and %s in a building, so a squad in trees is hit one-eighth as often as one in the open. Within %s of the shooter, cover no longer protects at all. A moving target keeps part of its cover (nearly all of a building's, about half of a wood's) but is hit %s times as often. A shot at point-blank range is up to %s times as likely to hit, the bonus fading with distance. Fire from several directions at once multiplies the damage, up to %s times for a squad that is surrounded. Higher ground partly defeats the cover below it." % [_pct(squad_u.base_hit_chance), _pct(squad_r.base_hit_chance), _num(cover[GameConfig.TerrainType.OPEN]), _num(cover[GameConfig.TerrainType.TREES]), _num(cover[GameConfig.TerrainType.BUILDING]), _metres(GameConfig.CLOSE_RANGE_COVER_DEFEAT_M), _num(GameConfig.MOVING_HIT_MULTIPLIER), _num(GameConfig.SQUAD_CLOSE_RANGE_HIT_MULTIPLIER), _num(CombatResolver.crossfire_multiplier(0.0))])
	lines.append("")
	lines.append("Casualties: a small-arms hit costs one person. A mortar round costs each person in reach a chance that depends on how far from the burst they are, and on their cover and posture: for a squad at its post in cover, or lying in the open, about %s of what a person standing alone in the open would have, and three times that for a squad on its feet in the open." % _pct(GameConfig.MORTAR_CASUALTY_FRACTION))
	lines.append("")
	lines.append("Posture: every unit is either upright or down, and a unit that is moving is always upright. A unit standing still stays upright until fire reaches it (a volley aimed at it, or a round landing within %s); %s later it goes to ground, stays down while fire keeps arriving and for %s after the last round, and gets up when it moves, which takes %s. Being down cuts the chance of being hit to %s of what it was in the open (a lying man is a smaller target) and to %s in cover (below the parapet), on top of what the cover itself does; so the first rounds of a barrage catch a squad upright and the later ones do not. A crew that has just fired stays on its feet at the gun. A unit that has gone down in the open is also %s as likely to be noticed." % [_metres(GameConfig.SUPPRESSION_BLAST_RADIUS_M), _secs(GameConfig.GO_TO_GROUND_REACTION_S), _secs(GameConfig.STAY_DOWN_AFTER_FIRE_S), _secs(GameConfig.RISE_DELAY_S), _pct(GameConfig.PRONE_IN_OPEN_FACTOR), _pct(GameConfig.PRONE_IN_COVER_FACTOR), _pct(GameConfig.LYING_SPOT_MULTIPLIER)])
	lines.append("")
	lines.append("Digging in: a unit that stays where it is digs, and loses what it has dug when it moves away (more than %s from the place). After %s it has a shell scrape, which is a little protection for a man lying in it; after %s a fighting position, deep enough to stand in with only the head and shoulders showing: there it has about %s of what a man on his feet in the open would have, and half of that again when crouched on the fire step. A round that lands in the hole is a direct hit and nothing protects against that, and within %s of the shooter a position is cleared as any cover is. Nobody digs in a building. The Ukrainian side starts the battle dug in where it is deployed (a unit in a building has the building); the Russian side starts with nothing. A unit in its fighting position does not walk off to the nearest cover, and does not bolt from it when a round lands." % [_metres(GameConfig.ENTRENCHMENT_ANCHOR_RADIUS_M), _secs(GameConfig.SHELL_SCRAPE_BUILD_S), _secs(GameConfig.FIGHTING_POSITION_BUILD_S), _pct(GameConfig.FIGHTING_POSITION_RATIO), _metres(GameConfig.CLOSE_RANGE_COVER_DEFEAT_M)])
	lines.append("")
	lines.append("Suppression: fire that misses still keeps heads down. Each volley aimed at a squad adds %s to its suppression, and a mortar round landing within %s adds up to %s, less the further off it lands. It fades completely in %d minutes. From %s a squad is pinned, and an enemy squad that is pinned does not start a new advance, until it falls below %s. A suppressed squad also shoots worse, by up to %s. A pinned squad is down, and stays down until it is released; one told to move hesitates %s first (once for each time it is pinned), and one that is pinned while it is moving halts; a retreat is not stopped. A pinned squad fires at a moving target at only %s of its chance, which is what covering fire is for: the squads moving are shot at less while the ones that would shoot at them are held down. A mortar gives extra weight to a squad that is firing on its own side's squads, unless it is being shelled already." % [_pct(GameConfig.SUPPRESSION_PER_VOLLEY), _metres(GameConfig.SUPPRESSION_BLAST_RADIUS_M), _pct(GameConfig.SUPPRESSION_BLAST_MAX), int(round(1.0 / GameConfig.SUPPRESSION_DECAY_PER_S / 60.0)), _pct(GameConfig.SUPPRESSION_PIN_LEVEL), _pct(GameConfig.SUPPRESSION_RELEASE_LEVEL), _pct(GameConfig.SUPPRESSION_MAX_ACCURACY_LOSS), _secs(GameConfig.PINNED_HESITATION_S), _pct(GameConfig.PINNED_VS_MOVING_FIRE_MULTIPLIER)])
	lines.append("")
	lines.append("Morale: it breaks off and retreats once it has lost %s of its people (the standing order), and it may surrender if it is cut off." % _pct(squad_u.retreat_threshold))
	lines.append("")
	lines.append("Pace, in metres per second of battle time: it marches at %s, repositions at %s, and withdraws at %s (Ukrainian) or %s (Russian)." % [_num(GameConfig.ENEMY_ADVANCE_SPEED / ppm), _num(GameConfig.REPOSITION_SPEED / ppm), _num(GameConfig.PLAYER_RETREAT_SPEED / ppm), _num(GameConfig.ENEMY_RETREAT_SPEED / ppm)])
	lines.append("")
	lines.append("Eyes: it notices enemies out to %s in the open, %s farther from higher ground, and %s times as readily while they are moving. Enemies in trees or buildings are much harder to notice, and so are those lying in the open." % [_metres(GameConfig.DETECTION_BASE_RANGE / ppm), _metres(GameConfig.DETECTION_ELEVATION_BONUS / ppm), _num(GameConfig.MOVING_SPOT_MULTIPLIER)])
	lines.append("")
	lines.append("MORTARS")
	lines.append("Crew-served indirect fire: it can hit whatever its side can see, from far beyond small-arms range.")
	lines.append("")
	lines.append("Crew: %d for the Ukrainians, %d for the Russians. A hit is decisive: it wounds or kills several of the crew at once, and a crew that breaks usually abandons the gun." % [mortar_u.crew_size, mortar_r.crew_size])
	lines.append("")
	lines.append("Range: %s (Ukrainian) or %s (Russian). A round takes %d seconds to land, so a target that has moved more than %s by then is missed, and a target in cover is much harder to hit: a mortar round is hampered by cover less than a bullet is (%s in the open, %s in trees, %s in a building)." % [_metres(GameConfig.MORTAR_MAX_RANGE_PLAYER / ppm), _metres(GameConfig.MORTAR_MAX_RANGE_ENEMY / ppm), int(GameConfig.MORTAR_FLIGHT_TIME), _metres(GameConfig.MORTAR_EVASION_RADIUS / ppm), _num(mortar_cover[GameConfig.TerrainType.OPEN]), _num(mortar_cover[GameConfig.TerrainType.TREES]), _num(mortar_cover[GameConfig.TerrainType.BUILDING])])
	lines.append("")
	lines.append("Rate of fire: bursts of up to %d rounds (%d inside %s), then a reload of %d seconds. The crew must stand still for %d seconds before it can fire, so a mortar that is moving cannot fire." % [GameConfig.MORTAR_BURST_MAX_SHOTS, GameConfig.MORTAR_BURST_CLOSE_RANGE_MAX_SHOTS, _metres(GameConfig.MORTAR_BURST_CLOSE_RANGE / ppm), int(mortar_u.reload_time), int(GameConfig.MORTAR_SETUP_TEARDOWN_TIME)])
	lines.append("")
	lines.append("Ammunition: it starts with %d rounds and can hold %d. A resupply run brings %d. A run is requested at first contact, waits off the map until the mortar is down to %d rounds, takes about %d minutes to arrive, and about one in %d does not get through. The run is unarmed and can be shot." % [mortar_u.mortar_rounds_remaining, GameConfig.MORTAR_MAX_AMMO_ON_HAND, GameConfig.MORTAR_RESUPPLY_ROUNDS, GameConfig.MORTAR_RESUPPLY_REORDER_POINT, int(GameConfig.MORTAR_RESUPPLY_DELAY_MEDIAN / 60.0), int(round(1.0 / GameConfig.MORTAR_RESUPPLY_FAILURE_CHANCE))])
	lines.append("")
	lines.append("Accuracy: the typical miss distance (half the rounds land closer) of fire that nobody observes is about %s of the range, never less than %s, and it never improves. When someone watches where the rounds fall, it shrinks with each round, toward a floor of %s with a squad watching, %s with a spotter and %s with a drone. A round aimed with a drone's help is also %s times as likely to hit." % [_pct(GameConfig.MORTAR_DISPERSION_CEP_FRACTION_OF_RANGE), _metres(GameConfig.MORTAR_DISPERSION_UNADJUSTED_FLOOR / ppm), _metres(GameConfig.MORTAR_DISPERSION_SQUAD_FLOOR / ppm), _metres(GameConfig.MORTAR_DISPERSION_SPOTTER_FLOOR / ppm), _metres(GameConfig.MORTAR_DISPERSION_DRONE_FLOOR / ppm), _num(GameConfig.DRONE_DIRECTED_MORTAR_ACCURACY_MULTIPLIER)])
	lines.append("")
	lines.append("Movement and siting: it relocates at %s metres per second (%s when hurried). It cannot fire from inside a building, and the Ukrainian crew will not set up in the populated-area exclusion zone around a town." % [_num(GameConfig.MORTAR_RELOCATE_SPEED / ppm), _num(GameConfig.MORTAR_RELOCATE_SPEED_URGENT / ppm)])
	lines.append("")
	lines.append("Concealment: every round fired gives its position away, and the other side's mortar may answer with counter-battery fire. In cover the crew can only be noticed from within %s; in the open it is noticed much more easily." % _metres(GameConfig.MORTAR_HIDDEN_DETECTION_RANGE / ppm))
	lines.append("")
	lines.append("Targets: an enemy mortar before anything else, then squads, weighing how many people are in them and how much of a danger they are. It holds fire to save ammunition as it runs low.")
	lines.append("")
	lines.append("SPOTTERS")
	lines.append("The Level 0 recon unit: a small ground team that calls in fire on whatever it can see. One hit puts it out of action. It is unarmed and never fires.")
	lines.append("")
	lines.append("Eyes: it notices enemies out to %s, which is %s farther than a squad. Hidden in cover it can only be noticed from within %s." % [_metres((GameConfig.DETECTION_BASE_RANGE + GameConfig.SPOTTER_DETECTION_RANGE_BONUS) / ppm), _metres(GameConfig.SPOTTER_DETECTION_RANGE_BONUS / ppm), _metres(GameConfig.SPOTTER_HIDDEN_DETECTION_RANGE / ppm)])
	lines.append("")
	lines.append("Use: it lets the mortar correct its fire onto what it sees, better than a squad can and not as well as a drone (see the mortar's accuracy above).")
	lines.append("")
	lines.append("DRONE TEAMS")
	lines.append("The Level 1 recon unit, in place of the spotter: %d people, unarmed, with %d Mavic 3 drones and %d spare batteries. You place the team; its pilot decides where the drones look." % [drone_team.crew_size, GameConfig.DRONE_FLEET_SIZE, GameConfig.DRONE_SPARE_BATTERIES])
	lines.append("")
	lines.append("Casualties: a hit is decisive against the crew, as it is against a mortar crew. Losing one of them does not end the flying, but each casualty makes the drones about %s less likely to notice what is in view and directing fire a little less effective." % _pct(1.0 - GameConfig.DRONE_TEAM_CASUALTY_SPOT_MULTIPLIER))
	lines.append("")
	lines.append("On the move: when the team itself is moving, the drones are flown with divided attention. They notice about %s less, and corrections to mortar fire are less precise." % _pct(1.0 - GameConfig.DRONE_TEAM_MOVING_SPOT_CHANCE_MULTIPLIER))
	lines.append("")
	lines.append("Batteries: swapping one takes %d minutes and recharging a flat one takes %d minutes. A drone is not launched below %s charge." % [int(GameConfig.DRONE_BATTERY_SWAP_DURATION / 60.0), int(GameConfig.DRONE_RECHARGE_DURATION / 60.0), _pct(GameConfig.DRONE_MIN_LAUNCH_CHARGE_FLOOR)])
	lines.append("")
	lines.append("DRONES")
	lines.append("A Mavic 3-class quadcopter: unarmed, pure reconnaissance.")
	lines.append("")
	lines.append("Flight: it flies at %d m and cruises at %s metres per second (%d km/h), up to %s. A battery lasts about %d minutes at cruise (the rated figure is %d), and the drone heads home, with a safety margin, before it runs flat. Climbing to its altitude takes about %d seconds." % [int(GameConfig.DRONE_ALTITUDE_M), _num(GameConfig.DRONE_CRUISE_SPEED / ppm), int(round(GameConfig.DRONE_CRUISE_SPEED / ppm * 3.6)), _num(GameConfig.DRONE_MAX_AIRSPEED / ppm), int(round(GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME / 60.0)), int(GameConfig.DRONE_MAX_FLIGHT_TIME / 60.0), int(round(GameConfig.DRONE_CLIMB_TIME))])
	lines.append("")
	lines.append("Eyes: it sees out to %s, the chance of noticing something falling off with the square of the distance from directly overhead. Buildings do not block its view, though it cannot see a unit inside one. A unit in trees is %s harder to notice from above." % [_metres(GameConfig.DRONE_DETECTION_RANGE / ppm), _pct(1.0 - GameConfig.DRONE_CONCEALMENT_MULTIPLIER[GameConfig.TerrainType.TREES])])
	lines.append("")
	lines.append("Risk: mortars and small arms cannot hit it. A person on the ground may notice it overhead, at about %s a minute within %s, which tells a crew it is being watched. Rain makes it fly lower or come home, and strong wind can keep it on the ground or, rarely, lose it." % [_pct(GameConfig.DRONE_GROUND_NOTICE_CHANCE_PER_MINUTE), _metres(GameConfig.DRONE_GROUND_NOTICE_MAX_RANGE_M)])
	for u in [squad_u, squad_r, mortar_u, mortar_r, drone_team]:
		u.free()
	return "\n".join(lines)


## A unit set up as the game sets it up, for reading its figures (freed by the caller).
static func _sample_unit(team: Unit.Team, kind: Unit.Kind) -> Unit:
	var u := Unit.new()
	u.setup(team, kind, Vector2.ZERO)
	return u


## "4,500 m": whole metres with thousands separators.
static func _metres(metres: float) -> String:
	var digits := str(int(round(metres)))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return "%s%s m" % [digits, out]


## 0.26 -> "26%"
static func _pct(fraction: float) -> String:
	return "%d%%" % int(round(fraction * 100.0))


## 3 -> "3 seconds"
static func _secs(seconds: float) -> String:
	return "%s second%s" % [_num(seconds), "" if is_equal_approx(seconds, 1.0) else "s"]


## A figure as short as it can be: 1.6, 0.2, 2, 4.
static func _num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(value)
	return ("%.2f" % value).rstrip("0")


func _build_option(title_text: String, body_text: String, mode: GameConfig.ReconMode) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.92)
	style.set_content_margin_all(16.0)
	style.set_corner_radius_all(6.0)
	box.add_theme_stylebox_override("panel", style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	box.add_child(inner)

	var option_title := GameConfig.make_selectable_label(title_text)
	option_title.add_theme_font_size_override("normal_font_size", 17)
	inner.add_child(option_title)

	var body := GameConfig.make_selectable_label(body_text)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(780, 0)
	inner.add_child(body)

	var button := Button.new()
	button.text = "Choose"
	button.pressed.connect(func(): mode_chosen.emit(mode))
	inner.add_child(button)

	return box
