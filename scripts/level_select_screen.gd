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
		"Roads, rivers, place names and the map locations: © OpenStreetMap contributors (openstreetmap.org/copyright), ODbL 1.0; a few road segments from TomTom, supplied through Overture Maps.",
		"Tree cover: ESA WorldCover © European Space Agency, CC BY 4.0, supplied through Overture Maps.",
		"Ground elevation: NASA Shuttle Radar Topography Mission (SRTM) 30 m data, supplied through OpenTopoData (opentopodata.org).",
		"Satellite pictures used only to check the maps against reality (they are not part of the game): Esri World Imagery (Esri, Maxar, Earthstar Geographics, and the GIS User Community).",
		"The account of the fighting at Voznesensk follows English Wikipedia (\"Battle of Voznesensk\") and a Krym.Realii interview with Ukrainian defenders (2023).",
		"",
		"SOUNDS",
		"All of the game's sounds are from Pixabay (pixabay.com/sound-effects), used under Pixabay's licence terms as Pixabay publishes them (pixabay.com/service/license-summary). Each is listed as its title, its Pixabay contributor (user name), its Pixabay ID and its page.",
		"Mortar shots: \"Mortar Shell 2\" by TommyLynn (Pixabay ID 371034, pixabay.com/sound-effects/film-special-effects-mortar-shell-2-371034), cut into six separate shots and made quieter.",
		"Wind: \"soft wind\" by storegraphic (318856, pixabay.com/sound-effects/nature-soft-wind-318856); \"wind blowing\" by soundreality (457954, pixabay.com/sound-effects/nature-wind-blowing-457954), edited into a seamless loop.",
		"Rain and sleet: \"gentle rain for relaxation and sleep\" by eryliaa (337279, pixabay.com/sound-effects/nature-gentle-rain-for-relaxation-and-sleep-337279), \"drizzle 4perspectives\" by freesound_community (23254, pixabay.com/sound-effects/nature-drizzle-4perspectives-23254) and \"rain sound\" by boons_freak (188158, pixabay.com/sound-effects/nature-rain-sound-188158), each shortened to its first 30 seconds; \"cozy midnight rain 04\" by dragon-studio (448568, pixabay.com/sound-effects/nature-cozy-midnight-rain-04-448568); \"snow rain\" by freesound_community (35637, pixabay.com/sound-effects/nature-snow-rain-35637).",
		"Gunfire: \"battle war zone gun fight\" by freesound_community (32155, pixabay.com/sound-effects/film-special-effects-battle-war-zone-gun-fight-32155).",
		"",
		"ENGINE",
		"Made with the Godot Engine (godotengine.org), MIT licence.",
	])


## "Designer notes" and, to its right, "Credits": the two pages that open over the setup.
func _build_page_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	designer_notes_button = Button.new()
	designer_notes_button.text = "Designer notes"
	designer_notes_button.custom_minimum_size = Vector2(150, 0)
	designer_notes_button.pressed.connect(_toggle_designer_notes)
	row.add_child(designer_notes_button)
	credits_button = Button.new()
	credits_button.text = "Credits"
	credits_button.custom_minimum_size = Vector2(120, 0)
	credits_button.pressed.connect(_toggle_credits)
	row.add_child(credits_button)
	return row


## Opens the credits page over the setup (or closes it again). Built on first use. Only one of the two pages shows at a time.
func _toggle_credits() -> void:
	if credits_panel == null:
		credits_panel = _build_page_panel(credits_text(), _toggle_credits)
	if designer_notes_panel != null:
		designer_notes_panel.visible = false
	credits_panel.visible = not credits_panel.visible


## Opens the designer notes over the setup (or closes them again), the same way.
func _toggle_designer_notes() -> void:
	if designer_notes_panel == null:
		designer_notes_panel = _build_page_panel(designer_notes_text(), _toggle_designer_notes)
	if credits_panel != null:
		credits_panel.visible = false
	designer_notes_panel.visible = not designer_notes_panel.visible


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
		"DESIGNER NOTES",
		"",
		"WHERE THE IDEA CAME FROM",
		"The game began as a question about command, not about drones or artillery. The designer wanted a wargame in which you cannot run every unit once the fight starts, because a real commander cannot either: \"my ability to make decisions during the battle may be limited. Sometimes my troops will make their own decisions based on general orders I give pre-battle.\" That sits between real-time micromanagement and the order-then-watch style of games like Combat Mission, and it is close to what armies call mission command: the commander says what is to be achieved and sets the limits, and the people on the ground decide how. Ukraine's army has been moving toward that way of fighting (planning centrally, acting locally), and the game is set in the opening of the 2022 invasion.",
		"The first version had two infantry squads and a mortar a side, and no drones at all. Drones were to come later, \"to use recon and artillery spotting\", once the command idea had proved itself without them. The maps are made from real map data of Ukrainian villages, and the Voznesensk map follows the account of the real battle there.",
		"",
		"THE RECON ROLES",
		"What your side knows decides everything, because every unit, yours and the enemy's, acts only on what its own side knows. Enemy units stay invisible until somebody sees them, and a mortar can fire at a target its side knows about, but its rounds only walk onto the target if someone is watching where they land. Fire that nobody observes never gets more accurate. So the question each setup asks is who does the watching.",
		"Level 0, Artillery Spotter: a small ground team that calls in fire on whatever it can see from wherever you post it. It is unarmed and sees only what is in its own line of sight, so it has to be near enough to see the enemy, which puts it at risk of being seen.",
		"Level 1, Drone Recon: a 3-person team with four Mavic 3 scout drones and spare batteries replaces the spotter. A drone sees much more ground, and one directly over a target lets the mortar's fire close in on it within a few rounds. The team's pilot decides where the drones look and flies them, so you do not. They are out of reach of ground fire in the game; what limits them is battery, wind and rain, and the team on the ground, which can still be found and lost.",
		"Your squads watch too, and their eyes count for something, but they are the weakest observers of the fall of shot. Each setup is scored separately, so the two levels can be compared.",
		"",
		"YOU ARE THE COMMANDER",
		"You are not a unit and you do not steer one. Before the battle you decide where the squads, the mortar and the recon team start. The standing orders are the ones a force would carry in: squads break off at 50%% casualties, and the mortar fires and moves rather than stay where it is found. After that the units decide: squads advance, take cover and fight, the mortar chooses its targets, when to move and when to hold fire, and the pilot flies.",
		"During the battle you have a few blunt orders: click a unit for its orders card (fall back; for the mortar, whether it may spend ammunition on enemy squads), or order every unit to fall back, or withdraw the whole force, or clear what you have ordered. You can pause and think at any time. To see why units did what they did, the AI inspector (I), the enemy heat map (E) and the drone pilot's reasoning (D) are on keys. You are judged on the result: how well the setup and the few orders fit the situation.",
		"",
		"WHY IT IS NOT A TWITCH GAME",
		"The pace rules it out. While the two sides are in contact, one second of your time is %d tactical minute. A mortar round takes %d tactical seconds to land, less than one second of yours, and a squad on foot covers about %d m in that second. No one could micromanage that, and no one could on a real battlefield: by the time a commander hears of something and answers, the situation has already changed. When nobody sees an enemy the clock runs %d times faster.",
		"What is scarce is information and foresight, not reflexes. The skill is in choosing where to stand, what to watch with, and when to give up ground, before the fighting starts, and in reading afterwards what happened and why. The aim is that after watching a squad hold or break, you want to change what you set up and try again, which is why the same seed gives the same weather and the same enemy force.",
	]) % [tactical_minute_per_second, shell_flight_s, squad_metres_per_second, fast_forward_ratio]
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
